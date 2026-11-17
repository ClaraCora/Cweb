import Foundation
import Testing
@testable import ProfileBrowser

@MainActor
struct AccountBalanceReaderTests {
    @Test
    func overlappingReadsAreCoalescedAndCheckInRefreshTakesPriority() throws {
        let coordinator = BalanceRefreshCoordinator()
        let id = UUID()
        let ordinary = try #require(coordinator.begin(id, afterCheckIn: false))
        #expect(coordinator.begin(id, afterCheckIn: false) == nil)
        let checkIn = try #require(coordinator.begin(id, afterCheckIn: true))
        #expect(!coordinator.contains(ordinary, for: id))
        #expect(coordinator.begin(id, afterCheckIn: false) == nil)
        #expect(coordinator.begin(id, afterCheckIn: true) == nil)
        coordinator.end(ordinary, for: id)
        #expect(coordinator.isRefreshing(id))
        coordinator.end(checkIn, for: id)
        #expect(!coordinator.isRefreshing(id))
        #expect(coordinator.begin(id, afterCheckIn: false) != nil)
    }

    @Test
    func burstOfBalanceRequestsKeepsOnlyOnePendingRead() async throws {
        let session = BrowserSession(profile: BrowserProfile(name: "合并读取"))
        defer { session.close() }
        var iterator = session.balanceReadRequests().makeAsyncIterator()
        for _ in 0..<100 { session.requestBalanceRead() }
        #expect(await iterator.next() != nil)
        session.close()
        #expect(await iterator.next() == nil)
        session.requestBalanceRead()
        #expect(await iterator.next() == nil)
    }

    @Test
    func returningToAGroupCanSubscribeAfterThePreviousViewWasCancelled() async {
        let session = BrowserSession(profile: BrowserProfile(name: "恢复分组"))
        defer { session.close() }
        var started = false
        let previousView = Task {
            for await _ in session.balanceReadRequests() { started = true }
        }
        while !started { await Task.yield() }
        previousView.cancel()
        await previousView.value
        var iterator = session.balanceReadRequests().makeAsyncIterator()
        #expect(await iterator.next() != nil)
        session.requestBalanceRead()
        #expect(await iterator.next() != nil)
        session.close()
        #expect(await iterator.next() == nil)
    }

    @Test
    func aNewSessionReplacesAnOrdinaryReadFromThePreviousBrowser() throws {
        let coordinator = BalanceRefreshCoordinator()
        let id = UUID()
        let previous = NSObject()
        let next = NSObject()
        let old = try #require(coordinator.begin(id, afterCheckIn: false, sessionID: ObjectIdentifier(previous)))
        let current = try #require(coordinator.begin(id, afterCheckIn: false, sessionID: ObjectIdentifier(next)))
        #expect(!coordinator.contains(old, for: id))
        coordinator.end(old, for: id)
        #expect(coordinator.contains(current, for: id))
    }

    @Test
    func balanceRedirectRequiresAnExplicitRuleAndSecureSameSiteOrigin() {
        let home = WebOrigin(url: URL(string: "https://cf.sheapi.cc/profile")!)
        let rules = [WebsiteRule(host: "cf.sheapi.cc")]
        let destination = WebOrigin(url: URL(string: "https://www.sheapi.cc/profile")!)
        #expect(AccountBalanceReader.permitsRead(from: home, home: home, rules: []))
        #expect(AccountBalanceReader.permitsRead(from: destination, home: home, rules: rules))
        #expect(!AccountBalanceReader.permitsRead(from: destination, home: home, rules: []))
        for address in ["http://www.sheapi.cc", "https://www.sheapi.cc:8443", "https://sheapi.cc.evil.invalid", "https://elsewhere.invalid"] {
            #expect(!AccountBalanceReader.permitsRead(from: WebOrigin(url: URL(string: address)!), home: home, rules: rules))
        }
        #expect(!AccountBalanceReader.permitsRead(from: destination, home: home, rules: [WebsiteRule(host: "other.invalid")]))
    }

    @Test
    func untrustedRedirectEndsReadImmediatelyInsteadOfPollingUntilTimeout() async throws {
        var reads = 0
        var waits = 0
        do {
            _ = try await AccountBalanceReader.readResult(afterCheckIn: false, reloadPage: {}, readValue: { () -> String? in
                reads += 1
                throw BalanceReadError.untrustedOrigin
            }, wait: { waits += 1 })
            Issue.record("Untrusted origin accepted")
        } catch {
            #expect(error is BalanceReadError)
        }
        #expect(reads == 1)
        #expect(waits == 0)
    }

    @Test
    func sourceVerificationMustAlsoBeStableBeforePublishingAReading() async throws {
        var reads = 0
        let result = try await AccountBalanceReader.readResult(afterCheckIn: true, reloadPage: {}, readValue: {
            reads += 1
            return AccountBalanceReading(value: "$12.50", sourceVerified: reads > 1)
        }, wait: {})
        #expect(reads == 3)
        #expect(result == AccountBalanceReading(value: "$12.50", sourceVerified: true))
    }

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
