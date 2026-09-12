import AppKit
import os
import SwiftUI

// MARK: - RequestTableBoundaryNavigation

// swiftlint:disable file_length

// Renders the request table interface for traffic list presentation.

enum RequestTableBoundaryNavigation: Equatable {
    case first
    case last

    // MARK: Internal

    static func resolve(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    )
        -> Self?
    {
        let relevantModifiers = modifierFlags.intersection([.command, .option, .control, .shift])
        guard relevantModifiers == .command else {
            return nil
        }

        switch keyCode {
        case 126:
            return .first // Up Arrow
        case 125:
            return .last // Down Arrow
        default:
            return nil
        }
    }
}

// MARK: - NavigableRequestTableView

/// Owns request-table-only key equivalents. Keeping these commands on the AppKit table means
/// Command-Up/Down retain their standard behavior everywhere else, including editable fields.
final class NavigableRequestTableView: NSTableView {
    var onBoundaryNavigation: ((RequestTableBoundaryNavigation) -> Void)?

    override func keyDown(with event: NSEvent) {
        guard let navigation = RequestTableBoundaryNavigation.resolve(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) else {
            super.keyDown(with: event)
            return
        }

        onBoundaryNavigation?(navigation)
    }
}

// MARK: - RequestTableView

/// AppKit `NSTableView` wrapped in `NSViewRepresentable` for the main request list.
/// Uses NSTableView instead of SwiftUI List because SwiftUI List cannot handle 100k+ rows
/// with acceptable scroll performance — NSTableView provides native virtual scrolling,
/// cell reuse, and column sorting out of the box.
struct RequestTableView: NSViewRepresentable {
    // MARK: Internal

    let workspaceID: UUID
    let rows: [RequestListRow]
    let refreshToken: Int
    let isAppendOnly: Bool
    var appendChainOrigin: Int?
    var selectionIndex: [UUID: TrafficSelectionIndexEntry] = [:]
    var revealRequest: TrafficRevealRequest?
    var displayMetricsOverride: AppUIDisplayMetrics?
    @Binding var selectedIDs: Set<UUID>

    var onSelectionChanged: ((Set<UUID>, UUID?) -> Void)?
    var onUserScroll: (() -> Void)?
    var onDoubleClick: ((HTTPTransaction) -> Void)?
    var mainCoordinator: MainContentCoordinator?
    var headerColumns: [HeaderColumn] = []

    static func makeColumns() -> [NSTableColumn] {
        let specs: [ColumnSpec] = [
            ColumnSpec(id: "status", title: "", width: 22, minWidth: 22),
            ColumnSpec(
                id: "row",
                title: String(localized: "ID", bundle: RockxyLocalization.bundle),
                width: 46,
                minWidth: 36
            ),
            ColumnSpec(
                id: "ai",
                title: String(localized: "Protocol", bundle: RockxyLocalization.bundle),
                width: 92,
                minWidth: 64
            ),
            ColumnSpec(
                id: "url",
                title: String(localized: "URL", bundle: RockxyLocalization.bundle),
                width: 300,
                minWidth: 200
            ),
            ColumnSpec(
                id: "client",
                title: String(localized: "Client", bundle: RockxyLocalization.bundle),
                width: 120,
                minWidth: 60
            ),
            ColumnSpec(
                id: "method",
                title: String(localized: "Method", bundle: RockxyLocalization.bundle),
                width: 82,
                minWidth: 72
            ),
            ColumnSpec(
                id: "state",
                title: String(localized: "Status", bundle: RockxyLocalization.bundle),
                width: 150,
                minWidth: 112
            ),
            ColumnSpec(
                id: "code",
                title: String(localized: "Compact HTTP status code", bundle: RockxyLocalization.bundle),
                width: 52,
                minWidth: 44
            ),
            ColumnSpec(
                id: "time",
                title: String(localized: "Time", bundle: RockxyLocalization.bundle),
                width: 80,
                minWidth: 60
            ),
            ColumnSpec(
                id: "duration",
                title: String(localized: "Duration", bundle: RockxyLocalization.bundle),
                width: 70,
                minWidth: 50
            ),
            ColumnSpec(
                id: "requestSize",
                title: String(localized: "Request", bundle: RockxyLocalization.bundle),
                width: 78,
                minWidth: 60
            ),
            ColumnSpec(
                id: "responseSize",
                title: String(localized: "Response", bundle: RockxyLocalization.bundle),
                width: 78,
                minWidth: 60
            ),
            ColumnSpec(
                id: "ssl",
                title: String(localized: "SSL", bundle: RockxyLocalization.bundle),
                width: 38,
                minWidth: 32
            ),
            ColumnSpec(
                id: "queryName",
                title: String(localized: "Operation", bundle: RockxyLocalization.bundle),
                width: 110,
                minWidth: 70
            ),
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
                column.maxWidth = 22
            } else if spec.id == "ai" {
                column.maxWidth = 112
                column.sortDescriptorPrototype = NSSortDescriptor(
                    key: spec.id,
                    ascending: true
                )
            } else if spec.id == "ssl" {
                column.maxWidth = 42
            } else {
                column.sortDescriptorPrototype = NSSortDescriptor(
                    key: spec.id,
                    ascending: true
                )
            }

            return column
        }
    }

    static func migrateLegacyDefaultColumnOrder(in tableView: NSTableView) {
        let legacyBuiltInOrder = [
            "status", "ai", "row", "url", "client", "method", "state", "code", "time",
            "duration", "requestSize", "responseSize", "ssl", "queryName",
        ]
        let columnIDs = tableView.tableColumns.map(\.identifier.rawValue)
        guard columnIDs.count >= legacyBuiltInOrder.count,
              Array(columnIDs.prefix(legacyBuiltInOrder.count)) == legacyBuiltInOrder,
              columnIDs.dropFirst(legacyBuiltInOrder.count).allSatisfy({ columnID in
                  columnID.hasPrefix("reqHeader.") || columnID.hasPrefix("resHeader.")
              }),
              let protocolIndex = columnIDs.firstIndex(of: "ai"),
              let rowIndex = columnIDs.firstIndex(of: "row") else
        {
            return
        }

        tableView.moveColumn(protocolIndex, toColumn: rowIndex)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let tableView = NavigableRequestTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 4, height: 0)
        tableView.headerView = NSTableHeaderView()
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.onBoundaryNavigation = { [weak coordinator = context.coordinator] navigation in
            MainActor.assumeIsolated {
                switch navigation {
                case .first:
                    coordinator?.mainCoordinator?.selectFirstFilteredTransaction()
                case .last:
                    coordinator?.mainCoordinator?.selectLastFilteredTransaction()
                }
            }
        }

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        for column in Self.makeColumns() {
            tableView.addTableColumn(column)
        }

        for headerCol in headerColumns.filter(\.isEnabled) {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(headerCol.columnIdentifier))
            col.title = headerCol.headerName
            col.width = 100
            col.minWidth = 50
            col.resizingMask = .userResizingMask
            col.sortDescriptorPrototype = NSSortDescriptor(key: headerCol.columnIdentifier, ascending: true)
            tableView.addTableColumn(col)
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
        Self.migrateLegacyDefaultColumnOrder(in: tableView)

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
        context.coordinator.observeUserScrolling(in: scrollView)
        context.coordinator.applyDisplayMetrics(to: tableView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else {
            return
        }

        let coordinator = context.coordinator
        let oldToken = coordinator.lastRefreshToken
        let newToken = refreshToken
        let oldWorkspaceID = coordinator.lastWorkspaceID
        let workspaceChanged = oldWorkspaceID != workspaceID

        coordinator.parent = self
        coordinator.rows = rows
        coordinator.mainCoordinator = mainCoordinator
        coordinator.lastRefreshToken = newToken
        coordinator.lastWorkspaceID = workspaceID

        let scrollAnchor = !workspaceChanged ? coordinator.makeScrollAnchor(in: tableView) : nil
        let displayChange = coordinator.applyDisplayMetrics(to: tableView)
        var reloadedVisibleRowsForMetrics = false

        if workspaceChanged || newToken != oldToken {
            let newCount = rows.count
            if coordinator.canInsertAppendedRows(
                newCount: newCount,
                isAppendOnly: isAppendOnly,
                appendChainOrigin: appendChainOrigin,
                lastAppliedToken: oldToken,
                workspaceChanged: workspaceChanged,
                tableRowCount: tableView.numberOfRows
            ) {
                // Append-only fast path: coordinator confirmed rows were only appended
                let newIndexes = IndexSet(integersIn: coordinator.previousRowCount ..< newCount)
                coordinator.performProgrammaticTableUpdate {
                    tableView.insertRows(at: newIndexes, withAnimation: [])
                }
                if displayChange?.reloadVisibleRows == true {
                    coordinator.reloadVisibleRows(in: tableView)
                    reloadedVisibleRowsForMetrics = true
                }
            } else {
                coordinator.performProgrammaticTableUpdate {
                    tableView.reloadData()
                }
                reloadedVisibleRowsForMetrics = displayChange?.reloadVisibleRows == true
            }
            coordinator.previousRowCount = newCount
        } else if displayChange?.reloadVisibleRows == true {
            coordinator.reloadVisibleRows(in: tableView)
            reloadedVisibleRowsForMetrics = true
        }

        coordinator.scheduleInitialAutosizeIfNeeded(in: tableView)

        coordinator.syncHeaderColumns(in: tableView)
        coordinator.syncSelection(to: selectedIDs, in: tableView)
        coordinator.syncRevealRequest(
            revealRequest,
            workspaceID: workspaceID,
            in: tableView
        )

        // Re-apply HeaderColumnStore visibility on every update (single source of truth)
        if let store = mainCoordinator?.headerColumnStore {
            for column in tableView.tableColumns {
                let colID = column.identifier.rawValue
                if !colID.hasPrefix("reqHeader."), !colID.hasPrefix("resHeader.") {
                    column.isHidden = !store.isBuiltInColumnVisible(colID)
                }
            }
        }

        // Sync per-workspace sort state into AppKit (e.g., after workspace switch).
        // A removed custom column must not leave the traffic list sorted invisibly.
        let currentSortDescriptors = mainCoordinator?.activeSortDescriptors ?? []
        let reconciledSortDescriptors = coordinator.sortDescriptors(
            currentSortDescriptors,
            availableIn: tableView
        )
        if reconciledSortDescriptors != currentSortDescriptors,
           let mainCoordinator
        {
            mainCoordinator.activeSortDescriptors = reconciledSortDescriptors
            mainCoordinator.activeWorkspace.lastDeriveWasAppendOnly = false
            mainCoordinator.deriveFilteredRows()
        }
        coordinator.syncSortDescriptors(from: reconciledSortDescriptors, into: tableView)

        if displayChange?.rowHeightChanged == true,
           let scrollAnchor
        {
            coordinator.restoreScrollAnchor(scrollAnchor, in: tableView)
        }

        if reloadedVisibleRowsForMetrics {
            coordinator.scheduleVisibleMetricsRefresh(in: tableView, preserving: scrollAnchor)
        }
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

    @Environment(\.appUIDisplayMetrics) private var displayMetrics

    private var effectiveDisplayMetrics: AppUIDisplayMetrics {
        displayMetricsOverride ?? displayMetrics
    }
}

// MARK: - ColumnSpec

private struct ColumnSpec {
    let id: String
    let title: String
    let width: CGFloat
    let minWidth: CGFloat
}

// MARK: - FixedIconCellView

private final class FixedIconCellView: NSView {
    // MARK: Lifecycle

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        let widthConstraint = imageView.widthAnchor.constraint(equalToConstant: 0)
        let heightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)
        self.widthConstraint = widthConstraint
        self.heightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthConstraint,
            heightConstraint,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    // MARK: Internal

    let imageView = NSImageView()

    func updateIconSize(_ size: CGFloat) {
        if widthConstraint?.constant != size {
            widthConstraint?.constant = size
        }
        if heightConstraint?.constant != size {
            heightConstraint?.constant = size
        }
    }

    // MARK: Private

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
}

// MARK: - RequestTableAppliedMetrics

private struct RequestTableAppliedMetrics: Equatable {
    // MARK: Lifecycle

    init(metrics: AppUIDisplayMetrics) {
        rowHeight = metrics.tableRowHeight
        usesAlternatingRowBackgroundColors = metrics.settings.useAlternatingRowBackgroundColors
        headerFontSize = metrics.secondaryFontSize
        contentMetrics = RequestTableContentMetrics(metrics: metrics)
    }

    // MARK: Internal

    let rowHeight: CGFloat
    let usesAlternatingRowBackgroundColors: Bool
    let headerFontSize: CGFloat
    let contentMetrics: RequestTableContentMetrics
}

// MARK: - RequestTableContentMetrics

private struct RequestTableContentMetrics: Equatable {
    // MARK: Lifecycle

    init(metrics: AppUIDisplayMetrics) {
        fontSize = metrics.fontSize
        secondaryFontSize = metrics.secondaryFontSize
        statusDotSize = metrics.tableStatusDotSize
        sslIconSize = metrics.tableSSLIconSize
        clientIconSize = metrics.tableClientIconSize
        useMonospacedFont = metrics.settings.useMonospacedFont
    }

    // MARK: Internal

    let fontSize: CGFloat
    let secondaryFontSize: CGFloat
    let statusDotSize: CGFloat
    let sslIconSize: CGFloat
    let clientIconSize: CGFloat
    let useMonospacedFont: Bool
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

        deinit {
            if let userScrollObserver {
                NotificationCenter.default.removeObserver(userScrollObserver)
            }
        }

        // MARK: Internal

        struct DisplayMetricsChange: Equatable {
            let reloadVisibleRows: Bool
            let autosizeContentColumns: Bool
            let rowHeightChanged: Bool
            let contentMetricsChanged: Bool
        }

        struct ScrollAnchor: Equatable {
            let row: Int
            let intraRowOffset: CGFloat
            let xOffset: CGFloat
        }

        var parent: RequestTableView
        var rows: [RequestListRow]
        var mainCoordinator: MainContentCoordinator?
        weak var tableView: NSTableView?
        var hasAutoSizedColumns = false
        var lastWorkspaceID: UUID?
        var lastClickedColumn: String?
        var lastRefreshToken: Int = 0
        var previousRowCount: Int = 0
        var lastAppliedDisplayMetrics: AppUIDisplayMetrics?
        /// Guard flag to prevent feedback loops: when we programmatically update NSTableView
        /// selection from SwiftUI state, we suppress the delegate callback that would
        /// re-propagate the change back to SwiftUI.
        private(set) var isUpdatingSelection = false

        /// Guard flag to prevent feedback loops when syncing sort descriptors from
        /// coordinator state back into NSTableView.
        private(set) var isUpdatingSortDescriptors = false

        // MARK: - NSTableViewDataSource

        /// AppKit posts this notification only for user-initiated live scrolling, including
        /// trackpad gestures and scroller tracking. Programmatic Follow Live scrolling does not
        /// pass through this path, so it cannot turn itself off.
        func observeUserScrolling(in scrollView: NSScrollView) {
            if let userScrollObserver {
                NotificationCenter.default.removeObserver(userScrollObserver)
            }
            userScrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.parent.onUserScroll?()
                }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        /// Incremental row insertion is valid only when AppKit and the SwiftUI coordinator agree
        /// on the old row count and the current append chain started from a model snapshot this
        /// table has already applied.
        func canInsertAppendedRows(
            newCount: Int,
            isAppendOnly: Bool,
            appendChainOrigin: Int?,
            lastAppliedToken: Int,
            workspaceChanged: Bool,
            tableRowCount: Int
        )
            -> Bool
        {
            guard let appendChainOrigin else {
                return false
            }
            return !workspaceChanged
                && isAppendOnly
                && previousRowCount > 0
                && tableRowCount == previousRowCount
                && appendChainOrigin <= lastAppliedToken
                && newCount > previousRowCount
        }

        /// AppKit may emit selection notifications while rows are inserted or reloaded. Treat the
        /// entire table mutation as coordinator-owned so those callbacks cannot re-enter SwiftUI
        /// selection/filter state halfway through applying a snapshot.
        func performProgrammaticTableUpdate(_ update: () -> Void) {
            let wasUpdatingSelection = isUpdatingSelection
            isUpdatingSelection = true
            defer { isUpdatingSelection = wasUpdatingSelection }
            update()
        }

        @discardableResult
        func applyDisplayMetrics(to tableView: NSTableView) -> DisplayMetricsChange? {
            let metrics = parent.effectiveDisplayMetrics
            let tableMetrics = RequestTableAppliedMetrics(metrics: metrics)
            guard lastAppliedRequestTableMetrics != tableMetrics else {
                lastAppliedDisplayMetrics = metrics
                return nil
            }

            let previousTableMetrics = lastAppliedRequestTableMetrics
            tableView.rowHeight = metrics.tableRowHeight
            tableView.usesAlternatingRowBackgroundColors = metrics.settings.useAlternatingRowBackgroundColors
            applyHeaderMetrics(to: tableView)
            tableView.needsDisplay = true

            lastAppliedDisplayMetrics = metrics
            lastAppliedRequestTableMetrics = tableMetrics

            let contentMetricsChanged = previousTableMetrics?.contentMetrics != tableMetrics.contentMetrics
            let rowHeightChanged = previousTableMetrics?.rowHeight != tableMetrics.rowHeight
            let reloadVisibleRows = previousTableMetrics == nil || contentMetricsChanged || rowHeightChanged
            let autosizeContentColumns = previousTableMetrics == nil

            return DisplayMetricsChange(
                reloadVisibleRows: reloadVisibleRows,
                autosizeContentColumns: autosizeContentColumns,
                rowHeightChanged: rowHeightChanged,
                contentMetricsChanged: contentMetricsChanged
            )
        }

        func applyHeaderMetrics(to tableView: NSTableView) {
            let metrics = parent.effectiveDisplayMetrics
            for column in tableView.tableColumns {
                column.headerCell.font = .systemFont(ofSize: metrics.secondaryFontSize, weight: .medium)
            }
            tableView.headerView?.needsDisplay = true
        }

        func makeScrollAnchor(in tableView: NSTableView) -> ScrollAnchor? {
            let visibleRect = tableView.visibleRect
            let visibleRange = tableView.rows(in: visibleRect)
            guard visibleRange.location != NSNotFound,
                  visibleRange.location >= 0,
                  visibleRange.location < rows.count else
            {
                return nil
            }
            let rowRect = tableView.rect(ofRow: visibleRange.location)
            let intraRowOffset = max(0, visibleRect.minY - rowRect.minY)
            return ScrollAnchor(
                row: visibleRange.location,
                intraRowOffset: intraRowOffset,
                xOffset: visibleRect.minX
            )
        }

        func restoreScrollAnchor(_ anchor: ScrollAnchor, in tableView: NSTableView) {
            guard let scrollView = tableView.enclosingScrollView,
                  anchor.row >= 0,
                  anchor.row < rows.count else
            {
                return
            }
            let rowRect = tableView.rect(ofRow: anchor.row)
            let maxY = max(0, tableView.bounds.height - scrollView.contentView.bounds.height)
            let restoredY = min(max(0, rowRect.minY + anchor.intraRowOffset), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: anchor.xOffset, y: restoredY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func scheduleInitialAutosizeIfNeeded(in tableView: NSTableView) {
            guard !hasAutoSizedColumns, rows.count > 10 else {
                return
            }
            hasAutoSizedColumns = true
            autosizeGeneration += 1
            let generation = autosizeGeneration
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self,
                      let tableView,
                      self.autosizeGeneration == generation else
                {
                    return
                }
                for (index, column) in tableView.tableColumns.enumerated() {
                    let colID = column.identifier.rawValue
                    if colID == "client" || colID == "url" {
                        let width = self.tableView(tableView, sizeToFitWidthOfColumn: index)
                        column.width = width
                    }
                }
            }
        }

        func reloadVisibleRows(in tableView: NSTableView) {
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            guard visibleRange.location != NSNotFound, visibleRange.length > 0 else {
                return
            }
            let rowStart = max(0, visibleRange.location)
            let rowEnd = min(rows.count, visibleRange.location + visibleRange.length)
            guard rowStart < rowEnd else {
                return
            }

            tableView.reloadData(
                forRowIndexes: IndexSet(integersIn: rowStart ..< rowEnd),
                columnIndexes: IndexSet(integersIn: 0 ..< tableView.numberOfColumns)
            )
        }

        func scheduleVisibleMetricsRefresh(
            in tableView: NSTableView,
            preserving scrollAnchor: ScrollAnchor?
        ) {
            visibleMetricsRefreshGeneration += 1
            let generation = visibleMetricsRefreshGeneration
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self,
                      let tableView,
                      self.visibleMetricsRefreshGeneration == generation else
                {
                    return
                }
                self.reloadVisibleRows(in: tableView)
                self.applyHeaderMetrics(to: tableView)
                tableView.needsDisplay = true
                if let scrollAnchor {
                    self.restoreScrollAnchor(scrollAnchor, in: tableView)
                }
            }
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

            if columnID == "ssl" {
                return makeSSLView(row: rowData, in: tableView)
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

            if columnID == "state", isErrorStatus(rowData) {
                return makeErrorStatusBadgeView(row: rowData, in: tableView)
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

            lastSyncedSelectionIDs = ids
            parent.selectedIDs = ids
            let primaryRow = selected.contains(tableView.clickedRow)
                ? tableView.clickedRow
                : tableView.selectedRow
            let primaryID = primaryRow >= 0 && primaryRow < rows.count
                ? rows[primaryRow].id
                : nil
            parent.onSelectionChanged?(ids, primaryID)
        }

        func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
            let tableColumn = tableView.tableColumns[column]
            let columnID = tableColumn.identifier.rawValue

            switch columnID {
            case "status": return 22
            case "ai": return 92
            case "row": return 46
            case "ssl": return 38
            default: break
            }

            var maxWidth = tableColumn.headerCell.cellSize.width + 8
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            let start = max(0, visibleRange.location)
            let end = min(rows.count, visibleRange.location + visibleRange.length)
            let metrics = parent.effectiveDisplayMetrics

            for rowIdx in start ..< end {
                let rowData = rows[rowIdx]
                let text: String
                let font: NSFont

                switch columnID {
                case "url":
                    text = rowData.host + rowData.path
                    font = metrics.appKitFont(monospaced: true)
                case "client":
                    text = rowData.clientApp ?? ""
                    font = metrics.appKitFont()
                case "ai":
                    text = rowData.smartBadgeText
                    font = metrics.appKitFont(weight: .semibold)
                case "method":
                    text = rowData.method
                    font = metrics.appKitFont(weight: .semibold)
                case "state":
                    text = errorStatusBadgeTitle(for: rowData) ?? rowData.displayStatus
                    font = isErrorStatus(rowData)
                        ? metrics.appKitFont(weight: .bold)
                        : metrics.appKitFont(weight: .medium)
                case "code":
                    text = rowData.statusCode.map { "\($0)" } ?? ""
                    font = .monospacedDigitSystemFont(ofSize: metrics.fontSize, weight: .medium)
                case "time":
                    text = RequestTableView.timeFormatter.string(from: rowData.timestamp)
                    font = .monospacedDigitSystemFont(ofSize: metrics.secondaryFontSize, weight: .regular)
                case "duration":
                    text = rowData.totalDuration.map {
                        DurationFormatter.format(seconds: $0)
                    } ?? "—"
                    font = .monospacedDigitSystemFont(ofSize: metrics.secondaryFontSize, weight: .regular)
                case "requestSize":
                    text = rowData.requestSize.map { SizeFormatter.format(bytes: $0) } ?? "—"
                    font = .monospacedDigitSystemFont(ofSize: metrics.secondaryFontSize, weight: .regular)
                case "responseSize":
                    text = rowData.responseSize.map { SizeFormatter.format(bytes: $0) } ?? "—"
                    font = .monospacedDigitSystemFont(ofSize: metrics.secondaryFontSize, weight: .regular)
                case "queryName":
                    // Unified display: WS rows show frame count, Web3 rows show RPC method, GraphQL rows show operation
                    // name.
                    if rowData.isWebSocket {
                        let count = rowData.webSocketFrameCount
                        text = String(AttributedString(
                            localized: "^[\(count) frame](inflect: true)",
                            bundle: RockxyLocalization.bundle,
                            locale: RockxyLocalization.locale
                        ).characters)
                    } else if rowData.isWeb3RPC {
                        text = rowData.web3RPCMethod ?? ""
                    } else {
                        text = rowData.graphQLOpName ?? ""
                    }
                    font = metrics.appKitFont()
                default:
                    if columnID.hasPrefix("reqHeader.") || columnID.hasPrefix("resHeader.") {
                        text = RequestListRow.resolveHeaderValue(for: columnID, row: rowData)
                        font = metrics.appKitFont(monospaced: true)
                    } else {
                        text = ""
                        font = metrics.appKitFont()
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
            synchronizeContextSelection(clickedRow: tableView.clickedRow, in: tableView)
            let clickedCol = tableView.clickedColumn >= 0
                ? tableView.tableColumns[tableView.clickedColumn].identifier.rawValue
                : "url"
            lastClickedColumn = clickedCol

            buildCopyGroup(menu, transaction: transaction)
            if ContextFilterSuggestion.tableCell(columnID: clickedCol, transaction: transaction) != nil {
                menu.addItem(.separator())
                buildFilterGroup(menu, transaction: transaction)
            }
            menu.addItem(.separator())
            buildAssistantGroup(menu, transaction: transaction)
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

        func menuDidClose(_ menu: NSMenu) {
            guard menu === tableView?.menu,
                  let ids = pendingContextSelectionIDs else
            {
                return
            }
            pendingContextSelectionIDs = nil
            let primaryID = pendingContextPrimaryID
            pendingContextPrimaryID = nil
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.lastSyncedSelectionIDs = ids
                self.parent.selectedIDs = ids
                self.parent.onSelectionChanged?(ids, primaryID)
            }
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
        func handleFilterCellValue(_ sender: NSMenuItem) {
            let columnID = lastClickedColumn ?? "url"
            withCoordinator(sender) { coordinator, transaction in
                guard let suggestion = ContextFilterSuggestion.tableCell(
                    columnID: columnID,
                    transaction: transaction
                ) else {
                    return
                }
                DispatchQueue.main.async { [weak coordinator] in
                    coordinator?.applyContextFilter(suggestion)
                }
            }
        }

        @objc
        func handleExcludeCellValue(_ sender: NSMenuItem) {
            let columnID = lastClickedColumn ?? "url"
            withCoordinator(sender) { coordinator, transaction in
                guard let suggestion = ContextFilterSuggestion.tableCell(
                    columnID: columnID,
                    transaction: transaction
                ) else {
                    return
                }
                DispatchQueue.main.async { [weak coordinator] in
                    coordinator?.applyContextFilter(suggestion, excluding: true)
                }
            }
        }

        @objc
        func handleAskDebugAssistant(_ sender: NSMenuItem) {
            guard let tableView else {
                return
            }
            let selectionIDs = contextSelectionIDs(
                clickedRow: tableView.clickedRow,
                selectedRowIndexes: tableView.selectedRowIndexes
            )
            withCoordinator(sender) { coordinator, transaction in
                coordinator.presentDebugAssistant(
                    for: transaction,
                    contextSelectionIDs: selectionIDs
                )
            }
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
        func handleAllow(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.createAllowListRule(for: $1) }
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
        func handleSSLProxyingAppDecrypt(_ sender: NSMenuItem) {
            withCoordinator(sender) { coordinator, transaction in
                guard let identity = transaction.clientApplicationIdentity
                    ?? transaction.clientApp.flatMap(coordinator.observedApplicationIdentity(named:)) else
                {
                    return
                }
                coordinator.setSSLProxyingFromInspector(
                    for: identity,
                    listType: .include,
                    fallbackDomain: transaction.request.host
                )
            }
        }

        @objc
        func handleSSLProxyingAppTunnel(_ sender: NSMenuItem) {
            withCoordinator(sender) { coordinator, transaction in
                guard let identity = transaction.clientApplicationIdentity
                    ?? transaction.clientApp.flatMap(coordinator.observedApplicationIdentity(named:)) else
                {
                    return
                }
                coordinator.setSSLProxyingFromInspector(
                    for: identity,
                    listType: .exclude,
                    fallbackDomain: transaction.request.host
                )
            }
        }

        @objc
        func handleOpenSSLProxyingList(_ sender: NSMenuItem) {
            NotificationCenter.default.post(name: .openSSLProxyingList, object: nil)
        }

        @objc
        func handleExportHAR(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.exportTransactionAsHAR($1) }
        }

        @objc
        func handleExportOpenAPIYAML(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.exportOpenAPIContextSelection(clicked: $1, format: .openAPIYAML) }
        }

        @objc
        func handleExportOpenAPIHTML(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.exportOpenAPIContextSelection(clicked: $1, format: .openAPIHTML) }
        }

        @objc
        func handlePublishToGist(_ sender: NSMenuItem) {
            withCoordinator(sender) { $0.publishGistContextSelection(clicked: $1) }
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
            let desired = if parent.selectionIndex.isEmpty, !rows.isEmpty {
                IndexSet(rows.indices.filter { ids.contains(rows[$0].id) })
            } else {
                IndexSet(ids.compactMap { id in
                    guard let index = parent.selectionIndex[id]?.rowIndex,
                          rows.indices.contains(index),
                          rows[index].id == id else
                    {
                        return nil
                    }
                    return index
                })
            }

            guard currentSelected != desired else {
                lastSyncedSelectionIDs = ids
                return
            }

            let shouldPreserveScroll = ids == lastSyncedSelectionIDs
            let visibleOrigin = shouldPreserveScroll
                ? tableView.enclosingScrollView?.contentView.bounds.origin
                : nil

            performProgrammaticTableUpdate {
                tableView.selectRowIndexes(desired, byExtendingSelection: false)
            }
            lastSyncedSelectionIDs = ids

            let isFollowingLiveTraffic = MainActor.assumeIsolated {
                parent.mainCoordinator?.isFollowingLiveTraffic == true
            }
            if isFollowingLiveTraffic,
               let newestSelectedRow = desired.last
            {
                tableView.scrollRowToVisible(newestSelectedRow)
            }

            if let visibleOrigin,
               let scrollView = tableView.enclosingScrollView
            {
                scrollView.contentView.scroll(to: visibleOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        /// Applies an explicit Jump reveal once per workspace generation. This is intentionally
        /// separate from selection syncing: ordinary selection updates preserve the user's scroll,
        /// while Jump commands always reveal their target even when it was already selected.
        func syncRevealRequest(
            _ request: TrafficRevealRequest?,
            workspaceID: UUID,
            in tableView: NSTableView
        ) {
            guard let request,
                  request.generation > (lastAppliedRevealGenerationByWorkspace[workspaceID] ?? 0),
                  let rowIndex = parent.selectionIndex[request.transactionID]?.rowIndex,
                  rows.indices.contains(rowIndex),
                  rows[rowIndex].id == request.transactionID else
            {
                return
            }

            tableView.scrollRowToVisible(rowIndex)
            lastAppliedRevealGenerationByWorkspace[workspaceID] = request.generation
        }

        func contextSelectionIDs(
            clickedRow: Int,
            selectedRowIndexes: IndexSet
        )
            -> Set<UUID>
        {
            guard clickedRow >= 0, clickedRow < rows.count else {
                return []
            }
            let effectiveIndexes = selectedRowIndexes.contains(clickedRow)
                ? selectedRowIndexes
                : IndexSet(integer: clickedRow)
            return Set(
                effectiveIndexes.compactMap { index in
                    guard index >= 0, index < rows.count else {
                        return nil
                    }
                    return rows[index].id
                }
            )
        }

        func syncHeaderColumns(in tableView: NSTableView) {
            MainActor.assumeIsolated {
                let enabledColumns = parent.headerColumns.filter(\.isEnabled)
                let enabledIDs = Set(enabledColumns.map(\.columnIdentifier))
                let existingCustomIDs = Set(
                    tableView.tableColumns
                        .map(\.identifier.rawValue)
                        .filter { $0.hasPrefix("reqHeader.") || $0.hasPrefix("resHeader.") }
                )

                var columnsChanged = false
                for colID in existingCustomIDs.subtracting(enabledIDs) {
                    if let col = tableView.tableColumns.first(where: { $0.identifier.rawValue == colID }) {
                        tableView.removeTableColumn(col)
                        columnsChanged = true
                    }
                }

                for headerCol in enabledColumns
                    where !existingCustomIDs.contains(headerCol.columnIdentifier)
                {
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
                    columnsChanged = true
                }

                if columnsChanged {
                    applyHeaderMetrics(to: tableView)
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

        func sortDescriptors(
            _ descriptors: [NSSortDescriptor],
            availableIn tableView: NSTableView
        )
            -> [NSSortDescriptor]
        {
            let availableColumnIDs = Set(tableView.tableColumns.map(\.identifier.rawValue))
            return descriptors.filter { descriptor in
                guard let key = descriptor.key else {
                    return true
                }
                return availableColumnIDs.contains(key)
            }
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
                _ = mainCoordinator?.headerColumnStore.addColumn(headerName: name, source: source)
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

        private struct AppIconCacheKey: Hashable {
            let appName: String
            let iconSize: Int
        }

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
        private static var resizedAppIconCache: [AppIconCacheKey: NSImage] = [:]
        private static var missingAppIconNames: Set<String> = []

        private static let bundleIDByAppName: [String: String] = [
            "Chrome": "com.google.Chrome",
            "Safari": "com.apple.Safari",
            "Firefox": "org.mozilla.firefox",
            "Slack": "com.tinyspeck.slackmacgap",
            "Xcode": "com.apple.dt.Xcode",
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

        private var autosizeGeneration = 0
        private var lastAppliedRequestTableMetrics: RequestTableAppliedMetrics?
        private var pendingContextSelectionIDs: Set<UUID>?
        private var pendingContextPrimaryID: UUID?
        private var userScrollObserver: NSObjectProtocol?
        private var lastAppliedRevealGenerationByWorkspace: [UUID: Int] = [:]

        private var lastSyncedSelectionIDs: Set<UUID> = []
        private var visibleMetricsRefreshGeneration = 0

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
            symbol: String? = nil,
            transaction: HTTPTransaction
        )
            -> NSMenuItem
        {
            // Apple context menus expose relevant actions, not shortcut ownership. Main-menu
            // equivalents remain the single source for key commands and their enabled state.
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = transaction
            if let symbol {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            return item
        }

        private func buildCopyGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            menu.addItem(menuItem(
                String(localized: "Copy URL", bundle: RockxyLocalization.bundle), action: #selector(handleCopyURL(_:)),
                symbol: "doc.on.doc", transaction: transaction
            ))
            menu.addItem(menuItem(
                String(localized: "Copy cURL", bundle: RockxyLocalization.bundle),
                action: #selector(handleCopyCURL(_:)),
                transaction: transaction
            ))
            menu.addItem(menuItem(
                String(localized: "Copy Cell Value", bundle: RockxyLocalization.bundle),
                action: #selector(handleCopyCellValue(_:)),
                transaction: transaction
            ))

            let copyAsSubmenu = NSMenu()
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Request Headers", bundle: RockxyLocalization.bundle),
                action: #selector(handleCopyRequestHeaders(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Response Headers", bundle: RockxyLocalization.bundle),
                action: #selector(handleCopyResponseHeaders(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Request Body", bundle: RockxyLocalization.bundle),
                action: #selector(handleCopyRequestBody(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Response Body", bundle: RockxyLocalization.bundle),
                action: #selector(handleCopyResponseBody(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(.separator())
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Request Cookies", bundle: RockxyLocalization.bundle),
                action: #selector(handleCopyRequestCookies(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Response Cookies", bundle: RockxyLocalization.bundle),
                action: #selector(handleCopyResponseCookies(_:)),
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
                String(localized: "Raw Request", bundle: RockxyLocalization.bundle),
                action: #selector(handleCopyRawRequest(_:)),
                transaction: transaction
            ))
            copyAsSubmenu.addItem(menuItem(
                String(localized: "Raw Response", bundle: RockxyLocalization.bundle),
                action: #selector(handleCopyRawResponse(_:)),
                transaction: transaction
            ))
            let copyAsItem = NSMenuItem(
                title: String(localized: "Copy as", bundle: RockxyLocalization.bundle), action: nil, keyEquivalent: ""
            )
            copyAsItem.submenu = copyAsSubmenu
            menu.addItem(copyAsItem)
        }

        private func buildFilterGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            menu.addItem(menuItem(
                String(localized: "Filter by Value", bundle: RockxyLocalization.bundle),
                action: #selector(handleFilterCellValue(_:)),
                symbol: "line.3.horizontal.decrease.circle",
                transaction: transaction
            ))
            menu.addItem(menuItem(
                String(localized: "Exclude Value", bundle: RockxyLocalization.bundle),
                action: #selector(handleExcludeCellValue(_:)),
                symbol: "line.3.horizontal.decrease.circle.fill",
                transaction: transaction
            ))
        }

        private func buildAssistantGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            let selectionCount = contextSelectionIDs(
                clickedRow: tableView?.clickedRow ?? -1,
                selectedRowIndexes: tableView?.selectedRowIndexes ?? []
            ).count
            let title = selectionCount > 1
                ? String(localized: "Ask Rockxy Assistant About Selection…", bundle: RockxyLocalization.bundle)
                : String(localized: "Ask Rockxy Assistant…", bundle: RockxyLocalization.bundle)
            menu.addItem(menuItem(
                title,
                action: #selector(handleAskDebugAssistant(_:)),
                symbol: "waveform.badge.magnifyingglass",
                transaction: transaction
            ))
        }

        private func buildRepeatGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            let canReplay = MainContentCoordinator.canReplay(transaction)
            let repeatItem = menuItem(
                String(localized: "Repeat", bundle: RockxyLocalization.bundle), action: #selector(handleRepeat(_:)),
                symbol: "arrow.clockwise", transaction: transaction
            )
            repeatItem.isEnabled = canReplay
            menu.addItem(repeatItem)
            let editAndRepeatItem = menuItem(
                String(localized: "Edit and Repeat…", bundle: RockxyLocalization.bundle),
                action: #selector(handleEditAndRepeat(_:)),
                transaction: transaction
            )
            editAndRepeatItem.isEnabled = canReplay
            menu.addItem(editAndRepeatItem)
        }

        private func buildPinGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            let pinTitle = transaction.isPinned
                ? String(localized: "Unpin", bundle: RockxyLocalization.bundle)
                : String(localized: "Pin", bundle: RockxyLocalization.bundle)
            let pinSymbol = transaction.isPinned ? "pin.slash" : "pin"
            menu.addItem(menuItem(
                pinTitle, action: #selector(handleTogglePin(_:)),
                symbol: pinSymbol, transaction: transaction
            ))
            let saveTitle = transaction.isSaved
                ? String(localized: "Unsave", bundle: RockxyLocalization.bundle)
                : String(localized: "Save this Request", bundle: RockxyLocalization.bundle)
            let saveSymbol = transaction.isSaved ? "tray.full.fill" : "tray.and.arrow.down.fill"
            menu.addItem(menuItem(
                saveTitle, action: #selector(handleSaveRequest(_:)),
                symbol: saveSymbol, transaction: transaction
            ))
        }

        private func buildToolsGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            let toolsSubmenu = NSMenu()

            // Group 1: Debugging
            let breakpointItem = menuItem(
                String(localized: "Breakpoint…", bundle: RockxyLocalization.bundle),
                action: #selector(handleBreakpoint(_:)),
                transaction: transaction
            )
            breakpointItem.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
            toolsSubmenu.addItem(breakpointItem)

            toolsSubmenu.addItem(.separator())

            // Group 2: Request modification
            let mapLocalItem = menuItem(
                String(localized: "Map Local…", bundle: RockxyLocalization.bundle),
                action: #selector(handleMapLocal(_:)),
                transaction: transaction
            )
            mapLocalItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            toolsSubmenu.addItem(mapLocalItem)

            let mapRemoteItem = menuItem(
                String(localized: "Map Remote…", bundle: RockxyLocalization.bundle),
                action: #selector(handleMapRemote(_:)),
                transaction: transaction
            )
            mapRemoteItem.image = NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: nil)
            toolsSubmenu.addItem(mapRemoteItem)

            toolsSubmenu.addItem(.separator())

            // Group 3: Request filtering
            let blockItem = menuItem(
                String(localized: "Block List…", bundle: RockxyLocalization.bundle), action: #selector(handleBlock(_:)),
                transaction: transaction
            )
            blockItem.image = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)
            toolsSubmenu.addItem(blockItem)

            let allowItem = menuItem(
                String(localized: "Allow List…", bundle: RockxyLocalization.bundle), action: #selector(handleAllow(_:)),
                transaction: transaction
            )
            allowItem.image = NSImage(
                systemSymbolName: "line.3.horizontal.decrease.circle",
                accessibilityDescription: nil
            )
            toolsSubmenu.addItem(allowItem)

            toolsSubmenu.addItem(.separator())

            // Group 4: Protocol conditions
            let networkConditionsItem = menuItem(
                String(localized: "Network Conditions…", bundle: RockxyLocalization.bundle),
                action: #selector(handleNetworkConditions(_:)),
                transaction: transaction
            )
            networkConditionsItem.image = NSImage(
                systemSymbolName: "wifi.exclamationmark",
                accessibilityDescription: nil
            )
            toolsSubmenu.addItem(networkConditionsItem)

            toolsSubmenu.addItem(.separator())

            // Group 5: SSL
            toolsSubmenu.addItem(sslProxyingMenuItem(for: transaction))

            let toolsItem = NSMenuItem(
                title: String(localized: "Tools", bundle: RockxyLocalization.bundle),
                action: nil,
                keyEquivalent: ""
            )
            toolsItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
            toolsItem.submenu = toolsSubmenu
            menu.addItem(toolsItem)
        }

        private func buildAnnotationGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            menu.addItem(menuItem(
                String(localized: "Add Note…", bundle: RockxyLocalization.bundle),
                action: #selector(handleAddComment(_:)),
                symbol: "pencil.line", transaction: transaction
            ))

            let highlightSubmenu = NSMenu()
            let colors: [(String, HighlightColor)] = [
                (String(localized: "Red", bundle: RockxyLocalization.bundle), .red),
                (String(localized: "Orange", bundle: RockxyLocalization.bundle), .orange),
                (String(localized: "Yellow", bundle: RockxyLocalization.bundle), .yellow),
                (String(localized: "Green", bundle: RockxyLocalization.bundle), .green),
                (String(localized: "Blue", bundle: RockxyLocalization.bundle), .blue),
                (String(localized: "Purple", bundle: RockxyLocalization.bundle), .purple),
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
                String(localized: "Remove Highlight", bundle: RockxyLocalization.bundle),
                action: #selector(handleRemoveHighlight(_:)),
                transaction: transaction
            )
            removeItem.isEnabled = transaction.highlightColor != nil
            highlightSubmenu.addItem(removeItem)

            let highlightItem = NSMenuItem(
                title: String(localized: "Highlight", bundle: RockxyLocalization.bundle), action: nil, keyEquivalent: ""
            )
            highlightItem.submenu = highlightSubmenu
            menu.addItem(highlightItem)
        }

        private func buildExportGroup(_ menu: NSMenu, transaction: HTTPTransaction) {
            let exportSubmenu = NSMenu()
            exportSubmenu.addItem(menuItem(
                String(localized: "Export as HAR…", bundle: RockxyLocalization.bundle),
                action: #selector(handleExportHAR(_:)),
                transaction: transaction
            ))

            let openAPITitle = openAPIExportTitle(for: transaction)
            let openAPIYAMLItem = menuItem(
                String(localized: "\(openAPITitle) YAML…", bundle: RockxyLocalization.bundle),
                action: #selector(handleExportOpenAPIYAML(_:)),
                transaction: transaction
            )
            let openAPIHTMLItem = menuItem(
                String(localized: "\(openAPITitle) HTML…", bundle: RockxyLocalization.bundle),
                action: #selector(handleExportOpenAPIHTML(_:)),
                transaction: transaction
            )
            let hasEligibleOpenAPI = openAPIContextTransactions(for: transaction)
                .contains(where: OpenAPIExporter.isEligible)
            openAPIYAMLItem.isEnabled = hasEligibleOpenAPI
            openAPIHTMLItem.isEnabled = hasEligibleOpenAPI
            exportSubmenu.addItem(openAPIYAMLItem)
            exportSubmenu.addItem(openAPIHTMLItem)

            exportSubmenu.addItem(.separator())
            exportSubmenu.addItem(menuItem(
                gistPublishTitle(for: transaction),
                action: #selector(handlePublishToGist(_:)),
                transaction: transaction
            ))

            let reqBodyItem = menuItem(
                String(localized: "Export Request Body…", bundle: RockxyLocalization.bundle),
                action: #selector(handleExportRequestBody(_:)),
                transaction: transaction
            )
            reqBodyItem.isEnabled = transaction.request.body != nil
            exportSubmenu.addItem(reqBodyItem)

            let respBodyItem = menuItem(
                String(localized: "Export Response Body…", bundle: RockxyLocalization.bundle),
                action: #selector(handleExportResponseBody(_:)),
                transaction: transaction
            )
            respBodyItem.isEnabled = transaction.response?.body != nil
            exportSubmenu.addItem(respBodyItem)

            let exportItem = NSMenuItem(
                title: String(localized: "Export", bundle: RockxyLocalization.bundle),
                action: nil,
                keyEquivalent: ""
            )
            exportItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
            exportItem.submenu = exportSubmenu
            menu.addItem(exportItem)

            menu.addItem(sslProxyingMenuItem(for: transaction))
        }

        private func sslProxyingMenuItem(for transaction: HTTPTransaction) -> NSMenuItem {
            let submenu = NSMenu()
            let applicationIdentity = MainActor.assumeIsolated {
                transaction.clientApplicationIdentity
                    ?? transaction.clientApp.flatMap { mainCoordinator?.observedApplicationIdentity(named: $0) }
            }
            if applicationIdentity != nil {
                submenu.addItem(menuItem(
                    String(localized: "Decrypt All HTTPS from This Application", bundle: RockxyLocalization.bundle),
                    action: #selector(handleSSLProxyingAppDecrypt(_:)),
                    transaction: transaction
                ))
            }
            let hostItem = menuItem(
                String(localized: "Decrypt Only This Host", bundle: RockxyLocalization.bundle),
                action: #selector(handleSSLProxying(_:)),
                transaction: transaction
            )
            let hostDecryptBlockedReason = MainActor.assumeIsolated {
                mainCoordinator?.sslProxyingHostDecryptBlockedReason(
                    for: transaction.request.host,
                    application: applicationIdentity
                )
            }
            if let hostDecryptBlockedReason {
                hostItem.isEnabled = false
                hostItem.toolTip = hostDecryptBlockedReason
            }
            submenu.addItem(hostItem)
            if applicationIdentity != nil {
                submenu.addItem(menuItem(
                    String(localized: "Tunnel All HTTPS from This Application", bundle: RockxyLocalization.bundle),
                    action: #selector(handleSSLProxyingAppTunnel(_:)),
                    transaction: transaction
                ))
            }

            submenu.addItem(.separator())
            submenu.addItem(menuItem(
                String(localized: "Open HTTPS Decryption", bundle: RockxyLocalization.bundle),
                action: #selector(handleOpenSSLProxyingList(_:)),
                transaction: transaction
            ))

            let item = NSMenuItem(
                title: String(localized: "HTTPS Behavior", bundle: RockxyLocalization.bundle),
                action: nil,
                keyEquivalent: ""
            )
            item.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
            item.submenu = submenu
            return item
        }

        private func openAPIExportTitle(for transaction: HTTPTransaction) -> String {
            MainActor.assumeIsolated {
                guard let coordinator = mainCoordinator,
                      coordinator.selectedTransactionIDs.contains(transaction.id),
                      coordinator.selectedTransactionIDs.count > 1 else
                {
                    return String(localized: "Export as OpenAPI", bundle: RockxyLocalization.bundle)
                }
                return String(localized: "Export Selected as OpenAPI", bundle: RockxyLocalization.bundle)
            }
        }

        private func openAPIContextTransactions(for transaction: HTTPTransaction) -> [HTTPTransaction] {
            MainActor.assumeIsolated {
                guard let coordinator = mainCoordinator,
                      coordinator.selectedTransactionIDs.contains(transaction.id),
                      coordinator.selectedTransactionIDs.count > 1 else
                {
                    return [transaction]
                }
                return coordinator.resolveSelectedTransactions()
            }
        }

        private func gistPublishTitle(for transaction: HTTPTransaction) -> String {
            MainActor.assumeIsolated {
                guard let coordinator = mainCoordinator,
                      coordinator.selectedTransactionIDs.contains(transaction.id),
                      coordinator.selectedTransactionIDs.count > 1 else
                {
                    return String(localized: "Publish to Gist…", bundle: RockxyLocalization.bundle)
                }
                return String(localized: "Publish Selected to Gist…", bundle: RockxyLocalization.bundle)
            }
        }

        private func buildCompareGroup(_ menu: NSMenu) {
            let selectedCount = tableView?.selectedRowIndexes.count ?? 0
            let item = NSMenuItem(
                title: String(localized: "Compare Selected", bundle: RockxyLocalization.bundle),
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
                String(localized: "Delete", bundle: RockxyLocalization.bundle), action: #selector(handleDelete(_:)),
                symbol: "trash", transaction: transaction
            )
            menu.addItem(item)
        }

        private func synchronizeContextSelection(
            clickedRow: Int,
            in tableView: NSTableView
        ) {
            guard clickedRow >= 0,
                  clickedRow < rows.count,
                  !tableView.selectedRowIndexes.contains(clickedRow) else
            {
                return
            }

            let selection = IndexSet(integer: clickedRow)
            let ids = contextSelectionIDs(
                clickedRow: clickedRow,
                selectedRowIndexes: selection
            )
            performProgrammaticTableUpdate {
                tableView.selectRowIndexes(selection, byExtendingSelection: false)
            }
            pendingContextSelectionIDs = ids
            pendingContextPrimaryID = rows[clickedRow].id
        }

        // MARK: - Column Header Context Menu

        @MainActor
        private func buildColumnHeaderMenu(_ menu: NSMenu) {
            guard let store = mainCoordinator?.headerColumnStore else {
                return
            }

            // Built-in column visibility
            let builtInColumns: [(id: String, title: String)] = [
                ("status", String(localized: "Status Icon", bundle: RockxyLocalization.bundle)),
                ("ai", String(localized: "Protocol", bundle: RockxyLocalization.bundle)),
                ("row", "#"),
                ("url", String(localized: "URL", bundle: RockxyLocalization.bundle)),
                ("client", String(localized: "Client", bundle: RockxyLocalization.bundle)),
                ("method", String(localized: "Method", bundle: RockxyLocalization.bundle)),
                ("state", String(localized: "Status", bundle: RockxyLocalization.bundle)),
                ("code", String(localized: "Compact HTTP status code", bundle: RockxyLocalization.bundle)),
                ("time", String(localized: "Time", bundle: RockxyLocalization.bundle)),
                ("duration", String(localized: "Duration", bundle: RockxyLocalization.bundle)),
                ("requestSize", String(localized: "Request", bundle: RockxyLocalization.bundle)),
                ("responseSize", String(localized: "Response", bundle: RockxyLocalization.bundle)),
                ("ssl", String(localized: "SSL", bundle: RockxyLocalization.bundle)),
                ("queryName", String(localized: "Operation", bundle: RockxyLocalization.bundle)),
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
                title: String(localized: "Manage Header Columns…", bundle: RockxyLocalization.bundle),
                action: #selector(handleOpenColumnManager(_:)),
                keyEquivalent: ""
            )
            manageReqItem.target = self
            reqSubmenu.addItem(manageReqItem)

            let reqItem = NSMenuItem(
                title: String(localized: "Request Headers", bundle: RockxyLocalization.bundle), action: nil,
                keyEquivalent: ""
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
                title: String(localized: "Manage Header Columns…", bundle: RockxyLocalization.bundle),
                action: #selector(handleOpenColumnManager(_:)),
                keyEquivalent: ""
            )
            manageResItem.target = self
            resSubmenu.addItem(manageResItem)

            let resItem = NSMenuItem(
                title: String(localized: "Response Headers", bundle: RockxyLocalization.bundle), action: nil,
                keyEquivalent: ""
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
            let dotSize = parent.effectiveDisplayMetrics.tableStatusDotSize

            if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? FixedIconCellView {
                configureStatusDotCell(existing, row: row, dotSize: dotSize)
                return existing
            }

            let container = FixedIconCellView(identifier: cellID)
            configureStatusDotCell(container, row: row, dotSize: dotSize)
            return container
        }

        private func makeSSLView(
            row: RequestListRow,
            in tableView: NSTableView
        )
            -> NSView
        {
            let cellID = NSUserInterfaceItemIdentifier("Cell_ssl")
            let iconSize = parent.effectiveDisplayMetrics.tableSSLIconSize

            if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? FixedIconCellView {
                configureSSLImageView(existing.imageView, row: row)
                existing.updateIconSize(iconSize)
                return existing
            }

            let container = FixedIconCellView(identifier: cellID)
            configureSSLImageView(container.imageView, row: row)
            container.updateIconSize(iconSize)
            return container
        }

        private func configureStatusDotCell(
            _ cell: FixedIconCellView,
            row: RequestListRow,
            dotSize: CGFloat
        ) {
            cell.imageView.imageScaling = .scaleProportionallyUpOrDown
            cell.imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: dotSize, weight: .regular)
            cell.imageView.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
            cell.imageView.contentTintColor = statusDotColor(for: row)
            cell.updateIconSize(dotSize)
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

        private func isErrorStatus(_ row: RequestListRow) -> Bool {
            if row.state == .failed {
                return true
            }
            guard let statusCode = row.statusCode else {
                return false
            }
            return statusCode >= 400
        }

        private func errorStatusBadgeTitle(for row: RequestListRow) -> String? {
            if let statusCode = row.statusCode {
                let message = row.statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !message.isEmpty else {
                    return "\(statusCode)"
                }
                return "\(statusCode) \(message)"
            }
            guard row.state == .failed else {
                return nil
            }
            return String(localized: "Failed", bundle: RockxyLocalization.bundle)
        }

        private func makeErrorStatusBadgeView(
            row: RequestListRow,
            in tableView: NSTableView
        )
            -> NSView
        {
            let cellID = NSUserInterfaceItemIdentifier("Cell_state_errorBadge")
            let label: NSTextField
            let container: NSView

            if let existing = tableView.makeView(withIdentifier: cellID, owner: nil),
               let existingLabel = existing.subviews.first as? NSTextField
            {
                container = existing
                label = existingLabel
            } else {
                container = NSView()
                container.identifier = cellID

                label = NSTextField(labelWithString: "")
                label.alignment = .center
                label.textColor = .white
                label.lineBreakMode = .byTruncatingTail
                label.wantsLayer = true
                label.layer?.cornerRadius = 8
                label.layer?.masksToBounds = true
                label.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(label)

                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -4),
                    label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    label.heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
                ])
            }

            label.font = parent.effectiveDisplayMetrics.appKitFont(weight: .bold)
            label.stringValue = errorStatusBadgeTitle(for: row) ?? row.displayStatus
            label.layer?.backgroundColor = NSColor.systemRed.cgColor
            return container
        }

        private func configureSSLImageView(_ imageView: NSImageView, row: RequestListRow) {
            let iconSize = parent.effectiveDisplayMetrics.tableSSLIconSize
            let symbolName: String
            let tintColor: NSColor

            switch row.sslState {
            case .insecure:
                symbolName = "lock.open"
                tintColor = .tertiaryLabelColor
            case .secureTunneled:
                symbolName = "lock.fill"
                tintColor = .secondaryLabelColor
            case .secureIntercepted:
                symbolName = "lock.open.fill"
                tintColor = .systemGreen
            }

            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            imageView.contentTintColor = tintColor
        }

        private func appIcon(for appName: String) -> NSImage? {
            let iconSize = parent.effectiveDisplayMetrics.tableClientIconSize
            let cacheKey = AppIconCacheKey(appName: appName, iconSize: Int(iconSize.rounded()))
            if let cached = Self.resizedAppIconCache[cacheKey] {
                return cached
            }
            guard let source = appIconSource(for: appName),
                  let icon = source.copy() as? NSImage else
            {
                return nil
            }
            icon.size = NSSize(width: iconSize, height: iconSize)
            Self.resizedAppIconCache[cacheKey] = icon
            return icon
        }

        private func appIconSource(for appName: String) -> NSImage? {
            guard !appName.isEmpty,
                  !Self.missingAppIconNames.contains(appName) else
            {
                return nil
            }
            if let cached = Self.appIconCache[appName] {
                return cached
            }
            if let bundleID = Self.bundleIDByAppName[appName],
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
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
                    Self.appIconCache[appName] = icon
                    return icon
                }
            }

            for app in NSWorkspace.shared.runningApplications {
                if app.localizedName == appName, let icon = app.icon {
                    Self.appIconCache[appName] = icon
                    return icon
                }
            }

            Self.missingAppIconNames.insert(appName)
            return nil
        }

        private func makeClientCellView(
            appName: String,
            identifier: NSUserInterfaceItemIdentifier,
            in tableView: NSTableView
        )
            -> NSView
        {
            let iconSize = parent.effectiveDisplayMetrics.tableClientIconSize
            let gap: CGFloat = 4
            let rowHeight = parent.effectiveDisplayMetrics.tableRowHeight
            let iconY = (rowHeight - iconSize) / 2

            // Reuse existing cell: subviews order is [imageView, fallbackView, nameLabel]
            if let existing = tableView.makeView(withIdentifier: identifier, owner: nil),
               existing.subviews.count == 3
            {
                let imageView = existing.subviews[0] as? NSImageView
                let fallbackView = existing.subviews[1]
                let nameLabel = existing.subviews[2] as? NSTextField

                updateClientIconFrames(
                    imageView: imageView,
                    fallbackView: fallbackView,
                    iconSize: iconSize,
                    iconY: iconY
                )
                if let nameLabel {
                    updateClientNameConstraints(nameLabel, in: existing, iconSize: iconSize, gap: gap)
                }
                nameLabel?.stringValue = appName
                nameLabel?.font = parent.effectiveDisplayMetrics.appKitFont()
                nameLabel?.toolTip = appName.isEmpty ? nil : appName
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
            initialsLabel.font = .systemFont(ofSize: max(7, iconSize * 0.44), weight: .bold)
            initialsLabel.textColor = .white
            initialsLabel.alignment = .center
            initialsLabel.frame = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
            initialsLabel.autoresizingMask = [.width, .height]
            fallbackView.addSubview(initialsLabel)
            container.addSubview(fallbackView)

            // Subview 2: app name label
            let nameLabel = NSTextField(labelWithString: "")
            nameLabel.font = parent.effectiveDisplayMetrics.appKitFont()
            nameLabel.textColor = .secondaryLabelColor
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(nameLabel)

            NSLayoutConstraint.activate([
                nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: iconSize + gap),
                nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])

            // Populate content
            nameLabel.stringValue = appName
            nameLabel.toolTip = appName.isEmpty ? nil : appName
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

        private func updateClientIconFrames(
            imageView: NSImageView?,
            fallbackView: NSView,
            iconSize: CGFloat,
            iconY: CGFloat
        ) {
            imageView?.frame = NSRect(x: 0, y: iconY, width: iconSize, height: iconSize)
            fallbackView.frame = NSRect(x: 0, y: iconY, width: iconSize, height: iconSize)
            fallbackView.layer?.cornerRadius = max(4, iconSize * 0.25)
            if let initialsLabel = fallbackView.subviews.first as? NSTextField {
                initialsLabel.frame = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
                initialsLabel.font = .systemFont(ofSize: max(7, iconSize * 0.44), weight: .bold)
            }
        }

        private func updateClientNameConstraints(
            _ nameLabel: NSTextField,
            in container: NSView,
            iconSize: CGFloat,
            gap: CGFloat
        ) {
            let leadingConstant = iconSize + gap
            if let leadingConstraint = container.constraints.first(where: { constraint in
                constraint.firstItem as AnyObject? === nameLabel
                    && constraint.firstAttribute == .leading
                    && constraint.secondItem as AnyObject? === container
            }) {
                if leadingConstraint.constant != leadingConstant {
                    leadingConstraint.constant = leadingConstant
                }
                return
            }

            NSLayoutConstraint.activate([
                nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leadingConstant),
                nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }

        private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSView {
            let container = NSView()
            container.identifier = identifier

            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.cell?.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.cell?.wraps = false
            if let textCell = field.cell as? NSTextFieldCell {
                textCell.usesSingleLineMode = true
                textCell.truncatesLastVisibleLine = true
            }
            field.font = parent.effectiveDisplayMetrics.appKitFont()
            field.textColor = .labelColor
            field.isBordered = false
            field.drawsBackground = false
            field.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(field)

            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])

            return container
        }

        private func configureCellContent(
            _ cell: NSTextField,
            column: String,
            row: Int,
            rowData: RequestListRow
        ) {
            defer {
                cell.lineBreakMode = .byTruncatingTail
                cell.cell?.lineBreakMode = .byTruncatingTail
                cell.maximumNumberOfLines = 1
                cell.cell?.wraps = false
                if let textCell = cell.cell as? NSTextFieldCell {
                    textCell.usesSingleLineMode = true
                    textCell.truncatesLastVisibleLine = true
                }
            }

            let metrics = parent.effectiveDisplayMetrics
            cell.stringValue = ""
            cell.textColor = .labelColor
            cell.alignment = .left
            cell.font = metrics.appKitFont()
            cell.toolTip = nil

            switch column {
            case "row":
                cell.stringValue = "\(rowData.sequenceNumber)"
                cell.alignment = .right
                cell.font = .monospacedDigitSystemFont(ofSize: metrics.secondaryFontSize, weight: .regular)
                cell.textColor = .secondaryLabelColor

            case "url":
                cell.stringValue = rowData.host + rowData.path
                cell.toolTip = cell.stringValue
                cell.font = metrics.appKitFont(monospaced: true)
                cell.textColor = .labelColor

            case "ai":
                cell.alignment = .center
                cell.stringValue = rowData.smartBadgeText
                cell.toolTip = rowData.smartBadgeTooltip
                cell.font = metrics.appKitFont(weight: .semibold)
                cell.textColor = protocolTextColor(for: rowData)

            case "method":
                cell.alignment = .center
                let method = rowData.method
                let color = methodColor(for: method)
                cell.attributedStringValue = NSAttributedString(
                    string: method,
                    attributes: [
                        .foregroundColor: color,
                        .font: metrics.appKitFont(weight: .semibold),
                    ]
                )

            case "state":
                cell.alignment = .left
                cell.stringValue = rowData.displayStatus
                cell.textColor = statusTextColor(for: rowData.state)
                cell.font = metrics.appKitFont(weight: .medium)

            case "code":
                cell.alignment = .center
                if let code = rowData.statusCode {
                    let color = statusCodeColor(for: code)
                    cell.attributedStringValue = NSAttributedString(
                        string: "\(code)",
                        attributes: [
                            .foregroundColor: color,
                            .font: NSFont.monospacedDigitSystemFont(ofSize: metrics.fontSize, weight: .medium),
                        ]
                    )
                } else {
                    cell.stringValue = stateLabel(for: rowData.state)
                    cell.textColor = .tertiaryLabelColor
                    cell.font = metrics.appKitFont()
                }

            case "time":
                cell.stringValue = RequestTableView.timeFormatter.string(from: rowData.timestamp)
                cell.font = .monospacedDigitSystemFont(ofSize: metrics.secondaryFontSize, weight: .regular)
                cell.textColor = .secondaryLabelColor

            case "duration":
                cell.alignment = .right
                if let duration = rowData.totalDuration {
                    cell.stringValue = DurationFormatter.format(seconds: duration)
                } else {
                    cell.stringValue = "—"
                }
                cell.font = .monospacedDigitSystemFont(ofSize: metrics.secondaryFontSize, weight: .regular)
                cell.textColor = .secondaryLabelColor

            case "requestSize":
                cell.alignment = .right
                if let requestSize = rowData.requestSize {
                    cell.stringValue = SizeFormatter.format(bytes: requestSize)
                } else {
                    cell.stringValue = "—"
                }
                cell.font = .monospacedDigitSystemFont(ofSize: metrics.secondaryFontSize, weight: .regular)
                cell.textColor = .secondaryLabelColor

            case "responseSize":
                cell.alignment = .right
                if let responseSize = rowData.responseSize {
                    cell.stringValue = SizeFormatter.format(bytes: responseSize)
                } else {
                    cell.stringValue = "—"
                }
                cell.font = .monospacedDigitSystemFont(ofSize: metrics.secondaryFontSize, weight: .regular)
                cell.textColor = .secondaryLabelColor

            case "queryName":
                if rowData.isWebSocket {
                    let count = rowData.webSocketFrameCount
                    cell.stringValue = String(
                        AttributedString(
                            localized: "^[\(count) frame](inflect: true)",
                            bundle: RockxyLocalization.bundle,
                            locale: RockxyLocalization.locale
                        ).characters
                    )
                    cell.textColor = .tertiaryLabelColor
                    cell.toolTip = nil
                } else if rowData.isWeb3RPC {
                    cell.stringValue = rowData.web3RPCMethod ?? ""
                    cell.textColor = rowData.web3RPCErrorCode == nil ? .secondaryLabelColor : .systemRed
                    cell.toolTip = rowData.web3RPCProviderHost
                } else {
                    cell.stringValue = rowData.graphQLOpName ?? ""
                    cell.textColor = .secondaryLabelColor
                    cell.toolTip = nil
                }

            default:
                if column.hasPrefix("reqHeader.") || column.hasPrefix("resHeader.") {
                    let headerValue = RequestListRow.resolveHeaderValue(for: column, row: rowData)
                    cell.stringValue = headerValue
                    cell.toolTip = headerValue.isEmpty ? nil : headerValue
                    cell.font = metrics.appKitFont(monospaced: true)
                    cell.textColor = .secondaryLabelColor
                } else {
                    cell.stringValue = ""
                }
            }
        }

        private func protocolTextColor(for row: RequestListRow) -> NSColor {
            switch row.smartBadgeText {
            case "RPC ERR":
                .systemRed
            case "Web3":
                .systemGreen
            case "AI API",
                 "AI Session",
                 "Likely AI":
                .controlAccentColor
            case "gRPC",
                 "GraphQL",
                 "WS":
                .systemBlue
            default:
                .secondaryLabelColor
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

        private func statusTextColor(for state: TransactionState) -> NSColor {
            switch state {
            case .pending,
                 .active:
                .systemOrange
            case .completed:
                .secondaryLabelColor
            case .failed:
                .systemRed
            case .blocked:
                .tertiaryLabelColor
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
