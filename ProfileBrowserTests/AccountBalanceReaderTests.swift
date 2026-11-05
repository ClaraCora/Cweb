import Foundation
import Testing
@testable import ProfileBrowser

@MainActor
struct AccountBalanceReaderTests {
    @Test
    func successReloadsBeforeReadingAndUsesTheNewDocument() async throws {
        var reloads = 0
        var balance = "$10.00"
        var reads = 0
        let result = try await AccountBalanceReader.read(afterCheckIn: true) {
            reloads += 1
            balance = "$10.50" // This site updates its balance only on reload.
        } readValue: {
            #expect(reloads == 1)
            reads += 1
            return balance
        } wait: {}
        #expect(result == "$10.50")
        #expect(reloads == 1)
        #expect(reads == 2)
    }

    @Test
    func waitsForBalanceToRenderAfterReload() async throws {
        var reads = 0
        let result = try await AccountBalanceReader.read(afterCheckIn: true) {} readValue: {
            reads += 1
            return reads < 3 ? nil : "$11.00"
        } wait: {}
        #expect(result == "$11.00")
        #expect(reads == 4)
    }

    @Test
    func unchangedBalanceDoesNotWaitForAnIncrease() async throws {
        var waits = 0
        let result = try await AccountBalanceReader.read(afterCheckIn: true) {} readValue: {
            "$10.00"
        } wait: { waits += 1 }
        #expect(result == "$10.00")
        #expect(waits == 1)
    }

    @Test
    func unreadableBalanceDoesNotReplaceCacheWithAnEmptyValue() async throws {
        let result = try await AccountBalanceReader.read(afterCheckIn: true) {} readValue: {
            "   "
        } wait: {}
        #expect(result == nil)
    }

    @Test
    func unstableAmountIsNotPublishedAsAFreshBalance() async throws {
        var read = 0
        let value = try await AccountBalanceReader.read(afterCheckIn: true) {} readValue: {
            read += 1
            return "$" + String(read)
        } wait: {}
        #expect(value == nil)
    }

    @Test
    func entryReadReturnsImmediatelyAndRetriesTransientErrors() async throws {
        var reads = 0
        var waits = 0
        var reloads = 0
        let result = try await AccountBalanceReader.read(afterCheckIn: false) {
            reloads += 1
        } readValue: {
            reads += 1
            if reads == 1 { throw CocoaError(.fileReadUnknown) }
            return " $12.00 "
        } wait: { waits += 1 }
        #expect(result == "$12.00")
        #expect(reads == 2)
        #expect(waits == 1)
        #expect(reloads == 0)
    }

    @Test
    func cancelledRefreshDoesNotReturnTheStaleBalance() async {
        do {
            _ = try await AccountBalanceReader.read(afterCheckIn: true) {} readValue: {
                "$10.00"
            } wait: { throw CancellationError() }
            Issue.record("Cancelled balance refresh returned a value")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test
    func failedReloadDoesNotReadTheOldPage() async {
        var reads = 0
        do {
            _ = try await AccountBalanceReader.read(afterCheckIn: true) {
                throw CocoaError(.fileReadUnknown)
            } readValue: {
                reads += 1
                return "$10.00"
            }
            Issue.record("Failed reload was accepted")
        } catch {
            #expect(reads == 0)
        }
    }

    @Test(arguments: [true, false])
    func stalledWebKitOperationTimesOutEvenIfItIgnoresCancellation(stallsDuringReload: Bool) async throws {
        let gate = BalanceReloadGate()
        var reads = 0
        let startedAt = ContinuousClock.now
        let result = try await AccountBalanceReader.read(afterCheckIn: true, reloadPage: {
            if stallsDuringReload { await gate.wait() }
        }, readValue: {
            reads += 1
            if !stallsDuringReload { await gate.wait() }
            return "$10.00"
        }, timeout: .milliseconds(100))
        gate.release()
        try await Task.sleep(for: .milliseconds(25))
        #expect(result == nil)
        #expect(reads == (stallsDuringReload ? 0 : 1))
        #expect(ContinuousClock.now - startedAt < .seconds(1))
    }

    @Test
    func cancellationWhileReloadIsStalledReturnsPromptly() async throws {
        let gate = BalanceReloadGate()
        let task = Task {
            try await AccountBalanceReader.read(afterCheckIn: true) {
                await gate.wait()
            } readValue: { "$10.00" }
        }
        while !gate.isWaiting { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled reload returned a balance")
        } catch {
            #expect(error is CancellationError)
        }
        gate.release()
    }
}

@MainActor
private final class BalanceReloadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
