import Foundation

/// Waits for the website's asynchronous balance update after check-in. Entry
/// reads can return immediately; success reads must allow the DOM to settle.
@MainActor
enum AccountBalanceReader {
    static func read(
        afterCheckIn: Bool,
        previousBalance: String?,
        readValue: @MainActor () async throws -> String?,
        wait: @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(500)) }
    ) async throws -> String? {
        let attempts = afterCheckIn ? 13 : 24
        var latestValue: String?
        var baseline = previousBalance
        var consecutiveMatches = 0
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            let value: String?
            do {
                value = try await readValue()?.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                value = nil
            }
            try Task.checkCancellation()
            if let value, !value.isEmpty {
                if !afterCheckIn { return value }
                if baseline == nil { baseline = value }
                consecutiveMatches = value == latestValue ? consecutiveMatches + 1 : 1
                latestValue = value
                // At least 1.5 seconds for the page's update; a changed value
                // must survive two reads. Unchanged balances get the full grace.
                if attempt >= 3, value != baseline, consecutiveMatches >= 2 {
                    return value
                }
            } else {
                consecutiveMatches = 0
            }
            if attempt + 1 < attempts { try await wait() }
        }
        return latestValue
    }
}
