import Foundation
import Observation

@MainActor @Observable
final class BalanceRefreshCoordinator {
    struct Ticket: Equatable {
        let id = UUID()
        let afterCheckIn: Bool
        let sessionID: ObjectIdentifier?
    }
    private var active: [UUID: Ticket] = [:]

    func isRefreshing(_ id: UUID) -> Bool { active[id] != nil }
    func begin(_ id: UUID, afterCheckIn: Bool, sessionID: ObjectIdentifier? = nil) -> Ticket? {
        // Coalesce normal reads; a confirmed check-in may supersede one, but
        // its fresh-document refresh must never be replaced by DOM updates.
        if let current = active[id], current.afterCheckIn || (!afterCheckIn && current.sessionID == sessionID) { return nil }
        let ticket = Ticket(afterCheckIn: afterCheckIn, sessionID: sessionID)
        active[id] = ticket
        return ticket
    }
    func contains(_ ticket: Ticket, for id: UUID) -> Bool { active[id] == ticket }
    func end(_ ticket: Ticket, for id: UUID) {
        if contains(ticket, for: id) { active.removeValue(forKey: id) }
    }
    func invalidate(_ id: UUID) { active.removeValue(forKey: id) }
}

enum BalanceRefreshResult: Codable, Equatable, Sendable {
    case updated(String)
    case failed(String)
    case cancelled

    var message: String {
        switch self {
        case .updated(let value): "余额已更新：\(value)"
        case .failed(let message): message
        case .cancelled: "余额更新已取消"
        }
    }
}
