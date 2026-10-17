import Foundation
import Observation

@MainActor
@Observable
final class GroupCheckInController {
    let groupName: String
    let profiles: [BrowserProfile]
    let settings: GlobalScriptSettings
    private(set) var queue: GroupCheckInQueue
    private(set) var session: BrowserSession?
    private(set) var isPaused = false
    private(set) var hasStarted = false
    private let model: AppModel

    init(groupName: String, profiles: [BrowserProfile], model: AppModel) {
        self.groupName = groupName
        self.profiles = profiles
        self.model = model
        queue = GroupCheckInQueue(profileIDs: profiles.map(\.id))
        var settings = model.globalScriptSettings
        // An explicit group run does not change automatic execution on entry.
        settings.enabled = true
        self.settings = settings
    }

    var canStart: Bool { !hasStarted || (session != nil && isPaused) }
    var canPause: Bool { session != nil && !isPaused }
    var canStop: Bool { session != nil }

    func start() {
        guard canStart else { return }
        if !hasStarted {
            hasStarted = true
            openNext()
        } else {
            isPaused = false
            if let id = queue.currentProfileID, !model.shouldRunAutomation(for: id) {
                finishCurrent(.completed)
                return
            }
            if let session { Task { await session.resumeAutomation() } }
        }
    }

    func pause() {
        guard canPause, let session else { return }
        isPaused = true
        session.pauseAutomation()
    }

    func stop() {
        queue.stop()
        session?.close()
        session = nil
        isPaused = false
    }

    func recheck() async {
        guard !isPaused, let activeSession = session else { return }
        if !model.shouldRunAutomation(for: activeSession.profile.id) {
            finishCurrent(.alreadyCompleted)
            return
        }
        await activeSession.recheckAutomation()
    }

    func receive(_ profileID: UUID, _ event: AutomationEvent) {
        guard !isPaused, event.kind == .success, queue.currentProfileID == profileID else { return }
        finishCurrent(.completed)
    }

    func skip() { finishCurrent(.skipped) }

    private func finishCurrent(_ outcome: GroupCheckInQueue.Outcome) {
        guard let id = queue.currentProfileID, queue.finish(id, outcome: outcome) else { return }
        session?.close()
        session = nil
        isPaused = false
        openNext()
    }

    private func openNext() {
        while let id = queue.currentProfileID {
            guard let profile = profiles.first(where: { $0.id == id }) else {
                queue.finish(id, outcome: .skipped)
                continue
            }
            if !model.shouldRunAutomation(for: id) {
                queue.finish(id, outcome: .alreadyCompleted)
                continue
            }
            session = BrowserSession(profile: profile, socksProxy: model.socksProxy(for: profile))
            return
        }
    }
}
