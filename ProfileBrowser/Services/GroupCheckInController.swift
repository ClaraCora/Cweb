import Foundation
import Observation

@MainActor
@Observable
final class GroupCheckInController {
    private let startedAt: Date
    let id: UUID
    let groupID: UUID?
    private var statuses: [UUID: String] = [:]
    let groupName: String
    let profiles: [BrowserProfile]
    let settings: GlobalScriptSettings
    private(set) var queue: GroupCheckInQueue
    private(set) var session: BrowserSession?
    private(set) var isPaused = false
    private(set) var hasStarted = false
    private(set) var isRefreshingBalance = false
    private unowned let model: AppModel
    private let refreshBalance: @MainActor (BrowserSession) async -> Void
    private var pendingCompletion: GroupCheckInQueue.Outcome?
    @ObservationIgnored private var balanceRefreshTask: Task<Void, Never>?

    init(
        groupName: String,
        profiles: [BrowserProfile],
        model: AppModel,
        refreshBalance: (@MainActor (BrowserSession) async -> Void)? = nil,
        groupID: UUID? = nil,
        restoring record: GroupRunRecord? = nil
    ) {
        self.startedAt = record?.updatedAt ?? .now
        self.id = record?.id ?? UUID()
        self.groupID = groupID ?? record?.groupID
        self.statuses = record?.statuses ?? [:]
        self.groupName = groupName
        self.profiles = profiles
        self.model = model
        self.refreshBalance = refreshBalance ?? { [unowned model] in await model.refreshBalance(for: $0, afterCheckIn: true) }
        queue = record?.queue ?? GroupCheckInQueue(profileIDs: profiles.map(\.id))
        var settings = model.globalScriptSettings
        // An explicit group run does not change automatic execution on entry.
        settings.enabled = true
        self.settings = settings
    }

    var canStart: Bool { !hasStarted || (session != nil && isPaused) }
    var canPause: Bool { session != nil && !isPaused }
    var canStop: Bool { session != nil }
    var canSkip: Bool { session != nil && pendingCompletion == nil }

    func start() {
        guard canStart else { return }
        guard Calendar.current.isDateInToday(startedAt) else { expire(); return }
        do { try model.claimGroupRun(self) } catch { model.present(error); return }
        defer { checkpoint() }
        if !hasStarted {
            hasStarted = true
            openNext()
        } else {
            isPaused = false
            if let pendingCompletion {
                if !isRefreshingBalance { finishCurrent(pendingCompletion) }
                return
            }
            if let id = queue.currentProfileID, !model.shouldRunAutomation(for: id) {
                completeAfterRefreshingBalance(.completed)
                return
            }
            if let session { Task { await session.resumeAutomation() } }
        }
    }

    func pause() {
        guard canPause, let session else { return }
        isPaused = true
        session.pauseAutomation()
        checkpoint()
    }

    func stop() {
        cancelBalanceRefresh()
        queue.stop()
        session?.close()
        session = nil
        isPaused = false
        checkpoint()
    }

    func recheck() async {
        guard Calendar.current.isDateInToday(startedAt) else { expire(); return }
        guard !isPaused, pendingCompletion == nil, let activeSession = session else { return }
        if !model.shouldRunAutomation(for: activeSession.profile.id) {
            completeAfterRefreshingBalance(.alreadyCompleted)
            return
        }
        await activeSession.recheckAutomation()
    }

    func receive(_ profileID: UUID, _ event: AutomationEvent) {
        guard !isPaused, queue.currentProfileID == profileID, pendingCompletion == nil else { return }
        statuses[profileID] = event.message
        checkpoint()
        if event.kind == .success { completeAfterRefreshingBalance(.completed) }
    }

    func skip() {
        guard canSkip else { return }
        finishCurrent(.skipped)
    }

    private func completeAfterRefreshingBalance(_ outcome: GroupCheckInQueue.Outcome) {
        guard pendingCompletion == nil, let activeSession = session else { return }
        pendingCompletion = outcome
        isRefreshingBalance = true
        balanceRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshBalance(activeSession)
            guard !Task.isCancelled, self.session === activeSession else { return }
            self.isRefreshingBalance = false
            self.balanceRefreshTask = nil
            if !self.isPaused { self.finishCurrent(outcome) }
        }
    }

    private func cancelBalanceRefresh() {
        balanceRefreshTask?.cancel()
        balanceRefreshTask = nil
        pendingCompletion = nil
        isRefreshingBalance = false
    }

    private func finishCurrent(_ outcome: GroupCheckInQueue.Outcome) {
        guard let id = queue.currentProfileID, queue.finish(id, outcome: outcome) else { return }
        cancelBalanceRefresh()
        session?.close()
        session = nil
        isPaused = false
        openNext()
        checkpoint()
    }

    private func expire() {
        stop()
        model.present(StorageTransactionError.recovery("签到任务已跨日，请重新开始本组任务以检测今天的状态。"))
    }

    private func checkpoint() {
        model.saveGroupRun(GroupRunRecord(id: id, groupID: groupID, groupName: groupName,
            queue: queue, updatedAt: .now, statuses: statuses))
    }

    private func openNext() {
        while let id = queue.currentProfileID {
            guard let profile = model.profiles.first(where: { $0.id == id }) else {
                queue.finish(id, outcome: .skipped)
                continue
            }
            if let groupID, profile.groupID != groupID {
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
