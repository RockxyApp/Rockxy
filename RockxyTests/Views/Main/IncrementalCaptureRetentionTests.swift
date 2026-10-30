import Foundation
@testable import Rockxy
import Testing

@MainActor
@Suite(.serialized)
struct IncrementalCaptureRetentionTests {
    // MARK: Internal

    @Test("Incremental retention matches authoritative trees after mutable metadata and eviction")
    func retentionMatchesRebuild() throws {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 100
        coordinator.processActiveProjectTestBatch((0 ..< 100).map { makeRow($0) })
        for round in 0 ..< 15 {
            let changing = try #require(coordinator.transactions.last)
            changing.clientApp = round.isMultiple(of: 2) ? "Safari" : "Terminal"
            changing.response = TestFixtures.makeResponse(statusCode: 503)
            changing.comment = "changed \(round)"
            changing.request = TestFixtures.makeRequest(method: "PATCH", url: "https://other.example.net/new/\(round)")
            coordinator.processActiveProjectTestBatch((0 ..< 10).map { makeRow(100 + round * 10 + $0) })
            let before = digest(coordinator.domainTree)
            let apps = coordinator.appNodes.map { "\($0.name)|\($0.requestCount)|\($0.domains)" }
            let rows = coordinator.filteredRows
                .map {
                    "\($0.id)|\($0.method)|\($0.path)|\($0.clientApp ?? "")|\($0.comment ?? "")|\($0.statusCode ?? 0)"
                }
            coordinator.rebuildSidebarIndexes()
            coordinator.recomputeFilteredTransactions()
            #expect(before == digest(coordinator.domainTree))
            #expect(apps == coordinator.appNodes.map { "\($0.name)|\($0.requestCount)|\($0.domains)" })
            #expect(rows == coordinator.filteredRows
                .map {
                    "\($0.id)|\($0.method)|\($0.path)|\($0.clientApp ?? "")|\($0.comment ?? "")|\($0.statusCode ?? 0)"
                })
        }
    }

    @Test("A scope change followed by a small append still rebuilds at retention")
    func changedScopeBeforeCap() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 100
        coordinator.processActiveProjectTestBatch((0 ..< 90).map { makeRow($0) })
        coordinator.filterCriteria.sidebarDomain = "api0.example.com"
        coordinator.processActiveProjectTestBatch((90 ..< 95).map { makeRow($0) })
        coordinator.processActiveProjectTestBatch((95 ..< 110).map { makeRow($0) })
        let before = digest(coordinator.domainTree)
        coordinator.rebuildSidebarIndexes()
        #expect(before == digest(coordinator.domainTree))
    }

    @Test("Evicting the last selected domain restores the complete remaining sidebar")
    func retentionPrunesEmptySelection() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 2
        let first = TestFixtures.makeTransaction(url: "https://first.invalid/old")
        let second = TestFixtures.makeTransaction(url: "https://second.invalid/old")
        coordinator.processActiveProjectTestBatch([first, second])
        coordinator.selectSidebarItem(.domainNode(domain: "first.invalid"))
        coordinator.rebuildSidebarIndexes()
        let newest = TestFixtures.makeTransaction(url: "https://newest.invalid/retained")
        coordinator.processActiveProjectTestBatch([newest])
        #expect(coordinator.filterCriteria.sidebarDomain == nil)
        #expect(coordinator.sidebarSelection == nil)
        #expect(coordinator.filteredRows.map(\.id) == [newest.id])
        #expect(coordinator.domainTree.reduce(0) { $0 + $1.requestCount } == 1)
    }

    @Test("Late and repeated attribution after rebuild does not count a row twice")
    func attributionIsIdempotent() {
        let coordinator = MainContentCoordinator()
        let row = makeRow(1)
        row.clientApp = nil
        coordinator.processActiveProjectTestBatch([row])
        row.clientApp = "Safari"
        coordinator.rebuildObservedDomainsByApp()
        coordinator.rebuildSidebarIndexes()
        coordinator.handleClientAppEnrichment([row, row])
        coordinator.handleClientAppEnrichment([row])
        #expect(coordinator.appNodes.count == 1)
        #expect(coordinator.appNodes.first?.requestCount == 1)
        #expect(coordinator.observedDomainCountsByApp["Safari"]?[row.request.host] == 1)
        row.clientApp = "Terminal"
        coordinator.handleClientAppEnrichment([row])
        #expect(coordinator.appNodes.map(\.name) == ["Terminal"])
        #expect(coordinator.observedDomainCountsByApp["Safari"] == nil)
        #expect(coordinator.observedDomainCountsByApp["Terminal"]?[row.request.host] == 1)
    }

    @Test("Saved requests remain in the Assistant index when capture reaches its cap")
    func retentionKeepsAssistantFavorites() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 10
        let saved = makeRow(999)
        coordinator.persistedFavorites = [saved]
        coordinator.processActiveProjectTestBatch((0 ..< 10).map { makeRow($0) })
        coordinator.processActiveProjectTestBatch([makeRow(11)])
        #expect(coordinator.debugAssistantIndexedTransactionIDs.contains(saved.id))
        #expect(coordinator.debugAssistantTransactionsByHost[saved.request.host]?.contains { $0 === saved } == true)
    }

    @Test("Restoring a Project keeps saved-only requests in the Assistant index")
    func projectRestoreKeepsAssistantFavorites() {
        let coordinator = MainContentCoordinator()
        let saved = makeRow(999)
        coordinator.persistedFavorites = [saved]
        coordinator.processActiveProjectTestBatch([makeRow(1)])
        coordinator.activateCurrentProject()
        #expect(coordinator.debugAssistantIndexedTransactionIDs.contains(saved.id))
    }

    @Test("Replacing saved requests with the same count invalidates the Assistant index")
    func sameCountFavoriteReplacement() {
        let coordinator = MainContentCoordinator()
        let first = makeRow(999)
        coordinator.persistedFavorites = [first]
        coordinator.processActiveProjectTestBatch([makeRow(1)])
        let replacement = makeRow(998)
        coordinator.persistedFavorites = [replacement]
        coordinator.appendToDebugAssistantTrafficIndex([])
        #expect(!coordinator.debugAssistantIndexedTransactionIDs.contains(first.id))
        #expect(coordinator.debugAssistantIndexedTransactionIDs.contains(replacement.id))
    }

    @Test("Projection revisions refresh cosmetic fields without invalidating body evidence")
    func projectionRevisionSeparatesBodyEvidence() {
        let row = makeRow(1)
        let initial = RequestListRow(from: row)
        let evidence = row.signalEvidenceRevision
        #expect(initial.canReuseProjection(of: row))
        row.comment = "reviewed"
        row.isPinned = true
        row.clientApp = "Terminal"
        row.state = .failed
        #expect(!initial.canReuseProjection(of: row))
        #expect(row.signalEvidenceRevision == evidence)
        let changed = RequestListRow(from: row)
        #expect(changed.canReuseProjection(of: row))
        row.response = TestFixtures.makeResponse(statusCode: 500)
        #expect(!changed.canReuseProjection(of: row))
        #expect(row.signalEvidenceRevision != evidence)
        let sameID = HTTPTransaction(id: row.id, request: row.request)
        #expect(!changed.canReuseProjection(of: sameID))
    }

    @Test("Cached state ordering exactly matches localized state comparisons")
    func statusSortMatchesOriginal() {
        let order = RequestListRow.StatusSortOrder()
        var rows = [TransactionState.pending, .active, .completed, .failed, .blocked].map {
            RequestListRow(from: TestFixtures.makeTransaction(state: $0))
        }
        let request = TestFixtures.makeRequest(url: "wss://fixture.invalid/socket")
        rows.append(RequestListRow(from: HTTPTransaction(
            request: request,
            state: .completed,
            webSocketConnection: WebSocketConnection(upgradeRequest: request)
        )))
        for ascending in [true, false] {
            let descriptors = [NSSortDescriptor(key: "state", ascending: ascending)]
            for lhs in rows {
                for rhs in rows {
                    #expect(RequestListRow.compare(lhs, rhs, using: descriptors) ==
                        RequestListRow.compare(lhs, rhs, using: descriptors, statusOrder: order))
                }
            }
        }
    }

    @Test("A live failure updates domain error counts without app count duplication")
    func liveFailureUpdatesGrouping() {
        let coordinator = MainContentCoordinator()
        let row = TestFixtures.makeTransaction(state: .active)
        coordinator.processActiveProjectTestBatch([row])
        row.response = TestFixtures.makeResponse(statusCode: 503)
        row.state = .failed
        coordinator.handleLiveTransactionUpdate([row, row])
        #expect(coordinator.domainTree.first?.errorCount == 1)
        #expect(coordinator.appNodes.first?.requestCount == 1)
    }

    @Test("Selection indexes preserve the latest source for sorted duplicate UUIDs")
    func duplicateUUIDSelectionSource() throws {
        let coordinator = MainContentCoordinator()
        let first = TestFixtures.makeTransaction(method: "ZZZ")
        let latest = HTTPTransaction(id: first.id, request: TestFixtures.makeRequest(method: "AAA"))
        let workspace = coordinator.activeWorkspace
        workspace.filteredTransactions = [first, latest]
        workspace.activeSortDescriptors = [NSSortDescriptor(key: "method", ascending: true)]
        workspace.selectedTransactionIDs = [first.id, UUID()]
        coordinator.deriveFilteredRows(for: workspace)
        let entry = try #require(workspace.trafficSelectionIndex[first.id])
        #expect(entry.transaction === latest)
        #expect(entry.rowIndex == 1)
        #expect(workspace.selectedTransactionIDs == [first.id])
    }

    @Test("Duplicate object aliases decline incremental removal")
    func duplicateAliasesFallBack() {
        let row = makeRow(1)
        var domains = DomainGroupingIndex()
        var apps = AppGroupingIndex()
        domains.add(row)
        domains.add(row)
        apps.add(row)
        apps.add(row)
        #expect(!domains.supportsIncrementalRemoval)
        #expect(!apps.supportsIncrementalRemoval)
        let removedDomains = domains.remove([row])
        let removedApps = apps.remove([row])
        #expect(!removedDomains)
        #expect(!removedApps)
        #expect(domains.makeTree().first?.requestCount == 2)
        #expect(apps.makeNodes().first?.requestCount == 2)
    }

    // MARK: Private

    private func makeRow(_ index: Int) -> HTTPTransaction {
        let row = TestFixtures.makeTransaction(
            method: index.isMultiple(of: 3) ? "POST" : "GET",
            url: "https://api\(index % 3).example.com/v\(index % 2)/item/\(index % 7)",
            statusCode: index.isMultiple(of: 5) ? 500 : 200
        )
        row.clientApp = index.isMultiple(of: 2) ? "Safari" : "Terminal"
        return row
    }

    private func digest(_ nodes: [DomainNode]) -> [String] {
        nodes.flatMap { node in
            ["\(node.id)|\(node.requestCount)|\(node.errorCount)|\(node.methods.sorted())|\(node.firstSeenSequence)"]
                + digest(node.children)
        }.sorted()
    }
}
