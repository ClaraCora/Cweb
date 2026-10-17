import Foundation
import Testing
@testable import ProfileBrowser

@MainActor
struct BackupServiceTests {
    @Test
    func encryptsAndImportsProfiles() throws {
        let vault = CredentialVault(inMemory: true)
        let service = BackupService(vault: vault)
        let homePage = try #require(URL(string: "https://example.com"))
        let loginURL = try #require(URL(string: "https://example.com/login"))
        let profile = BrowserProfile(
            name: "测试",
            groupSortOrder: 3,
            homePage: homePage,
            socksProxyNumber: 2
        )
        let origin = try #require(WebOrigin(url: loginURL))
        let credential = StoredCredential(
            profileID: profile.id,
            origin: origin,
            username: "user@example.com",
            password: "secret",
            label: "主账号"
        )
        try vault.save(credential)
        defer { try? vault.deleteAll(profileID: profile.id) }

        let data = try service.export(profiles: [profile], password: "correct horse")
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: BackupDocument.defaultFilename)
        let document = BackupDocument(data: data)
        try document.data.write(to: fileURL)
        let selectedFile = try BackupImportFile(contentsOf: fileURL)
        let imported = try service.importProfiles(from: selectedFile.data, password: "correct horse")

        #expect(fileURL.pathExtension == "json")
        #expect(selectedFile.filename == fileURL.lastPathComponent)
        #expect(selectedFile.data == data)
        #expect(imported.count == 1)
        #expect(imported[0].name == profile.name)
        #expect(imported[0].id != profile.id)
        #expect(imported[0].websiteDataStoreID != profile.websiteDataStoreID)
        #expect(imported[0].socksProxyNumber == profile.socksProxyNumber)
        #expect(imported[0].groupSortOrder == profile.groupSortOrder)
        let importedCredentials = try vault.credentials(profileID: imported[0].id, origin: origin)
        #expect(importedCredentials.count == 1)
        #expect(importedCredentials[0].username == credential.username)
        #expect(importedCredentials[0].password == credential.password)
        try vault.deleteAll(profileID: imported[0].id)
    }

    @Test
    func rejectsWrongPassword() throws {
        let service = BackupService(vault: CredentialVault(inMemory: true))
        let profile = BrowserProfile(name: "测试")
        let data = try service.export(profiles: [profile], password: "correct horse")

        #expect(throws: BackupError.invalidPassword) {
            _ = try service.importProfiles(from: data, password: "wrong password")
        }
    }

    @Test(arguments: ["ProfileBrowser-backup", "ProfileBrowser-backup.json"])
    func importsLegacyBackupAndRetriesFromCachedData(filename: String) throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: filename)
        try Self.legacyBackup.write(to: fileURL)
        let selectedFile = try BackupImportFile(contentsOf: fileURL)
        try FileManager.default.removeItem(at: fileURL)
        let service = BackupService(vault: CredentialVault(inMemory: true))

        #expect(selectedFile.filename == filename)
        #expect(selectedFile.data == Self.legacyBackup)
        #expect(throws: BackupError.invalidPassword) {
            _ = try service.importProfiles(from: selectedFile.data, password: "wrong password")
        }
        let imported = try service.importProfiles(from: selectedFile.data, password: "legacy password")
        let profile = try #require(imported.first)
        #expect(imported.count == 1)
        #expect(profile.name == "Legacy profile")
        #expect(profile.homePage.absoluteString == "https://example.com")
        #expect(profile.id.uuidString != "00000000-0000-0000-0000-000000000002")
        #expect(profile.websiteDataStoreID.uuidString != "00000000-0000-0000-0000-000000000003")
        #expect(profile.groupName == nil)
    }

    @Test(arguments: ["", "not json", "[]", "{}", "{\"version\":1}"])
    func rejectsInvalidFilesBeforeAskingForPassword(contents: String) throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "invalid.json")
        let data = Data(contents.utf8)
        try data.write(to: fileURL)

        #expect(throws: BackupError.invalidFormat) {
            _ = try BackupImportFile(contentsOf: fileURL)
        }
        #expect(throws: BackupError.invalidFormat) {
            _ = try BackupService(vault: CredentialVault(inMemory: true))
                .importProfiles(from: data, password: "correct horse")
        }
    }

    @Test
    func rejectsDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: BackupError.invalidFormat) {
            _ = try BackupImportFile(contentsOf: directory)
        }
    }

    @Test
    func reportsMissingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: CocoaError.self) {
            _ = try BackupImportFile(contentsOf: directory.appending(path: "missing.json"))
        }
    }

    @Test(arguments: [0, 2])
    func rejectsUnsupportedVersion(version: Int) throws {
        let data = try legacyBackup(replacing: "version", with: version)
        #expect(throws: BackupError.invalidFormat) {
            try BackupService.validateBackupData(data)
        }
    }

    @Test(arguments: [9_999, 500_001])
    func rejectsInvalidIterationCount(iterations: Int) throws {
        let data = try legacyBackup(replacing: "iterations", with: iterations)
        #expect(throws: BackupError.invalidFormat) {
            try BackupService.validateBackupData(data)
        }
    }

    @Test(arguments: ["not base64", "", "AA=="])
    func rejectsMalformedSalt(salt: String) throws {
        let data = try legacyBackup(replacing: "salt", with: salt)
        #expect(throws: BackupError.invalidFormat) {
            try BackupService.validateBackupData(data)
        }
    }

    @Test(arguments: ["not base64", "", "AA=="])
    func rejectsMalformedCiphertext(sealedData: String) throws {
        let data = try legacyBackup(replacing: "sealedData", with: sealedData)
        #expect(throws: BackupError.invalidFormat) {
            try BackupService.validateBackupData(data)
        }
        #expect(throws: BackupError.invalidFormat) {
            _ = try BackupService(vault: CredentialVault(inMemory: true))
                .importProfiles(from: data, password: "legacy password")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func legacyBackup(replacing key: String, with value: Any) throws -> Data {
        var envelope = try #require(JSONSerialization.jsonObject(with: Self.legacyBackup) as? [String: Any])
        envelope[key] = value
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    // Independent v1 fixture: PBKDF2-HMAC-SHA256 and AES-256-GCM, password "legacy password".
    private static var legacyBackup: Data {
        Data("""
        {
          "version": 1,
          "iterations": 120000,
          "salt": "AAECAwQFBgcICQoLDA0ODw==",
          "sealedData": "AAECAwQFBgcICQoLCPURpqHQhL4ZWtAdbcwuOEpwNbepHZjPOvtToT8BoFydjHX15rHvFhBxfuXKP6b1NlrxWswTJZEKqfrnNxo2dxloJPRC7xvCYw46mMUs7rNtMAMOmqhGDfpDJdXjsYJ+R468gQZPgN/qTNZtXftL6tXNl53pc+YSaxCjxUKRME6ti4V5gf9s3wFNW4FOIFiHpaN55Q+5C+UFRuYQyD19jm8NhgTdLi19Q+y54+1y1wx29utJLeuXmOoc4gnjbRukQ2LhWRWB6y1D2ViB3hdarxSu1sxTWjanUA8IrO0tv7/d7zQUDL2cZU/0V+CkYl1yELUVTsbKVNbzVMrrSEpqZU5bl18cu5uUGckLVa0ktFcn6ZwQJzFG9DzgnAXx7wps0Sb78Vmfr9DLZTXOWsUvKD7ngEbK3xk6E1lDoRSBXkmFAgfddFvVSVgwXhtnhwAzZK/4UEBe2b70aRVGKImg9HSQHKogBd35QZVkiuWaonK5THkDxc39a+NGf1c="
        }
        """.utf8)
    }
}
