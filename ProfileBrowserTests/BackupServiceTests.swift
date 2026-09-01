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
        let imported = try service.importProfiles(from: data, password: "correct horse")

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
}
