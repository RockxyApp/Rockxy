import AppKit
import os
import SwiftUI

// swiftlint:disable file_length

// Renders the request table interface for traffic list presentation.

// MARK: - RequestTableView

/// AppKit `NSTableView` wrapped in `NSViewRepresentable` for the main request list.
/// Uses NSTableView instead of SwiftUI List because SwiftUI List cannot handle 100k+ rows
/// with acceptable scroll performance — NSTableView provides native virtual scrolling,
/// cell reuse, and column sorting out of the box.
struct RequestTableView: NSViewRepresentable {
    // MARK: Internal

    let rows: [RequestListRow]
    let refreshToken: Int
    let isAppendOnly: Bool
    @Binding var selectedIDs: Set<UUID>

    var onSelectionChanged: ((Set<UUID>) -> Void)?
    var onDoubleClick: ((HTTPTransaction) -> Void)?
    var mainCoordinator: MainContentCoordinator?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 4, height: 0)
        tableView.rowHeight = 28
        tableView.headerView = NSTableHeaderView()
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        for column in Self.makeColumns() {
            tableView.addTableColumn(column)
        }

        if let store = mainCoordinator?.headerColumnStore {
            for headerCol in store.enabledColumns {
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(headerCol.columnIdentifier))
                col.title = headerCol.headerName
                col.width = 100
                col.minWidth = 50
                col.resizingMask = .userResizingMask
                col.sortDescriptorPrototype = NSSortDescriptor(key: headerCol.columnIdentifier, ascending: true)
                tableView.addTableColumn(col)
            }
        }

        // Apply built-in column visibility
        if let store = mainCoordinator?.headerColumnStore {
            for column in tableView.tableColumns {
                let colID = column.identifier.rawValue
                if !colID.hasPrefix("reqHeader."), !colID.hasPrefix("resHeader.") {
                    column.isHidden = !store.isBuiltInColumnVisible(colID)
                }
            }
        }

        let headerMenu = NSMenu()
        headerMenu.delegate = context.coordinator
        tableView.headerView?.menu = headerMenu

        // Column state persistence: AppKit owns width and order, HeaderColumnStore owns visibility
        tableView.autosaveName = RockxyIdentity.current.defaultsKey("requestTable")
        tableView.autosaveTableColumns = true

        // Re-apply HeaderColumnStore visibility after AppKit restores autosaved state
        if let store = mainCoordinator?.headerColumnStore {
            for column in tableView.tableColumns {
                let colID = column.identifier.rawValue
                if !colID.hasPrefix("reqHeader."), !colID.hasPrefix("resHeader.") {
                    column.isHidden = !store.isBuiltInColumnVisible(colID)
                }
            }
        }

        scrollView.documentView = tableView
        scrollView.autoresizingMask = [.width, .height]
        tableView.sizeLastColumnToFit()
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else {
            return
        }

        let coordinator = context.coordinator
        let oldToken = coordinator.lastRefreshToken
        let newToken = refreshToken

        coordinator.parent = self
        coordinator.rows = rows
        coordinator.mainCoordinator = mainCoordinator
        coordinator.lastRefreshToken = newToken

        if newToken != oldToken {
            let newCount = rows.count
            if isAppendOnly,
               newCount > coordinator.previousRowCount,
               coordinator.previousRowCount > 0
            {
                // Append-only fast path: coordinator confirmed rows were only appended
                let newIndexes = IndexSet(integersIn: coordinator.previousRowCount ..< newCount)
                tableView.insertRows(at: newIndexes, withAnimation: [])
            } else {
                tableView.reloadData()
            }
            coordinator.previousRowCount = newCount
        }

        if !coordinator.hasAutoSizedColumns, rows.count > 10 {
            coordinator.hasAutoSizedColumns = true
            DispatchQueue.main.async {
                for (index, column) in tableView.tableColumns.enumerated() {
                    let colID = column.identifier.rawValue
                    if colID == "client" || colID == "url" {
                        let width = coordinator.tableView(tableView, sizeToFitWidthOfColumn: index)
                        column.width = width
                    }
                }
            }
        }

        coordinator.syncHeaderColumns(in: tableView)
        coordinator.syncSelection(to: selectedIDs, in: tableView)

        // Re-apply HeaderColumnStore visibility on every update (single source of truth)
        if let store = mainCoordinator?.headerColumnStore {
            for column in tableView.tableColumns {
                let colID = column.identifier.rawValue
                if !colID.hasPrefix("reqHeader."), !colID.hasPrefix("resHeader.") {
                    column.isHidden = !store.isBuiltInColumnVisible(colID)
                }
            }
        }

        // Sync per-workspace sort state into AppKit (e.g., after workspace switch)
        coordinator.syncSortDescriptors(
            from: mainCoordinator?.activeSortDescriptors ?? [],
            into: tableView
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func makeColumns() -> [NSTableColumn] {
        let specs: [ColumnSpec] = [
            ColumnSpec(id: "status", title: "", width: 20, minWidth: 20),
            ColumnSpec(id: "row", title: "#", width: 40, minWidth: 30),
            ColumnSpec(id: "url", title: String(localized: "URL"), width: 300, minWidth: 200),
            ColumnSpec(id: "client", title: String(localized: "Client"), width: 120, minWidth: 60),
            ColumnSpec(id: "method", title: String(localized: "Method"), width: 70, minWidth: 55),
            ColumnSpec(id: "code", title: String(localized: "Code"), width: 50, minWidth: 40),
            ColumnSpec(id: "time", title: String(localized: "Time"), width: 80, minWidth: 60),
            ColumnSpec(id: "duration", title: String(localized: "Duration"), width: 70, minWidth: 50),
            ColumnSpec(id: "size", title: String(localized: "Size"), width: 70, minWidth: 50),
            ColumnSpec(id: "queryName", title: String(localized: "Query Name"), width: 100, minWidth: 60),
        ]

        return specs.map { spec in
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = spec.minWidth
            column.resizingMask = .userResizingMask

            if spec.id == "url" || spec.id == "client" {
                column.resizingMask = [.userResizingMask, .autoresizingMask]
            }

            if spec.id == "status" {
                column.resizingMask = []
                column.maxWidth = 20
            } else {
                column.sortDescriptorPrototype = NSSortDescriptor(
                    key: spec.id,
                    ascending: true
                )
            }

            return column
        }
    }
}

// MARK: - ColumnSpec

private struct ColumnSpec {
    let id: String
    let title: String
    let width: CGFloat
    let minWidth: CGFloat
}

// MARK: - RequestTableView.Coordinator

extension RequestTableView {
    // swiftlint:disable:next type_body_length
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        // MARK: Lifecycle

        init(parent: RequestTableView) {
            self.parent = parent
            self.rows = parent.rows
            self.mainCoordinator = parent.mainCoordinator
        }

        // MARK: Internal

        var parent: RequestTableView
        var rows: [RequestListRow]
        var mainCoordinator: MainContentCoordinator?
        weak var tableView: NSTableView?
        var hasAutoSizedColumns = false
        var lastClickedColumn: String?
        var lastRefreshToken: Int = 0
        var previousRowCount: Int = 0

        /// Guard flag to prevent feedback loops: when we programmatically update NSTableView
        /// selection from SwiftUI state, we suppress the delegate callback that would
        /// re-propagate the change back to SwiftUI.
        private(set) var isUpdatingSelection = false

        /// Guard flag to prevent feedback loops when syncing sort descriptors from
        /// coordinator state back into NSTableView.
        private(set) var isUpdatingSortDescriptors = false

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isUpdatingSortDescriptors else {
                return
            }
            MainActor.assumeIsolated {
                guard let coordinator = mainCoordinator else {
                    return
                }
                coordinator.activeSortDescriptors = tableView.sortDescriptors
                coordinator.activeWorkspace.lastDeriveWasAppendOnly = false
                coordinator.deriveFilteredRows()
            }
        }

        // MARK: - NSTableViewDelegate

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        )
            -> NSView?
        {
            guard row < rows.count,
                  let columnID = tableColumn?.identifier.rawValue else
            {
                return nil
            }

            let rowData = rows[row]

            if columnID == "status" {
                return makeStatusDotView(row: rowData, in: tableView)
            }

            if columnID == "client" {
                let clientCellID = NSUserInterfaceItemIdentifier("Cell_client")
                let appName = rowData.clientApp ?? ""
                return makeClientCellView(
                    appName: appName,
                    identifier: clientCellID,
                    in: tableView
                )
            }

            let cellID = NSUserInterfaceItemIdentifier("Cell_\(columnID)")
            let cell: NSView = if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) {
                reused
            } else {
                makeCellView(identifier: cellID)
            }

            if let textField = cell.subviews.first as? NSTextField {
                configureCellContent(textField, column: columnID, row: row, rowData: rowData)
            }

            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard row < rows.count else {
                return nil
            }
            let rowData = rows[row]
            guard let color = rowData.highlightColor else {
                return nil
            }
            let rowView = NSTableRowView()
            rowView.wantsLayer = true
            rowView.layer?.backgroundColor = color.nsColor.withAlphaComponent(0.12).cgColor
            return rowView
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection,
                  let tableView = notification.object as? NSTableView else
            {
                return
            }

            let selected = tableView.selectedRowIndexes
            var ids = Set<UUID>()
            for index in selected where index < rows.count {
                ids.insert(rows[index].id)
            }

            parent.selectedIDs = ids
            parent.onSelectionChanged?(ids)
        }

        func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
            let tableColumn = tableView.tableColumns[column]
            let columnID = tableColumn.identifier.rawValue

            switch columnID {
            case "status": return 20
            case "row": return 40
            default: break
            }

            var maxWidth = tableColumn.headerCell.cellSize.width + 8
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            let start = max(0, visibleRange.location)
            let end = min(rows.count, visibleRange.location + visibleRange.length)

            for rowIdx in start ..< end {
                let rowData = rows[rowIdx]
                let text: String
                let font: NSFont

                switch columnID {
                case "url":
                    text = rowData.host + rowData.path
                    font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                case "client":
                    text = rowData.clientApp ?? ""
                    font = .systemFont(ofSize: 12)
                case "method":
                    text = rowData.method
                    font = .systemFont(ofSize: 12, weight: .semibold)
                case "code":
                    text = rowData.statusCode.map { "\($0)" } ?? ""
                    font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                case "time":
                    text = RequestTableView.timeFormatter.string(from: rowData.timestamp)
                    font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                case "duration":
                    text = rowData.totalDuration.map {
                        DurationFormatter.format(seconds: $0)
                    } ?? "—"
                    font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                case "size":
                    text = rowData.responseBodySize.map { SizeFormatter.format(bytes: $0) } ?? "—"
                    font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                case "queryName":
                    // Unified display: WS rows show frame count, others show GraphQL op name
                    if rowData.isWebSocket {
                        let count = rowData.webSocketFrameCount
                        text = "\(count) \(count == 1 ? "frame" : "frames")"
                    } else {
                        text = rowData.graphQLOpName ?? ""
                    }
                    font = .systemFont(ofSize: 12)
                default:
                    if columnID.hasPrefix("reqHeader.") || columnID.hasPrefix("resHeader.") {
                        text = RequestListRow.resolveHeaderValue(for: columnID, row: rowData)
                        font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                    } else {
                        text = ""
                        font = .systemFont(ofSize: 12)
                    }
                }

                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                let size = (text as NSString).size(withAttributes: attrs)
                let cellWidth = columnID == "client" ? size.width + 24 : size.width + 16
                maxWidth = max(maxWidth, cellWidth)
            }

            return min(maxWidth, 600)
        }

        @objc
        func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < rows.count else {
                return
            }
            MainActor.assumeIsolated {
                guard let transaction = mainCoordinator?.transaction(for: rows[row].id) else {
                    return
                }
                parent.onDoubleClick?(transaction)
            }
        }

        // MARK: - NSMenuDelegate

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()

            if menu === tableView?.headerView?.menu {
                buildColumnHeaderMenu(menu)
                return
            }

            guard let tableView,
                  tableView.clickedRow >= 0,
                  tableView.clickedRow < rows.count else
            {
                return
            }

            let rowData = rows[tableView.clickedRow]
            guard let transaction = mainCoordinator?.transaction(for: rowData.id) else {
                return
            }
            let clickedCol = tableView.clickedColumn >= 0
                ? tableView.tableColumns[tableView.clickedColumn].identifier.rawValue
                : "url"
            lastClickedColumn = clickedCol

            buildCopyGroup(menu, transaction: transaction)
            menu.addItem(.separator())
            buildRepeatGroup(menu, transaction: transaction)
            menu.addItem(.separator())
            buildPinGroup(menu, transaction: transaction)
            menu.addItem(.separator())
            buildToolsGroup(menu, transaction: transaction)
            menu.addItem(.separator())
            buildAnnotationGroup(menu, transaction: transaction)
            menu.addItem(.separator())
            buildExportGroup(menu, transaction: transaction)
            menu.addItem(.separator())
            buildCompareGroup(menu)
            menu.addItem(.separator())
            buildDeleteGroup(menu, transaction: transaction)
        }

        @objc
        func handleCopyURL(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyURL(for: $1) }
        }

        @objc
        func handleCopyCURL(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyCURL(for: $1) }
        }

        @objc
        func handleCopyCellValue(_ sender: NSMenuItem) {
            let col = lastClickedColumn ?? "url"
            withCoordinator(sender) { $0.copyCellValue(for: $1, column: col) }
        }

        @objc
        func handleCopyAsJSON(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyAsJSON(for: $1) }
        }

        @objc
        func handleCopyAsHAR(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyAsHAREntry(for: $1) }
        }

        @objc
        func handleCopyRawRequest(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyAsRawRequest(for: $1) }
        }

        @objc
        func handleCopyRawResponse(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyAsRawResponse(for: $1) }
        }

        @objc
        func handleCopyRawHeaders(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyAsRawHeaders(for: $1) }
        }

        @objc
        func handleCopyRequestHeaders(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyRequestHeaders(for: $1) }
        }

        @objc
        func handleCopyResponseHeaders(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyResponseHeaders(for: $1) }
        }

        @objc
        func handleCopyRequestBody(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyRequestBody(for: $1) }
        }

        @objc
        func handleCopyResponseBody(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyResponseBody(for: $1) }
        }

        @objc
        func handleCopyRequestCookies(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyRequestCookies(for: $1) }
        }

        @objc
        func handleCopyResponseCookies(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.copyResponseCookies(for: $1) }
        }

        @objc
        func handleRepeat(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.replayTransaction($1) }
        }

        @objc
        func handleEditAndRepeat(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.editAndReplayTransaction($1) }
        }

        @objc
        func handleTogglePin(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.togglePin(for: $1) }
        }

        @objc
        func handleSaveRequest(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.saveRequest($1) }
        }

        @objc
        func handleAddComment(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.promptComment(for: $1) }
        }

        @objc
        func handleHighlight(_ sender: NSMenuItem) {
            let tag = sender.tag
            withCoordinator(sender) { coordinator, transaction in
                let allColors = HighlightColor.allCases
                guard tag >= 0, tag < allColors.count else {
                    return
                }
                coordinator.setHighlight(allColors[tag], for: transaction)
            }
        }

        @objc
        func handleRemoveHighlight(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.setHighlight(nil, for: $1) }
        }

        @objc
        func handleMapLocal(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.createMapLocalRule(for: $1) }
        }

        @objc
        func handleMapRemote(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.createMapRemoteRule(for: $1) }
        }

        @objc
        func handleBlock(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.createBlockRule(for: $1) }
        }

        @objc
        func handleBreakpoint(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.createBreakpointRule(for: $1) }
        }

        @objc
        func handleNetworkConditions(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.createNetworkConditionsRule(for: $1) }
        }

        @objc
        func handleSSLProxying(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.enableSSLProxying(for: $1) }
        }

        @objc
        func handleExportHAR(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.exportTransactionAsHAR($1) }
        }

        @objc
        func handleExportRequestBody(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.exportRequestBody(for: $1) }
        }

        @objc
        func handleExportResponseBody(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.exportResponseBody(for: $1) }
        }

        @objc
        func handleDelete(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.deleteTransactions([$1]) }
        }

        @objc
        func handleCompareSelected(_ sender: NSMenuItem) {
            guard let tableView,
                  let coordinator = mainCoordinator else
            {
                return
            }
            let selected = tableView.selectedRowIndexes
            guard selected.count == 2 else {
                return
            }
            let sorted = selected.sorted()
            guard sorted[0] < rows.count, sorted[1] < rows.count else {
                return
            }
            MainActor.assumeIsolated {
                guard let a = coordinator.transaction(for: rows[sorted[0]].id),
                      let b = coordinator.transaction(for: rows[sorted[1]].id) else
                {
                    return
                }
                coordinator.compareTransactions(a, b)
            }
        }

        func syncSelection(to ids: Set<UUID>, in tableView: NSTableView) {
            let currentSelected = tableView.selectedRowIndexes
            var desired = IndexSet()
            for (index, rowData) in rows.enumerated() where ids.contains(rowData.id) {
                desired.insert(index)
            }

            guard currentSelected != desired else {
                return
            }

            isUpdatingSelection = true
            tableView.selectRowIndexes(desired, byExtendingSelection: false)
            isUpdatingSelection = false
        }

        func syncHeaderColumns(in tableView: NSTableView) {
            MainActor.assumeIsolated {
                guard let store = mainCoordinator?.headerColumnStore else {
                    return
                }

                let enabledIDs = Set(store.enabledColumns.map(\.columnIdentifier))
                let existingCustomIDs = Set(
                    tableView.tableColumns
                        .map(\.identifier.rawValue)
                        .filter { $0.hasPrefix("reqHeader.") || $0.hasPrefix("resHeader.") }
                )

                for colID in existingCustomIDs.subtracting(enabledIDs) {
                    if let col = tableView.tableColumns.first(where: { $0.identifier.rawValue == colID }) {
                        tableView.removeTableColumn(col)
                    }
                }

                for colID in enabledIDs.subtracting(existingCustomIDs) {
                    if let headerCol = store.enabledColumns.first(where: { $0.columnIdentifier == colID }) {
                        let col = NSTableColumn(
                            identifier: NSUserInterfaceItemIdentifier(headerCol.columnIdentifier)
                        )
                        col.title = headerCol.headerName
                        col.width = 100
                        col.minWidth = 50
                        col.resizingMask = .userResizingMask
                        col.sortDescriptorPrototype = NSSortDescriptor(
                            key: headerCol.columnIdentifier, ascending: true
                        )
                        tableView.addTableColumn(col)
                    }
                }
            }
        }

        func syncSortDescriptors(from descriptors: [NSSortDescriptor], into tableView: NSTableView) {
            guard tableView.sortDescriptors != descriptors else {
                return
            }
            isUpdatingSortDescriptors = true
            tableView.sortDescriptors = descriptors
            isUpdatingSortDescriptors = false
        }

        @objc
        func handleToggleHeaderColumn(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else {
                return
            }
            MainActor.assumeIsolated {
                mainCoordinator?.headerColumnStore.toggleColumn(id: id)
            }
        }

        @objc
        func handleAddDiscoveredHeader(_ sender: NSMenuItem) {
            guard let info = sender.representedObject as? [String: String],
                  let name = info["name"],
                  let sourceStr = info["source"] else
            {
                return
            }
            let source: HeaderColumnSource = sourceStr == "request" ? .request : .response
            MainActor.assumeIsolated {
                mainCoordinator?.headerColumnStore.addColumn(headerName: name, source: source)
            }
        }

        @objc
        func handleOpenColumnManager(_ sender: NSMenuItem) {
            NotificationCenter.default.post(
                name: RockxyIdentity.current.notificationName("openCustomColumnsWindow"),
                object: nil
            )
        }

        @objc
        func handleToggleBuiltInColumn(_ sender: NSMenuItem) {
            guard let colID = sender.representedObject as? String else {
                return
            }
            MainActor.assumeIsolated {
                mainCoordinator?.headerColumnStore.toggleBuiltInColumn(colID)
                // Hide/show the column in the table
                if let tableView,
                   let col = tableView.tableColumns.first(where: { $0.identifier.rawValue == colID })
                {
                    col.isHidden = !(mainCoordinator?.headerColumnStore.isBuiltInColumnVisible(colID) ?? true)
                }
                tableView?.sizeLastColumnToFit()
            }
        }

        // MARK: Private

        private static let logger = Logger(
            subsystem: RockxyIdentity.current.logSubsystem,
            category: "RequestTableView"
        )

        private static let clientIconColors: [NSColor] = [
            colorFromHex(0x3399DB), // blue
            colorFromHex(0x29B577), // green
            colorFromHex(0xD9544F), // red
            colorFromHex(0x9C59B5), // purple
            colorFromHex(0xE67D21), // orange
            colorFromHex(0x10A380), // teal
            colorFromHex(0xD42E6B), // pink
            colorFromHex(0x667F99), // slate
        ]

        private static let knownAppColors: [String: NSColor] = [
            "ChatGPT": colorFromHex(0x10A37F),
            "Chrome": colorFromHex(0x4285F4),
            "Safari": colorFromHex(0x007AFF),
            "Firefox": colorFromHex(0xFF7300),
            "System": colorFromHex(0x595961),
            "Google Drive": colorFromHex(0x0F8561),
            "Code Helper": colorFromHex(0x2E3340),
            "Xcode": colorFromHex(0x2978FC),
            "Slack": colorFromHex(0x3D1759),
        ]

        // MARK: - Client Cell with App Icons

        private static var appIconCache: [String: NSImage] = [:]

        private static let bundleIDByAppName: [String: String] = [
            "Chrome": "com.google.Chrome",
            "Safari": "com.apple.Safari",
            "Firefox": "org.mozilla.firefox",
            "Slack": "com.tinyspeck.slackmacgap",
            "Xcode": "com.apple.dt.Xcode",
            "ChatGPT": "com.openai.chat",
            "Google Drive": "com.google.drivefs",
            "Code Helper": "com.microsoft.VSCode",
            "Spotify": "com.spotify.client",
            "Discord": "com.hnc.Discord",
            "Telegram": "ru.keepcoder.Telegram",
            "WhatsApp": "net.whatsapp.WhatsApp",
            "Postman": "com.postmanlabs.mac",
            "Figma": "com.figma.Desktop",
            "Arc": "company.thebrowser.Browser",
            "Brave Browser": "com.brave.Browser",
            "Microsoft Edge": "com.microsoft.edgemac",
            "Opera": "com.operasoftware.Opera",
        ]

        private static func colorFromHex(_ hex: UInt32) -> NSColor {
            let red = CGFloat((hex >> 16) & 0xFF) / 255.0
            let green = CGFloat((hex >> 8) & 0xFF) / 255.0
            let blue = CGFloat(hex & 0xFF) / 255.0
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
        }

        // MARK: - Menu Building

        private func menuItem(
            _ title: String,
            action: Selector,
            key: String = "",
            modifiers: NSEvent.ModifierFlags = .command,
            symbol: String? = nil,
            transaction: HTTPTransaction
        )
            -> NSMenuItem
        {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
            item.representedObject = transaction
            if let symbol {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            return item
        }

        private func buildCopyGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            menu.addItem(menuItem(
                String(localized: "Copy URL"), action: #selector(handleCopyURL(_:)),
                key: "c", symbol: "doc.on.doc", transaction: transaction
            ))
            menu.addItem(menuItem(
                String(localized: "Copy cURL"), action: #selector(handleCopyCURL(_:)),
                key: "c", modifiers: [.command, .shift], transaction: transaction
            ))
            menu.addItem(menuItem(
                String(localized: "Copy Cell Value"), action: #selector(handleCopyCellValue(_:)),
                transaction: transaction
            ))

            let copyAsSubmenu = NSMenu()
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Request Headers"), action: #selector(handleCopyRequestHeaders(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Response Headers"), action: #selector(handleCopyResponseHeaders(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Request Body"), action: #selector(handleCopyRequestBody(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Response Body"), action: #selector(handleCopyResponseBody(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(.separator())
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Request Cookies"), action: #selector(handleCopyRequestCookies(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Response Cookies"), action: #selector(handleCopyResponseCookies(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(.separator())
            copyAsSubmenu.addItem(menuItem(
                "JSON", action: #selector(handleCopyAsJSON(_:)), transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                "HAR Entry", action: #selector(handleCopyAsHAR(_:)), transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Raw Request"), action: #selector(handleCopyRawRequest(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Raw Response"), action: #selector(handleCopyRawResponse(_:)),
                transaction: transaction
            ))
            let copyAsItem = NSMenuItem(
                title: String(localized: "Copy as"), action: nil, keyEquivalent: ""
            )
            copyAsItem.submenu = copyAsSubmenu
            menu.addItem(copyAsItem)
        }

        private func buildRepeatGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            menu.addItem(menuItem(
                String(localized: "Repeat"), action: #selector(handleRepeat(_:)),
                key: "\r", symbol: "arrow.clockwise", transaction: transaction
            ))
            menu.addItem(menuItem(
                String(localized: "Edit and Repeat…"), action: #selector(handleEditAndRepeat(_:)),
                key: "\r", modifiers: [.command, .option], transaction: transaction
            ))
        }

        private func buildPinGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            let pinTitle = transaction.isPinned
                ? String(localized: "Unpin")
                : String(localized: "Pin")
            let pinSymbol = transaction.isPinned ? "pin.slash" : "pin"
            menu.addItem(menuItem(
                pinTitle, action: #selector(handleTogglePin(_:)),
                symbol: pinSymbol, transaction: transaction
            ))
            let saveTitle = transaction.isSaved
                ? String(localized: "Unsave")
                : String(localized: "Save this Request")
            let saveSymbol = transaction.isSaved ? "tray.full.fill" : "tray.and.arrow.down.fill"
            menu.addItem(menuItem(
                saveTitle, action: #selector(handleSaveRequest(_:)),
                key: "s", modifiers: [.command, .shift], symbol: saveSymbol, transaction: transaction
            ))
        }

        private func buildToolsGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            let toolsSubmenu = NSMenu()
            let mapLocalItem = menuItem(
                String(localized: "Map Local…"), action: #selector(handleMapLocal(_:)),
                transaction: transaction
            )
            mapLocalItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            toolsSubmenu.addItem(mapLocalItem)

            let mapRemoteItem = menuItem(
                String(localized: "Map Remote…"), action: #selector(handleMapRemote(_:)),
                transaction: transaction
            )
            mapRemoteItem.image = NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: nil)
            toolsSubmenu.addItem(mapRemoteItem)

            let blockItem = menuItem(
                String(localized: "Block List…"), action: #selector(handleBlock(_:)),
                transaction: transaction
            )
            blockItem.image = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)
            toolsSubmenu.addItem(blockItem)

            let breakpointItem = menuItem(
                String(localized: "Breakpoint…"), action: #selector(handleBreakpoint(_:)),
                transaction: transaction
            )
            breakpointItem.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
            toolsSubmenu.addItem(breakpointItem)

            let networkConditionsItem = menuItem(
                String(localized: "Network Conditions…"), action: #selector(handleNetworkConditions(_:)),
                transaction: transaction
            )
            networkConditionsItem.image = NSImage(
                systemSymbolName: "wifi.exclamationmark",
                accessibilityDescription: nil
            )
            toolsSubmenu.addItem(networkConditionsItem)

            toolsSubmenu.addItem(.separator())

            let sslItem = menuItem(
                String(localized: "SSL Proxying"), action: #selector(handleSSLProxying(_:)),
                transaction: transaction
            )
            sslItem.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
            toolsSubmenu.addItem(sslItem)

            let toolsItem = NSMenuItem(title: String(localized: "Tools"), action: nil, keyEquivalent: "")
            toolsItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
            toolsItem.submenu = toolsSubmenu
            menu.addItem(toolsItem)
        }

        private func buildAnnotationGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            menu.addItem(menuItem(
                String(localized: "Add Comment…"), action: #selector(handleAddComment(_:)),
                key: "l", symbol: "pencil.line", transaction: transaction
            ))

            let highlightSubmenu = NSMenu()
            let colors: [(String, HighlightColor)] = [
                (String(localized: "Red"), .red),
                (String(localized: "Orange"), .orange),
                (String(localized: "Yellow"), .yellow),
                (String(localized: "Green"), .green),
                (String(localized: "Blue"), .blue),
                (String(localized: "Purple"), .purple),
            ]
            for (name, color) in colors {
                let item = menuItem(
                    name, action: #selector(handleHighlight(_:)), transaction: transaction
                )
                item.tag = HighlightColor.allCases.firstIndex(of: color) ?? 0
                item.image = colorCircleImage(color.nsColor)
                if transaction.highlightColor == color {
                    item.state = .on
                }
                highlightSubmenu.addItem(item)
            }
            highlightSubmenu.addItem(.separator())
            let removeItem = menuItem(
                String(localized: "Remove Highlight"), action: #selector(handleRemoveHighlight(_:)),
                transaction: transaction
            )
            removeItem.isEnabled = transaction.highlightColor != nil
            highlightSubmenu.addItem(removeItem)

            let highlightItem = NSMenuItem(
                title: String(localized: "Highlight"), action: nil, keyEquivalent: ""
            )
            highlightItem.submenu = highlightSubmenu
            menu.addItem(highlightItem)
        }

        private func buildExportGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            let exportSubmenu = NSMenu()
            exportSubmenu.addItem(menuItem(
                String(localized: "Export as HAR…"), action: #selector(handleExportHAR(_:)),
                transaction: transaction
            ))
            let reqBodyItem = menuItem(
                String(localized: "Export Request Body…"), action: #selector(handleExportRequestBody(_:)),
                transaction: transaction
            )
            reqBodyItem.isEnabled = transaction.request.body != nil
            exportSubmenu.addItem(reqBodyItem)

            let respBodyItem = menuItem(
                String(localized: "Export Response Body…"), action: #selector(handleExportResponseBody(_:)),
                transaction: transaction
            )
            respBodyItem.isEnabled = transaction.response?.body != nil
            exportSubmenu.addItem(respBodyItem)

            let exportItem = NSMenuItem(title: String(localized: "Export"), action: nil, keyEquivalent: "")
            exportItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
            exportItem.submenu = exportSubmenu
            menu.addItem(exportItem)

            menu.addItem(menuItem(
                String(localized: "Enable SSL Proxying"), action: #selector(handleSSLProxying(_:)),
                transaction: transaction
            ))
        }

        private func buildCompareGroup(_ menu: NSMenu) {
            let selectedCount = tableView?.selectedRowIndexes.count ?? 0
            let item = NSMenuItem(
                title: String(localized: "Compare Selected"),
                action: selectedCount == 2 ? #selector(handleCompareSelected(_:)) : nil,
                keyEquivalent: ""
            )
            item.target = self
            item.image = NSImage(
                systemSymbolName: "arrow.left.arrow.right",
                accessibilityDescription: nil
            )
            if selectedCount != 2 {
                item.isEnabled = false
            }
            menu.addItem(item)
        }

        private func buildDeleteGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            let item = menuItem(
                String(localized: "Delete"), action: #selector(handleDelete(_:)),
                key: "\u{8}", modifiers: [], symbol: "trash", transaction: transaction
            )
            menu.addItem(item)
        }

        // MARK: - Column Header Context Menu

        @MainActor
        private func buildColumnHeaderMenu(_ menu: NSMenu) {
            guard let store = mainCoordinator?.headerColumnStore else {
                return
            }

            // Built-in column visibility
            let builtInColumns: [(id: String, title: String)] = [
                ("status", String(localized: "Status Icon")),
                ("row", "#"),
                ("url", String(localized: "URL")),
                ("client", String(localized: "Client")),
                ("method", String(localized: "Method")),
                ("code", String(localized: "Code")),
                ("time", String(localized: "Time")),
                ("duration", String(localized: "Duration")),
                ("size", String(localized: "Size")),
                ("queryName", String(localized: "Query Name")),
            ]

            for col in builtInColumns {
                let item = NSMenuItem(
                    title: col.title,
                    action: #selector(handleToggleBuiltInColumn(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = col.id
                item.state = store.isBuiltInColumnVisible(col.id) ? .on : .off
                menu.addItem(item)
            }

            menu.addItem(.separator())

            let reqSubmenu = NSMenu()
            for col in store.requestColumns {
                let item = NSMenuItem(
                    title: col.headerName,
                    action: #selector(handleToggleHeaderColumn(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = col.id
                item.state = col.isEnabled ? .on : .off
                reqSubmenu.addItem(item)
            }

            if let coordinator = mainCoordinator {
                let discovered = store.discoverHeaders(from: coordinator.transactions)
                if !discovered.request.isEmpty, !store.requestColumns.isEmpty {
                    reqSubmenu.addItem(.separator())
                }
                for name in discovered.request {
                    let item = NSMenuItem(
                        title: name,
                        action: #selector(handleAddDiscoveredHeader(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = ["name": name, "source": "request"]
                    reqSubmenu.addItem(item)
                }
            }

            reqSubmenu.addItem(.separator())
            let manageReqItem = NSMenuItem(
                title: String(localized: "Manage Header Columns…"),
                action: #selector(handleOpenColumnManager(_:)),
                keyEquivalent: ""
            )
            manageReqItem.target = self
            reqSubmenu.addItem(manageReqItem)

            let reqItem = NSMenuItem(
                title: String(localized: "Request Headers"), action: nil, keyEquivalent: ""
            )
            reqItem.submenu = reqSubmenu
            menu.addItem(reqItem)

            let resSubmenu = NSMenu()
            for col in store.responseColumns {
                let item = NSMenuItem(
                    title: col.headerName,
                    action: #selector(handleToggleHeaderColumn(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = col.id
                item.state = col.isEnabled ? .on : .off
                resSubmenu.addItem(item)
            }

            if let coordinator = mainCoordinator {
                let discovered = store.discoverHeaders(from: coordinator.transactions)
                if !discovered.response.isEmpty, !store.responseColumns.isEmpty {
                    resSubmenu.addItem(.separator())
                }
                for name in discovered.response {
                    let item = NSMenuItem(
                        title: name,
                        action: #selector(handleAddDiscoveredHeader(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = ["name": name, "source": "response"]
                    resSubmenu.addItem(item)
                }
            }

            resSubmenu.addItem(.separator())
            let manageResItem = NSMenuItem(
                title: String(localized: "Manage Header Columns…"),
                action: #selector(handleOpenColumnManager(_:)),
                keyEquivalent: ""
            )
            manageResItem.target = self
            resSubmenu.addItem(manageResItem)

            let resItem = NSMenuItem(
                title: String(localized: "Response Headers"), action: nil, keyEquivalent: ""
            )
            resItem.submenu = resSubmenu
            menu.addItem(resItem)
        }

        // MARK: - Color Circle for Highlight Menu

        private func colorCircleImage(_ color: NSColor) -> NSImage {
            let size = NSSize(width: 12, height: 12)
            let image = NSImage(size: size, flipped: false) { rect in
                color.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
            image.isTemplate = false
            return image
        }

        // MARK: - Context Menu Action Handlers

        private func withCoordinator(
            _ sender: NSMenuItem,
            _ action: @MainActor (MainContentCoordinator, HTTPTransaction) -> Void
        ) {
            guard let transaction = sender.representedObject as? HTTPTransaction,
                  let coordinator = mainCoordinator else
            {
                return
            }
            MainActor.assumeIsolated {
                action(coordinator, transaction)
            }
        }

        private func clientIconColor(for appName: String) -> NSColor {
            if let known = Self.knownAppColors[appName] {
                return known
            }
            let hash = abs(appName.hashValue)
            return Self.clientIconColors[hash % Self.clientIconColors.count]
        }

        private func clientIconInitials(for appName: String) -> String {
            let trimmed = appName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                return "?"
            }

            let words = trimmed.split(separator: " ")
            if words.count >= 2 {
                let first = words[0].prefix(1)
                let second = words[1].prefix(1)
                return "\(first)\(second)".uppercased()
            }
            return String(trimmed.prefix(2)).uppercased()
        }

        // MARK: - Status Dot

        private func makeStatusDotView(
            row: RequestListRow,
            in tableView: NSTableView
        )
            -> NSView
        {
            let cellID = NSUserInterfaceItemIdentifier("Cell_status")
            let dotSize: CGFloat = 8
            let rowHeight: CGFloat = 28

            if let existing = tableView.makeView(withIdentifier: cellID, owner: nil),
               let imageView = existing.subviews.first as? NSImageView
            {
                imageView.contentTintColor = statusDotColor(for: row)
                return existing
            }

            let container = NSView()
            container.identifier = cellID

            let imageView = NSImageView(frame: NSRect(
                x: (20 - dotSize) / 2,
                y: (rowHeight - dotSize) / 2,
                width: dotSize,
                height: dotSize
            ))

            if let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) {
                imageView.image = image
            }
            imageView.contentTintColor = statusDotColor(for: row)
            container.addSubview(imageView)
            return container
        }

        private func statusDotColor(for row: RequestListRow) -> NSColor {
            switch row.state {
            case .pending,
                 .active:
                return .systemYellow
            case .completed:
                guard let code = row.statusCode else {
                    return .systemGreen
                }
                switch code {
                case 200 ..< 300: return .systemGreen
                case 300 ..< 400: return .systemBlue
                case 400 ..< 500: return .systemOrange
                case 500 ..< 600: return .systemRed
                default: return .systemGray
                }
            case .failed:
                return .systemRed
            case .blocked:
                return .systemGray
            }
        }

        private func appIcon(for appName: String) -> NSImage? {
            if let cached = Self.appIconCache[appName] {
                return cached
            }

            if let bundleID = Self.bundleIDByAppName[appName],
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 16, height: 16)
                Self.appIconCache[appName] = icon
                return icon
            }

            let appPaths = [
                "/Applications/\(appName).app",
                "/System/Applications/\(appName).app",
                "/Applications/Utilities/\(appName).app",
            ]
            for path in appPaths {
                if FileManager.default.fileExists(atPath: path) {
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    icon.size = NSSize(width: 16, height: 16)
                    Self.appIconCache[appName] = icon
                    return icon
                }
            }

            for app in NSWorkspace.shared.runningApplications {
                if app.localizedName == appName, let icon = app.icon {
                    icon.size = NSSize(width: 16, height: 16)
                    Self.appIconCache[appName] = icon
                    return icon
                }
            }

            return nil
        }

        private func makeClientCellView(
            appName: String,
            identifier: NSUserInterfaceItemIdentifier,
            in tableView: NSTableView
        )
            -> NSView
        {
            let iconSize: CGFloat = 16
            let gap: CGFloat = 4
            let rowHeight: CGFloat = 28
            let iconY = (rowHeight - iconSize) / 2
            let labelHeight: CGFloat = 18

            // Reuse existing cell: subviews order is [imageView, fallbackView, nameLabel]
            if let existing = tableView.makeView(withIdentifier: identifier, owner: nil),
               existing.subviews.count == 3
            {
                let imageView = existing.subviews[0] as? NSImageView
                let fallbackView = existing.subviews[1]
                let nameLabel = existing.subviews[2] as? NSTextField

                nameLabel?.stringValue = appName
                if let icon = appIcon(for: appName) {
                    imageView?.image = icon
                    imageView?.isHidden = false
                    fallbackView.isHidden = true
                } else {
                    imageView?.isHidden = true
                    fallbackView.isHidden = false
                    fallbackView.layer?.backgroundColor = clientIconColor(for: appName).cgColor
                    if let initialsLabel = fallbackView.subviews.first as? NSTextField {
                        initialsLabel.stringValue = clientIconInitials(for: appName)
                    }
                }
                return existing
            }

            let container = NSView()
            container.identifier = identifier

            // Subview 0: app icon image
            let imageView = NSImageView(frame: NSRect(x: 0, y: iconY, width: iconSize, height: iconSize))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            container.addSubview(imageView)

            // Subview 1: fallback initials badge
            let fallbackView = NSView(frame: NSRect(x: 0, y: iconY, width: iconSize, height: iconSize))
            fallbackView.wantsLayer = true
            fallbackView.layer?.cornerRadius = 4
            let initialsLabel = NSTextField(labelWithString: "")
            initialsLabel.font = .systemFont(ofSize: 7, weight: .bold)
            initialsLabel.textColor = .white
            initialsLabel.alignment = .center
            initialsLabel.frame = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
            initialsLabel.autoresizingMask = [.width, .height]
            fallbackView.addSubview(initialsLabel)
            container.addSubview(fallbackView)

            // Subview 2: app name label
            let nameLabel = NSTextField(labelWithString: "")
            nameLabel.font = .systemFont(ofSize: 12)
            nameLabel.textColor = .secondaryLabelColor
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(nameLabel)

            NSLayoutConstraint.activate([
                nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: iconSize + gap),
                nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                nameLabel.heightAnchor.constraint(equalToConstant: labelHeight),
            ])

            // Populate content
            nameLabel.stringValue = appName
            if let icon = appIcon(for: appName) {
                imageView.image = icon
                imageView.isHidden = false
                fallbackView.isHidden = true
            } else {
                imageView.isHidden = true
                fallbackView.isHidden = false
                fallbackView.layer?.backgroundColor = clientIconColor(for: appName).cgColor
                initialsLabel.stringValue = clientIconInitials(for: appName)
            }

            return container
        }

        private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSView {
            let container = NSView()
            container.identifier = identifier

            let textHeight: CGFloat = 17
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.font = .systemFont(ofSize: 12)
            field.textColor = .labelColor
            field.isBordered = false
            field.drawsBackground = false
            field.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(field)

            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                field.heightAnchor.constraint(equalToConstant: textHeight),
            ])

            return container
        }

        private func configureCellContent(
            _ cell: NSTextField,
            column: String,
            row: Int,
            rowData: RequestListRow
        ) {
            cell.stringValue = ""
            cell.textColor = .labelColor
            cell.alignment = .left
            cell.font = .systemFont(ofSize: 12)

            switch column {
            case "row":
                cell.stringValue = "\(rowData.sequenceNumber)"
                cell.alignment = .right
                cell.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                cell.textColor = .secondaryLabelColor

            case "url":
                cell.stringValue = rowData.host + rowData.path
                cell.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                cell.textColor = .labelColor

            case "method":
                cell.alignment = .center
                let method = rowData.method
                let color = methodColor(for: method)
                cell.attributedStringValue = NSAttributedString(
                    string: method,
                    attributes: [
                        .foregroundColor: color,
                        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    ]
                )

            case "code":
                cell.alignment = .center
                if let code = rowData.statusCode {
                    let color = statusCodeColor(for: code)
                    cell.attributedStringValue = NSAttributedString(
                        string: "\(code)",
                        attributes: [
                            .foregroundColor: color,
                            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                        ]
                    )
                } else {
                    cell.stringValue = stateLabel(for: rowData.state)
                    cell.textColor = .tertiaryLabelColor
                    cell.font = .systemFont(ofSize: 11)
                }

            case "time":
                cell.stringValue = RequestTableView.timeFormatter.string(from: rowData.timestamp)
                cell.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                cell.textColor = .secondaryLabelColor

            case "duration":
                cell.alignment = .right
                if let duration = rowData.totalDuration {
                    cell.stringValue = DurationFormatter.format(seconds: duration)
                } else {
                    cell.stringValue = "—"
                }
                cell.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                cell.textColor = .secondaryLabelColor

            case "size":
                cell.alignment = .right
                if let bodySize = rowData.responseBodySize {
                    cell.stringValue = SizeFormatter.format(bytes: bodySize)
                } else {
                    cell.stringValue = "—"
                }
                cell.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                cell.textColor = .secondaryLabelColor

            case "queryName":
                if rowData.isWebSocket {
                    let count = rowData.webSocketFrameCount
                    cell.stringValue = "\(count) \(count == 1 ? "frame" : "frames")"
                    cell.textColor = .tertiaryLabelColor
                } else {
                    cell.stringValue = rowData.graphQLOpName ?? ""
                    cell.textColor = .secondaryLabelColor
                }

            default:
                if column.hasPrefix("reqHeader.") || column.hasPrefix("resHeader.") {
                    cell.stringValue = RequestListRow.resolveHeaderValue(for: column, row: rowData)
                    cell.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                    cell.textColor = .secondaryLabelColor
                } else {
                    cell.stringValue = ""
                }
            }
        }

        private func methodColor(for method: String) -> NSColor {
            switch method.uppercased() {
            case "GET": .systemBlue
            case "POST": .systemGreen
            case "PUT": .systemOrange
            case "PATCH": .systemYellow
            case "DELETE": .systemRed
            default: .labelColor
            }
        }

        private func statusCodeColor(for code: Int) -> NSColor {
            switch code {
            case 200 ..< 300: .systemGreen
            case 300 ..< 400: .systemBlue
            case 400 ..< 500: .systemOrange
            case 500 ..< 600: .systemRed
            default: .labelColor
            }
        }

        private func stateLabel(for state: TransactionState) -> String {
            switch state {
            case .pending: "..."
            case .active: "..."
            case .completed: ""
            case .failed: "err"
            case .blocked: "blk"
            }
        }
    }
}
