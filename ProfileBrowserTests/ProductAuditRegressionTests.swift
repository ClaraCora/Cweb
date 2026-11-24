import Foundation
import Observation
import os
import Testing
@testable import ProfileBrowser

@MainActor
@Suite(.serialized)
struct ProductAuditRegressionTests {
    @Test func cachedListProjectionsStillNotifyObserversAndShowEdits() throws {
        let profile = BrowserProfile(name: "Before")
        let fixture = try AuditFixture(profiles: [profile]); defer { fixture.cleanUp() }
        let model = fixture.model
        _ = model.profileGroups
        _ = model.rankedSocksProxies

        let groupsChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = model.profileGroups } onChange: { groupsChanged.withLock { $0 = true } }
        var edited = try #require(model.profiles.first)
        edited.name = "After"
        try model.updateProfile(edited)
        #expect(groupsChanged.withLock { $0 })
        #expect(model.profileGroups.first?.profiles.first?.name == "After")

        let proxiesChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = model.rankedSocksProxies } onChange: { proxiesChanged.withLock { $0 = true } }
        let proxy = SocksProxy(host: "new.example.invalid", port: 1080)
        try model.addSocksProxy(proxy)
        #expect(proxiesChanged.withLock { $0 })
        #expect(model.socksProxy(forDisplayNumber: 1)?.id == proxy.id)
    }

    @Test func completionChangesNotifyTheProfileList() throws {
        let profile = BrowserProfile(name: "Observable completion")
        let fixture = try AuditFixture(profiles: [profile]); defer { fixture.cleanUp() }
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = fixture.model.shouldRunAutomation(for: profile.id)
        } onChange: {
            changed.withLock { $0 = true }
        }
        fixture.model.recordAutomationSuccess(for: profile.id)
        #expect(changed.withLock { $0 })
        #expect(!fixture.model.shouldRunAutomation(for: profile.id))
    }
    @Test func changingOriginInvalidatesMoneyAndDailyCompletion() throws {
        var profile = BrowserProfile(name: "A", homePage: URL(string: "https://a.example.invalid")!, cachedBalance: "$12.50")
        profile.balanceSourceVerified = true
        let fixture = try AuditFixture(profiles: [profile]); defer { fixture.cleanUp() }
        let model = fixture.model
        model.recordAutomationSuccess(for: profile.id)
        let previousKey = model.automationCompletionKey(for: profile.id)
        var edited = try #require(model.profiles.first)
        edited.homePage = URL(string: "https://b.example.invalid")!
        try model.updateProfile(edited)
        #expect(model.profiles.first?.cachedBalance == nil)
        #expect(model.profiles.first?.balanceSourceVerified == nil)
        #expect(model.shouldRunAutomation(for: profile.id))
        #expect(model.automationCompletionKey(for: profile.id) != previousKey)
    }

    @Test func sameOriginPathEditKeepsAccountStateAndExplicitResetInvalidatesIt() throws {
        let profile = BrowserProfile(name: "A", homePage: URL(string: "https://a.example.invalid/console")!, cachedBalance: "$12.50")
        let fixture = try AuditFixture(profiles: [profile]); defer { fixture.cleanUp() }
        fixture.model.recordAutomationSuccess(for: profile.id)
        var edited = try #require(fixture.model.profiles.first)
        edited.homePage = URL(string: "https://a.example.invalid/dashboard")!
        try fixture.model.updateProfile(edited)
        #expect(fixture.model.profiles.first?.cachedBalance == "$12.50")
        #expect(!fixture.model.shouldRunAutomation(for: profile.id))
        let key = fixture.model.automationCompletionKey(for: profile.id)
        try fixture.model.resetAccountState(for: edited)
        #expect(fixture.model.shouldRunAutomation(for: profile.id))
        #expect(fixture.model.automationCompletionKey(for: profile.id) != key)
    }

    @Test func duplicateDoesNotInheritAccountResults() throws {
        let profile = BrowserProfile(name: "A", cachedBalance: "$12.50")
        let fixture = try AuditFixture(profiles: [profile]); defer { fixture.cleanUp() }
        fixture.model.recordAutomationSuccess(for: profile.id)
        try fixture.model.duplicateProfile(try #require(fixture.model.profiles.first))
        let duplicate = try #require(fixture.model.profiles.last)
        #expect(duplicate.websiteDataStoreID != profile.websiteDataStoreID)
        #expect(duplicate.cachedBalance == nil)
        #expect(fixture.model.shouldRunAutomation(for: duplicate.id))
    }

    @Test func legacyDailyRecordsStayReadableButCannotSurviveAnAccountReset() throws {
        let profile = BrowserProfile(name: "Legacy")
        let fixture = try AuditFixture(profiles: [profile]); defer { fixture.cleanUp() }
        fixture.defaults.set(try JSONEncoder().encode([profile.id.uuidString: AutomationCompletionStore.dayKey(.now)]), forKey: AppSettings.checkInRecordsKey)
        let reloaded = fixture.reload()
        #expect(!reloaded.shouldRunAutomation(for: profile.id))
        try reloaded.resetAccountState(for: try #require(reloaded.profiles.first))
        #expect(reloaded.shouldRunAutomation(for: profile.id))
    }

    @Test func fixedBindingSurvivesSortingAndUnrelatedDeletionAndRestart() throws {
        let slow = SocksProxy(host: "slow.example.invalid", port: 1080, latencyMilliseconds: 200, status: .available)
        let fast = SocksProxy(host: "fast.example.invalid", port: 1080, latencyMilliseconds: 10, status: .available)
        let fixed = BrowserProfile(name: "Fixed", socksProxyNumber: 1, fixedProxyID: fast.id)
        let fixture = try AuditFixture(profiles: [fixed], proxies: [slow, fast]); defer { fixture.cleanUp() }
        var settings = fixture.model.socksProxyValidationSettings; settings.sortMode = .inputOrder
        try fixture.model.updateSocksProxyValidationSettings(settings)
        #expect(fixture.model.socksProxy(for: fixed)?.id == fast.id)
        #expect(fixture.model.proxyNumber(for: fixed) == 2)
        try fixture.model.deleteSocksProxy(slow)
        let stored = try #require(fixture.model.profiles.first)
        #expect(stored.unresolvedProxyNumber == nil)
        #expect(fixture.model.socksProxy(for: stored)?.id == fast.id)
        #expect(fixture.reload().socksProxy(for: stored)?.id == fast.id)
        try fixture.model.deleteSocksProxy(fast)
        #expect(fixture.model.profiles.first?.unresolvedProxyNumber != nil)
        #expect(fixture.model.socksProxy(for: try #require(fixture.model.profiles.first)) == nil)
    }

    @Test func groupRequiresExplicitConfirmationAfterRankedExitChanges() throws {
        let slow = SocksProxy(host: "slow.example.invalid", port: 1080, latencyMilliseconds: 200, status: .available)
        let fast = SocksProxy(host: "fast.example.invalid", port: 1080, latencyMilliseconds: 10, status: .available)
        let profile = BrowserProfile(name: "Ranked", socksProxyNumber: 1)
        let fixture = try AuditFixture(profiles: [profile], proxies: [slow, fast]); defer { fixture.cleanUp() }
        fixture.model.confirmEntry(for: profile)
        var settings = fixture.model.socksProxyValidationSettings; settings.sortMode = .inputOrder
        try fixture.model.updateSocksProxyValidationSettings(settings)
        let run = GroupCheckInController(groupName: "Test", profiles: [profile], model: fixture.model)
        run.start()
        #expect(run.awaitsEntryConfirmation)
        #expect(run.session == nil)
        run.confirmAndStart()
        #expect(run.session?.socksProxy?.id == slow.id)
        run.stop()
    }

    @Test func missingProxyIsCaughtBeforeStartingAGroup() throws {
        let profile = BrowserProfile(name: "Missing", socksProxyNumber: 99)
        let fixture = try AuditFixture(profiles: [profile]); defer { fixture.cleanUp() }
        let run = GroupCheckInController(groupName: "Test", profiles: [profile], model: fixture.model)
        run.start()
        #expect(!run.preflightIssues.isEmpty)
        #expect(!run.hasStarted)
        #expect(run.session == nil)
    }

    @Test func unavailableEnvironmentsCanBeExcludedAndStayExcludedAfterRestore() throws {
        let missing = BrowserProfile(name: "Missing", socksProxyNumber: 99)
        let available = BrowserProfile(name: "Available")
        let fixture = try AuditFixture(profiles: [available, missing]); defer { fixture.cleanUp() }
        let run = GroupCheckInController(groupName: "Test", profiles: fixture.model.profiles, model: fixture.model)
        run.start()
        run.excludeUnavailableAndStart()
        #expect(run.session?.profile.id == available.id)
        let record = run.record
        run.stop()
        let restored = GroupCheckInController(groupName: "Test", profiles: fixture.model.profiles, model: fixture.model, restoring: record)
        #expect(restored.preflightIssues.isEmpty)
        restored.start()
        restored.skip()
        #expect(restored.queue.outcomes[missing.id] == .failed)
        #expect(restored.queue.failedCount == 1)
        #expect(restored.queue.isFinished)
    }

    @Test func fixedAndRankedCollisionAfterSortingIsBlocked() throws {
        let slow = SocksProxy(host: "slow.example.invalid", port: 1080, latencyMilliseconds: 200, status: .available)
        let fast = SocksProxy(host: "fast.example.invalid", port: 1080, latencyMilliseconds: 10, status: .available)
        let fixed = BrowserProfile(name: "Fixed", socksProxyNumber: 1, fixedProxyID: fast.id)
        let ranked = BrowserProfile(name: "Ranked", socksProxyNumber: 2)
        let fixture = try AuditFixture(profiles: [fixed, ranked], proxies: [slow, fast]); defer { fixture.cleanUp() }
        var settings = fixture.model.socksProxyValidationSettings; settings.sortMode = .inputOrder
        try fixture.model.updateSocksProxyValidationSettings(settings)
        #expect(fixture.model.entryPreflightIssue(for: fixed) != nil)
        #expect(fixture.model.entryPreflightIssue(for: ranked) != nil)
        let reloaded = fixture.reload()
        #expect(reloaded.profiles.first?.fixedProxyID == fast.id)
        #expect(reloaded.entryPreflightIssues(for: reloaded.profiles).count == 2)
    }

    @Test func fixedBindingRoundTripsEncryptedBackup() throws {
        let proxy = SocksProxy(host: "proxy.example.invalid", port: 1080, username: "account", password: "synthetic-password")
        let profile = BrowserProfile(name: "Fixed", socksProxyNumber: 1, fixedProxyID: proxy.id)
        let source = try AuditFixture(profiles: [profile], proxies: [proxy]); defer { source.cleanUp() }
        let data = try BackupService.encrypt(source.model.backupSnapshot(), password: "synthetic-backup-password")
        let archive = try BackupService.decrypt(data, password: "synthetic-backup-password")
        let destination = try AuditFixture(profiles: []); defer { destination.cleanUp() }
        let plan = destination.model.prepareBackupRestore(archive)
        _ = try destination.model.restoreBackup(plan, restoreSettings: true)
        let restored = try #require(destination.model.profiles.first)
        #expect(restored.id != profile.id)
        #expect(restored.fixedProxyID != nil)
        #expect(restored.unresolvedProxyNumber == nil)
        #expect(destination.model.socksProxy(for: restored)?.host == proxy.host)
        #expect(destination.model.socksProxy(for: restored)?.password == "synthetic-password")
    }

    @Test func cancelledBalanceOnlyRunIsNotCountedAsSuccess() async throws {
        let profile = BrowserProfile(name: "Balance")
        let fixture = try AuditFixture(profiles: [profile]); defer { fixture.cleanUp() }
        fixture.model.confirmEntry(for: profile)
        let run = GroupCheckInController(groupName: "Test", profiles: fixture.model.profiles, model: fixture.model,
            refreshBalance: { _ in .cancelled }, mode: .balanceOnly)
        run.start()
        for _ in 0..<100 where run.isRefreshingBalance { try await Task.sleep(for: .milliseconds(5)) }
        #expect(run.queue.completedCount == 0)
        #expect(run.queue.outcomes[profile.id] == .failed)
        #expect(run.record.balanceRetryProfileIDs == [profile.id])
    }

    @Test func timeoutAdvancesButCaptchaWaitsForTheUser() async throws {
        let home = URL(string: "https://timer.example.invalid")!
        let fixture = try AuditFixture(profiles: [BrowserProfile(name: "One", homePage: home), BrowserProfile(name: "Two", homePage: home)])
        defer { fixture.cleanUp() }
        let limit = 90
        var rule = WebsiteRule(host: "timer.example.invalid")
        rule.environmentTimeoutSeconds = limit
        try fixture.model.updateWebsiteRules([rule])
        for profile in fixture.model.profiles { fixture.model.confirmEntry(for: profile) }
        let run = GroupCheckInController(groupName: "Test", profiles: fixture.model.profiles, model: fixture.model)
        run.start()
        defer { run.stop() }
        let first = try #require(run.session)
        first.configureAutomation(settings: run.settings, shouldRunToday: true, completionKey: "timeout-test")
        first.receiveAutomationMessage(type: "captcha", message: "请验证")
        let lastCaptchaPoll = Date().addingTimeInterval(TimeInterval(limit * 3))
        await run.recheck(now: lastCaptchaPoll)
        #expect(run.queue.index == 0)
        // Only the user's native “继续检测” action can release a CAPTCHA pause.
        first.receiveAutomationMessage(type: "resume", message: "")
        #expect(first.automationState == .captcha)
        await first.resumeAutomation()
        #expect(first.automationState == .running)
        await run.recheck(now: lastCaptchaPoll.addingTimeInterval(TimeInterval(limit - 1)))
        #expect(run.queue.index == 0)
        await run.recheck(now: lastCaptchaPoll.addingTimeInterval(TimeInterval(limit)))
        #expect(run.queue.outcomes[first.profile.id] == .failed)
        #expect(run.queue.index == 1)
    }

    @Test func successfulCheckInRetainsSeparateBalanceFailureAndNameSnapshot() async throws {
        let fixture = try AuditFixture(profiles: [BrowserProfile(name: "Original")]); defer { fixture.cleanUp() }
        for profile in fixture.model.profiles { fixture.model.confirmEntry(for: profile) }
        let run = GroupCheckInController(groupName: "Test", profiles: fixture.model.profiles, model: fixture.model,
            refreshBalance: { _ in .failed("登录过期") })
        run.start()
        let id = try #require(run.session?.profile.id)
        run.receive(id, AutomationEvent(kind: .success, message: "签到成功"))
        for _ in 0..<100 where run.isRefreshingBalance { try await Task.sleep(for: .milliseconds(5)) }
        #expect(run.queue.outcomes[id] == .completed)
        #expect(run.record.details?[id]?.balance == .failed("登录过期"))
        #expect(run.record.details?[id]?.name == "Original")
        #expect(run.record.balanceRetryProfileIDs == [id])
        #expect(run.record.retryProfileIDs.isEmpty)
        let restored = try JSONDecoder().decode(GroupRunRecord.self, from: JSONEncoder().encode(run.record))
        #expect(restored.details?[id]?.balance == .failed("登录过期"))
    }

    @Test func malformedCSSIsRejectedAndSelectorsAreTrimmed() async throws {
        let fixture = try AuditFixture(profiles: []); defer { fixture.cleanUp() }
        var rule = WebsiteRule(host: "example.invalid"); rule.balanceSelector = "["
        #expect(throws: WebsiteRuleError.self) { try fixture.model.updateWebsiteRules([rule]) }
        rule.balanceSelector = " .balance "
        try fixture.model.updateWebsiteRules([rule])
        #expect(fixture.model.globalScriptSettings.siteRules?.first?.balanceSelector == ".balance")
        rule.balanceSelector = ":this-is-not-a-valid-pseudo"
        do { try await WebsiteRuleValidator.validate([rule]); Issue.record("Invalid CSS was accepted") }
        catch { #expect(error is WebsiteRuleError) }
    }

    @Test func exportCanExcludeCredentials() throws {
        let proxy = SocksProxy(host: "proxy.example.invalid", port: 1080, username: "account", password: "secret")
        let result = try SocksProxyExport.text(for: [proxy], includeCredentials: false)
        #expect(!result.contains("account")); #expect(!result.contains("secret"))
        let parsed = try SocksProxy(urlString: result.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(parsed.username == nil); #expect(parsed.password == nil)
    }

    @Test func nativeDeadlineAndCancellationDoNotAwaitAStalledOperation() async throws {
        let start = ContinuousClock.now
        do {
            _ = try await BoundedOperation.run(timeout: .milliseconds(50)) {
                try? await Task.sleep(for: .seconds(2))
                return 1
            }
            Issue.record("Deadline was ignored")
        } catch { #expect(ContinuousClock.now - start < .seconds(1)) }
        let task = Task {
            try await BoundedOperation.run(timeout: .seconds(10)) {
                try? await Task.sleep(for: .seconds(2)); return 1
            }
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation was ignored") }
        catch { #expect(error is CancellationError) }
    }
}

@MainActor
private struct AuditFixture {
    let directory: URL
    let suite: String
    let defaults: UserDefaults
    let repository: ProfileRepository
    let proxyRepository: SocksProxyRepository
    let model: AppModel
    init(profiles: [BrowserProfile], proxies: [SocksProxy] = []) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "CwebAudit-" + UUID().uuidString)
        suite = "Cweb.Audit." + UUID().uuidString
        defaults = try #require(UserDefaults(suiteName: suite))
        repository = ProfileRepository(fileURL: directory.appending(path: "profiles.json"))
        proxyRepository = SocksProxyRepository(fileURL: directory.appending(path: "proxies.json"), credentialStore: SocksProxyCredentialStore(inMemory: true))
        try repository.save(profiles); try proxyRepository.save(proxies)
        model = AppModel(profileRepository: repository, credentialVault: CredentialVault(inMemory: true), socksProxyRepository: proxyRepository, userDefaults: defaults)
    }
    func reload() -> AppModel {
        AppModel(profileRepository: repository, credentialVault: CredentialVault(inMemory: true), socksProxyRepository: proxyRepository, userDefaults: defaults)
    }
    func cleanUp() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
}
