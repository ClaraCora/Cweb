import Foundation

/// WebKit calls can outlive cancellation. Stop waiting at the native deadline
/// and discard their late result, instead of awaiting an uncooperative child.
@MainActor
enum BoundedOperation {
    static func run<Value>(timeout: Duration, operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let box = Completion<Value>()
        let task = Task { @MainActor in
            do { box.result = .success(try await operation()) }
            catch { box.result = .failure(error) }
        }
        defer { task.cancel() }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            if let result = box.result { return try result.get() }
            guard ContinuousClock.now < deadline else { throw BrowserSessionDiagnosticError(message: "操作超时，请重试。") }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
    private final class Completion<Value> { var result: Result<Value, Error>? }
}
