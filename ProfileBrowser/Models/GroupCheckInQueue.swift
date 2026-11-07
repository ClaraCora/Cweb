import Foundation

/// Only the active environment may advance this queue. Late or duplicate
/// messages from a previous WebPage cannot complete the next environment.
struct GroupCheckInQueue: Codable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case completed
        case alreadyCompleted
        case skipped
        case failed
        case balanceUpdated
    }

    let profileIDs: [UUID]
    private(set) var outcomes: [UUID: Outcome] = [:]
    private(set) var index = 0
    private(set) var isStopped = false

    init(profileIDs: [UUID]) {
        var seen = Set<UUID>()
        self.profileIDs = profileIDs.filter { seen.insert($0).inserted }
    }

    var currentProfileID: UUID? {
        guard !isStopped, index < profileIDs.count else { return nil }
        return profileIDs[index]
    }

    var isFinished: Bool { index == profileIDs.count }
    var completedCount: Int { outcomes.values.filter { $0 == .completed || $0 == .alreadyCompleted || $0 == .balanceUpdated }.count }
    var failedCount: Int { outcomes.values.filter { $0 == .failed }.count }
    var skippedCount: Int { outcomes.values.filter { $0 == .skipped }.count }

    @discardableResult
    mutating func finish(_ profileID: UUID, outcome: Outcome) -> Bool {
        guard currentProfileID == profileID else { return false }
        outcomes[profileID] = outcome
        index += 1
        return true
    }

    mutating func stop() { isStopped = true }
}

struct GroupRunRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let groupID: UUID?
    let groupName: String
    var queue: GroupCheckInQueue
    var updatedAt: Date
    var statuses: [UUID: String]
    var details: [UUID: GroupEnvironmentResult]? = nil
    var mode: GroupRunMode? = nil
    var excludedProfileIDs: Set<UUID>? = nil
}

enum GroupRunMode: String, Codable, Sendable { case checkIn, balanceOnly }

struct GroupEnvironmentResult: Codable, Sendable {
    var name: String
    var balance: BalanceRefreshResult?
    var message: String
    var duration: TimeInterval
}

extension GroupRunRecord {
    var retryProfileIDs: [UUID] {
        queue.profileIDs.filter { id in
            queue.outcomes[id] == .failed || queue.outcomes[id] == .skipped || queue.outcomes[id] == nil
        }
    }
    var balanceRetryProfileIDs: [UUID] {
        queue.profileIDs.filter { id in
            if case .updated = details?[id]?.balance { return false }
            return true
        }
    }
}


extension GroupCheckInQueue.Outcome {
    var title: String {
        switch self {
        case .completed: "签到完成"
        case .alreadyCompleted: "今天已完成"
        case .skipped: "已跳过"
        case .failed: "待处理"
        case .balanceUpdated: "余额已更新"
        }
    }
}
