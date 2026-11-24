import Foundation

/// WebKit calls can outlive cancellation. Stop waiting at the native deadline
/// and discard their late result, instead of awaiting an uncooperative child.
@MainActor
enum BoundedOperation {
    struct Timeout: LocalizedError {
        var errorDescription: String? { "操作超时，请重试。" }
    }

    static func run<Value: Sendable>(timeout: Duration, operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let (stream, completion) = AsyncThrowingStream<Value, Error>.makeStream()
        let task = Task { @MainActor in
            do {
                try Task.checkCancellation()
                completion.yield(try await operation())
                completion.finish()
            } catch { completion.finish(throwing: error) }
        }
        let timer = Task {
            try await Task.sleep(until: deadline, clock: .continuous)
            completion.finish(throwing: Timeout())
        }
        defer { task.cancel(); timer.cancel() }
        var iterator = stream.makeAsyncIterator()
        guard let value = try await iterator.next() else { throw CancellationError() }
        try Task.checkCancellation()
        return value
    }
}
