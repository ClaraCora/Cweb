import Foundation
import Observation

@MainActor
@Observable
final class GroupCheckInController: Identifiable {
    private let startedAt: Date
    let id: UUID
    let groupID: UUID?
    private var statuses: [UUID: String] = [:]
    private(set) var details: [UUID: GroupEnvironmentResult] = [:]
    let groupName: String
    let profiles: [BrowserProfile]
    let settings: GlobalScriptSettings
    let mode: GroupRunMode
    private(set) var queue: GroupCheckInQueue
    private(set) var session: BrowserSession?
    private(set) var isPaused = false
    private(set) var hasStarted = false
    private(set) var isRefreshingBalance = false
    private(set) var awaitsEntryConfirmation = false
    private unowned let model: AppModel
    private let refreshBalance: @MainActor (BrowserSession) async -> BalanceRefreshResult
    private var pendingCompletion: GroupCheckInQueue.Outcome?
    private var deadline: Date?
    private var openedAt: Date?
    private var pausedAt: Date?
    private var excludedProfileIDs: Set<UUID>
    @ObservationIgnored private var balanceRefreshTask: Task<Void, Never>?

    init(groupName: String, profiles: [BrowserProfile], model: AppModel,
         refreshBalance: (@MainActor (BrowserSession) async -> BalanceRefreshResult)? = nil,
         groupID: UUID? = nil, restoring record: GroupRunRecord? = nil,
         mode: GroupRunMode = .checkIn) {
        startedAt = record?.updatedAt ?? .now
        id = record?.id ?? UUID()
        self.groupID = groupID ?? record?.groupID
        statuses = record?.statuses ?? [:]
        details = record?.details ?? [:]
        excludedProfileIDs = record?.excludedProfileIDs ?? []
        self.groupName = groupName
        self.profiles = profiles
        self.model = model
        self.mode = record?.mode ?? mode
        let isCheckIn = (record?.mode ?? mode) == .checkIn
        self.refreshBalance = refreshBalance ?? { [unowned model] in
            await model.refreshBalance(for: $0, afterCheckIn: isCheckIn)
        }
        queue = record?.queue ?? GroupCheckInQueue(profileIDs: profiles.map(\.id))
        var settings = model.globalScriptSettings
        settings.enabled = isCheckIn
        self.settings = settings
    }

    var canStart: Bool { !hasStarted || (session != nil && isPaused) }
    var canPause: Bool { session != nil && !isPaused }
    var canStop: Bool { session != nil }
    var canSkip: Bool { session != nil && pendingCompletion == nil }
    var currentProfiles: [BrowserProfile] {
        queue.profileIDs.dropFirst(queue.index).compactMap { id in
            model.profiles.first { $0.id == id && !excludedProfileIDs.contains(id) }
        }.filter { mode == .balanceOnly || model.shouldRunAutomation(for: $0.id) }
    }
    var preflightIssues: [String] { model.entryPreflightIssues(for: currentProfiles) }
    var changedEntries: [BrowserProfile] { currentProfiles.filter { model.entryPreflightIssue(for: $0) == nil && model.needsEntryConfirmation(for: $0) } }
    var record: GroupRunRecord {
        GroupRunRecord(id: id, groupID: groupID, groupName: groupName, queue: queue,
            updatedAt: .now, statuses: statuses, details: details, mode: mode, excludedProfileIDs: excludedProfileIDs)
    }

    func excludeUnavailableAndStart() {
        for profile in currentProfiles {
            guard let issue = model.entryPreflightIssue(for: profile) else { continue }
            excludedProfileIDs.insert(profile.id)
            statuses[profile.id] = issue
        }
        confirmAndStart()
    }

    func confirmAndStart() {
        guard preflightIssues.isEmpty else { return }
        for profile in changedEntries { model.confirmEntry(for: profile) }
        awaitsEntryConfirmation = false
        start()
    }

    func start() {
        guard canStart else { return }
        guard Calendar.current.isDateInToday(startedAt) else { expire(); return }
        if !hasStarted, !preflightIssues.isEmpty || !changedEntries.isEmpty {
            awaitsEntryConfirmation = true
            return
        }
        do { try model.claimGroupRun(self) } catch { model.present(error); return }
        defer { checkpoint() }
        if !hasStarted {
            hasStarted = true
            openNext()
        } else {
            if let pausedAt, let deadline { self.deadline = deadline.addingTimeInterval(Date().timeIntervalSince(pausedAt)) }
            pausedAt = nil
            isPaused = false
            if let pendingCompletion {
                if !isRefreshingBalance { finishCurrent(pendingCompletion) }
                return
            }
            if mode == .balanceOnly { completeAfterRefreshingBalance(.balanceUpdated); return }
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
        pausedAt = .now
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

    func recheck(now: Date = .now) async {
        guard Calendar.current.isDateInToday(startedAt) else { expire(); return }
        guard !isPaused, pendingCompletion == nil, let activeSession = session else { return }
        if activeSession.automationState == .captcha {
            // Human verification has no automatic skip deadline.
            deadline = now.addingTimeInterval(waitLimit(for: activeSession.profile))
        } else if let deadline, now >= deadline {
            statuses[activeSession.profile.id] = "等待超时：请检查登录、网络或网站识别规则。"
            finishCurrent(.failed)
            return
        }
        if !model.shouldRunAutomation(for: activeSession.profile.id) {
            completeAfterRefreshingBalance(.alreadyCompleted)
            return
        }
        await activeSession.recheckAutomation()
    }

    func receive(_ profileID: UUID, _ event: AutomationEvent) {
        guard !isPaused, queue.currentProfileID == profileID, pendingCompletion == nil else { return }
        if !event.message.isEmpty {
            statuses[profileID] = event.message
        }
        checkpoint()
        if event.kind == .success { completeAfterRefreshingBalance(.completed) }
    }

    func skip() { if canSkip { finishCurrent(.skipped) } }

    private func completeAfterRefreshingBalance(_ outcome: GroupCheckInQueue.Outcome) {
        guard pendingCompletion == nil, let activeSession = session else { return }
        pendingCompletion = outcome
        isRefreshingBalance = true
        balanceRefreshTask = Task { [weak self] in
            guard let self else { return }
            // Balance-only sessions do not have a BrowserView yet when created.
            if self.mode == .balanceOnly { activeSession.start() }
            let result = await self.refreshBalance(activeSession)
            guard !Task.isCancelled, self.session === activeSession else { return }
            self.details[activeSession.profile.id]?.balance = result
            let finalOutcome: GroupCheckInQueue.Outcome
            if self.mode == .balanceOnly {
                if case .updated = result { finalOutcome = .balanceUpdated }
                else { finalOutcome = .failed }
            } else { finalOutcome = outcome }
            self.pendingCompletion = finalOutcome
            self.isRefreshingBalance = false
            self.balanceRefreshTask = nil
            self.checkpoint()
            if !self.isPaused {
                self.finishCurrent(finalOutcome)
            }
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
        details[id]?.message = statuses[id] ?? ""
        details[id]?.duration = openedAt.map { Date().timeIntervalSince($0) } ?? 0
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

    private func checkpoint() { model.saveGroupRun(record) }
    private func waitLimit(for profile: BrowserProfile) -> TimeInterval {
        TimeInterval(settings.siteRules?.first { $0.normalizedHost == profile.homePageHost }?.environmentTimeoutSeconds ?? 60)
    }

    private func openNext() {
        while let id = queue.currentProfileID {
            guard let profile = model.profiles.first(where: { $0.id == id }),
                  groupID == nil || profile.groupID == groupID else {
                queue.finish(id, outcome: .skipped)
                continue
            }
            details[id] = GroupEnvironmentResult(name: profile.name, message: "", duration: 0)
            if excludedProfileIDs.contains(id) {
                details[id]?.message = statuses[id] ?? "代理配置需要处理"
                queue.finish(id, outcome: .failed)
                continue
            }
            if mode == .checkIn, !model.shouldRunAutomation(for: id) {
                queue.finish(id, outcome: .alreadyCompleted)
                continue
            }
            session = BrowserSession(profile: profile, socksProxy: model.socksProxy(for: profile))
            openedAt = .now
            deadline = Date().addingTimeInterval(waitLimit(for: profile))
            if mode == .balanceOnly { completeAfterRefreshingBalance(.balanceUpdated) }
            return
        }
    }
}
