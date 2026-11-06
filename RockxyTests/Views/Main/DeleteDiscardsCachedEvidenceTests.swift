import Foundation
@testable import Rockxy
import Testing

/// The paths where the user explicitly deletes rows must drop the cached AI evidence for them,
/// the way eviction and Clear Session do. Hygiene only: the cache holds no header, cookie or
/// body material.
@MainActor
@Suite("Delete discards cached evidence", .serialized, .sharedPolicyState)
struct DeleteDiscardsCachedEvidenceTests {
    // MARK: Lifecycle

    /// `NSCache` may shed an entry at any time (memory pressure from other suites in a full run),
    /// which made the "was cached" precondition flaky. Pinning keeps every entry stored from here
    /// on until an explicit discard removes it, so absence after the action can only mean the
    /// delete discarded it. Idempotent and process-wide; it only adds strong references to small
    /// derived values.
    init() {
        AITrafficDetector.pinCachedEvidenceAgainstSheddingForTesting()
    }

    // MARK: Internal

    @Test("Explicit Delete discards the deleted rows' evidence and keeps the rest")
    func contextMenuDeleteDiscardsEvidence() {
        let coordinator = MainContentCoordinator()
        let deleted = TestFixtures.makeTransaction(url: "https://delete-evidence.example.test/a")
        let kept = TestFixtures.makeTransaction(url: "https://kept-evidence.example.test/b")
        coordinator.transactions = [deleted, kept]
        warm([deleted, kept])

        coordinator.deleteTransactions([deleted])

        expectDiscarded(deleted)
        expectCached(kept)
    }

    @Test("Removing a domain from the sidebar discards that domain's evidence")
    func sidebarDomainRemovalDiscardsEvidence() {
        let coordinator = MainContentCoordinator()
        let removed = TestFixtures.makeTransaction(url: "https://domain-evidence.example.test/a")
        let kept = TestFixtures.makeTransaction(url: "https://other-evidence.example.test/b")
        coordinator.transactions = [removed, kept]
        warm([removed, kept])

        coordinator.removeDomainFromSidebar("domain-evidence.example.test")

        expectDiscarded(removed)
        expectCached(kept)
    }

    @Test("Removing an app from the sidebar discards that app's evidence")
    func sidebarAppRemovalDiscardsEvidence() {
        let coordinator = MainContentCoordinator()
        let removed = TestFixtures.makeTransaction(url: "https://app-evidence.example.test/a")
        removed.clientApp = "EvidenceApp"
        let kept = TestFixtures.makeTransaction(url: "https://app-kept.example.test/b")
        kept.clientApp = "OtherApp"
        coordinator.transactions = [removed, kept]
        warm([removed, kept])

        coordinator.removeAppFromSidebar("EvidenceApp")

        expectDiscarded(removed)
        expectCached(kept)
    }

    // MARK: Private

    private func warm(_ transactions: [HTTPTransaction]) {
        for transaction in transactions {
            _ = AITrafficDetector.signal(transaction: transaction)
            _ = AITrafficDetector.filterFacts(transaction: transaction)
            expectCached(transaction)
        }
    }

    private func expectCached(_ transaction: HTTPTransaction) {
        #expect(AITrafficDetector.cachedSignal(transaction: transaction) != nil)
        #expect(AITrafficDetector.cachedFilterFacts(transaction: transaction) != nil)
    }

    private func expectDiscarded(_ transaction: HTTPTransaction) {
        #expect(AITrafficDetector.cachedSignal(transaction: transaction) == nil)
        #expect(AITrafficDetector.cachedFilterFacts(transaction: transaction) == nil)
    }
}
