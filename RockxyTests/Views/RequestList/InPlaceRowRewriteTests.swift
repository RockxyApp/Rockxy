import Foundation
@testable import Rockxy
import SwiftUI
import Testing

// MARK: - InPlaceRowRewriteTests

/// Pins what an in-place row refresh costs as counted work: rows rebuilt per batch, and rows
/// the table is told to reload. Client-app enrichment and live-stream refreshes arrive on every
/// delivery batch for as long as capture runs, so a cost proportional to the retained list
/// (here 1,000 rows) rather than to the batch is what kept the main thread busy.
@MainActor
struct InPlaceRowRewriteTests {
    // MARK: Internal

    @Test("Enriching a batch rebuilds only the enriched rows, not the retained list")
    func enrichmentRebuildsOnlyEnrichedRows() throws {
        let coordinator = MainContentCoordinator()
        let history = Self.fill(coordinator, count: Self.retained)
        let enriched = Array(history.suffix(Self.batch))
        for transaction in enriched {
            transaction.clientApp = "Safari"
        }
        let workspace = coordinator.activeWorkspace
        let projectionsBefore = RequestListRow.mainThreadProjectionCount

        coordinator.handleClientAppEnrichment(enriched)

        let rebuilt = RequestListRow.mainThreadProjectionCount - projectionsBefore
        #expect(rebuilt == Self.batch)
        let chain = try #require(workspace.activeRewriteChain)
        #expect(chain.rowIndexes.count == Self.batch)
        #expect(chain.rowIndexes == IndexSet(integersIn: (Self.retained - Self.batch) ..< Self.retained))
        #expect(workspace.filteredRows.suffix(Self.batch).allSatisfy { $0.clientApp == "Safari" })
        #expect(workspace.filteredRows.prefix(Self.retained - Self.batch).allSatisfy { $0.clientApp == nil })
    }

    @Test("An enrichment that changes no row rebuilds nothing and leaves the table alone")
    func unchangedRowsAreNotRebuilt() {
        let coordinator = MainContentCoordinator()
        let history = Self.fill(coordinator, count: Self.retained)
        let workspace = coordinator.activeWorkspace
        let tokenBefore = workspace.refreshToken
        let projectionsBefore = RequestListRow.mainThreadProjectionCount

        // The same rows, with nothing about them changed since their rows were built.
        coordinator.handleLiveTransactionUpdate(Array(history.suffix(Self.batch)))

        #expect(RequestListRow.mainThreadProjectionCount - projectionsBefore == 0)
        #expect(workspace.refreshToken == tokenBefore)
        #expect(workspace.activeRewriteChain == nil)
    }

    @Test("A live refresh of one row among a full list rebuilds one row")
    func liveRefreshRebuildsOneRow() throws {
        let coordinator = MainContentCoordinator()
        let history = Self.fill(coordinator, count: Self.retained)
        let target = history[Self.retained / 2]
        target.measuredDuration = 3
        let projectionsBefore = RequestListRow.mainThreadProjectionCount

        coordinator.handleLiveTransactionUpdate([target])

        #expect(RequestListRow.mainThreadProjectionCount - projectionsBefore == 1)
        let chain = try #require(coordinator.activeWorkspace.activeRewriteChain)
        #expect(chain.rowIndexes == IndexSet(integer: Self.retained / 2))
    }

    @Test("Consecutive rewrites extend one chain from the first base token")
    func consecutiveRewritesShareOneChain() throws {
        let coordinator = MainContentCoordinator()
        let history = Self.fill(coordinator, count: 100)
        let workspace = coordinator.activeWorkspace
        let base = workspace.refreshToken

        history[10].clientApp = "Safari"
        coordinator.handleClientAppEnrichment([history[10]])
        history[20].clientApp = "Safari"
        coordinator.handleClientAppEnrichment([history[20]])

        let chain = try #require(workspace.activeRewriteChain)
        #expect(chain.originToken == base)
        #expect(chain.rowIndexes == IndexSet([10, 20]))
    }

    @Test("Any other row mutation retires the rewrite chain")
    func otherMutationsRetireTheChain() {
        let coordinator = MainContentCoordinator()
        let history = Self.fill(coordinator, count: 100)
        let workspace = coordinator.activeWorkspace
        history[10].clientApp = "Safari"
        coordinator.handleClientAppEnrichment([history[10]])
        #expect(workspace.activeRewriteChain != nil)

        let appended = TestFixtures.makeTransaction(url: "https://api.example.com/appended")
        coordinator.transactions.append(appended)
        coordinator.appendFilteredTransactions([appended])
        #expect(workspace.activeRewriteChain == nil)

        history[11].clientApp = "Safari"
        coordinator.handleClientAppEnrichment([history[11]])
        #expect(workspace.activeRewriteChain != nil)

        coordinator.recomputeFilteredTransactions()
        #expect(workspace.activeRewriteChain == nil)
    }

    @Test("The table reloads rewritten rows only when nothing but rewrites happened since it last applied")
    func tableReloadDecision() {
        let rows = Self.rows(count: 50)
        let coordinator = Self.tableCoordinator(rows: rows)
        coordinator.previousRowCount = 50
        let tailRows = IndexSet([48, 49])

        func decide(
            origin: Int? = 7,
            indexes: IndexSet = tailRows,
            applied: Int = 7,
            workspaceChanged: Bool = false,
            newCount: Int = 50,
            tableRows: Int = 50,
            previous: [RequestListRow]? = nil
        )
            -> Bool
        {
            coordinator.canReloadRewrittenRows(
                newCount: newCount,
                rewriteChainOrigin: origin,
                rewrittenRowIndexes: indexes,
                lastAppliedToken: applied,
                workspaceChanged: workspaceChanged,
                tableRowCount: tableRows,
                previousRows: previous ?? rows
            )
        }

        #expect(decide())
        #expect(decide(applied: 12), "A table ahead of the chain's base has applied a prefix of it")
        #expect(!decide(origin: nil), "No unbroken rewrite chain")
        #expect(!decide(applied: 6), "The table has not reached the chain's base")
        #expect(!decide(indexes: IndexSet()), "Nothing was rewritten")
        #expect(!decide(workspaceChanged: true))
        #expect(!decide(newCount: 51), "Rows were added")
        #expect(!decide(tableRows: 49), "AppKit and the model disagree on the row count")
        #expect(!decide(indexes: IndexSet([50])), "An index outside the list")
    }

    @Test("A rewrite that changes a row's highlight is not reloaded by cell")
    func highlightChangeFallsBackToFullReload() {
        let rows = Self.rows(count: 50)
        let coordinator = Self.tableCoordinator(rows: rows)
        coordinator.previousRowCount = 50
        let highlighted = TestFixtures.makeTransaction(
            url: "https://api.example.com/row/49",
            highlightColor: .red
        )
        var previous = rows
        previous[49] = RequestListRow(from: highlighted)

        #expect(!coordinator.canReloadRewrittenRows(
            newCount: 50,
            rewriteChainOrigin: 7,
            rewrittenRowIndexes: IndexSet(integer: 49),
            lastAppliedToken: 7,
            workspaceChanged: false,
            tableRowCount: 50,
            previousRows: previous
        ))
    }

    // MARK: Private

    private static let retained = 1_000
    private static let batch = 20

    @discardableResult
    private static func fill(_ coordinator: MainContentCoordinator, count: Int) -> [HTTPTransaction] {
        let transactions = (0 ..< count).map { index in
            TestFixtures.makeTransaction(url: "https://api.example.com/row/\(index)")
        }
        for start in stride(from: 0, to: count, by: 50) {
            coordinator.processActiveProjectTestBatch(Array(transactions[start ..< min(start + 50, count)]))
        }
        return transactions
    }

    private static func rows(count: Int) -> [RequestListRow] {
        (0 ..< count).map { index in
            RequestListRow(from: TestFixtures.makeTransaction(url: "https://api.example.com/row/\(index)"))
        }
    }

    private static func tableCoordinator(rows: [RequestListRow]) -> RequestTableView.Coordinator {
        var selected: Set<UUID> = []
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 0,
            isAppendOnly: false,
            selectedIDs: Binding(get: { selected }, set: { selected = $0 })
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        coordinator.rows = rows
        return coordinator
    }
}
