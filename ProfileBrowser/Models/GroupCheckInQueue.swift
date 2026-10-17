import Foundation

/// Only the active environment may advance this queue. Late or duplicate
/// messages from a previous WebPage cannot complete the next environment.
struct GroupCheckInQueue {
    enum Outcome: Equatable {
        case completed
        case alreadyCompleted
        case skipped
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
    var completedCount: Int { outcomes.values.filter { $0 != .skipped }.count }
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
