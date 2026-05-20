import SwiftUI

// Presents the breakpoint window for breakpoint review and editing.

// MARK: - BreakpointQueueLayoutMode

private enum BreakpointQueueLayoutMode: String, CaseIterable {
    case horizontal
    case vertical

    var next: BreakpointQueueLayoutMode {
        switch self {
        case .horizontal: .vertical
        case .vertical: .horizontal
        }
    }

    var systemImage: String {
        switch self {
        case .horizontal: "rectangle.split.1x2"
        case .vertical: "rectangle.split.2x1"
        }
    }

    var help: String {
        switch self {
        case .horizontal:
            String(localized: "Switch Layout Mode: Vertical")
        case .vertical:
            String(localized: "Switch Layout Mode: Horizontal")
        }
    }
}

// MARK: - BreakpointWindowView

/// Standalone window for managing breakpoint-paused requests.
/// The queue mirrors a native macOS proxy table while the editor keeps the
/// existing breakpoint editing workflow on the selected item.
struct BreakpointWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            mainContent
            Divider()
            queueToolbar
            Divider()
            actionBar
        }
        .frame(minWidth: 960, minHeight: 560)
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @AppStorage("breakpointQueueLayoutMode") private var layoutModeRaw = BreakpointQueueLayoutMode.horizontal.rawValue

    private let manager = BreakpointManager.shared
    private let windowModel = BreakpointWindowModel.shared
    private let queueRatio: CGFloat = 0.4

    private var layoutMode: BreakpointQueueLayoutMode {
        get { BreakpointQueueLayoutMode(rawValue: layoutModeRaw) ?? .horizontal }
        nonmutating set { layoutModeRaw = newValue.rawValue }
    }

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { geometry in
            switch layoutMode {
            case .horizontal:
                HStack(spacing: 0) {
                    queueTable
                        .frame(width: max(360, geometry.size.width * queueRatio))
                    Divider()
                    editor
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .vertical:
                VStack(spacing: 0) {
                    queueTable
                        .frame(height: max(180, geometry.size.height * queueRatio))
                    Divider()
                    editor
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear(perform: normalizePersistedLayoutMode)
    }

    private var queueTable: some View {
        BreakpointQueueTableView(manager: manager, centersEmptyState: layoutMode == .vertical)
    }

    private var editor: some View {
        BreakpointEditorView(manager: manager, windowModel: windowModel)
    }

    private var queueToolbar: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Manage Rules")) {
                openWindow(id: "breakpointRules")
            }
            .keyboardShortcut("b", modifiers: .command)

            Spacer()

            Button {
                layoutMode = layoutMode.next
            } label: {
                Label(String(localized: "Switch Layout"), systemImage: layoutMode.systemImage)
                    .labelStyle(.iconOnly)
            }
            .help(layoutMode.help)

            Divider()
                .frame(height: 22)

            moreMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                resolveSelected(.cancel)
            } label: {
                Label(String(localized: "Continue"), systemImage: "play.fill")
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!hasSelection)

            Button {
                resolveSelected(.abort)
            } label: {
                Label(String(localized: "Abort"), systemImage: "xmark.octagon")
            }
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(!hasSelection)

            Button {
                resolveSelected(.cancel)
            } label: {
                Label(String(localized: "Skip Once"), systemImage: "forward.frame")
            }
            .disabled(!hasSelection)

            Spacer()

            Button {
                resolveSelected(.execute)
            } label: {
                Label(String(localized: "Execute"), systemImage: "arrowshape.turn.up.right.fill")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!hasSelection)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "Execute")) {
                resolveSelected(.execute)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!hasSelection)

            Button(String(localized: "Execute All")) {
                manager.resolveAll(decision: .execute)
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(!manager.hasPausedItems)

            Divider()

            Button(String(localized: "Continue")) {
                resolveSelected(.cancel)
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!hasSelection)

            Button(String(localized: "Continue All")) {
                manager.resolveAll(decision: .cancel)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(!manager.hasPausedItems)

            Divider()

            Button(String(localized: "Abort")) {
                resolveSelected(.abort)
            }
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(!hasSelection)

            Button(String(localized: "Abort All")) {
                manager.resolveAll(decision: .abort)
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])
            .disabled(!manager.hasPausedItems)

            Divider()

            Menu(String(localized: "Advanced Settings")) {
                Button(layoutMode.help) {
                    layoutMode = layoutMode.next
                }
                Button(String(localized: "Templates...")) {
                    openWindow(id: "breakpointTemplates")
                }
            }

            Divider()

            Button(String(localized: "Add Rule")) {
                openWindow(id: "breakpointRules")
            }
            .keyboardShortcut("b", modifiers: .command)
        } label: {
            Label(String(localized: "More"), systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var hasSelection: Bool {
        manager.selectedItemId != nil
    }

    private func resolveSelected(_ decision: BreakpointDecision) {
        guard let selectedId = manager.selectedItemId else {
            return
        }
        manager.resolve(id: selectedId, decision: decision)
    }

    private func normalizePersistedLayoutMode() {
        if BreakpointQueueLayoutMode(rawValue: layoutModeRaw) == nil {
            layoutModeRaw = BreakpointQueueLayoutMode.horizontal.rawValue
        }
    }
}

// MARK: - BreakpointQueueTableView

private struct BreakpointQueueTableView: View {
    @Bindable var manager: BreakpointManager
    let centersEmptyState: Bool

    private struct Column {
        let title: String
        let minWidth: CGFloat
        let preferredWidth: CGFloat
    }

    private let columns: [Column] = [
        Column(title: String(localized: "ID"), minWidth: 44, preferredWidth: 54),
        Column(title: String(localized: "URL"), minWidth: 220, preferredWidth: 360),
        Column(title: String(localized: "Client"), minWidth: 90, preferredWidth: 150),
        Column(title: String(localized: "Method"), minWidth: 70, preferredWidth: 86),
        Column(title: String(localized: "Status"), minWidth: 74, preferredWidth: 96),
        Column(title: String(localized: "Code"), minWidth: 52, preferredWidth: 64),
        Column(title: String(localized: "Time"), minWidth: 78, preferredWidth: 102),
        Column(title: String(localized: "Duration"), minWidth: 78, preferredWidth: 102),
        Column(title: String(localized: "Request"), minWidth: 70, preferredWidth: 86),
        Column(title: String(localized: "Response"), minWidth: 78, preferredWidth: 94),
        Column(title: String(localized: "Query Name"), minWidth: 90, preferredWidth: 136),
    ]

    var body: some View {
        GeometryReader { geometry in
            let columnWidths = effectiveColumnWidths(for: geometry.size.width)
            let contentWidth = max(tableWidth(for: columnWidths), geometry.size.width)
            let contentHeight = max(geometry.size.height, headerHeight + 1)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        headerRow(columnWidths: columnWidths)
                            .frame(width: contentWidth, alignment: .leading)
                        Divider()
                        ForEach(manager.pausedItems) { item in
                            queueRow(item, columnWidths: columnWidths)
                            Divider()
                        }
                    }
                    .frame(width: contentWidth, alignment: .topLeading)
                    .frame(minHeight: contentHeight, alignment: .topLeading)

                    if manager.pausedItems.isEmpty {
                        emptyState
                            .frame(
                                width: geometry.size.width,
                                height: max(0, contentHeight - headerHeight - 1),
                                alignment: centersEmptyState ? .center : .leading
                            )
                            .padding(.top, headerHeight + 1)
                    }
                }
                .frame(width: contentWidth, alignment: .topLeading)
                .frame(minHeight: contentHeight, alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func tableWidth(for columnWidths: [CGFloat]) -> CGFloat {
        columnWidths.reduce(0, +)
    }

    private func effectiveColumnWidths(for availableWidth: CGFloat) -> [CGFloat] {
        let preferredTotal = columns.reduce(CGFloat.zero) { $0 + $1.preferredWidth }
        let minimumTotal = columns.reduce(CGFloat.zero) { $0 + $1.minWidth }

        guard availableWidth < preferredTotal else {
            return columns.map(\.preferredWidth)
        }
        guard availableWidth > minimumTotal else {
            return columns.map(\.minWidth)
        }

        let flexibleTotal = preferredTotal - minimumTotal
        let availableFlex = availableWidth - minimumTotal
        return columns.map { column in
            let columnFlex = column.preferredWidth - column.minWidth
            return column.minWidth + (columnFlex / flexibleTotal * availableFlex)
        }
    }

    private var headerHeight: CGFloat {
        32
    }

    private var emptyState: some View {
        VStack(alignment: centersEmptyState ? .center : .leading, spacing: 8) {
            Text(String(localized: "No Breakpoints"))
                .font(.title3.weight(.semibold))
            Text(String(localized: "Click \"Manage Rules\" button to create your first Breakpoint Rules"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(centersEmptyState ? .center : .leading)
        .padding(.horizontal, centersEmptyState ? 24 : 16)
    }

    private func headerRow(columnWidths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { offset, column in
                Text(column.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: columnWidths[offset], height: headerHeight, alignment: .leading)
                    .padding(.leading, 8)
                    .overlay(alignment: .trailing) {
                        Divider().frame(height: 20)
                    }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func queueRow(_ item: PausedBreakpointItem, columnWidths: [CGFloat]) -> some View {
        let isSelected = manager.selectedItemId == item.id
        return HStack(spacing: 0) {
            Group {
                cell("\(item.sequenceNumber)", width: columnWidths[0], monospaced: true)
                cell(item.url, width: columnWidths[1], monospaced: true, help: item.url)
                cell(item.client, width: columnWidths[2])
                cell(item.method, width: columnWidths[3], monospaced: true)
                cell(String(localized: "Paused"), width: columnWidths[4], color: .orange)
                cell(
                    item.statusCode.map(String.init) ?? "",
                    width: columnWidths[5],
                    color: statusColor(for: item.statusCode)
                )
            }
            Group {
                timeCell(item.createdAt, width: columnWidths[6])
                durationCell(item.createdAt, width: columnWidths[7])
                phaseCell(item.phase == .request ? "REQ" : "", width: columnWidths[8])
                phaseCell(item.phase == .response ? "RES" : "", width: columnWidths[9])
                cell(item.queryName, width: columnWidths[10])
            }
        }
        .frame(height: 28)
        .background(isSelected ? Color.accentColor.opacity(0.18) : rowBackground(for: item))
        .contentShape(Rectangle())
        .onTapGesture {
            manager.selectedItemId = item.id
        }
    }

    private func cell(
        _ value: String,
        width: CGFloat,
        color: Color = .primary,
        monospaced: Bool = false,
        help: String? = nil
    )
        -> some View
    {
        Text(value)
            .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
            .foregroundStyle(color)
            .lineLimit(1)
            .help(help ?? value)
            .frame(width: width, alignment: .leading)
            .padding(.leading, 8)
    }

    private func timeCell(_ date: Date, width: CGFloat) -> some View {
        Text(date, format: .dateTime.hour().minute().second())
            .font(.system(.caption, design: .monospaced))
            .monospacedDigit()
            .frame(width: width, alignment: .leading)
            .padding(.leading, 8)
    }

    private func durationCell(_ date: Date, width: CGFloat) -> some View {
        ElapsedTimeLabel(since: date)
            .frame(width: width, alignment: .leading)
            .padding(.leading, 8)
    }

    private func phaseText(_ value: String) -> some View {
        Text(value)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundStyle(value == "REQ" ? Color.green : Color.blue)
    }

    private func phaseCell(_ value: String, width: CGFloat) -> some View {
        phaseText(value)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .frame(width: width, alignment: .leading)
            .padding(.leading, 8)
    }

    private func rowBackground(for item: PausedBreakpointItem) -> Color {
        item.sequenceNumber.isMultiple(of: 2)
            ? Color(nsColor: .textBackgroundColor)
            : Color(nsColor: .controlBackgroundColor).opacity(0.45)
    }

    private func statusColor(for statusCode: Int?) -> Color {
        guard let statusCode else {
            return Color.secondary
        }
        switch statusCode {
        case 200 ..< 300: return Color.green
        case 300 ..< 400: return Color.blue
        case 400 ..< 500: return Color.orange
        case 500...: return Color.red
        default: return Color.secondary
        }
    }
}
