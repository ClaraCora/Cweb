import Foundation
import Observation

@MainActor
@Observable
final class AutomationCompletionStore {
    private let defaults: UserDefaults
    private var records: [String: String]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        records = defaults.data(forKey: AppSettings.checkInRecordsKey)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    func isCompleted(_ profile: BrowserProfile, now: Date) -> Bool {
        let record = records[profile.accountScopeKey]
            ?? ((profile.accountRevision ?? 0) == 0 ? records[profile.id.uuidString] : nil)
        return record == Self.dayKey(now)
    }

    func record(_ profile: BrowserProfile, now: Date) {
        records[profile.accountScopeKey] = Self.dayKey(now)
        records.removeValue(forKey: profile.id.uuidString)
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: AppSettings.checkInRecordsKey)
        }
    }

    static func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
