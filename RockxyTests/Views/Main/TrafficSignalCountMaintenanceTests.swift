import Foundation
@testable import Rockxy
import Testing

// Regression tests for the sidebar's Traffic Signal badges as rows arrive, refresh, and leave.

@MainActor
struct TrafficSignalCountMaintenanceTests {
    /// The badges used to be counted inside the sidebar's own `body`, once per signal, each
    /// pass scanning the whole retained capture. Reading a maintained count instead is only
    /// correct if a row delivered more than once is still counted once -- a live row is
    /// delivered when it opens and again when it finishes, and a duplicate close is normal.
    @Test("A row delivered more than once is counted once per signal")
    func repeatedDeliveryCountsOnce() {
        let coordinator = MainContentCoordinator()
        let stream = TestFixtures.makeTransaction(
            url: "wss://api.example.com/socket",
            statusCode: nil,
            state: .active
        )
        coordinator.processActiveProjectTestBatch([stream])
        #expect(coordinator.trafficSignalCount(.webSocket) == 1)

        stream.state = .failed
        coordinator.enqueueLiveTransactionUpdates([stream, stream])
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.trafficSignalCount(.webSocket) == 1)
        #expect(coordinator.trafficSignalCount(.errors) == 1)
    }

    /// A row acquires and loses signals as its response and timing arrive, so the counts
    /// have to be able to go back down. A running total cannot do that without knowing how
    /// the row was counted before.
    @Test("A row that stops matching a signal stops being counted")
    func refreshOutOfASignalLowersTheCount() {
        let coordinator = MainContentCoordinator()
        let retried = TestFixtures.makeTransaction(
            url: "https://api.example.com/retry",
            statusCode: 503,
            state: .active
        )
        coordinator.processActiveProjectTestBatch([retried])
        #expect(coordinator.trafficSignalCount(.errors) == 1)

        retried.response = TestFixtures.makeResponse(statusCode: 200)
        retried.state = .completed
        coordinator.enqueueLiveTransactionUpdates([retried])
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.trafficSignalCount(.errors) == 0)
    }

    /// One row can belong to several signals at once, and each has to count it. Folding a
    /// single flag forward would have collapsed them.
    @Test("A row matching several signals is counted in each of them")
    func oneRowCountsInEverySignalItMatches() {
        let coordinator = MainContentCoordinator()
        let slowFailure = TestFixtures.makeTransaction(
            url: "https://api.example.com/slow",
            statusCode: 500
        )
        slowFailure.measuredDuration = 3
        slowFailure.matchedRuleName = "Rewrite host"
        coordinator.processActiveProjectTestBatch([slowFailure])

        #expect(coordinator.trafficSignalCount(.errors) == 1)
        #expect(coordinator.trafficSignalCount(.slow) == 1)
        #expect(coordinator.trafficSignalCount(.rulesHit) == 1)
        #expect(coordinator.trafficSignalCount(.webSocket) == 0)
        #expect(coordinator.trafficSignalCount(.graphQL) == 0)
    }

    /// Removal is the one change the counts cannot fold forward, because the rows are gone
    /// by the time anything looks at them. This is the path that left the status bar's error
    /// count stale before, so the badges are covered on it too.
    @Test("Deleting a domain's traffic drops its signals from the badges")
    func deletingADomainDropsItsSignals() {
        let coordinator = MainContentCoordinator()
        let kept = TestFixtures.makeTransaction(url: "https://keep.example.com/bad", statusCode: 500)
        let dropped = TestFixtures.makeTransaction(url: "https://drop.example.com/bad", statusCode: 502)
        dropped.measuredDuration = 2
        coordinator.processActiveProjectTestBatch([kept, dropped])
        #expect(coordinator.trafficSignalCount(.errors) == 2)
        #expect(coordinator.trafficSignalCount(.slow) == 1)

        coordinator.removeDomainFromSidebar("drop.example.com")
        #expect(coordinator.trafficSignalCount(.errors) == 1)
        #expect(coordinator.trafficSignalCount(.slow) == 0)
    }

    /// TLS-failure rows are never shown in the request list, and the badges counted them
    /// out before. Reading a maintained count has to keep excluding them.
    @Test("A TLS failure row is counted in no signal")
    func tlsFailureRowIsNotCounted() {
        let coordinator = MainContentCoordinator()
        let refused = TestFixtures.makeTransaction(
            url: "https://pinned.example.com/handshake",
            statusCode: nil,
            state: .failed
        )
        refused.isTLSFailure = true
        coordinator.processActiveProjectTestBatch([refused])

        #expect(coordinator.trafficSignalCount(.errors) == 0)
    }

    /// Clearing the session has to forget how every row was classified, or the next row to
    /// arrive is folded against a stale mask.
    @Test("Clearing the session forgets every signal classification")
    func clearingSessionForgetsSignals() async {
        let coordinator = MainContentCoordinator()
        let failure = TestFixtures.makeTransaction(url: "https://api.example.com/bad", statusCode: 500)
        coordinator.processActiveProjectTestBatch([failure])
        #expect(coordinator.trafficSignalCount(.errors) == 1)

        await coordinator.clearSession()
        #expect(coordinator.trafficSignalCount(.errors) == 0)
        #expect(coordinator.signalMaskByTransactionID.isEmpty)
    }
}
