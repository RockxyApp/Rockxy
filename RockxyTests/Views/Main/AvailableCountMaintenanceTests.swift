import Foundation
@testable import Rockxy
import Testing

// Regression tests for the status bar's "available" count as rows arrive, refresh, and leave.

@MainActor
struct AvailableCountMaintenanceTests {
    // MARK: Internal

    /// The count used to be `transactions.count { !$0.isTLSFailure }`, evaluated inside the
    /// centre pane's `body`. Reading it from a maintained set is only correct if the set
    /// tracks exactly the TLS-failure rows the history holds, so each test below compares
    /// the reported count against what the retained rows actually say.
    @Test("Arriving TLS failures leave the available count")
    func arrivingTLSFailuresAreExcluded() {
        let coordinator = MainContentCoordinator()
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://api.example.com/ok", statusCode: 200),
            makeTLSFailure(url: "https://blocked.example.com"),
            TestFixtures.makeTransaction(url: "https://api.example.com/also-ok", statusCode: 200)
        ])

        #expect(coordinator.transactions.count == 3)
        #expect(coordinator.tlsFailureTransactionIDs.count == 1)
        #expect(coordinator.availableTransactionCountForCurrentScope == 2)
    }

    /// A row is delivered when it opens and again when it finishes, and a duplicate close
    /// is normal. Folding deliveries into a count without remembering which rows were
    /// counted reported more rows than the history holds.
    @Test("A repeated delivery of one TLS failure is excluded once")
    func repeatedDeliveryExcludesOnce() {
        let coordinator = MainContentCoordinator()
        let tunnel = makeTLSFailure(url: "https://pinned.example.com")
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://api.example.com/ok", statusCode: 200),
            tunnel
        ])
        #expect(coordinator.availableTransactionCountForCurrentScope == 1)

        coordinator.enqueueLiveTransactionUpdates([tunnel, tunnel])
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.tlsFailureTransactionIDs.count == 1)
        #expect(coordinator.availableTransactionCountForCurrentScope == 1)
    }

    /// A handshake that fails after the tunnel row was already delivered flips the row's
    /// disposition, so the count has to move in both directions rather than only down.
    @Test("A row that becomes, then stops being, a TLS failure moves the count both ways")
    func dispositionChangeMovesTheCountBothWays() {
        let coordinator = MainContentCoordinator()
        let tunnel = TestFixtures.makeTransaction(
            url: "https://api.example.com/tunnel",
            statusCode: nil,
            state: .active
        )
        coordinator.processActiveProjectTestBatch([tunnel])
        #expect(coordinator.availableTransactionCountForCurrentScope == 1)

        tunnel.isTLSFailure = true
        coordinator.enqueueLiveTransactionUpdates([tunnel])
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.availableTransactionCountForCurrentScope == 0)

        tunnel.isTLSFailure = false
        coordinator.enqueueLiveTransactionUpdates([tunnel])
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.tlsFailureTransactionIDs.isEmpty)
        #expect(coordinator.availableTransactionCountForCurrentScope == 1)
    }

    /// Removal is the one change the set cannot fold forward: the rows are gone by the time
    /// anything looks at them. A leftover id would be subtracted from a history that no
    /// longer holds it, so the status bar would under-report for the rest of the session.
    @Test("Deleting a TLS failure's domain drops it from the set")
    func deletingADomainDropsItsTLSFailures() {
        let coordinator = MainContentCoordinator()
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://keep.example.com/ok", statusCode: 200),
            makeTLSFailure(url: "https://drop.example.com"),
            makeTLSFailure(url: "https://keep.example.com")
        ])
        #expect(coordinator.availableTransactionCountForCurrentScope == 1)

        coordinator.removeDomainFromSidebar("drop.example.com")
        #expect(coordinator.tlsFailureTransactionIDs.count == 1)
        #expect(coordinator.availableTransactionCountForCurrentScope == 1)
    }

    @Test("Evicted TLS failures leave the set")
    func evictionDropsEvictedTLSFailures() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 10
        coordinator.processActiveProjectTestBatch(
            (0 ..< 10).map { makeTLSFailure(url: "https://old\($0).example.com") }
        )
        #expect(coordinator.availableTransactionCountForCurrentScope == 0)

        coordinator.processActiveProjectTestBatch(
            (0 ..< 10).map {
                TestFixtures.makeTransaction(url: "https://api.example.com/new/\($0)", statusCode: 200)
            }
        )
        #expect(coordinator.transactions.count == 10)
        let retainedFailures = coordinator.transactions.count { $0.isTLSFailure }
        #expect(coordinator.tlsFailureTransactionIDs.count == retainedFailures)
        #expect(coordinator.availableTransactionCountForCurrentScope == 10 - retainedFailures)
    }

    /// Clear Session empties the history without going through `recomputeErrorCount()`, so
    /// a set left describing cleared rows would be subtracted from the rows captured after
    /// the clear -- a count that never recovers for the rest of the session.
    @Test("Clearing the session forgets which rows were TLS failures")
    func clearingForgetsRememberedTLSFailures() async {
        let coordinator = MainContentCoordinator()
        coordinator.processActiveProjectTestBatch([
            makeTLSFailure(url: "https://blocked.example.com")
        ])
        #expect(coordinator.tlsFailureTransactionIDs.count == 1)

        await coordinator.clearSession()
        #expect(coordinator.tlsFailureTransactionIDs.isEmpty)
        #expect(coordinator.availableTransactionCountForCurrentScope == 0)

        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://api.example.com/after", statusCode: 200)
        ])
        #expect(coordinator.availableTransactionCountForCurrentScope == 1)
    }

    // MARK: Private

    private func makeTLSFailure(url: String) -> HTTPTransaction {
        let transaction = TestFixtures.makeTransaction(url: url, statusCode: nil, state: .failed)
        transaction.isTLSFailure = true
        return transaction
    }
}
