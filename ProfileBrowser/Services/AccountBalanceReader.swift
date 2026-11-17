import Foundation

struct AccountBalanceReading: Equatable {
    let value: String
    let sourceVerified: Bool
}

/// Reloads after confirmed check-in instead of waiting for an old document's
/// balance to change. The whole operation is bounded, including WebKit calls.
@MainActor
enum AccountBalanceReader {
    static func permitsRead(from origin: WebOrigin?, home: WebOrigin?, rules: [WebsiteRule]) -> Bool {
        guard let origin, let home else { return false }
        if origin == home { return true }
        return origin.isSecure && home.isSecure && origin.port == home.port
            && WebsiteRule.sameSite(origin.host, home.host)
            && rules.contains { $0.matches(host: home.host) && $0.matches(host: origin.host) }
    }

    static func read(
        afterCheckIn: Bool,
        reloadPage: @escaping @MainActor () async throws -> Void,
        readValue: @escaping @MainActor () async throws -> String?,
        wait: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) },
        timeout: Duration? = nil
    ) async throws -> String? {
        try await readResult(afterCheckIn: afterCheckIn, reloadPage: reloadPage, readValue: {
            guard let value = try await readValue()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }, wait: wait, timeout: timeout)
    }

    static func readResult<Value: Equatable>(
        afterCheckIn: Bool,
        reloadPage: @escaping @MainActor () async throws -> Void,
        readValue: @escaping @MainActor () async throws -> Value?,
        wait: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) },
        timeout: Duration? = nil
    ) async throws -> Value? {
        try Task.checkCancellation()
        let completion = BalanceReadCompletion<Value>()
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

    private static func readDocument<Value: Equatable>(
        afterCheckIn: Bool,
        readValue: @MainActor () async throws -> Value?,
        wait: @MainActor () async throws -> Void
    ) async throws -> Value? {
        let attempts = afterCheckIn ? 20 : 48
        var latestValue: Value?
        var consecutiveMatches = 0
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            let value: Value?
            do {
                value = try await readValue()
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as WebsiteRuleError {
                throw error
            } catch let error as BalanceReadError {
                throw error
            } catch {
                value = nil
            }
            try Task.checkCancellation()
            if let value {
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
private final class BalanceReadCompletion<Value> {
    var result: Result<Value?, Error>?
}

enum BalanceReadError: LocalizedError {
    case untrustedOrigin

    var errorDescription: String? {
        "当前页面不属于主页或已配置的同站点 HTTPS 域名，请返回账户页面后重试。"
    }
}
