import Foundation
import Testing
@testable import ProfileBrowser

struct GroupCheckInTests {
    @Test
    func queueKeepsOrderAndIgnoresLateOrDuplicateCompletion() {
        let ids = (0..<3).map { _ in UUID() }
        var queue = GroupCheckInQueue(profileIDs: ids)
        #expect(queue.currentProfileID == ids[0])
        // Keep mutations outside #expect's diagnostic closures, which receive immutable values.
        let acceptedOutOfOrder = queue.finish(ids[1], outcome: .completed)
        #expect(!acceptedOutOfOrder)
        let acceptedFirst = queue.finish(ids[0], outcome: .completed)
        #expect(acceptedFirst)
        let acceptedDuplicate = queue.finish(ids[0], outcome: .completed)
        #expect(!acceptedDuplicate)
        #expect(queue.currentProfileID == ids[1])
        let acceptedAlreadyCompleted = queue.finish(ids[1], outcome: .alreadyCompleted)
        #expect(acceptedAlreadyCompleted)
        let acceptedSkip = queue.finish(ids[2], outcome: .skipped)
        #expect(acceptedSkip)
        #expect(queue.isFinished)
        #expect(queue.completedCount == 2)
        #expect(queue.skippedCount == 1)
        #expect(queue.currentProfileID == nil)
    }

    @Test
    func stoppedQueueCannotAdvanceAndDuplicateProfilesAreRemoved() {
        let id = UUID()
        var queue = GroupCheckInQueue(profileIDs: [id, id, UUID()])
        #expect(queue.profileIDs.count == 2)
        queue.stop()
        let acceptedAfterStop = queue.finish(id, outcome: .completed)
        #expect(!acceptedAfterStop)
        #expect(queue.completedCount == 0)
        #expect(!queue.isFinished)
    }

    @Test
    @MainActor
    func controllerWaitsForSuccessAndPauseAndStopBlockAdvancement() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "Cweb.GroupCheckInTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = ProfileRepository(fileURL: directory.appending(path: "profiles.json"))
        try repository.save([])
        let model = AppModel(
            profileRepository: repository,
            socksProxyRepository: SocksProxyRepository(
                fileURL: directory.appending(path: "proxies.json"),
                credentialStore: SocksProxyCredentialStore(inMemory: true)
            ),
            userDefaults: defaults
        )
        let profiles = (1...3).map { BrowserProfile(name: "环境 \($0)") }
        model.recordAutomationSuccess(for: profiles[0].id)
        let controller = GroupCheckInController(groupName: "测试", profiles: profiles, model: model, refreshBalance: { _ in })
        #expect(controller.session == nil) // Creating a run never starts browsing.
        controller.start()
        #expect(controller.queue.currentProfileID == profiles[1].id)
        #expect(controller.queue.outcomes[profiles[0].id] == .alreadyCompleted)
        for kind in [AutomationEventKind.captcha, .noButton, .error, .resume] {
            controller.receive(profiles[1].id, AutomationEvent(kind: kind, message: ""))
            #expect(controller.queue.currentProfileID == profiles[1].id)
        }
        controller.pause()
        controller.receive(profiles[1].id, AutomationEvent(kind: .success, message: ""))
        #expect(controller.queue.currentProfileID == profiles[1].id)
        controller.start()
        controller.receive(profiles[1].id, AutomationEvent(kind: .success, message: ""))
        await waitForBalanceRefresh(controller)
        #expect(controller.queue.currentProfileID == profiles[2].id)
        controller.receive(profiles[1].id, AutomationEvent(kind: .success, message: "late"))
        #expect(controller.queue.currentProfileID == profiles[2].id)
        controller.stop()
        controller.receive(profiles[2].id, AutomationEvent(kind: .success, message: "late"))
        #expect(controller.queue.completedCount == 2)
        #expect(controller.session == nil)
        #expect(!model.globalScriptSettings.enabled)
    }

    @Test
    @MainActor
    func successKeepsPageOpenUntilBalanceRefreshAndPauseDefersAdvancement() async throws {
        let fixture = try GroupRunFixture()
        defer { fixture.cleanUp() }
        let gate = BalanceRefreshGate()
        let controller = GroupCheckInController(
            groupName: "测试", profiles: fixture.profiles, model: fixture.model,
            refreshBalance: { _ in await gate.wait() }
        )
        controller.start()
        let firstSession = try #require(controller.session)
        let firstID = fixture.profiles[0].id
        fixture.model.recordAutomationSuccess(for: firstID)
        controller.receive(firstID, AutomationEvent(kind: .success, message: "成功"))
        await gate.waitUntilStarted()
        #expect(controller.isRefreshingBalance)
        #expect(controller.session === firstSession)
        #expect(!firstSession.isClosed)
        #expect(!controller.canSkip)
        controller.receive(firstID, AutomationEvent(kind: .success, message: "重复"))
        await controller.recheck()
        controller.skip()
        #expect(gate.callCount == 1)
        #expect(controller.queue.completedCount == 0)

        controller.pause()
        gate.release()
        await waitForBalanceRefresh(controller)
        #expect(controller.isPaused)
        #expect(controller.session === firstSession)
        #expect(!firstSession.isClosed)
        controller.start()
        #expect(firstSession.isClosed)
        #expect(controller.queue.currentProfileID == fixture.profiles[1].id)
        #expect(controller.queue.completedCount == 1)
        controller.stop()
    }

    @Test
    @MainActor
    func stoppingWhileRefreshingRejectsLateBalanceCompletion() async throws {
        let fixture = try GroupRunFixture()
        defer { fixture.cleanUp() }
        let gate = BalanceRefreshGate()
        let controller = GroupCheckInController(
            groupName: "测试", profiles: fixture.profiles, model: fixture.model,
            refreshBalance: { _ in await gate.wait() }
        )
        controller.start()
        let session = try #require(controller.session)
        controller.receive(session.profile.id, AutomationEvent(kind: .success, message: ""))
        await gate.waitUntilStarted()
        controller.stop()
        gate.release()
        // Let the suspended refresh return after the stop.
        try await Task.sleep(for: .milliseconds(20))
        #expect(session.isClosed)
        #expect(controller.session == nil)
        #expect(controller.queue.isStopped)
        #expect(controller.queue.completedCount == 0)
        #expect(!controller.isRefreshingBalance)
    }

    @Test
    @MainActor
    func completedSessionIgnoresReloadAndLateScriptMessages() async {
        let session = BrowserSession(profile: BrowserProfile(name: "环境"))
        var successes = 0
        session.configureAutomation(
            settings: GlobalScriptSettings(enabled: true, source: "", updatedAt: .now),
            shouldRunToday: true, completionKey: UUID().uuidString
        ) { event in
            if event.kind == .success { successes += 1 }
        }
        session.receiveAutomationMessage(type: "success", message: "签到成功")
        await session.resumeAutomation()
        await session.recheckAutomation()
        session.receiveAutomationMessage(type: "success", message: "刷新后重复成功")
        session.receiveAutomationMessage(type: "resume", message: "旧脚本恢复")
        session.receiveAutomationMessage(type: "error", message: "旧页面延迟错误")
        #expect(successes == 1)
        #expect(session.automationState == .success)
        #expect(session.automationMessage == "签到成功")
        session.close()
    }

    @MainActor
    private func waitForBalanceRefresh(_ controller: GroupCheckInController) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while controller.isRefreshingBalance, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(!controller.isRefreshingBalance)
    }
}

@MainActor
private final class BalanceRefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0

    func wait() async {
        callCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private struct GroupRunFixture {
    let directory: URL
    let defaults: UserDefaults
    let suite: String
    let profiles: [BrowserProfile]
    let model: AppModel

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        suite = "Cweb.GroupBalanceTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        profiles = (1...2).map { BrowserProfile(name: "环境 \($0)") }
        let repository = ProfileRepository(fileURL: directory.appending(path: "profiles.json"))
        try repository.save(profiles)
        model = AppModel(
            profileRepository: repository,
            socksProxyRepository: SocksProxyRepository(
                fileURL: directory.appending(path: "proxies.json"),
                credentialStore: SocksProxyCredentialStore(inMemory: true)
            ),
            userDefaults: defaults
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
