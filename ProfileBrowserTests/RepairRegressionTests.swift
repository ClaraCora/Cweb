import Foundation
import Testing
@testable import ProfileBrowser

@MainActor
struct RepairRegressionTests {
    @Test
    func thirdCredentialFailureRollsBackWholeDuplicate() throws {
        var saves = 0
        var armed = false
        var duplicateID: UUID?
        let vault = CredentialVault(inMemory: true) { mutation in
            if armed, case .save(let credential) = mutation {
                duplicateID = credential.profileID
                saves += 1
                if saves == 3 { throw CocoaError(.fileWriteUnknown) }
            }
        }
        let fixture = try RepairFixture(vault: vault)
        defer { fixture.cleanUp() }
        let profile = BrowserProfile(name: "原环境")
        try fixture.model.addImportedProfile(profile)
        let origin = try #require(WebOrigin(url: profile.homePage))
        for index in 1...3 { try vault.save(StoredCredential(profileID: profile.id, origin: origin, username: "user\(index)", password: "secret", label: "")) }
        armed = true
        #expect(throws: CocoaError.self) { try fixture.model.duplicateProfile(profile) }
        #expect(fixture.model.profiles.count == 1)
        #expect(try fixture.repository.load().count == 1)
        #expect(try vault.credentials(profileID: profile.id).count == 3)
        let failedCopyID = try #require(duplicateID)
        #expect(try vault.credentials(profileID: failedCopyID).isEmpty)
    }

    @Test
    func failedProfileWriteRestoresUpdatedCredential() throws {
        var failWrite = false
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = ProfileRepository(fileURL: directory.appending(path: "profiles.json"), writeData: { data, url in
            if failWrite { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        })
        let fixture = try RepairFixture(directory: directory, repository: repository)
        defer { fixture.cleanUp() }
        try fixture.model.addProfile(name: "原环境", homePage: BrowserProfile.defaultHomePage,
            userAgent: BrowserProfile.defaultUserAgent, color: .indigo, autofillUsername: "user", autofillPassword: "old-password")
        var profile = try #require(fixture.model.profiles.first)
        profile.name = "修改后"
        failWrite = true
        #expect(throws: CocoaError.self) { try fixture.model.updateProfile(profile, autofillUsername: "user", autofillPassword: "new-password") }
        #expect(fixture.model.profiles.first?.name == "原环境")
        #expect(try repository.load().first?.name == "原环境")
        #expect(try fixture.model.credentialVault.credentials(profileID: profile.id).first?.password == "old-password")
    }

    @Test
    func proxyPasswordFailureLeavesJsonAndAllSecretsUnchanged() throws {
        let fault = MutationFault()
        let store = SocksProxyCredentialStore(inMemory: true) { _ in try fault.check() }
        let fixture = try RepairFixture(credentialStore: store)
        defer { fixture.cleanUp() }
        let first = SocksProxy(host: "one.test", port: 1080, password: "one")
        let second = SocksProxy(host: "two.test", port: 1080, password: "two")
        try fixture.proxyRepository.save([first, second])
        var changed = first; changed.password = "updated"
        fault.arm(failAt: 2)
        #expect(throws: CocoaError.self) { try fixture.proxyRepository.save([changed, second]) }
        #expect(try fixture.proxyRepository.load() == [first, second])
    }

    @Test
    func failedProxyFileWriteRestoresItsPassword() throws {
        var failing = false
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SocksProxyRepository(fileURL: directory.appending(path: "proxies.json"), credentialStore: SocksProxyCredentialStore(inMemory: true), writeData: { data, url in
            if failing { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        })
        let original = SocksProxy(host: "one.test", port: 1080, password: "original")
        try repository.save([original])
        failing = true
        var updated = original; updated.password = "updated"
        #expect(throws: CocoaError.self) { try repository.save([updated]) }
        #expect(try repository.load() == [original])
    }

    @Test
    func failedCompleteRestoreRollsBackProxyCredentialsAndProfileCredentials() throws {
        var failing = false
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = ProfileRepository(fileURL: directory.appending(path: "profiles.json"), writeData: { data, url in
            if failing { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        })
        let fixture = try RepairFixture(directory: directory, repository: repository)
        defer { fixture.cleanUp() }
        let originalProxy = SocksProxy(host: "original.test", port: 1080, password: "original")
        try fixture.model.addSocksProxy(originalProxy)
        let profile = BrowserProfile(name: "导入", socksProxyNumber: 1)
        let proxy = SocksProxy(host: "imported.test", port: 1080, password: "imported")
        let credential = StoredCredential(profileID: profile.id, origin: try #require(WebOrigin(url: profile.homePage)), username: "user", password: "secret", label: "")
        let archive = BackupArchive(profiles: [profile], credentials: [credential], proxies: [BackupProxy(proxy: proxy, password: proxy.password)], bindings: [BackupProxyBinding(profileID: profile.id, proxyID: proxy.id)])
        let plan = fixture.model.prepareBackupRestore(archive)
        failing = true
        #expect(throws: CocoaError.self) { try fixture.model.restoreBackup(plan, restoreSettings: false) }
        #expect(fixture.model.profiles.isEmpty)
        #expect(try fixture.model.credentialVault.credentials(profileID: profile.id).isEmpty)
        #expect(try fixture.proxyRepository.load() == [originalProxy])
    }

    @Test
    func rollbackFailureIsReportedWithBothErrorsAndContinuesOtherRecovery() {
        var attempted: [Int] = []
        do {
            try StorageTransaction.perform { throw CocoaError(.fileWriteUnknown) } rollback: {
                try StorageTransaction.restoreAll([1, 2, 3]) { value in
                    attempted.append(value)
                    if value == 1 { throw CocoaError(.fileWriteNoPermission) }
                }
            }
            Issue.record("Recovery failure was hidden")
        } catch {
            #expect(error is StorageTransactionError)
            #expect(error.localizedDescription.contains("未能完整恢复"))
            #expect(attempted == [1, 2, 3])
        }
    }

    @Test
    func fullArchiveRestoresProxyPasswordAndAssociationWithoutOverwritingExisting() throws {
        let source = try RepairFixture()
        let destination = try RepairFixture()
        defer { source.cleanUp(); destination.cleanUp() }
        let proxy = SocksProxy(host: "source.test", port: 1080, username: "proxy-user", password: "proxy-secret")
        try source.model.addSocksProxy(proxy)
        try source.model.addProfile(name: "来源", homePage: BrowserProfile.defaultHomePage,
            userAgent: BrowserProfile.defaultUserAgent, color: .indigo, socksProxyNumber: 1, autofillUsername: "user", autofillPassword: "site-secret")
        try source.model.updateOrAddProxyPreset(SocksProxyPreset(name: "订阅", url: URL(string: "https://feed.test/proxies")!))
        try source.model.updateWebsiteRules([WebsiteRule(host: "example.test", balanceSelector: "#balance", balanceReadySelector: "#ready")])
        try destination.model.addSocksProxy(SocksProxy(host: "destination.test", port: 1080))
        try destination.model.addImportedProfile(BrowserProfile(name: "目标已有环境"))
        let data = try BackupService.encrypt(source.model.backupSnapshot(), password: "test password")
        let archive = try BackupService.decrypt(data, password: "test password")
        let plan = destination.model.prepareBackupRestore(archive)
        #expect(destination.model.profiles.count == 1)
        let report = try destination.model.restoreBackup(plan, restoreSettings: true)
        #expect(report.contains("已新增 1 个环境"))
        let imported = try #require(destination.model.profiles.last)
        let restoredProxy = try #require(destination.model.socksProxy(for: imported))
        #expect(restoredProxy.host == "source.test")
        #expect(restoredProxy.password == "proxy-secret")
        #expect(restoredProxy.id != proxy.id)
        #expect(try destination.model.credentialVault.credentials(profileID: imported.id).first?.password == "site-secret")
        #expect(destination.model.proxyPresets.count == 1)
        #expect(destination.model.globalScriptSettings.siteRules?.first?.balanceSelector == "#balance")
        #expect(destination.model.profiles.first?.name == "目标已有环境")
    }

    @Test
    func incompleteProxyStoreCannotProduceAPartialFullBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid json".utf8).write(to: directory.appending(path: "proxies.json"))
        let fixture = try RepairFixture(directory: directory)
        defer { fixture.cleanUp() }
        #expect(!fixture.model.isBackupStoreAvailable)
        #expect(throws: BackupError.incompleteStore) { try fixture.model.backupSnapshot() }
        try Data("[]".utf8).write(to: directory.appending(path: "proxies.json"), options: .atomic)
        fixture.model.retryLoadingBackupStores()
        #expect(fixture.model.isBackupStoreAvailable)
    }

    @Test
    func missingLegacyProxyIsBlockedInsteadOfUsingDestinationsNumber() throws {
        let fixture = try RepairFixture()
        defer { fixture.cleanUp() }
        try fixture.model.addSocksProxy(SocksProxy(host: "unrelated.test", port: 1080))
        let archive = BackupArchive(profiles: [BrowserProfile(name: "旧备份", socksProxyNumber: 1)], credentials: [])
        let plan = fixture.model.prepareBackupRestore(archive)
        _ = try fixture.model.restoreBackup(plan, restoreSettings: false)
        #expect(fixture.model.profiles.first?.socksProxyNumber == nil)
        #expect(fixture.model.profiles.first?.unresolvedProxyNumber == 1)
        #expect(fixture.model.socksProxy(for: fixture.model.profiles[0]) == nil)
    }

    @Test
    func oversizedBackupIsRejectedBeforeParsingAndBackgroundCancellationIsObserved() async throws {
        #expect(throws: BackupError.fileTooLarge) { try BackupService.validateBackupData(Data(repeating: 0, count: BackupService.maximumFileSize + 1)) }
        let task = Task {
            try await BackupService.background {
                try Task.checkCancellation()
                return try BackupService.encrypt(BackupArchive(profiles: [], credentials: []), password: "test password")
            }
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled crypto completed") }
        catch { #expect(error is CancellationError) }
    }

    @Test
    func latestFailureWinsAcrossAvailabilityAndDeletingProxyCanBeUndone() throws {
        let fixture = try RepairFixture()
        defer { fixture.cleanUp() }
        var proxy = SocksProxy(host: "one.test", port: 1080, password: "secret", latencyMilliseconds: 10, status: .available, lastCheckedAt: .now.addingTimeInterval(-60))
        proxy.lastLatencyCheck = .init(proxyID: proxy.id, status: .unavailable, latencyMilliseconds: 8000, checkedAt: .now, message: "offline")
        try fixture.model.addSocksProxy(proxy)
        #expect(!fixture.model.socksProxies[0].isAvailable)
        #expect(fixture.model.socksProxies[0].latestLatency == nil)
        try fixture.model.addProfile(name: "使用代理", homePage: BrowserProfile.defaultHomePage, userAgent: BrowserProfile.defaultUserAgent, color: .indigo, socksProxyNumber: 1)
        try fixture.model.deleteSocksProxy(proxy)
        #expect(fixture.model.profiles[0].unresolvedProxyNumber == 1)
        try fixture.model.undoProxyDeletion()
        #expect(fixture.model.profiles[0].socksProxyNumber == 1)
        #expect(fixture.model.socksProxies[0].password == "secret")
    }

    @Test
    func pausedRunLocksMutationAndResumesPersistedQueueOnNewModel() async throws {
        let fixture = try RepairFixture()
        defer { fixture.cleanUp() }
        try fixture.model.addImportedProfiles([BrowserProfile(name: "一", groupName: "测试"), BrowserProfile(name: "二", groupName: "测试")])
        let group = try #require(fixture.model.profileGroups.first)
        let run = fixture.model.groupRun(for: group)
        run.start(); run.skip(); run.pause()
        #expect(throws: ProfileError.taskInProgress) { try fixture.model.updateProfile(fixture.model.profiles[1]) }
        await fixture.model.deleteProfile(fixture.model.profiles[1])
        #expect(fixture.model.profiles.count == 2)
        #expect(fixture.model.presentedError?.message == ProfileError.taskInProgress.localizedDescription)
        let restarted = AppModel(profileRepository: fixture.repository, credentialVault: CredentialVault(inMemory: true), socksProxyRepository: fixture.proxyRepository, userDefaults: fixture.defaults)
        let restored = restarted.groupRun(for: try #require(restarted.profileGroups.first))
        restored.start()
        #expect(restored.queue.index == 1)
        #expect(restored.queue.skippedCount == 1)
        restored.stop(); run.stop()
        #expect(!restarted.groupRunHistory.isEmpty)
        #expect(restarted.reservedProfileIDs.isEmpty)
    }

    @Test
    func previewRefusesToOverwriteChangesMadeAfterPreview() throws {
        let fixture = try RepairFixture()
        defer { fixture.cleanUp() }
        let archive = BackupArchive(profiles: [BrowserProfile(name: "导入")], credentials: [])
        let plan = fixture.model.prepareBackupRestore(archive)
        try fixture.model.addSocksProxy(SocksProxy(host: "new.test", port: 1080))
        #expect(throws: BackupError.stateChanged) { try fixture.model.restoreBackup(plan, restoreSettings: false) }
        #expect(fixture.model.profiles.isEmpty)
    }

    @Test
    func routineEntryIsDirectUntilItsNetworkPathChanges() throws {
        let fixture = try RepairFixture()
        defer { fixture.cleanUp() }
        var profile = BrowserProfile(name: "环境")
        #expect(fixture.model.needsEntryConfirmation(for: profile))
        fixture.model.confirmEntry(for: profile)
        #expect(!fixture.model.needsEntryConfirmation(for: profile))
        profile.name = "改名"
        #expect(!fixture.model.needsEntryConfirmation(for: profile))
        profile.socksProxyNumber = 99
        #expect(fixture.model.needsEntryConfirmation(for: profile))
    }

    @Test
    func proxyImportReportsUpdatesDuplicatesAndInvalidLinesAndRoundTrips() throws {
        let fixture = try RepairFixture()
        defer { fixture.cleanUp() }
        try fixture.model.addSocksProxy(SocksProxy(host: "one.test", port: 1080, password: "old"))
        let report = try fixture.model.importSocksProxies(text: "socks5://:new@one.test:1080\nsocks5://two.test:1080\nsocks5://two.test:1080\ninvalid\n")
        #expect(report.added == 1)
        #expect(report.updated == 1)
        #expect(report.duplicates == 1)
        #expect(report.invalid.map(\.line) == [4])
        let exported = try SocksProxyExport.text(for: fixture.model.socksProxies)
        let again = try fixture.model.importSocksProxies(text: exported)
        #expect(again.added == 0 && again.updated == 0 && again.duplicates == 2)
    }

    @Test
    func orphanSelectionExcludesCurrentAndLeasedStores() {
        let ids = (0..<3).map { _ in UUID() }
        #expect(WebsiteDataStoreManager.orphanIDs(all: Set(ids), referenced: [ids[0]], leased: [ids[1]]) == [ids[2]])
    }
}

@MainActor
private struct RepairFixture {
    let directory: URL
    let repository: ProfileRepository
    let proxyRepository: SocksProxyRepository
    let defaults: UserDefaults
    let suite: String
    let model: AppModel
    init(directory: URL? = nil, repository: ProfileRepository? = nil, vault: CredentialVault = CredentialVault(inMemory: true), credentialStore: SocksProxyCredentialStore = SocksProxyCredentialStore(inMemory: true)) throws {
        let path = directory ?? FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        self.directory = path
        let profiles = repository ?? ProfileRepository(fileURL: path.appending(path: "profiles.json"))
        self.repository = profiles
        self.proxyRepository = SocksProxyRepository(fileURL: path.appending(path: "proxies.json"), credentialStore: credentialStore)
        self.suite = "Cweb.RepairTests." + UUID().uuidString
        self.defaults = try #require(UserDefaults(suiteName: suite))
        self.model = AppModel(profileRepository: profiles, credentialVault: vault, socksProxyRepository: proxyRepository, userDefaults: defaults)
    }
    func cleanUp() { model.activeGroupRun?.stop(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
}

private final class MutationFault: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var failAt: Int?
    func arm(failAt: Int) { lock.lock(); defer { lock.unlock() }; self.failAt = failAt; count = 0 }
    func check() throws {
        lock.lock(); defer { lock.unlock() }
        count += 1
        if count == failAt { failAt = nil; throw CocoaError(.fileWriteUnknown) }
    }
}
