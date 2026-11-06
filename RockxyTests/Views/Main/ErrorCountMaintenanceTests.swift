import Foundation
@testable import Rockxy
import Testing

// Regression tests for the status bar's error counter as rows arrive, refresh, and leave.

@MainActor
struct ErrorCountMaintenanceTests {
    /// A live row is delivered when it opens and again when it finishes, and those two
    /// deliveries can arrive in either order or be repeated. Counting each delivery, which
    /// the old `errorCount +=` did, reported more failures than the list actually holds.
    @Test("A repeated completion for one live row is counted once")
    func repeatedLiveCompletionCountsOnce() {
        let coordinator = MainContentCoordinator()
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://api.example.com/ok", statusCode: 200),
            TestFixtures.makeTransaction(url: "https://api.example.com/gone", statusCode: 404)
        ])
        #expect(coordinator.errorCount == 1)

        let stream = TestFixtures.makeTransaction(
            url: "https://api.example.com/stream",
            statusCode: nil,
            state: .active
        )
        coordinator.processActiveProjectTestBatch([stream])
        #expect(coordinator.errorCount == 1)

        stream.response = TestFixtures.makeResponse(statusCode: 500)
        stream.state = .failed
        coordinator.enqueueLiveTransactionUpdates([stream])
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.errorCount == 2)

        // The same terminal delivery again, as a duplicate close would arrive.
        coordinator.enqueueLiveTransactionUpdates([stream, stream])
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.errorCount == 2)
    }

    /// The counter has to be able to go back down. A row that was counted as an error and
    /// then refreshes into a success must stop being counted, which a running total cannot
    /// do without knowing how the row was counted before.
    @Test("A row that stops being an error stops being counted")
    func refreshOutOfErrorLowersTheCount() {
        let coordinator = MainContentCoordinator()
        let retried = TestFixtures.makeTransaction(
            url: "https://api.example.com/retry",
            statusCode: 503,
            state: .active
        )
        coordinator.processActiveProjectTestBatch([retried])
        #expect(coordinator.errorCount == 1)

        retried.response = TestFixtures.makeResponse(statusCode: 200)
        retried.state = .completed
        coordinator.enqueueLiveTransactionUpdates([retried])
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.errorCount == 0)
    }

    /// Removal is the one change the counter cannot fold forward, because the rows are
    /// already gone by the time anything looks at them. Deleting a domain's traffic from
    /// the sidebar left the count untouched, so the status bar kept reporting failures for
    /// rows the user had just removed.
    @Test("Deleting a domain's traffic drops its failures from the count")
    func deletingADomainDropsItsErrors() {
        let coordinator = MainContentCoordinator()
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://keep.example.com/ok", statusCode: 200),
            TestFixtures.makeTransaction(url: "https://keep.example.com/bad", statusCode: 500),
            TestFixtures.makeTransaction(url: "https://drop.example.com/bad", statusCode: 502),
            TestFixtures.makeTransaction(url: "https://drop.example.com/worse", statusCode: 503)
        ])
        #expect(coordinator.errorCount == 3)

        coordinator.removeDomainFromSidebar("drop.example.com")
        #expect(coordinator.transactions.count == 2)
        #expect(coordinator.errorCount == 1)
    }

    /// Eviction removes the oldest rows once capture passes the cap, so the count has to
    /// come back down with them rather than describing rows the list no longer has.
    @Test("Evicted failures leave the count")
    func evictionDropsEvictedErrors() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 10
        coordinator.processActiveProjectTestBatch(
            (0 ..< 10).map {
                TestFixtures.makeTransaction(url: "https://api.example.com/old/\($0)", statusCode: 500)
            }
        )
        #expect(coordinator.errorCount == 10)

        coordinator.processActiveProjectTestBatch(
            (0 ..< 10).map {
                TestFixtures.makeTransaction(url: "https://api.example.com/new/\($0)", statusCode: 200)
            }
        )
        #expect(coordinator.transactions.count == 10)
        // Whatever the eviction policy kept, the count must equal what is actually there.
        let actualErrors = coordinator.transactions.count { ($0.response?.statusCode ?? 0) >= 400 }
        #expect(coordinator.errorCount == actualErrors)
        #expect(coordinator.erroredTransactionIDs.count == actualErrors)
    }

    /// Clear Session must leave nothing behind, including the remembered classification.
    /// A leftover id would be counted again the moment that row was imported back.
    @Test("Clearing the session forgets which rows were failures")
    func clearingForgetsRememberedErrors() async {
        let coordinator = MainContentCoordinator()
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://api.example.com/bad", statusCode: 500)
        ])
        #expect(coordinator.errorCount == 1)

        await coordinator.clearSession()
        #expect(coordinator.errorCount == 0)
        #expect(coordinator.erroredTransactionIDs.isEmpty)
    }

    /// The refresh handle is also the "a flush is already scheduled" flag, so an exit that
    /// leaves it set stops every later flush from being scheduled: live rows would freeze
    /// for the rest of the session and the pending map would only grow. A cancelled sleep
    /// is the one exit that does not reach the flush that clears it.
    @Test("A cancelled refresh still lets the next flush be scheduled")
    func cancelledRefreshDoesNotWedgeScheduling() async throws {
        let coordinator = MainContentCoordinator()
        let row = TestFixtures.makeTransaction(
            url: "https://api.example.com/stream",
            statusCode: nil,
            state: .active
        )
        coordinator.processActiveProjectTestBatch([row])

        coordinator.enqueueLiveTransactionUpdates([row])
        let scheduled = try #require(coordinator.liveRowRefreshTask)
        scheduled.cancel()
        await scheduled.value
        #expect(coordinator.liveRowRefreshTask == nil)

        row.response = TestFixtures.makeResponse(statusCode: 500)
        row.state = .failed
        coordinator.enqueueLiveTransactionUpdates([row])
        #expect(coordinator.liveRowRefreshTask != nil)
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.errorCount == 1)
    }
}
