import SwiftUI

// Renders the traffic quick-action strip that sits above the protocol filter bar.

// MARK: - TrafficCommandKind

enum TrafficCommandKind: String, CaseIterable {
    case clearSession
    case jumpToFirstRequest
    case followLive
    case jumpToLastRequest
    case copyAsCURL
    case togglePin
    case toggleSave
}

// MARK: - TrafficCommandDescriptor

/// Value-typed presentation contract for traffic-strip controls and their structured overflow menu.
/// The main menu remains the keyboard-shortcut owner; this surface mirrors those commands and keeps
/// their live state and availability close to the request list.
struct TrafficCommandDescriptor: Identifiable, Equatable {
    let id: TrafficCommandKind
    let title: String
    let systemImage: String
    let help: String
    let isActive: Bool
    let isEnabled: Bool

    static func clearSession(isEnabled: Bool = true) -> Self {
        .init(
            id: .clearSession,
            title: String(localized: "Clear Session", bundle: RockxyLocalization.bundle),
            systemImage: "trash",
            help: String(
                localized: "Clear captured requests and logs from this session across all tabs. ⌘K",
                bundle: RockxyLocalization.bundle
            ),
            isActive: false,
            isEnabled: isEnabled
        )
    }

    static func jumpToFirstRequest(isEnabled: Bool) -> Self {
        .init(
            id: .jumpToFirstRequest,
            title: String(localized: "Jump to First Request", bundle: RockxyLocalization.bundle),
            systemImage: "arrow.up.to.line",
            help: String(localized: "Jump to the first visible request. ⌘↑", bundle: RockxyLocalization.bundle),
            isActive: false,
            isEnabled: isEnabled
        )
    }

    static func followLive(isActive: Bool) -> Self {
        .init(
            id: .followLive,
            title: String(localized: "Follow Live", bundle: RockxyLocalization.bundle),
            systemImage: "dot.radiowaves.right",
            help: isActive
                ? String(
                    localized: "Follow Live is on for this tab. Scroll, select a row, or click again to stop. ⇧⌘L",
                    bundle: RockxyLocalization.bundle
                )
                : String(
                    localized: "Keep the newest request in this tab selected. ⇧⌘L",
                    bundle: RockxyLocalization.bundle
                ),
            isActive: isActive,
            isEnabled: true
        )
    }

    static func jumpToLastRequest(isEnabled: Bool) -> Self {
        .init(
            id: .jumpToLastRequest,
            title: String(localized: "Jump to Last Request", bundle: RockxyLocalization.bundle),
            systemImage: "arrow.down.to.line",
            help: String(
                localized: "Jump to the latest visible request without changing Follow Live. ⌘↓",
                bundle: RockxyLocalization.bundle
            ),
            isActive: false,
            isEnabled: isEnabled
        )
    }

    static func copyAsCURL(isEnabled: Bool) -> Self {
        .init(
            id: .copyAsCURL,
            title: String(localized: "Copy as cURL", bundle: RockxyLocalization.bundle),
            systemImage: "terminal",
            help: String(
                localized: "Copy the selected request as a cURL command. ⇧⌘C",
                bundle: RockxyLocalization.bundle
            ),
            isActive: false,
            isEnabled: isEnabled
        )
    }

    static func togglePin(isPinned: Bool, isEnabled: Bool) -> Self {
        .init(
            id: .togglePin,
            title: isPinned ? String(localized: "Unpin Request", bundle: RockxyLocalization.bundle) : String(
                localized: "Pin Request",
                bundle: RockxyLocalization.bundle
            ),
            systemImage: isPinned ? "pin.fill" : "pin",
            help: isPinned
                ? String(
                    localized: "Unpin the selected request from the current session.",
                    bundle: RockxyLocalization.bundle
                )
                : String(
                    localized: "Keep the selected request pinned in the current session.",
                    bundle: RockxyLocalization.bundle
                ),
            isActive: isPinned,
            isEnabled: isEnabled
        )
    }

    static func toggleSave(isSaved: Bool, isEnabled: Bool) -> Self {
        .init(
            id: .toggleSave,
            title: isSaved ? String(localized: "Unsave Request", bundle: RockxyLocalization.bundle) : String(
                localized: "Save Request",
                bundle: RockxyLocalization.bundle
            ),
            systemImage: isSaved ? "tray.full.fill" : "tray.and.arrow.down",
            help: isSaved
                ? String(localized: "Remove the selected request from the Library.", bundle: RockxyLocalization.bundle)
                : String(localized: "Save the selected request to the Library.", bundle: RockxyLocalization.bundle),
            isActive: isSaved,
            isEnabled: isEnabled
        )
    }
}

// MARK: - TrafficRecordingCommandPresentation

/// Presentation for the capture-buffer toggle. Start/Stop remains a window-toolbar lifecycle
/// control, while this command explicitly names the recording-buffer state so the two actions
/// cannot be mistaken for one another.
struct TrafficRecordingCommandPresentation: Equatable {
    let title: String
    let systemImage: String
    let help: String
    let isEnabled: Bool

    static func make(isProxyRunning: Bool, isRecording: Bool) -> Self {
        .init(
            title: isRecording ? String(localized: "Pause Recording", bundle: RockxyLocalization.bundle) : String(
                localized: "Resume Recording",
                bundle: RockxyLocalization.bundle
            ),
            systemImage: isRecording ? "pause.circle" : "record.circle",
            help: isProxyRunning
                ? (isRecording
                    ? String(
                        localized: "Pause recording new traffic without stopping the proxy. ⌥⌘R",
                        bundle: RockxyLocalization.bundle
                    )
                    : String(localized: "Resume recording new traffic. ⌥⌘R", bundle: RockxyLocalization.bundle))
                : String(
                    localized: "Start the proxy before changing recording. ⌥⌘R",
                    bundle: RockxyLocalization.bundle
                ),
            isEnabled: isProxyRunning
        )
    }
}

// MARK: - TrafficActionsMenuPresentation

enum TrafficActionsMenuPresentation {
    static let systemImage = "ellipsis.circle"

    static var help: String {
        String(localized: "More traffic actions", bundle: RockxyLocalization.bundle)
    }

    static var accessibilityLabel: String {
        String(localized: "More Traffic Actions", bundle: RockxyLocalization.bundle)
    }
}

// MARK: - TrafficCommandBar

/// A native command strip for immediate traffic work. Recording, session clearing, and live-tail
/// state stay visible; richer request, rule, navigation, session, and export workflows live in one
/// structured icon menu. Proxy Start/Stop remains in the window toolbar, spatially separate from
/// the explicitly labeled recording-buffer control here.
struct TrafficCommandBar: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    var onOpenToolWindow: (String) -> Void = { _ in }
    var isEmbeddedInControlShelf = false
    var showsQuickTools = true

    var body: some View {
        commandRow
            .padding(.horizontal, Theme.Layout.contentPadding)
            .padding(.vertical, max(4, (metrics.fontSize - 10) / 3))
            .background {
                if !isEmbeddedInControlShelf {
                    Color(nsColor: .windowBackgroundColor)
                }
            }
            .overlay(alignment: .bottom) {
                if !isEmbeddedInControlShelf {
                    Divider()
                }
            }
            .fixedSize(horizontal: isEmbeddedInControlShelf, vertical: true)
            .task { persistResolvedQuickToolsLayoutIfNeeded() }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
    @AppStorage(QuickToolsLayout.storageKey) private var quickToolsLayoutRaw = ""
    @AppStorage(QuickToolsLayout.legacyFooterStorageKey) private var legacyFooterQuickToolOrder = ""
    @State private var isCustomizingQuickTools = false

    /// Stable reference to the Allow List singleton so Observation tracks `isActive` inside `body`
    /// and re-renders the Allow List capsule's active state when the master toggle changes.
    private let allowListManager = AllowListManager.shared

    private var actions: MainContentCommandActions {
        MainContentCommandActions(coordinator: coordinator)
    }

    private var quickToolsLayout: QuickToolsLayout {
        QuickToolsLayout.resolved(
            storageRaw: quickToolsLayoutRaw,
            legacyFooterRaw: legacyFooterQuickToolOrder
        )
    }

    private var selectedTransaction: HTTPTransaction? {
        coordinator.selectedTransaction
    }

    private var effectiveSelectionCount: Int {
        max(coordinator.selectedTransactionIDs.count, selectedTransaction == nil ? 0 : 1)
    }

    private var hasSingleRequestSelection: Bool {
        TrafficCommandAvailability.canActOnSingleRequest(
            hasPrimarySelection: selectedTransaction != nil,
            selectionCount: effectiveSelectionCount
        )
    }

    private var canUseHTTPOnlySelection: Bool {
        guard let selectedTransaction else {
            return false
        }
        return TrafficCommandAvailability.canUseHTTPOnlyRequestAction(
            hasPrimarySelection: true,
            selectionCount: effectiveSelectionCount,
            isWebSocket: selectedTransaction.webSocketConnection != nil,
            method: selectedTransaction.request.method
        )
    }

    private var canClearSession: Bool {
        TrafficCommandAvailability.canClearSession(
            transactionCount: coordinator.transactions.count,
            logCount: coordinator.logEntries.count,
            hasSessionProvenance: coordinator.sessionProvenance != nil,
            isClearingSession: coordinator.isClearingSession
        )
    }

    private var commandRow: some View {
        HStack(spacing: 8) {
            recordingButton
            clearSessionButton
            commandDivider
            followLiveButton
            if showsQuickTools {
                responsiveQuickToolsGroup
            }

            Spacer(minLength: showsQuickTools ? 12 : 4)
            moreActionsMenu
        }
    }

    private var recordingButton: some View {
        let presentation = TrafficRecordingCommandPresentation.make(
            isProxyRunning: coordinator.isProxyRunning,
            isRecording: coordinator.isRecording
        )
        return Button {
            actions.toggleRecording()
        } label: {
            commandLabel(title: presentation.title, systemImage: presentation.systemImage)
        }
        .rockxyGlassButtonStyle()
        .controlSize(.small)
        .disabled(!presentation.isEnabled)
        .help(presentation.help)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(
            coordinator.isRecording ? String(localized: "Recording", bundle: RockxyLocalization.bundle) : String(
                localized: "Paused",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    /// The shared quick-tool capsules for the command bar. Responsive: three capsules when wide,
    /// two when medium, none when narrow — it never degrades to icon-only controls. Hidden tools
    /// stay reachable through the Traffic Actions "Quick Tools" submenu.
    private var responsiveQuickToolsGroup: some View {
        let descriptors = FooterActionDescriptor.toolingActions(
            isAllowListActive: allowListManager.isActive,
            quickTools: quickToolsLayout.commandBar
        )
        return ViewThatFits(in: .horizontal) {
            quickToolsGroup(descriptors)
            quickToolsGroup(Array(descriptors.prefix(2)))
            EmptyView()
        }
    }

    private var clearSessionButton: some View {
        let descriptor = TrafficCommandDescriptor.clearSession(isEnabled: canClearSession)
        return Button {
            actions.clearSession()
        } label: {
            commandLabel(title: descriptor.title, systemImage: descriptor.systemImage)
        }
        .rockxyGlassButtonStyle()
        .controlSize(.small)
        .disabled(!descriptor.isEnabled)
        .help(descriptor.help)
        .accessibilityLabel(descriptor.title)
    }

    private var followLiveButton: some View {
        let descriptor = TrafficCommandDescriptor.followLive(isActive: coordinator.isFollowingLiveTraffic)
        return Button {
            coordinator.setFollowingLiveTraffic(!coordinator.isFollowingLiveTraffic)
        } label: {
            commandLabel(title: descriptor.title, systemImage: descriptor.systemImage)
                .foregroundStyle(.primary)
        }
        .rockxyGlassButtonStyle()
        .controlSize(.small)
        .overlay {
            if descriptor.isActive {
                Capsule(style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(Theme.Glass.activeStrokeOpacity), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .help(descriptor.help)
        .accessibilityLabel(descriptor.title)
        .accessibilityValue(descriptor.isActive ? String(localized: "On", bundle: RockxyLocalization.bundle) : String(
            localized: "Off",
            bundle: RockxyLocalization.bundle
        ))
    }

    private var moreActionsMenu: some View {
        Menu {
            navigationMenu

            Divider()

            requestMenu
            createRuleMenu

            Divider()

            quickToolsMenu

            Divider()

            Button(String(localized: "Compose…", bundle: RockxyLocalization.bundle)) { actions.composeFreshRequest() }
            sessionMenu
            exportMenu
        } label: {
            Image(systemName: TrafficActionsMenuPresentation.systemImage)
                .font(.system(size: metrics.controlFontSize, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: metrics.filterBarHeight, height: metrics.filterBarHeight)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(TrafficActionsMenuPresentation.help)
        .accessibilityLabel(TrafficActionsMenuPresentation.accessibilityLabel)
        .popover(isPresented: $isCustomizingQuickTools, arrowEdge: .bottom) {
            QuickToolsEditor(
                layout: quickToolsLayout,
                onSave: { quickToolsLayoutRaw = $0.encoded },
                onReset: { quickToolsLayoutRaw = QuickToolsLayout.default.encoded },
                onDone: { isCustomizingQuickTools = false }
            )
        }
    }

    /// Keeps the command-bar quick tools discoverable when the responsive strip collapses, and
    /// bridges into the shared customization editor through the stable trailing More menu.
    @ViewBuilder private var quickToolsMenu: some View {
        Menu(String(localized: "Quick Tools", bundle: RockxyLocalization.bundle)) {
            ForEach(
                FooterActionDescriptor.toolingActions(
                    isAllowListActive: allowListManager.isActive,
                    quickTools: quickToolsLayout.commandBar
                )
            ) { descriptor in
                Button {
                    openQuickTool(descriptor.id)
                } label: {
                    Label(descriptor.title, systemImage: descriptor.systemImage)
                }
            }
        }
        Button(String(localized: "Customize Quick Tools…", bundle: RockxyLocalization.bundle)) {
            // A macOS `Menu` tears down its transient window before the next presentation can
            // begin. Defer the popover state change to the next main-queue turn so the stable
            // command-bar anchor presents reliably after the menu has closed.
            DispatchQueue.main.async {
                isCustomizingQuickTools = true
            }
        }
    }

    @ViewBuilder private var navigationMenu: some View {
        Button(String(localized: "Jump to First Request", bundle: RockxyLocalization.bundle)) {
            actions.selectFirstTransaction()
        }
        .disabled(coordinator.filteredTransactions.isEmpty)
        Button(String(localized: "Jump to Last Request", bundle: RockxyLocalization.bundle)) {
            actions.selectLastTransaction()
        }
        .disabled(coordinator.filteredTransactions.isEmpty)
    }

    private var requestMenu: some View {
        Menu(String(localized: "Selected Request", bundle: RockxyLocalization.bundle)) {
            let copy = TrafficCommandDescriptor.copyAsCURL(isEnabled: canUseHTTPOnlySelection)
            Button(copy.title) { actions.copyAsCURL() }
                .disabled(!copy.isEnabled)

            let pin = TrafficCommandDescriptor.togglePin(
                isPinned: selectedTransaction?.isPinned == true,
                isEnabled: hasSingleRequestSelection
            )
            Button(pin.title) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.togglePin(for: selectedTransaction)
            }

            let save = TrafficCommandDescriptor.toggleSave(
                isSaved: selectedTransaction?.isSaved == true,
                isEnabled: hasSingleRequestSelection
            )
            Button(save.title) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.saveRequest(selectedTransaction)
            }

            Divider()

            Button(String(localized: "Repeat", bundle: RockxyLocalization.bundle)) { actions.replayRequest() }
                .disabled(!canUseHTTPOnlySelection)
            Button(String(localized: "Edit and Repeat…", bundle: RockxyLocalization.bundle)) { actions.editAndRepeat() }
                .disabled(!canUseHTTPOnlySelection)

            Divider()

            Button(String(localized: "Add Note…", bundle: RockxyLocalization.bundle)) { actions.addComment() }
            Menu(String(localized: "Highlight", bundle: RockxyLocalization.bundle)) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button(color.displayName) { actions.setHighlight(color) }
                }
                Divider()
                Button(String(localized: "Remove Highlight", bundle: RockxyLocalization.bundle)) {
                    actions.setHighlight(nil)
                }
                Button(String(localized: "Strikethrough", bundle: RockxyLocalization.bundle)) {
                    actions.toggleStrikethrough()
                }
            }
        }
        .disabled(!hasSingleRequestSelection)
    }

    private var createRuleMenu: some View {
        Menu(String(localized: "Create Rule from Request", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Breakpoint…", bundle: RockxyLocalization.bundle)) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.createBreakpointRule(for: selectedTransaction)
            }
            Button(String(localized: "Map Local…", bundle: RockxyLocalization.bundle)) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.createMapLocalRule(for: selectedTransaction)
            }
            Button(String(localized: "Map Remote…", bundle: RockxyLocalization.bundle)) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.createMapRemoteRule(for: selectedTransaction)
            }
            Button(String(localized: "Network Condition…", bundle: RockxyLocalization.bundle)) {
                guard let selectedTransaction else {
                    return
                }
                coordinator.createNetworkConditionsRule(for: selectedTransaction)
            }
        }
        .disabled(!canUseHTTPOnlySelection)
    }

    private var sessionMenu: some View {
        Menu(String(localized: "Session", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Clear Session and Filters", bundle: RockxyLocalization.bundle)) {
                actions.clearCaptureAndFilters()
            }
            .disabled(!canClearSession)
            Button(String(localized: "Save Session…", bundle: RockxyLocalization.bundle)) { actions.saveSession() }
                .disabled(coordinator.transactions.isEmpty)
        }
    }

    private var exportMenu: some View {
        Menu(String(localized: "Export", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Export as HAR…", bundle: RockxyLocalization.bundle)) { actions.exportHAR() }
                .disabled(coordinator.transactions.isEmpty)
            Button(String(localized: "Export as CSV…", bundle: RockxyLocalization.bundle)) { actions.exportCSV() }
                .disabled(coordinator.transactions.isEmpty)
            Button(String(localized: "Export as Rockxy Session…", bundle: RockxyLocalization.bundle)) {
                actions.exportRockxySession()
            }
            .disabled(coordinator.transactions.isEmpty)
            Button(String(localized: "Export as OpenAPI YAML…", bundle: RockxyLocalization.bundle)) {
                actions.exportOpenAPIYAML()
            }
            .disabled(!actions.canExportOpenAPI)
            Button(String(localized: "Export as OpenAPI HTML…", bundle: RockxyLocalization.bundle)) {
                actions.exportOpenAPIHTML()
            }
            .disabled(!actions.canExportOpenAPI)
            Divider()
            Button(String(localized: "Publish Selected to Gist…", bundle: RockxyLocalization.bundle)) {
                actions.publishSelectedToGist()
            }
            .disabled(!actions.canPublishGist)
        }
    }

    private var commandDivider: some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func commandLabel(title: String, systemImage: String) -> some View {
        if isEmbeddedInControlShelf {
            Image(systemName: systemImage)
                .font(.system(size: metrics.controlFontSize, weight: .medium))
                .frame(width: metrics.filterBarHeight, height: metrics.filterBarHeight)
        } else {
            Label(title, systemImage: systemImage)
                .font(.system(size: metrics.secondaryFontSize))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func quickToolsRow(_ descriptors: [FooterActionDescriptor]) -> some View {
        HStack(spacing: 6) {
            ForEach(descriptors) { descriptor in
                FooterToolingButton(descriptor: descriptor) {
                    openQuickTool(descriptor.id)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func quickToolsGroup(_ descriptors: [FooterActionDescriptor]) -> some View {
        HStack(spacing: 8) {
            commandDivider
            quickToolsRow(descriptors)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func persistResolvedQuickToolsLayoutIfNeeded() {
        let normalized = quickToolsLayout.encoded
        if quickToolsLayoutRaw != normalized {
            quickToolsLayoutRaw = normalized
        }
    }

    private func openQuickTool(_ kind: FooterActionKind) {
        guard let windowID = kind.toolWindowID else {
            return
        }
        onOpenToolWindow(windowID)
    }
}

// MARK: - TrafficCommandAvailability

enum TrafficCommandAvailability {
    static func canClearSession(
        transactionCount: Int,
        logCount: Int,
        hasSessionProvenance: Bool,
        isClearingSession: Bool
    )
        -> Bool
    {
        !isClearingSession && (transactionCount > 0 || logCount > 0 || hasSessionProvenance)
    }

    static func canActOnSingleRequest(hasPrimarySelection: Bool, selectionCount: Int) -> Bool {
        hasPrimarySelection && selectionCount == 1
    }

    static func canUseHTTPOnlyRequestAction(
        hasPrimarySelection: Bool,
        selectionCount: Int,
        isWebSocket: Bool,
        method: String
    )
        -> Bool
    {
        canActOnSingleRequest(
            hasPrimarySelection: hasPrimarySelection,
            selectionCount: selectionCount
        ) && !isWebSocket && method.caseInsensitiveCompare("CONNECT") != .orderedSame
    }
}
