import Foundation
@testable import Rockxy
import Testing

// Eviction used to rebuild every Traffic Tab's sidebar indexes from the whole retained
// history. It now subtracts the rows that left, so each tab has to publish exactly what a
// rebuild over the surviving rows would -- under every tab's own filter, and across a long
// chain of steps rather than the first one.

@MainActor
struct WorkspaceEvictionEquivalenceTests {
    // MARK: Internal

    @Test("Interleaved adds and evictions leave every workspace equal to its rebuild")
    func interleavedEvictionMatchesRebuildInEveryWorkspace() {
        for seed in 1 ... 6 {
            var generator = SplitMix64(seed: UInt64(seed))
            let coordinator = MainContentCoordinator()
            coordinator.liveHistoryLimit = 100_000
            let filters = makeFilters()
            for filter in filters {
                coordinator.workspaceStore.createWorkspace(title: "Tab", filter: filter)
            }
            var serial = 0

            for round in 0 ..< 25 {
                let additions = 3 + Int(generator.next() % 14)
                let batch = (0 ..< additions).map { _ -> HTTPTransaction in
                    serial += 1
                    return makeRow(serial, using: &generator)
                }
                coordinator.processActiveProjectTestBatch(batch)

                // The patched path is only taken when every tab's ledger describes exactly
                // the history; prove the test is not silently exercising the fallback.
                for workspace in coordinator.workspaceStore.allWorkspaces {
                    #expect(
                        workspace.sidebarTransactionRevisions.count == coordinator.transactions.count,
                        "seed \(seed) round \(round): ledger precondition"
                    )
                }

                switch round % 3 {
                case 0:
                    coordinator.evictOldestTransactions(count: 1 + Int(generator.next() % 12))
                case 1:
                    evictScattered(from: coordinator, using: &generator)
                default:
                    evictWholeDomain(from: coordinator, using: &generator)
                }
                assertMatchesRebuild(coordinator, context: "seed \(seed) round \(round)")
            }
        }
    }

    @Test("Evicting the earliest row of a host reorders its tab the way a rebuild does")
    func evictingEarliestRowOfAHost() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 1_000
        coordinator.workspaceStore.createWorkspace(title: "Tab")
        let rows = [
            makeNamedRow("https://a.example.com/x", app: "Safari"),
            makeNamedRow("https://b.example.com/x", app: "Terminal"),
            makeNamedRow("https://a.example.com/y", app: "Safari"),
        ]
        coordinator.processActiveProjectTestBatch(rows)
        coordinator.evictOldestTransactions(count: 1)

        for workspace in coordinator.workspaceStore.allWorkspaces {
            #expect(workspace.domainTree.first?.children.map(\.domain) == ["b.example.com", "a.example.com"])
            #expect(workspace.appNodes.map(\.name) == ["Terminal", "Safari"])
        }
        assertMatchesRebuild(coordinator, context: "earliest row")
    }

    // MARK: Private

    private struct SplitMix64: RandomNumberGenerator {
        // MARK: Lifecycle

        init(seed: UInt64) {
            state = seed &* 0x9E3779B97F4A7C15
        }

        // MARK: Internal

        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
    }

    private static let hosts = [
        "example.com", "api.example.com", "cdn.example.com", "shop.test", "www.shop.test",
        "a.b.example.co.uk", "localhost",
    ]
    private static let paths = ["/", "/v1/users", "/v1/users/42", "/static/app.js", "/health", "/a/b/c/d"]
    private static let apps = ["Safari", "Terminal", "curl", "Xcode"]

    private func makeFilters() -> [FilterCriteria] {
        var getOnly = FilterCriteria.empty
        getOnly.methods = ["GET"]
        var safari = FilterCriteria.empty
        safari.sidebarApp = "Safari"
        var example = FilterCriteria.empty
        example.sidebarDomain = "example.com"
        return [getOnly, safari, example]
    }

    private func makeNamedRow(_ url: String, app: String) -> HTTPTransaction {
        let transaction = TestFixtures.makeTransaction(url: url)
        transaction.clientApp = app
        return transaction
    }

    private func makeRow(_ serial: Int, using generator: inout SplitMix64) -> HTTPTransaction {
        let host = Self.hosts[Int(generator.next() % UInt64(Self.hosts.count))]
        let path = Self.paths[Int(generator.next() % UInt64(Self.paths.count))]
        let transaction = TestFixtures.makeTransaction(
            method: serial.isMultiple(of: 3) ? "POST" : "GET",
            url: "https://\(host)\(path)",
            statusCode: serial.isMultiple(of: 7) ? 500 : 200
        )
        transaction.clientApp = Self.apps[Int(generator.next() % UInt64(Self.apps.count))]
        return transaction
    }

    private func evictScattered(from coordinator: MainContentCoordinator, using generator: inout SplitMix64) {
        let removed = coordinator.transactions.filter { _ in generator.next() % 6 == 0 }
        evict(removed, from: coordinator)
    }

    private func evictWholeDomain(from coordinator: MainContentCoordinator, using generator: inout SplitMix64) {
        guard !coordinator.transactions.isEmpty else {
            return
        }
        let victim = coordinator.transactions[Int(generator.next() % UInt64(coordinator.transactions.count))]
        let host = DomainGrouping.nodeSpecs(for: victim).first?.id
        let removed = coordinator.transactions.filter { DomainGrouping.nodeSpecs(for: $0).first?.id == host }
        evict(removed, from: coordinator)
    }

    private func evict(_ removed: [HTTPTransaction], from coordinator: MainContentCoordinator) {
        let ids = Set(removed.map(\.id))
        coordinator.transactions.removeAll { ids.contains($0.id) }
        coordinator.transactionsByProjectID[coordinator.projectStore.activeProjectID] = coordinator.transactions
        coordinator.evictFromAllWorkspaces(removedIDs: ids, removed: removed)
    }

    /// Rebuilds the same tabs in a second coordinator over the same rows, so the comparison
    /// is against an index that never saw an incremental step and the coordinator under
    /// test keeps running from its patched state.
    private func assertMatchesRebuild(_ coordinator: MainContentCoordinator, context: String) {
        let oracle = MainContentCoordinator()
        oracle.transactions = coordinator.transactions
        let tabs = coordinator.workspaceStore.allWorkspaces
        for (index, workspace) in tabs.enumerated() {
            let reference = index == 0
                ? oracle.workspaceStore.allWorkspaces[0]
                : oracle.workspaceStore.createWorkspace(title: "Tab", filter: workspace.filterCriteria)
            oracle.rebuildSidebarIndexes(for: reference)
            oracle.recomputeFilteredTransactions(for: reference)

            #expect(workspace.domainTree == reference.domainTree, "\(context) tab \(index): domain tree")
            #expect(workspace.totalDomainCount == reference.totalDomainCount, "\(context) tab \(index): total")
            #expect(
                workspace.appNodes.map(appSummary) == reference.appNodes.map(appSummary),
                "\(context) tab \(index): apps"
            )
            #expect(
                workspace.filteredTransactions.map(\.id) == reference.filteredTransactions.map(\.id),
                "\(context) tab \(index): filtered"
            )
            #expect(
                workspace.filteredRows.map(\.id) == reference.filteredRows.map(\.id),
                "\(context) tab \(index): rows"
            )
        }
    }

    private func appSummary(_ node: AppInfo) -> String {
        "\(node.name)|\(node.requestCount)|\(node.domains)"
    }
}
