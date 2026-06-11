import AppKit
import SwiftUI
@testable import Rockxy
import Testing

@MainActor
struct RequestTableSelectionScrollTests {
    @Test("Appearance display metrics keep default request table density")
    func appearanceDisplayMetricsKeepDefaultRequestTableDensity() {
        let cases: [(
            fontSize: Int,
            control: CGFloat,
            secondary: CGFloat,
            metadata: CGFloat,
            badge: CGFloat,
            sidebarNavigation: CGFloat,
            sidebarSecondary: CGFloat,
            sidebarSection: CGFloat,
            sidebarBadge: CGFloat,
            sidebarAppIcon: CGFloat,
            tableStatusDot: CGFloat,
            tableSSLIcon: CGFloat,
            tableClientIcon: CGFloat,
            chromeFont: CGFloat,
            chromeDot: CGFloat,
            chromeControl: CGFloat,
            workspaceTab: CGFloat,
            sidebarRow: CGFloat,
            row: CGFloat,
            status: CGFloat,
            filter: CGFloat,
            tab: CGFloat
        )] = [
            (10, 11, 9, 10, 10, 11, 10, 10, 10, 20, 8, 10, 14, 11, 9, 32, 13, 24, 26, 34, 26, 22),
            (11, 11, 10, 10, 10, 11, 10, 10, 10, 20, 8, 10, 14, 11, 9, 32, 13, 24, 27, 34, 26, 22),
            (12, 11, 11, 10, 10, 12, 11, 10, 10, 20, 9, 11, 15, 11, 9, 32, 13, 24, 28, 34, 26, 22),
            (13, 12, 12, 11, 10, 13, 12, 11, 11, 20, 10, 12, 16, 12, 10, 32, 13, 25, 28, 35, 27, 23),
            (14, 13, 13, 12, 11, 14, 13, 12, 12, 21, 11, 13, 17, 13, 11, 32, 13, 26, 30, 36, 28, 24),
            (20, 19, 19, 18, 17, 20, 19, 18, 18, 27, 12, 16, 18, 19, 14, 35, 18, 32, 36, 42, 34, 30),
            (28, 27, 27, 26, 25, 28, 27, 26, 26, 32, 12, 16, 18, 27, 14, 43, 18, 40, 44, 50, 42, 38),
        ]

        for item in cases {
            var appUI = AppUISettings()
            appUI.fontSize = item.fontSize
            let metrics = AppUIDisplayMetrics(settings: appUI)

            #expect(metrics.fontSize == CGFloat(item.fontSize))
            #expect(metrics.primaryFontSize == CGFloat(item.fontSize))
            #expect(metrics.controlFontSize == item.control)
            #expect(metrics.secondaryFontSize == item.secondary)
            #expect(metrics.metadataFontSize == item.metadata)
            #expect(metrics.badgeFontSize == item.badge)
            #expect(metrics.monospacedContentFontSize == CGFloat(item.fontSize))
            #expect(metrics.sidebarNavigationFontSize == item.sidebarNavigation)
            #expect(metrics.sidebarSecondaryFontSize == item.sidebarSecondary)
            #expect(metrics.sidebarSectionHeaderFontSize == item.sidebarSection)
            #expect(metrics.sidebarBadgeFontSize == item.sidebarBadge)
            #expect(metrics.sidebarAppIconSize == item.sidebarAppIcon)
            #expect(metrics.tableStatusDotSize == item.tableStatusDot)
            #expect(metrics.tableSSLIconSize == item.tableSSLIcon)
            #expect(metrics.tableClientIconSize == item.tableClientIcon)
            #expect(metrics.chromeFontSize == item.chromeFont)
            #expect(metrics.chromeSecondaryFontSize == item.secondary)
            #expect(metrics.chromeStatusDotSize == item.chromeDot)
            #expect(metrics.chromeControlHeight == item.chromeControl)
            #expect(metrics.workspaceTabFontSize == item.workspaceTab)
            #expect(metrics.sidebarRowHeight == item.sidebarRow)
            #expect(metrics.tableRowHeight == item.row)
            #expect(metrics.statusBarHeight == item.status)
            #expect(metrics.filterBarHeight == item.filter)
            #expect(metrics.inspectorTabHeight == item.tab)
        }
    }

    @Test("Developer Setup display metrics derive from Appearance font size")
    func developerSetupDisplayMetricsDeriveFromAppearanceFontSize() {
        let cases: [(
            fontSize: Int,
            title: CGFloat,
            sectionTitle: CGFloat,
            body: CGFloat,
            secondary: CGFloat,
            metadata: CGFloat,
            badge: CGFloat,
            snippet: CGFloat,
            sidebarRow: CGFloat,
            cardMinimum: CGFloat
        )] = [
            (10, 15, 13, 10, 11, 10, 10, 10, 36, 82),
            (11, 16, 13, 11, 11, 10, 10, 11, 36, 82),
            (12, 17, 13, 12, 11, 10, 10, 12, 36, 82),
            (13, 18, 14, 13, 12, 11, 10, 13, 37, 82),
            (14, 19, 15, 14, 13, 12, 11, 14, 38, 82),
            (20, 25, 21, 20, 19, 18, 17, 20, 44, 88),
            (28, 33, 29, 28, 27, 26, 25, 28, 52, 96),
        ]

        for item in cases {
            var appUI = AppUISettings()
            appUI.fontSize = item.fontSize
            let metrics = DeveloperSetupDisplayMetrics(appMetrics: AppUIDisplayMetrics(settings: appUI))

            #expect(metrics.titleFontSize == item.title)
            #expect(metrics.sectionTitleFontSize == item.sectionTitle)
            #expect(metrics.bodyFontSize == item.body)
            #expect(metrics.secondaryFontSize == item.secondary)
            #expect(metrics.metadataFontSize == item.metadata)
            #expect(metrics.badgeFontSize == item.badge)
            #expect(metrics.snippetFontSize == item.snippet)
            #expect(metrics.sidebarRowHeight == item.sidebarRow)
            #expect(metrics.cardMinimumHeight == item.cardMinimum)
        }
    }

    @Test("Inspector tab metrics use scalable control text without growing default table density")
    func inspectorTabMetricsUseScalableControlText() {
        var appUI = AppUISettings()
        appUI.fontSize = AppUISettings.defaultFontSize
        let defaultMetrics = AppUIDisplayMetrics(settings: appUI)
        appUI.fontSize = 20
        let largeMetrics = AppUIDisplayMetrics(settings: appUI)

        #expect(defaultMetrics.controlFontSize == 12)
        #expect(defaultMetrics.inspectorTabHeight == 23)
        #expect(defaultMetrics.tableRowHeight == 28)
        #expect(largeMetrics.controlFontSize == 19)
        #expect(largeMetrics.inspectorTabHeight == 30)
        #expect(largeMetrics.tableRowHeight == 36)
    }

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

    @Test("Request table default font keeps dense row height")
    func requestTableDefaultFontKeepsDenseRowHeight() {
        var selectedIDs = Set<UUID>()
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: [],
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: .default),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        let tableView = makeTableView(rowCount: 1, coordinator: coordinator)

        coordinator.applyDisplayMetrics(to: tableView)

        #expect(AppUISettings.defaultFontSize == 13)
        #expect(tableView.rowHeight == 28)
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

    @Test("Request table ignores inspector-only appearance options")
    func requestTableIgnoresInspectorOnlyAppearanceOptions() {
        var selectedIDs = Set<UUID>()
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: [],
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: .default),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        let tableView = makeTableView(rowCount: 1, coordinator: coordinator)

        let firstChange = coordinator.applyDisplayMetrics(to: tableView)

        var inspectorOnlyAppUI = AppUISettings.default
        inspectorOnlyAppUI.bodyWordWrap.toggle()
        inspectorOnlyAppUI.bodyShowInvisibles.toggle()
        inspectorOnlyAppUI.bodyShowMinimap.toggle()
        inspectorOnlyAppUI.bodyScrollBeyondLastLine.toggle()
        coordinator.parent = RequestTableView(
            workspaceID: UUID(),
            rows: [],
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: inspectorOnlyAppUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )

        let secondChange = coordinator.applyDisplayMetrics(to: tableView)

        #expect(firstChange?.reloadVisibleRows == true)
        #expect(firstChange?.autosizeContentColumns == true)
        #expect(secondChange == nil)
    }

    @Test("Request table alternating-row option avoids content autosize")
    func requestTableAlternatingRowOptionAvoidsContentAutosize() {
        var selectedIDs = Set<UUID>()
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: [],
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: .default),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        let tableView = makeTableView(rowCount: 1, coordinator: coordinator)
        _ = coordinator.applyDisplayMetrics(to: tableView)

        var appUI = AppUISettings.default
        appUI.useAlternatingRowBackgroundColors = false
        coordinator.parent = RequestTableView(
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

        let change = coordinator.applyDisplayMetrics(to: tableView)

        #expect(change?.reloadVisibleRows == false)
        #expect(change?.autosizeContentColumns == false)
        #expect(tableView.usesAlternatingRowBackgroundColors == false)
    }

    @Test("Request table font metric changes reload visible rows without rescheduling autosize")
    func requestTableFontMetricChangesReloadVisibleRowsWithoutReschedulingAutosize() {
        var selectedIDs = Set<UUID>()
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: [],
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: .default),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        let tableView = makeTableView(rowCount: 1, coordinator: coordinator)
        _ = coordinator.applyDisplayMetrics(to: tableView)

        var appUI = AppUISettings.default
        appUI.fontSize = 20
        coordinator.parent = RequestTableView(
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

        let change = coordinator.applyDisplayMetrics(to: tableView)

        #expect(change?.reloadVisibleRows == true)
        #expect(change?.contentMetricsChanged == true)
        #expect(change?.rowHeightChanged == true)
        #expect(change?.autosizeContentColumns == false)
    }

    @Test("Request table row-height metric changes preserve top visible row anchor")
    func requestTableRowHeightChangesPreserveTopVisibleRowAnchor() throws {
        var selectedIDs = Set<UUID>()
        let rows = TestFixtures.makeBulkTransactions(count: 80).map {
            RequestListRow(from: $0, sslState: .insecure)
        }
        var appUI = AppUISettings.default
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        coordinator.rows = rows
        let tableView = makeTableView(rowCount: rows.count, coordinator: coordinator)
        let scrollView = makeScrollView(documentView: tableView)
        _ = coordinator.applyDisplayMetrics(to: tableView)
        tableView.reloadData()
        tableView.frame.size.height = CGFloat(rows.count) * tableView.rowHeight

        tableView.scrollRowToVisible(25)
        let anchor = try #require(coordinator.makeScrollAnchor(in: tableView))

        appUI.fontSize = 20
        coordinator.parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 1,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        _ = coordinator.applyDisplayMetrics(to: tableView)
        tableView.frame.size.height = CGFloat(rows.count) * tableView.rowHeight
        coordinator.restoreScrollAnchor(anchor, in: tableView)

        #expect(tableView.rows(in: scrollView.contentView.bounds).location == anchor.row)
    }

    @Test("Request table scales row height after default size")
    func requestTableScalesRowHeightAfterDefaultSize() {
        var selectedIDs = Set<UUID>()
        var appUI = AppUISettings()
        appUI.fontSize = 14
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

        #expect(tableView.rowHeight == 30)
    }

    @Test("Applying request table metrics preserves column widths")
    func applyingRequestTableMetricsPreservesColumnWidths() {
        var selectedIDs = Set<UUID>()
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: [],
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: .default),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        let tableView = makeTableView(rowCount: 1, coordinator: coordinator)
        tableView.tableColumns[0].width = 333

        coordinator.applyDisplayMetrics(to: tableView)

        #expect(tableView.tableColumns[0].width == 333)
    }

    @Test("Request table size-to-fit measures with active metrics without mutating columns")
    func requestTableSizeToFitMeasuresWithActiveMetricsWithoutMutatingColumns() {
        let compactWidth = measuredURLWidth(fontSize: 12)
        let largeWidth = measuredURLWidth(fontSize: 20)

        #expect(largeWidth > compactWidth)
    }

    @Test("Method column sizing accounts for CONNECT at default font")
    func methodColumnSizingAccountsForConnectAtDefaultFont() {
        var selectedIDs = Set<UUID>()
        let rows = [
            TestFixtures.makeTransaction(method: "CONNECT", url: "https://example.com:443"),
        ].map {
            RequestListRow(from: $0, sslState: .secureTunneled)
        }
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: .default),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        coordinator.rows = rows
        let tableView = makeTableView(rowCount: rows.count, coordinator: coordinator, columns: ["method"])

        let measuredWidth = coordinator.tableView(tableView, sizeToFitWidthOfColumn: 0)
        let cellView = coordinator.tableView(tableView, viewFor: tableView.tableColumns[0], row: 0)
        let textField = cellView?.subviews.first as? NSTextField

        #expect(measuredWidth <= 82)
        #expect(textField?.stringValue == "CONNECT")
        #expect(textField?.maximumNumberOfLines == 1)
        #expect(textField?.cell?.wraps == false)
        #expect((textField?.cell as? NSTextFieldCell)?.usesSingleLineMode == true)
        #expect((textField?.cell as? NSTextFieldCell)?.truncatesLastVisibleLine == true)
    }

    @Test("Request table SSL icon constraints shrink after large-to-small metric changes")
    func requestTableSSLIconConstraintsShrinkAfterLargeToSmallMetricChanges() throws {
        var selectedIDs = Set<UUID>()
        var appUI = AppUISettings()
        appUI.fontSize = 28
        let rows = [
            TestFixtures.makeTransaction(method: "CONNECT", url: "https://example.com:443"),
        ].map {
            RequestListRow(from: $0, sslState: .secureIntercepted)
        }
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        coordinator.rows = rows
        let tableView = makeTableView(rowCount: rows.count, coordinator: coordinator, columns: ["ssl"])
        _ = coordinator.applyDisplayMetrics(to: tableView)

        _ = tableView.view(atColumn: 0, row: 0, makeIfNecessary: true)

        appUI.fontSize = 10
        coordinator.parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 1,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        _ = coordinator.applyDisplayMetrics(to: tableView)
        tableView.reloadData()

        let smallView = try #require(tableView.view(atColumn: 0, row: 0, makeIfNecessary: true))
        let imageView = try #require(smallView.subviews.first as? NSImageView)
        let expected = AppUIDisplayMetrics(settings: appUI).tableSSLIconSize

        #expect(fixedConstraintConstant(.width, for: imageView) == expected)
        #expect(fixedConstraintConstant(.height, for: imageView) == expected)
    }

    @Test("Request table client app icon frame shrinks after large-to-small metric changes")
    func requestTableClientIconFrameShrinksAfterLargeToSmallMetricChanges() throws {
        var selectedIDs = Set<UUID>()
        var appUI = AppUISettings()
        appUI.fontSize = 28
        let transaction = TestFixtures.makeTransaction()
        transaction.clientApp = "Example Client"
        let rows = [RequestListRow(from: transaction, sslState: .insecure)]
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        coordinator.rows = rows
        let tableView = makeTableView(rowCount: rows.count, coordinator: coordinator, columns: ["client"])
        _ = coordinator.applyDisplayMetrics(to: tableView)

        _ = tableView.view(atColumn: 0, row: 0, makeIfNecessary: true)

        appUI.fontSize = 10
        coordinator.parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 1,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        _ = coordinator.applyDisplayMetrics(to: tableView)
        tableView.reloadData()

        let smallView = try #require(tableView.view(atColumn: 0, row: 0, makeIfNecessary: true))
        let imageView = try #require(smallView.subviews.first as? NSImageView)
        let fallbackView = smallView.subviews[1]
        let nameLabel = try #require(smallView.subviews[2] as? NSTextField)
        let expected = AppUIDisplayMetrics(settings: appUI).tableClientIconSize

        #expect(imageView.frame.size.width == expected)
        #expect(imageView.frame.size.height == expected)
        #expect(fallbackView.frame.size.width == expected)
        #expect(fallbackView.frame.size.height == expected)
        #expect(leadingConstraintConstant(for: nameLabel, in: smallView) == expected + 4)
    }

    @Test("Request table status, SSL, and client icons remain consistent after repeated metric changes")
    func requestTableIconsRemainConsistentAfterRepeatedMetricChanges() throws {
        var selectedIDs = Set<UUID>()
        var appUI = AppUISettings()
        appUI.fontSize = 10
        let transaction = TestFixtures.makeTransaction(method: "CONNECT", url: "https://example.com:443")
        transaction.clientApp = "Example Client"
        let rows = [RequestListRow(from: transaction, sslState: .secureIntercepted)]
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        coordinator.rows = rows
        let tableView = makeTableView(rowCount: rows.count, coordinator: coordinator, columns: ["status", "ssl", "client"])

        for fontSize in [10, 28, 10, 28, 10] {
            appUI.fontSize = fontSize
            coordinator.parent = RequestTableView(
                workspaceID: UUID(),
                rows: rows,
                refreshToken: fontSize,
                isAppendOnly: false,
                displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
                selectedIDs: Binding(
                    get: { selectedIDs },
                    set: { selectedIDs = $0 }
                )
            )
            _ = coordinator.applyDisplayMetrics(to: tableView)
            tableView.reloadData()
            for column in 0 ..< tableView.numberOfColumns {
                _ = tableView.view(atColumn: column, row: 0, makeIfNecessary: true)
            }
        }

        let expected = AppUIDisplayMetrics(settings: appUI)
        let statusView = try #require(tableView.view(atColumn: 0, row: 0, makeIfNecessary: true))
        let statusImageView = try #require(statusView.subviews.first as? NSImageView)
        let sslView = try #require(tableView.view(atColumn: 1, row: 0, makeIfNecessary: true))
        let sslImageView = try #require(sslView.subviews.first as? NSImageView)
        let clientView = try #require(tableView.view(atColumn: 2, row: 0, makeIfNecessary: true))
        let clientImageView = try #require(clientView.subviews.first as? NSImageView)
        let fallbackView = clientView.subviews[1]
        let nameLabel = try #require(clientView.subviews[2] as? NSTextField)

        #expect(fixedConstraintConstant(.width, for: statusImageView) == expected.tableStatusDotSize)
        #expect(fixedConstraintConstant(.height, for: statusImageView) == expected.tableStatusDotSize)
        #expect(fixedConstraintCount(for: statusImageView) == 2)
        #expect(fixedConstraintConstant(.width, for: sslImageView) == expected.tableSSLIconSize)
        #expect(fixedConstraintConstant(.height, for: sslImageView) == expected.tableSSLIconSize)
        #expect(fixedConstraintCount(for: sslImageView) == 2)
        #expect(clientImageView.frame.size.width == expected.tableClientIconSize)
        #expect(clientImageView.frame.size.height == expected.tableClientIconSize)
        #expect(fallbackView.frame.size.width == expected.tableClientIconSize)
        #expect(fallbackView.frame.size.height == expected.tableClientIconSize)
        #expect(leadingConstraintConstant(for: nameLabel, in: clientView) == expected.tableClientIconSize + 4)
        #expect(leadingConstraintCount(for: nameLabel, in: clientView) == 1)
    }

    @Test("Request table visible metric refresh converges after rapid large-small jumps")
    func requestTableVisibleMetricRefreshConvergesAfterRapidJumps() async throws {
        var selectedIDs = Set<UUID>()
        var appUI = AppUISettings()
        appUI.fontSize = 13
        let transaction = TestFixtures.makeTransaction(method: "CONNECT", url: "https://example.com:443")
        transaction.clientApp = "Example Client"
        let rows = [RequestListRow(from: transaction, sslState: .secureIntercepted)]
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        coordinator.rows = rows
        let tableView = makeTableView(rowCount: rows.count, coordinator: coordinator, columns: ["status", "ssl", "client"])
        _ = makeScrollView(documentView: tableView)

        for fontSize in [13, 28, 10, 28, 10] {
            appUI.fontSize = fontSize
            coordinator.parent = RequestTableView(
                workspaceID: UUID(),
                rows: rows,
                refreshToken: fontSize,
                isAppendOnly: false,
                displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
                selectedIDs: Binding(
                    get: { selectedIDs },
                    set: { selectedIDs = $0 }
                )
            )
            _ = coordinator.applyDisplayMetrics(to: tableView)
            coordinator.reloadVisibleRows(in: tableView)
            coordinator.scheduleVisibleMetricsRefresh(in: tableView, preserving: nil)
        }

        await Task.yield()

        let expected = AppUIDisplayMetrics(settings: appUI)
        let statusView = try #require(tableView.view(atColumn: 0, row: 0, makeIfNecessary: true))
        let statusImageView = try #require(statusView.subviews.first as? NSImageView)
        let sslView = try #require(tableView.view(atColumn: 1, row: 0, makeIfNecessary: true))
        let sslImageView = try #require(sslView.subviews.first as? NSImageView)
        let clientView = try #require(tableView.view(atColumn: 2, row: 0, makeIfNecessary: true))
        let clientImageView = try #require(clientView.subviews.first as? NSImageView)
        let fallbackView = clientView.subviews[1]
        let nameLabel = try #require(clientView.subviews[2] as? NSTextField)

        #expect(fixedConstraintConstant(.width, for: statusImageView) == expected.tableStatusDotSize)
        #expect(fixedConstraintConstant(.height, for: statusImageView) == expected.tableStatusDotSize)
        #expect(fixedConstraintConstant(.width, for: sslImageView) == expected.tableSSLIconSize)
        #expect(fixedConstraintConstant(.height, for: sslImageView) == expected.tableSSLIconSize)
        #expect(clientImageView.frame.size.width == expected.tableClientIconSize)
        #expect(clientImageView.frame.size.height == expected.tableClientIconSize)
        #expect(fallbackView.frame.size.width == expected.tableClientIconSize)
        #expect(fallbackView.frame.size.height == expected.tableClientIconSize)
        #expect(leadingConstraintConstant(for: nameLabel, in: clientView) == expected.tableClientIconSize + 4)
    }

    @Test("Request table reapplies header font to custom columns after appearance changes")
    func requestTableHeaderMetricsApplyToCustomColumns() throws {
        var selectedIDs = Set<UUID>()
        var appUI = AppUISettings()
        appUI.fontSize = 28
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
        let tableView = makeTableView(rowCount: 1, coordinator: coordinator, columns: ["url"])
        let customColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("reqHeader.X-Test"))
        tableView.addTableColumn(customColumn)

        _ = coordinator.applyDisplayMetrics(to: tableView)
        coordinator.applyHeaderMetrics(to: tableView)

        let expected = AppUIDisplayMetrics(settings: appUI).secondaryFontSize
        let customHeaderFont = try #require(customColumn.headerCell.font)

        #expect(customHeaderFont.pointSize == expected)
    }

    private func makeScrollView(documentView: NSTableView) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 120))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = documentView
        return scrollView
    }

    private func makeTableView(
        rowCount: Int,
        coordinator: RequestTableView.Coordinator,
        columns: [String] = ["url"]
    )
        -> NSTableView
    {
        let tableView = NSTableView(
            frame: NSRect(x: 0, y: 0, width: 480, height: CGFloat(rowCount) * 28)
        )
        tableView.rowHeight = 28
        tableView.intercellSpacing = .zero
        for column in columns {
            tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column)))
        }
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        coordinator.tableView = tableView
        tableView.reloadData()
        return tableView
    }

    private func measuredURLWidth(fontSize: Int) -> CGFloat {
        var selectedIDs = Set<UUID>()
        var appUI = AppUISettings()
        appUI.fontSize = fontSize
        let rows = [
            TestFixtures.makeTransaction(
                url: "https://example.com/api/v1/workspaces/current/traffic/transactions?include=metadata"
            ),
        ].map {
            RequestListRow(from: $0, sslState: .insecure)
        }
        let parent = RequestTableView(
            workspaceID: UUID(),
            rows: rows,
            refreshToken: 0,
            isAppendOnly: false,
            displayMetricsOverride: AppUIDisplayMetrics(settings: appUI),
            selectedIDs: Binding(
                get: { selectedIDs },
                set: { selectedIDs = $0 }
            )
        )
        let coordinator = RequestTableView.Coordinator(parent: parent)
        coordinator.rows = rows
        let tableView = makeTableView(rowCount: rows.count, coordinator: coordinator)
        let durationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("duration"))
        durationColumn.width = 70
        tableView.addTableColumn(durationColumn)
        tableView.tableColumns[0].width = 222

        let measuredWidth = coordinator.tableView(tableView, sizeToFitWidthOfColumn: 0)

        #expect(tableView.tableColumns[0].width == 222)
        #expect(tableView.tableColumns[1].width == 70)
        return measuredWidth
    }

    private func fixedConstraintConstant(
        _ attribute: NSLayoutConstraint.Attribute,
        for imageView: NSImageView
    )
        -> CGFloat?
    {
        imageView.constraints.first { constraint in
            constraint.firstItem as AnyObject? === imageView
                && constraint.secondItem == nil
                && constraint.firstAttribute == attribute
        }?.constant
    }

    private func fixedConstraintCount(for imageView: NSImageView) -> Int {
        imageView.constraints.filter { constraint in
            constraint.firstItem as AnyObject? === imageView
                && constraint.secondItem == nil
                && (constraint.firstAttribute == .width || constraint.firstAttribute == .height)
        }.count
    }

    private func leadingConstraintConstant(for textField: NSTextField, in container: NSView) -> CGFloat? {
        container.constraints.first { constraint in
            constraint.firstItem as AnyObject? === textField
                && constraint.secondItem as AnyObject? === container
                && constraint.firstAttribute == .leading
        }?.constant
    }

    private func leadingConstraintCount(for textField: NSTextField, in container: NSView) -> Int {
        container.constraints.filter { constraint in
            constraint.firstItem as AnyObject? === textField
                && constraint.secondItem as AnyObject? === container
                && constraint.firstAttribute == .leading
        }.count
    }
}
