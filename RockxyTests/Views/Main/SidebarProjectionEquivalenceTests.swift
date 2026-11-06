import Foundation
@testable import Rockxy
import Testing

// MARK: - SidebarProjectionEquivalenceTests

// Equivalence tests for the patched sidebar projections: after any mutation, what the
// index publishes must be exactly what a full rebuild from the retained history produces,
// including order. The pre-existing retention tests compare a sorted digest, so they
// cannot see an ordering defect at all -- everything here compares document order.

@MainActor
@Suite(.serialized)
struct SidebarProjectionEquivalenceTests {
    // MARK: Internal

    /// The projection is patched per branch and the sibling order is maintained by
    /// insertion rather than re-sorted, so the interesting failures are the ones a single
    /// hand-written case cannot reach: a branch left stale, a node left in the wrong place
    /// after its earliest row was evicted, a dirty flag never cleared. A few hundred mixed
    /// mutations against an authoritative rebuild covers that space.
    @Test("Patched sidebar projections match a full rebuild across randomized mutations")
    func patchedProjectionsMatchRebuild() {
        var generator = SeededGenerator(seed: 0x5EED1234)
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 60
        TrafficDomainSnapshot.shared.reset()

        for round in 0 ..< 220 {
            switch round % 4 {
            case 0:
                let batch = (0 ..< Int.random(in: 1 ... 6, using: &generator))
                    .map { _ in makeRow(using: &generator) }
                coordinator.processActiveProjectTestBatch(batch)
            case 1:
                guard let row = coordinator.transactions.randomElement(using: &generator) else {
                    continue
                }
                // Late attribution: the app grouping's order depends on it, and the key
                // set alone can stay identical while the correct order changes.
                // `apps` carries a nil on purpose, to exercise the unattributed branch, so
                // `randomElement` hands back a double optional that has to be flattened.
                row.clientApp = Self.apps.randomElement(using: &generator) ?? nil
                coordinator.handleClientAppEnrichment([row])
            case 2:
                guard let row = coordinator.transactions.randomElement(using: &generator) else {
                    continue
                }
                // A rule rewrite moves a row to another host, which retires nodes on the
                // old branch and creates them on the new one.
                row.request = TestFixtures.makeRequest(
                    method: "PATCH",
                    url: "https://\(Self.hosts.randomElement(using: &generator) ?? "a.example.com")/moved/\(round)"
                )
                coordinator.handleLiveTransactionUpdate([row])
            default:
                guard let row = coordinator.transactions.randomElement(using: &generator) else {
                    continue
                }
                row.response = TestFixtures.makeResponse(statusCode: round.isMultiple(of: 3) ? 503 : 200)
                row.state = round.isMultiple(of: 3) ? .failed : .completed
                coordinator.handleLiveTransactionUpdate([row])
            }

            let workspace = coordinator.activeWorkspace
            let tree = orderedDigest(coordinator.domainTree)
            let apps = appDigest(coordinator.appNodes)
            let total = coordinator.totalDomainCount
            let indexMap = workspace.domainIndexMap
            let maintainedDomains = TrafficDomainSnapshot.shared.domains

            // The snapshot's list is maintained by the index now; this is the derivation it
            // replaced, run against the very tree the index just published.
            TrafficDomainSnapshot.shared.update(appNodes: coordinator.appNodes, domainTree: coordinator.domainTree)
            #expect(maintainedDomains == TrafficDomainSnapshot.shared.domains, "round \(round)")

            coordinator.rebuildSidebarIndexes()
            #expect(tree == orderedDigest(coordinator.domainTree), "round \(round)")
            #expect(apps == appDigest(coordinator.appNodes), "round \(round)")
            #expect(total == coordinator.totalDomainCount, "round \(round)")
            #expect(indexMap == workspace.domainIndexMap, "round \(round)")
        }
        // The randomized run has to have actually reached the interesting states.
        #expect(coordinator.transactions.count > 40)
        #expect(coordinator.transactions.count <= 60)
        #expect(coordinator.domainTree.count > 1)
    }

    /// The case that makes gating on the key set unsound: with rows `t1 -> Zebra`,
    /// `t2 -> Zebra`, `t3 -> Xray`, moving `t1` to `Xray` leaves the set of app names
    /// identical while the correct order changes, because the order follows which app the
    /// oldest retained row belongs to.
    @Test("Late attribution reorders the app list exactly as a rebuild would")
    func lateAttributionReordersAppNodes() {
        let coordinator = MainContentCoordinator()
        let first = TestFixtures.makeTransaction(url: "https://a.example.com/one")
        let second = TestFixtures.makeTransaction(url: "https://b.example.com/two")
        let third = TestFixtures.makeTransaction(url: "https://c.example.com/three")
        first.clientApp = "Zebra"
        second.clientApp = "Zebra"
        third.clientApp = "Xray"
        coordinator.processActiveProjectTestBatch([first, second, third])
        #expect(coordinator.appNodes.map(\.name) == ["Zebra", "Xray"])

        first.clientApp = "Xray"
        coordinator.handleClientAppEnrichment([first])
        let patched = appDigest(coordinator.appNodes)
        #expect(coordinator.appNodes.map(\.name) == ["Xray", "Zebra"])

        coordinator.rebuildSidebarIndexes()
        #expect(patched == appDigest(coordinator.appNodes))
    }

    /// Evicting the row a node was positioned by has to move the node, not leave it where
    /// its departed earliest sequence put it. A re-sort could not get this wrong; an
    /// order maintained by insertion can, which is why it is covered on its own.
    ///
    /// The tree roots at the registrable domain, so the nodes that move are the hosts among
    /// `example.com`'s children. With a cap of 4 the fifth row overflows by one and the
    /// headroom (`min(4, max(2, (4 + 9) / 10))` = 2) evicts the two oldest rows: `zulu`
    /// loses the row it was positioned by and `bravo` loses its only row, so `alpha` --
    /// first seen after `zulu` before -- now precedes it.
    @Test("Evicting a branch's earliest row repositions it like a rebuild")
    func evictionRepositionsByEarliestRemainingRow() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 4
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://zulu.example.com/early"),
            TestFixtures.makeTransaction(url: "https://bravo.example.com/only"),
            TestFixtures.makeTransaction(url: "https://alpha.example.com/mid"),
            TestFixtures.makeTransaction(url: "https://zulu.example.com/late")
        ])
        #expect(coordinator.domainTree.map(\.domain) == ["example.com"])
        #expect(
            coordinator.domainTree.first?.children.map(\.domain)
                == ["zulu.example.com", "bravo.example.com", "alpha.example.com"]
        )

        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://charlie.example.com/new")
        ])
        #expect(coordinator.transactions.count == 3)
        #expect(
            coordinator.domainTree.first?.children.map(\.domain)
                == ["alpha.example.com", "zulu.example.com", "charlie.example.com"]
        )
        let patched = orderedDigest(coordinator.domainTree)
        coordinator.rebuildSidebarIndexes()
        #expect(patched == orderedDigest(coordinator.domainTree))
    }

    /// Each Traffic Tab keeps its own projection, and a tab can be scoped to a different
    /// slice of the same history. A patch applied to one must not reach the other, and no
    /// tab may be left listing a row that eviction removed -- a tab holding on is how a
    /// deleted row kept its last strong reference before.
    @Test("Per-tab projections stay independent through retention")
    func perTabProjectionsStayIndependent() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 8
        var scoped = FilterCriteria.empty
        scoped.sidebarDomain = "keep.example.com"
        let second = coordinator.workspaceStore.createWorkspace(title: "Scoped", filter: scoped)
        let first = coordinator.workspaceStore.workspaces[0]
        coordinator.workspaceStore.selectWorkspace(id: first.id)

        // Eviction takes the oldest rows, never the batch just added, so the evicted set is
        // every id seen earlier that is no longer retained.
        var seenIDs: Set<UUID> = []
        for round in 0 ..< 10 {
            let batch = [
                TestFixtures.makeTransaction(url: "https://keep.example.com/v\(round)/item"),
                TestFixtures.makeTransaction(url: "https://other.example.com/v\(round)/item")
            ]
            coordinator.processActiveProjectTestBatch(batch)
            seenIDs.formUnion(batch.map(\.id))
            let retained = Set(coordinator.transactions.map(\.id))
            let evictedIDs = seenIDs.subtracting(retained)

            for workspace in [first, second] {
                let tree = orderedDigest(workspace.domainTree)
                let apps = appDigest(workspace.appNodes)
                coordinator.rebuildSidebarIndexes(for: workspace)
                #expect(tree == orderedDigest(workspace.domainTree), "round \(round)")
                #expect(apps == appDigest(workspace.appNodes), "round \(round)")
                #expect(workspace.filteredTransactions.allSatisfy { !evictedIDs.contains($0.id) })
                #expect(workspace.filteredRows.allSatisfy { !evictedIDs.contains($0.id) })
            }
        }
        #expect(seenIDs.count > coordinator.transactions.count)
        // The scoped tab never saw the other host, so the two projections really do differ:
        // both share the `example.com` root, but only the unscoped tab has both hosts under it.
        #expect(second.domainTree.map(\.domain) == ["example.com"])
        #expect(second.domainTree.first?.children.map(\.domain) == ["keep.example.com"])
        #expect(first.domainTree.map(\.domain) == ["example.com"])
        #expect(first.domainTree.first?.children.count == 2)
    }

    /// The one-shot alphabetical sort publishes an order the index does not maintain, so it
    /// must not leave the projection describing that order: the next ordinary refresh has
    /// to come back in capture order.
    @Test("The alphabetical sort does not poison the maintained projection")
    func alphabeticalSortLeavesProjectionIntact() {
        let coordinator = MainContentCoordinator()
        // Two registrable domains, so there are two roots to order.
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://zulu.test/one"),
            TestFixtures.makeTransaction(url: "https://alpha.test/two")
        ])
        let captureOrder = coordinator.domainTree.map(\.domain)
        #expect(captureOrder == ["zulu.test", "alpha.test"])

        coordinator.sortDomainTreeAlphabetically()
        #expect(coordinator.domainTree.map(\.domain) == ["alpha.test", "zulu.test"])
        #expect(coordinator.activeWorkspace.domainIndexMap["alpha.test"] == 0)

        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://zulu.test/three")
        ])
        #expect(coordinator.domainTree.map(\.domain) == captureOrder)
        #expect(coordinator.activeWorkspace.domainIndexMap["zulu.test"] == 0)
        let patched = orderedDigest(coordinator.domainTree)
        coordinator.rebuildSidebarIndexes()
        #expect(patched == orderedDigest(coordinator.domainTree))
    }

    /// An app's contacted-host list is published from a maintained order now instead of
    /// being sorted on every batch, so it has to lose a host when the last row naming it
    /// leaves -- and keep the comparator the sort used.
    ///
    /// With a cap of 4 the fifth row overflows by one and the headroom evicts the two oldest
    /// (`min(4, max(2, (4 + 9) / 10))` = 2): the only `zulu` row goes, so that host leaves
    /// the list, while `alpha` survives through its second row.
    @Test("An app's domain list is maintained through arrival and eviction")
    func appDomainListTracksRetention() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 4
        for host in ["zulu", "alpha", "mike", "alpha", "bravo"].map({ "\($0).example.com" }) {
            let row = TestFixtures.makeTransaction(url: "https://\(host)/item")
            row.clientApp = "Safari"
            coordinator.processActiveProjectTestBatch([row])
        }
        #expect(coordinator.transactions.count == 3)
        #expect(
            coordinator.appNodes.first?.domains == ["alpha.example.com", "bravo.example.com", "mike.example.com"]
        )
        let patched = appDigest(coordinator.appNodes)
        coordinator.rebuildSidebarIndexes()
        #expect(patched == appDigest(coordinator.appNodes))
    }

    // MARK: Private

    private static let hosts = [
        "api.example.com", "cdn.example.com", "example.com",
        "api.other.example.net", "other.example.net", "zulu.example.org"
    ]
    private static let apps = ["Safari", "Terminal", "Xcode", nil]

    private func makeRow(using generator: inout SeededGenerator) -> HTTPTransaction {
        let host = Self.hosts.randomElement(using: &generator) ?? "api.example.com"
        let depth = Int.random(in: 1 ... 3, using: &generator)
        let path = (0 ..< depth).map { "seg\(Int.random(in: 0 ... 3, using: &generator))\($0)" }
            .joined(separator: "/")
        let row = TestFixtures.makeTransaction(
            method: Bool.random(using: &generator) ? "GET" : "POST",
            url: "https://\(host)/\(path)",
            statusCode: Bool.random(using: &generator) ? 200 : 500
        )
        row.clientApp = Self.apps.randomElement(using: &generator) ?? nil
        return row
    }

    /// Document order, deliberately unsorted: the order is the thing under test.
    private func orderedDigest(_ nodes: [DomainNode]) -> [String] {
        nodes.flatMap { node in
            ["\(node.id)|\(node.requestCount)|\(node.errorCount)|\(node.methods.sorted())|\(node.firstSeenSequence)"]
                + orderedDigest(node.children)
        }
    }

    private func appDigest(_ nodes: [AppInfo]) -> [String] {
        nodes.map { "\($0.name)|\($0.requestCount)|\($0.domains)|\($0.identity?.identifier ?? "")" }
    }
}

// MARK: - SeededGenerator

/// Deterministic so a failing round is reproducible from the seed in the test.
private struct SeededGenerator: RandomNumberGenerator {
    // MARK: Lifecycle

    init(seed: UInt64) {
        state = seed
    }

    // MARK: Internal

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    // MARK: Private

    private var state: UInt64
}
