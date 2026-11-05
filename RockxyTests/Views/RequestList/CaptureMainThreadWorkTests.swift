import AppKit
import Foundation
@testable import Rockxy
import SwiftUI
import Testing

// MARK: - CaptureMainThreadWorkTests

/// Pins the main-thread cost of sustained capture at the history cap as counted work: rows
/// examined while evicting from the Assistant index, symbol images constructed, columns
/// touched, and whether a retention step reaches the table as a head trim plus a tail
/// append. None of these assertions read a clock.
@MainActor
struct CaptureMainThreadWorkTests {
    // MARK: Internal

    @Test("Evicting from the Assistant index examines each evicted row once, not the bucket per row")
    func assistantIndexEvictionScansEvictedRowsOnly() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 400
        coordinator.processActiveProjectTestBatch((0 ..< 400).map { Self.transaction(index: $0) })
        let before = Set(coordinator.transactions.map(\.id))
        coordinator.debugAssistantIndexRemovalScans = 0

        coordinator.processActiveProjectTestBatch((400 ..< 405).map { Self.transaction(index: $0) })

        let retained = Set(coordinator.transactions.map(\.id))
        let evicted = before.subtracting(retained).count
        #expect(evicted > 1)
        // One bucket holds all 400 rows (single host). Removing row by row scanned it once
        // per evicted row; the leading run is now walked once.
        #expect(coordinator.debugAssistantIndexRemovalScans == evicted)
        let bucket = coordinator.debugAssistantTransactionsByHost["api.example.com"] ?? []
        #expect(Set(bucket.map(\.id)) == retained)
        #expect(coordinator.debugAssistantIndexedTransactionIDs == retained)
    }

    @Test("Symbol images are built once per name however many cells ask")
    func symbolImagesAreCached() {
        let name = "bolt.fill"
        for _ in 0 ..< 500 {
            _ = RequestTableSymbolCache.image(systemSymbolName: name)
        }
        let key = "\(name)|"
        #expect(RequestTableSymbolCache.constructionCounts[key] == 1)

        for _ in 0 ..< 500 {
            _ = RequestTableSymbolCache.configuredImage(
                systemSymbolName: "wand.and.rays",
                accessibilityDescription: "Modified by a rule",
                pointSize: 11,
                weight: .semibold
            )
        }
        let wandBuilds = RequestTableSymbolCache.constructionCounts["wand.and.rays|Modified by a rule"]
        #expect(wandBuilds == 1)
    }

    @Test("A refresh that changes no column visibility touches no column")
    func unchangedColumnVisibilityIsNotReapplied() {
        let coordinator = Self.tableCoordinator(rows: [])
        let tableView = NSTableView()
        RequestTableView.makeColumns().forEach { tableView.addTableColumn($0) }
        let hidden = "ai"
        #expect(tableView.tableColumns.first { $0.identifier.rawValue == hidden }?.isHidden == false)

        let first = coordinator.syncBuiltInColumnVisibility(in: tableView) { $0 != hidden }
        let second = coordinator.syncBuiltInColumnVisibility(in: tableView) { $0 != hidden }

        #expect(first == 1)
        #expect(second == 0)
    }

    @Test("Row changes compose into one head trim and tail append, and refuse a gap")
    func rowChangeCompositionIsExact() {
        let ledger = [
            RowChangeStep(token: 5, removedHead: 0, appended: 3, rewritten: []),
            RowChangeStep(token: 6, removedHead: 10, appended: 10, rewritten: IndexSet(integer: 20)),
            RowChangeStep(token: 7, removedHead: 0, appended: 0, rewritten: IndexSet(integer: 40)),
        ]
        let window = RowChangeWindow.compose(ledger, after: 4, through: 7, startingRowCount: 100)
        #expect(window?.removedHead == 10)
        #expect(window?.appended == 13)
        #expect(window?.rewritten == IndexSet([20, 40]))

        // A table that already applied token 6 is not told about 6 again.
        let tail = RowChangeWindow.compose(ledger, after: 6, through: 7, startingRowCount: 103)
        #expect(tail == RowChangeWindow(removedHead: 0, appended: 0, rewritten: IndexSet(integer: 40)))

        // Token 6 never recorded: some other mutation changed the rows, so there is no window.
        let gapped = ledger.filter { $0.token != 6 }
        #expect(RowChangeWindow.compose(gapped, after: 4, through: 7, startingRowCount: 100) == nil)

        // A later step that eats rows an earlier step appended is not a head trim plus a tail append.
        let eatsAppended = [
            RowChangeStep(token: 1, removedHead: 0, appended: 5, rewritten: []),
            RowChangeStep(token: 2, removedHead: 12, appended: 0, rewritten: []),
        ]
        #expect(RowChangeWindow.compose(eatsAppended, after: 0, through: 2, startingRowCount: 10) == nil)
    }

    @Test("A retention step at the cap records a shift and rebuilds only the new rows")
    func retentionStepIsRecordedAsShift() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 100
        coordinator.processActiveProjectTestBatch((0 ..< 100).map { Self.transaction(index: $0) })
        let workspace = coordinator.activeWorkspace
        let rowsBefore = workspace.filteredRows.count
        let projectionsBefore = RequestListRow.mainThreadProjectionCount

        coordinator.processActiveProjectTestBatch((100 ..< 105).map { Self.transaction(index: $0) })

        let step = workspace.rowChangeLedger.last
        #expect(step?.token == workspace.refreshToken)
        #expect((step?.removedHead ?? 0) > 0)
        #expect(step?.appended == 5)
        #expect(step?.rewritten.isEmpty == true)
        #expect(workspace.filteredRows.count == rowsBefore - (step?.removedHead ?? 0) + 5)
        // Survivors are reused; only the five arrivals are projected.
        #expect(RequestListRow.mainThreadProjectionCount - projectionsBefore == 5)
    }

    @Test("The table applies a retention step without a full reload")
    func tableAppliesRetentionWithoutReload() {
        let old = Self.rows(0 ..< 50)
        let new = Array(old.dropFirst(10)) + Self.rows(50 ..< 60)
        let coordinator = Self.tableCoordinator(rows: new)
        coordinator.previousRowCount = old.count
        let ledger = [RowChangeStep(token: 8, removedHead: 10, appended: 10, rewritten: [])]

        let window = coordinator.rowChangeWindow(
            ledger: ledger,
            lastAppliedToken: 7,
            newToken: 8,
            newCount: new.count,
            workspaceChanged: false,
            tableRowCount: old.count,
            previousRows: old
        )
        #expect(window == RowChangeWindow(removedHead: 10, appended: 10, rewritten: []))

        // AppKit disagreeing about the old count, or a ledger that stops short, reloads.
        let disagree = coordinator.rowChangeWindow(
            ledger: ledger, lastAppliedToken: 7, newToken: 8, newCount: new.count,
            workspaceChanged: false, tableRowCount: old.count + 1, previousRows: old
        )
        #expect(disagree == nil)
        let short = coordinator.rowChangeWindow(
            ledger: ledger, lastAppliedToken: 6, newToken: 8, newCount: new.count,
            workspaceChanged: false, tableRowCount: old.count, previousRows: old
        )
        #expect(short == nil)
    }

    // MARK: Private

    private static func transaction(index: Int) -> HTTPTransaction {
        TestFixtures.makeTransaction(url: "https://api.example.com/v1/route/\(index)", state: .completed)
    }

    private static func rows(_ range: Range<Int>) -> [RequestListRow] {
        range.map { RequestListRow(from: transaction(index: $0)) }
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
