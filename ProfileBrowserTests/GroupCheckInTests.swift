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
    func controllerWaitsForSuccessAndPauseAndStopBlockAdvancement() throws {
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
        let controller = GroupCheckInController(groupName: "测试", profiles: profiles, model: model)
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
        #expect(controller.queue.currentProfileID == profiles[2].id)
        controller.receive(profiles[1].id, AutomationEvent(kind: .success, message: "late"))
        #expect(controller.queue.currentProfileID == profiles[2].id)
        controller.stop()
        controller.receive(profiles[2].id, AutomationEvent(kind: .success, message: "late"))
        #expect(controller.queue.completedCount == 2)
        #expect(controller.session == nil)
        #expect(!model.globalScriptSettings.enabled)
    }
}
