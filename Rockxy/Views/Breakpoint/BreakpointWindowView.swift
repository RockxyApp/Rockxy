import SwiftUI

// Presents the native queue used to review and resolve breakpoint-paused traffic.

// MARK: - BreakpointQueueLayoutMode

private enum BreakpointQueueLayoutMode: String, CaseIterable {
    case horizontal
    case vertical

    // MARK: Internal

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
            String(localized: "Switch to stacked layout", bundle: RockxyLocalization.bundle)
        case .vertical:
            String(localized: "Switch to side-by-side layout", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - BreakpointWindowView

/// Standalone window for reviewing paused traffic without interrupting the
/// user's current selection when additional breakpoint hits arrive.
struct BreakpointWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            mainContent
            Divider()
            actionBar
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(1_060, toolMetrics.bodyFontSize * 34 + 618),
            minHeight: max(640, toolMetrics.bodyFontSize * 18 + 406)
        )
        .onAppear {
            manager.isQueueWindowVisible = true
            normalizePersistedLayoutMode()
        }
        .onDisappear {
            manager.isQueueWindowVisible = false
        }
        .onExitCommand {
            dismiss()
        }
        .confirmationDialog(
            String(localized: "Abort all paused traffic?", bundle: RockxyLocalization.bundle),
            isPresented: $isAbortAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "Abort All with 503", bundle: RockxyLocalization.bundle),
                role: .destructive
            ) {
                manager.resolveAll(decision: .abort)
            }
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {}
        } message: {
            Text(
                String(AttributedString(
                    localized: "^[\(manager.pausedItems.count) paused item](inflect: true) will receive a 503 Service Unavailable response.",
                    bundle: RockxyLocalization.bundle,
                    locale: RockxyLocalization.locale
                ).characters)
            )
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @AppStorage("breakpointQueueLayoutMode") private var layoutModeRaw = BreakpointQueueLayoutMode.horizontal.rawValue
    @State private var canApplySelectedChanges = true
    @State private var isAbortAllConfirmationPresented = false

    private let manager = BreakpointManager.shared

    private var layoutMode: BreakpointQueueLayoutMode {
        get { BreakpointQueueLayoutMode(rawValue: layoutModeRaw) ?? .horizontal }
        nonmutating set { layoutModeRaw = newValue.rawValue }
    }

    private var queueSelection: Binding<UUID?> {
        Binding(
            get: { manager.selectedItemId },
            set: { manager.selectedItemId = $0 }
        )
    }

    private var queueSummary: String {
        String(AttributedString(
            localized: "^[\(manager.pausedItems.count) item](inflect: true) waiting",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }

    private var hasSelection: Bool {
        guard let selectedItemId = manager.selectedItemId else {
            return false
        }
        return manager.pausedItems.contains(where: { $0.id == selectedItemId })
    }

    private var canApplySelection: Bool {
        guard canApplySelectedChanges,
              let selectedItemId = manager.selectedItemId else
        {
            return false
        }
        guard let item = manager.pausedItems.first(where: { $0.id == selectedItemId }) else {
            return false
        }
        return item.editableDraft.executionValidationMessage == nil
    }

    private var applyButtonHelp: String {
        guard hasSelection else {
            return String(localized: "Select paused traffic to apply changes", bundle: RockxyLocalization.bundle)
        }
        if let selectedItemId = manager.selectedItemId,
           let item = manager.pausedItems.first(where: { $0.id == selectedItemId }),
           !item.editableDraft.isBodyEditable
        {
            return String(
                localized: "The body is protected. Request-line, status, and header changes can still be applied.",
                bundle: RockxyLocalization.bundle
            )
        }
        if !canApplySelectedChanges {
            return String(
                localized: "Fix or discard the invalid Raw message before applying changes",
                bundle: RockxyLocalization.bundle
            )
        }
        if let selectedItemId = manager.selectedItemId,
           let item = manager.pausedItems.first(where: { $0.id == selectedItemId }),
           let message = item.editableDraft.executionValidationMessage
        {
            return message
        }
        return String(localized: "Apply the edited message and continue (⌘↩)", bundle: RockxyLocalization.bundle)
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder private var mainContent: some View {
        switch layoutMode {
        case .horizontal:
            HSplitView {
                queuePanel
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
                editor
                    .frame(minWidth: 660)
            }
        case .vertical:
            VSplitView {
                queuePanel
                    .frame(minHeight: 210, idealHeight: 260)
                editor
                    .frame(minHeight: 380)
            }
        }
    }

    private var queuePanel: some View {
        VStack(spacing: 0) {
            queueHeader
            Divider()

            ZStack {
                if manager.pausedItems.isEmpty {
                    ContentUnavailableView {
                        Label(
                            String(localized: "No Paused Traffic", bundle: RockxyLocalization.bundle),
                            systemImage: "pause.circle"
                        )
                    } description: {
                        Text(String(
                            localized: "Traffic matching an enabled breakpoint rule will appear here.",
                            bundle: RockxyLocalization.bundle
                        ))
                    } actions: {
                        Button(String(localized: "Manage Rules", bundle: RockxyLocalization.bundle)) {
                            openWindow(id: "breakpointRules")
                        }
                    }
                } else {
                    List(selection: queueSelection) {
                        ForEach(manager.pausedItems) { item in
                            BreakpointQueueRow(item: item)
                                .tag(item.id)
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()
            queueFooter
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var queueHeader: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Paused Traffic", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .semibold))
                Text(queueSummary)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                layoutMode = layoutMode.next
            } label: {
                Label(
                    String(localized: "Switch Layout", bundle: RockxyLocalization.bundle),
                    systemImage: layoutMode.systemImage
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(layoutMode.help)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, 10)
    }

    private var queueFooter: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Button {
                manager.selectPreviousItem()
            } label: {
                Label(String(localized: "Previous Item", bundle: RockxyLocalization.bundle), systemImage: "chevron.up")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!manager.hasPausedItems)
            .help(String(localized: "Previous Item (⌘[)", bundle: RockxyLocalization.bundle))

            Button {
                manager.selectNextItem()
            } label: {
                Label(String(localized: "Next Item", bundle: RockxyLocalization.bundle), systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!manager.hasPausedItems)
            .help(String(localized: "Next Item (⌘])", bundle: RockxyLocalization.bundle))

            Spacer()

            Button(String(localized: "Manage Rules", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "breakpointRules")
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            moreMenu
        }
        .controlSize(.small)
        .frame(minHeight: toolMetrics.footerControlHeight)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .rockxyFunctionalBar()
    }

    private var editor: some View {
        BreakpointEditorView(
            manager: manager,
            canApplySelectedChanges: $canApplySelectedChanges
        )
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                resolveSelected(.cancel)
            } label: {
                Label(
                    String(localized: "Continue Original", bundle: RockxyLocalization.bundle),
                    systemImage: "play.fill"
                )
                .frame(minWidth: 132)
            }
            .help(String(
                localized: "Discard edits and continue with the original message",
                bundle: RockxyLocalization.bundle
            ))
            .disabled(!hasSelection)

            Button(role: .destructive) {
                resolveSelected(.abort)
            } label: {
                Label(
                    String(localized: "Abort with 503", bundle: RockxyLocalization.bundle),
                    systemImage: "xmark.octagon"
                )
                .frame(minWidth: 132)
            }
            .keyboardShortcut(".", modifiers: .command)
            .help(String(
                localized: "Stop this transaction with a 503 Service Unavailable response",
                bundle: RockxyLocalization.bundle
            ))
            .disabled(!hasSelection)

            Spacer()

            Button {
                resolveSelected(.execute)
            } label: {
                Label(
                    String(localized: "Apply Changes & Continue", bundle: RockxyLocalization.bundle),
                    systemImage: "arrowshape.turn.up.right.fill"
                )
                .frame(minWidth: 180)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .rockxyGlassButtonStyle(prominent: true)
            .help(applyButtonHelp)
            .disabled(!canApplySelection)
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .rockxyFunctionalBar()
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "Continue All Original", bundle: RockxyLocalization.bundle)) {
                manager.resolveAll(decision: .cancel)
            }
            .disabled(!manager.hasPausedItems)

            Button(String(localized: "Abort All with 503", bundle: RockxyLocalization.bundle), role: .destructive) {
                isAbortAllConfirmationPresented = true
            }
            .disabled(!manager.hasPausedItems)

            Divider()

            Button(layoutMode.help) {
                layoutMode = layoutMode.next
            }

            Button(String(localized: "Templates…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "breakpointTemplates")
            }

            Button(String(localized: "Manage Rules…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "breakpointRules")
            }
        } label: {
            Label(String(localized: "More", bundle: RockxyLocalization.bundle), systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .fixedSize()
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

// MARK: - BreakpointQueueRow

private struct BreakpointQueueRow: View {
    // MARK: Internal

    let item: PausedBreakpointItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            phaseBadge

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(primaryValue)
                        .font(toolMetrics.secondaryFont(weight: .semibold, monospaced: true))
                        .foregroundStyle(primaryColor)

                    Text(displayHost)
                        .font(toolMetrics.secondaryFont(weight: .medium))
                        .lineLimit(1)
                }

                Text(displayPath)
                    .font(toolMetrics.secondaryFont(monospaced: true))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Label(item.client, systemImage: "desktopcomputer")
                    if !item.queryName.isEmpty {
                        Label(item.queryName, systemImage: "text.magnifyingglass")
                    }
                    Spacer(minLength: 4)
                    ElapsedTimeLabel(since: item.createdAt)
                }
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var primaryValue: String {
        if item.phase == .request {
            return item.editableDraft.method
        }
        return String(item.editableDraft.statusCode)
    }

    private var primaryColor: Color {
        guard item.phase == .response else {
            return .primary
        }
        switch item.editableDraft.statusCode {
        case 200 ..< 300: return .green
        case 300 ..< 400: return .blue
        case 400 ..< 500: return .orange
        case 500...: return .red
        default: return .secondary
        }
    }

    private var displayComponents: URLComponents? {
        URLComponents(string: item.editableDraft.url)
    }

    private var displayHost: String {
        var value = displayComponents?.host ?? item.host
        if let port = displayComponents?.port {
            value += ":\(port)"
        }
        return value.isEmpty ? String(localized: "Unknown Host", bundle: RockxyLocalization.bundle) : value
    }

    private var displayPath: String {
        guard let components = displayComponents else {
            return item.editableDraft.url
        }
        var value = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery, !query.isEmpty {
            value += "?\(query)"
        }
        return value
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var phaseBadge: some View {
        Text(item.phase == .request ? "REQ" : "RES")
            .font(toolMetrics.metadataFont(weight: .semibold, monospaced: true))
            .foregroundStyle(item.phase == .request ? Color.green : Color.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                (item.phase == .request ? Color.green : Color.blue)
                    .opacity(0.12),
                in: RoundedRectangle(cornerRadius: 4)
            )
    }
}

// MARK: - ElapsedTimeLabel

/// Live-updating elapsed time shared by the queue and selected-item banner.
struct ElapsedTimeLabel: View {
    // MARK: Internal

    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(since))
            Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
