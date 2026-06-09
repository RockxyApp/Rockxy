import AppKit
import SwiftUI
@testable import Rockxy
import Testing

@MainActor
struct RequestTableSelectionScrollTests {
    @Test("Replaying unchanged selection preserves table scroll position")
    func unchangedSelectionReplayPreservesScrollPosition() {
        var selectedIDs = Set<UUID>()
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: [],
            refreshToken: 0,
            isAppendOnly: false,
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        let rows = TestFixtures.makeBulkTransactions(count: 100).map {
            RequestListRow(from: $0, sslState: .insecure)
        }
        let selectedRow = rows[80]
        selectedIDs = [selectedRow.id]
        coordinator.rows = rows

        let tableView = makeTableView(rowCount: rows.count, coordinator: coordinator)
        let scrollView = makeScrollView(documentView: tableView)

        coordinator.syncSelection(to: [selectedRow.id], in: tableView)

        let preservedOrigin = NSPoint(x: 0, y: tableView.rowHeight * 24)
        scrollView.contentView.scroll(to: preservedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        coordinator.rows = [selectedRow] + rows.filter { $0.id != selectedRow.id }
        tableView.reloadData()
        coordinator.syncSelection(to: [selectedRow.id], in: tableView)

        #expect(tableView.selectedRowIndexes == IndexSet(integer: 0))
        #expect(scrollView.contentView.bounds.origin.y == preservedOrigin.y)
    }

    @Test("Request table applies appearance display metrics")
    func requestTableAppliesAppearanceDisplayMetrics() {
        var selectedIDs = Set<UUID>()
        var appUI = AppUISettings()
        appUI.fontSize = 24
        appUI.useAlternatingRowBackgroundColors = false
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: [],
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        let tableView = makeTableView(rowCount: 1, coordinator: coordinator)

        coordinator.applyDisplayMetrics(to: tableView)

        #expect(tableView.rowHeight == 40)
        #expect(tableView.usesAlternatingRowBackgroundColors == false)
    }

    private func makeScrollView(documentView: NSTableView) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 120))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = documentView
        return scrollView
    }

    private func makeTableView(
        rowCount: Int,
        coordinator: RequestTableView.Coordinator
    )
        -> NSTableView
    {
        let tableView = NSTableView(
            frame: NSRect(x: 0, y: 0, width: 480, height: CGFloat(rowCount) * 28)
        )
        tableView.rowHeight = 28
        tableView.intercellSpacing = .zero
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url")))
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        coordinator.tableView = tableView
        tableView.reloadData()
        return tableView
    }
}
