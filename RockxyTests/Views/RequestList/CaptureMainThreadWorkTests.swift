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

    @Test("A retention step at the cap rebuilds only the new rows")
    func retentionStepRebuildsOnlyNewRows() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 100
        coordinator.processActiveProjectTestBatch((0 ..< 100).map { Self.transaction(index: $0) })
        let workspace = coordinator.activeWorkspace
        let projectionsBefore = RequestListRow.mainThreadProjectionCount

        coordinator.processActiveProjectTestBatch((100 ..< 105).map { Self.transaction(index: $0) })

        #expect(workspace.filteredRows.count == workspace.filteredTransactions.count)
        // Survivors are reused; only the five arrivals are projected.
        #expect(RequestListRow.mainThreadProjectionCount - projectionsBefore == 5)
    }

    // MARK: Private

    private static func transaction(index: Int) -> HTTPTransaction {
        TestFixtures.makeTransaction(url: "https://api.example.com/v1/route/\(index)", state: .completed)
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
