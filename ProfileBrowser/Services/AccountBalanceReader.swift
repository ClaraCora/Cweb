import Foundation

/// Reloads after confirmed check-in instead of waiting for an old document's
/// balance to change. The whole operation is bounded, including WebKit calls.
@MainActor
enum AccountBalanceReader {
    static func read(
        afterCheckIn: Bool,
        reloadPage: @escaping @MainActor () async throws -> Void,
        readValue: @escaping @MainActor () async throws -> String?,
        wait: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) },
        timeout: Duration? = nil
    ) async throws -> String? {
        try Task.checkCancellation()
        let completion = BalanceReadCompletion()
        let operation = Task { @MainActor in
            do {
                try Task.checkCancellation()
                if afterCheckIn { try await reloadPage() }
                try Task.checkCancellation()
                let value = try await readDocument(afterCheckIn: afterCheckIn, readValue: readValue, wait: wait)
                completion.result = .success(value)
            } catch {
                completion.result = .failure(error)
            }
        }
        defer { operation.cancel() }

        let deadline = ContinuousClock.now.advanced(by: timeout ?? .seconds(afterCheckIn ? 5 : 12))
        while true {
            try Task.checkCancellation()
            if let result = completion.result { return try result.get() }
            if ContinuousClock.now >= deadline { return nil }
            // Do not await the child task on timeout: a stalled WebKit call
            // may ignore cancellation. Its late result must never block the queue.
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func readDocument(
        afterCheckIn: Bool,
        readValue: @MainActor () async throws -> String?,
        wait: @MainActor () async throws -> Void
    ) async throws -> String? {
        let attempts = afterCheckIn ? 20 : 48
        var latestValue: String?
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
                consecutiveMatches = value == latestValue ? consecutiveMatches + 1 : 1
                latestValue = value
                // This is a fresh document. A stable balance is valid even if
                // today's check-in did not change it; no extra grace is needed.
                if consecutiveMatches >= 2 { return value }
            } else {
                consecutiveMatches = 0
            }
            if attempt + 1 < attempts { try await wait() }
        }
        return nil
    }
}

@MainActor
private final class BalanceReadCompletion {
    var result: Result<String?, Error>?
}
