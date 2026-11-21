import Foundation
@testable import Rockxy
import Testing

// Equivalence tests for the indexes a retention step used to rebuild from the whole
// retained history: the observed-domain ledger, the Assistant's host index, and the error
// and Traffic Signal counts. Each is now patched from the rows that arrived and the rows
// that left, so each has to still equal what its rebuild would produce.

@MainActor
struct RetentionMaintenanceEquivalenceTests {
    // MARK: Internal

    /// Eviction only begins once history reaches its cap and then runs for the rest of the
    /// session, so the patched path is the steady state of a long capture -- it has to hold
    /// over many consecutive steps, not just the first one.
    @Test("Retention leaves every maintained index equal to its rebuild")
    func retentionMatchesRebuiltIndexes() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 40
        coordinator.processActiveProjectTestBatch((0 ..< 40).map { makeRow($0) })

        for round in 0 ..< 12 {
            coordinator.processActiveProjectTestBatch((0 ..< 7).map { makeRow(100 + round * 7 + $0) })

            let observedCounts = coordinator.observedDomainCountsByApp
            let observedDomains = coordinator.observedDomainsByApp
            let assistant = assistantDigest(coordinator)
            let errorCount = coordinator.errorCount
            let errored = coordinator.erroredTransactionIDs
            let tlsFailures = coordinator.tlsFailureTransactionIDs
            let signals = nonZero(coordinator.trafficSignalCounts)
            let masks = coordinator.signalMaskByTransactionID

            coordinator.rebuildObservedDomainsByApp()
            coordinator.rebuildDebugAssistantTrafficIndex()
            coordinator.recomputeErrorCount()

            #expect(observedCounts == coordinator.observedDomainCountsByApp, "round \(round)")
            #expect(observedDomains == coordinator.observedDomainsByApp, "round \(round)")
            #expect(assistant == assistantDigest(coordinator), "round \(round)")
            #expect(errorCount == coordinator.errorCount, "round \(round)")
            #expect(errored == coordinator.erroredTransactionIDs, "round \(round)")
            #expect(tlsFailures == coordinator.tlsFailureTransactionIDs, "round \(round)")
            #expect(signals == nonZero(coordinator.trafficSignalCounts), "round \(round)")
            #expect(masks == coordinator.signalMaskByTransactionID, "round \(round)")
        }
        #expect(coordinator.transactions.count <= 40)
        #expect(coordinator.errorCount > 0)
    }

    /// The Assistant index holds `transactions + persistedFavorites`, deduplicated by id
    /// with the live row winning. When the live row is evicted the saved copy is what a
    /// rebuild would index, so the patch has to swap the object rather than drop the id.
    @Test("A saved request survives the eviction of its live row under the saved copy")
    func savedRequestSurvivesEvictionOfItsLiveRow() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 4
        let live = makeRow(1)
        let saved = HTTPTransaction(id: live.id, request: live.request)
        coordinator.persistedFavorites = [saved]
        coordinator.processActiveProjectTestBatch([live])
        #expect(coordinator.debugAssistantTransactionsByHost[live.request.host]?.contains { $0 === live } == true)

        coordinator.processActiveProjectTestBatch((2 ..< 8).map { makeRow($0) })
        #expect(!coordinator.transactions.contains { $0 === live })
        #expect(coordinator.debugAssistantIndexedTransactionIDs.contains(saved.id))
        let bucket = coordinator.debugAssistantTransactionsByHost[saved.request.host] ?? []
        #expect(bucket.contains { $0 === saved })
        #expect(!bucket.contains { $0 === live })
    }

    /// A row whose request was rewritten after it was indexed sits in the bucket it was
    /// filed under, not the one its request names now. Removing by the current host left
    /// the evicted row in the index holding the last strong reference to it.
    @Test("An evicted row leaves the Assistant index even after its host was rewritten")
    func rewrittenHostStillLeavesTheAssistantIndex() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 3
        let moved = makeRow(1)
        coordinator.processActiveProjectTestBatch([moved])
        let originalHost = moved.request.host
        moved.request = TestFixtures.makeRequest(url: "https://moved.example.net/elsewhere")

        coordinator.processActiveProjectTestBatch((2 ..< 8).map { makeRow($0) })
        #expect(!coordinator.transactions.contains { $0 === moved })
        #expect(!coordinator.debugAssistantIndexedTransactionIDs.contains(moved.id))
        #expect(coordinator.debugAssistantTransactionsByHost[originalHost]?.contains { $0 === moved } != true)
        #expect(coordinator.debugAssistantTransactionsByHost["moved.example.net"]?.contains { $0 === moved } != true)
        #expect(coordinator.debugAssistantIndexedHostByID[moved.id] == nil)
    }

    /// `recomputeErrorCount()` did two things besides counting, and they are the reason it
    /// could not simply be dropped from the retention path: it retires the sidebar
    /// favourites cache, whose key no longer carries the history count, and it rebuilds the
    /// TLS-failure set the status bar's "available" count subtracts.
    @Test("Retention still retires the favourites cache and maintains the TLS set")
    func retentionRetiresFavoritesCacheAndTLSSet() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 4
        let tlsFailure = makeRow(1)
        tlsFailure.isTLSFailure = true
        coordinator.processActiveProjectTestBatch([tlsFailure])
        #expect(coordinator.tlsFailureTransactionIDs == [tlsFailure.id])
        _ = coordinator.allPinnedTransactions
        let revision = coordinator.sidebarFavoritesRevision

        coordinator.processActiveProjectTestBatch((2 ..< 9).map { makeRow($0) })
        #expect(!coordinator.transactions.contains { $0 === tlsFailure })
        #expect(coordinator.tlsFailureTransactionIDs.isEmpty)
        #expect(coordinator.sidebarFavoritesRevision != revision)

        let tlsSet = coordinator.tlsFailureTransactionIDs
        coordinator.recomputeErrorCount()
        #expect(tlsSet == coordinator.tlsFailureTransactionIDs)
    }

    /// Memory-pressure eviction reclaims rows outside the capture batch path, and it
    /// subtracts from the same ledgers rather than rebuilding them.
    @Test("Memory-pressure eviction matches a rebuild of the ledgers it subtracts from")
    func memoryPressureEvictionMatchesRebuild() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 500
        coordinator.processActiveProjectTestBatch((0 ..< 300).map { makeRow($0) })
        coordinator.evictOldestTransactions(count: 120)
        #expect(coordinator.transactions.count == 180)

        let observedCounts = coordinator.observedDomainCountsByApp
        let errored = coordinator.erroredTransactionIDs
        let signals = nonZero(coordinator.trafficSignalCounts)
        coordinator.rebuildObservedDomainsByApp()
        coordinator.recomputeErrorCount()
        #expect(observedCounts == coordinator.observedDomainCountsByApp)
        #expect(errored == coordinator.erroredTransactionIDs)
        #expect(signals == nonZero(coordinator.trafficSignalCounts))
    }

    // MARK: Private

    private func makeRow(_ index: Int) -> HTTPTransaction {
        let row = TestFixtures.makeTransaction(
            method: index.isMultiple(of: 3) ? "POST" : "GET",
            url: "https://api\(index % 4).example.com/v\(index % 2)/item/\(index % 7)",
            statusCode: index.isMultiple(of: 5) ? 500 : 200
        )
        row.clientApp = index.isMultiple(of: 2) ? "Safari" : "Terminal"
        if index.isMultiple(of: 11) {
            row.measuredDuration = 3
        }
        return row
    }

    private func assistantDigest(_ coordinator: MainContentCoordinator) -> [String] {
        coordinator.debugAssistantTransactionsByHost.keys.sorted().map { host in
            let ids = (coordinator.debugAssistantTransactionsByHost[host] ?? [])
                .map { "\($0.id)@\(UInt(bitPattern: ObjectIdentifier($0).hashValue))" }
            return "\(host)|\(ids)"
        }
            + ["ids:\(coordinator.debugAssistantIndexedTransactionIDs.sorted { $0.uuidString < $1.uuidString })"]
            + ["hosts:\(coordinator.debugAssistantIndexedHostByID.map { "\($0.key)=\($0.value)" }.sorted())"]
    }

    private func nonZero(_ counts: [TrafficSignal: Int]) -> [TrafficSignal: Int] {
        counts.filter { $0.value != 0 }
    }
}
