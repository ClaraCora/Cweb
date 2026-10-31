import Foundation
import Testing
@testable import ProfileBrowser

@MainActor
struct AccountBalanceReaderTests {
    @Test
    func successIgnoresOldBalanceUntilUpdatedValueSettles() async throws {
        let values = ["$10.00", "$10.00", "$10.00", "$10.50", "$10.50"]
        var reads = 0
        let result = try await AccountBalanceReader.read(afterCheckIn: true, previousBalance: "$10.00") {
            defer { reads += 1 }
            return values[min(reads, values.count - 1)]
        } wait: {}
        #expect(result == "$10.50")
        #expect(reads == 5)
    }

    @Test
    func missingEntryBalanceUsesFirstDOMValueAsBaseline() async throws {
        var reads = 0
        let result = try await AccountBalanceReader.read(afterCheckIn: true, previousBalance: nil) {
            reads += 1
            return reads < 7 ? "$10.00" : "$11.00"
        } wait: {}
        #expect(result == "$11.00")
        #expect(reads == 8)
    }

    @Test
    func unchangedBalanceWaitsFullGraceWithoutInventingAReward() async throws {
        var waits = 0
        let result = try await AccountBalanceReader.read(afterCheckIn: true, previousBalance: "$10.00") {
            "$10.00"
        } wait: { waits += 1 }
        #expect(result == "$10.00")
        #expect(waits == 12)
    }

    @Test
    func unreadableBalanceDoesNotReplaceCacheWithAnEmptyValue() async throws {
        let result = try await AccountBalanceReader.read(afterCheckIn: true, previousBalance: "$10.00") {
            "   "
        } wait: {}
        #expect(result == nil)
    }

    @Test
    func entryReadReturnsImmediatelyAndRetriesTransientErrors() async throws {
        var reads = 0
        var waits = 0
        let result = try await AccountBalanceReader.read(afterCheckIn: false, previousBalance: nil) {
            reads += 1
            if reads == 1 { throw CocoaError(.fileReadUnknown) }
            return " $12.00 "
        } wait: { waits += 1 }
        #expect(result == "$12.00")
        #expect(reads == 2)
        #expect(waits == 1)
    }

    @Test
    func cancelledRefreshDoesNotReturnTheStaleBalance() async {
        do {
            _ = try await AccountBalanceReader.read(afterCheckIn: true, previousBalance: "$10.00") {
                "$10.00"
            } wait: { throw CancellationError() }
            Issue.record("Cancelled balance refresh returned a value")
        } catch {
            #expect(error is CancellationError)
        }
    }
}
