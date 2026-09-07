import SwiftUI

// Renders the center content interface for traffic list presentation.

// MARK: - CenterContentView

/// Primary content area composing the traffic command strip, the protocol filter bar, the optional
/// advanced filter bar, the NSTableView-backed request list, an optional bottom inspector panel,
/// and the status bar. Manages the bridge between NSTableView selection (Set<UUID>) and the
/// coordinator's single-selection model.
///
/// The `TrafficCommandBar` owns session, live-navigation, and selected-request handoffs.
/// Persistent tool launchers stay in the footer, while filtering stays exclusively with
/// `SearchFilterBar` / `AdvancedFilterBar`.
struct CenterContentView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let onOpenToolWindow: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TrafficControlShelf(
                coordinator: coordinator,
                advancedRuleCount: advancedRuleCount,
                onOpenToolWindow: onOpenToolWindow
            )

            inspectorWorkspace

            StatusBarView(
                totalCount: coordinator.filteredTransactions.count,
                selectedCount: selectedIDs.count,
                availableCount: coordinator.availableTransactionCountForCurrentScope,
                isProxyRunning: coordinator.isProxyRunning,
                proxyHost: AppSettingsManager.shared.settings.effectiveListenAddress,
                proxyPort: coordinator.activeProxyPort,
                totalDataSize: coordinator.totalDataSize,
                uploadSpeed: coordinator.uploadSpeed,
                downloadSpeed: coordinator.downloadSpeed,
                isProxyOverridden: coordinator.isProxyOverridden,
                isAllowListActive: allowListManager.isActive,
                isNoCachingActive: isNoCachingEnabled,
                activeFilterCount: activeFilterCount,
                errorCount: coordinator.errorCount,
                proxyStartedAt: coordinator.proxyStartedAt,
                selectedRequestInfo: coordinator.selectedTransaction.map {
                    "\($0.request.method) \($0.request.path)"
                },
                sessionProvenance: coordinator.sessionProvenance,
                activeRules: coordinator.rules,
                mapLocalToolEnabled: mapLocalToolEnabled,
                mapRemoteToolEnabled: mapRemoteToolEnabled,
                breakpointToolEnabled: breakpointToolEnabled,
                pausedBreakpointCount: coordinator.breakpointManager.pausedItems.count,
                onSwitchOffProxyOverride: {
                    coordinator.switchOffSystemProxyOverride()
                },
                onOpenToolWindow: onOpenToolWindow
            )
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(Theme.Glass.ambientAccentOpacity),
                        Color.cyan.opacity(Theme.Glass.ambientSecondaryOpacity),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [
                        Color.cyan.opacity(Theme.Glass.ambientSecondaryOpacity),
                        Color.accentColor.opacity(Theme.Glass.ambientSecondaryOpacity * 0.45),
                        Color.clear,
                    ],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 520
                )
            }
        }
        .onChange(of: coordinator.selectedTransaction?.id) { _, newID in
            // Only sync single selection to multi-selection IDs when not actively multi-selecting
            if coordinator.selectedTransactionIDs.count <= 1 {
                if let newID {
                    selectedIDs = [newID]
                } else {
                    selectedIDs = []
                }
            }
        }
        .onChange(of: coordinator.activeWorkspace.id) {
            selectedIDs = coordinator.selectedTransactionIDs
        }
    }

    // MARK: Private

    private static let bottomInspectorSplitAutosaveName = RockxyIdentity.current.defaultsKey(
        // v2 applies the taller payload-first default once, then preserves every subsequent
        // user-adjusted divider position normally again.
        "workspaceBottomInspectorSplit.payloadFirst.v2"
    )

    @AppStorage(NoCacheHeaderMutator.userDefaultsKey) private var isNoCachingEnabled = false
    @AppStorage("mapLocalToolEnabled") private var mapLocalToolEnabled = true
    @AppStorage("mapRemoteToolEnabled") private var mapRemoteToolEnabled = true
    @AppStorage("breakpointToolEnabled") private var breakpointToolEnabled = true
    @Environment(\.appUIDisplayMetrics) private var displayMetrics

    @State private var selectedIDs: Set<UUID> = []

    /// Stable reference to the Allow List singleton so SwiftUI's Observation framework
    /// tracks access to `isActive` inside `body` and re-renders the status bar when
    /// the master toggle changes.
    private let allowListManager = AllowListManager.shared

    private var advancedRuleCount: Int {
        FilterRuleEvaluator.activeRules(
            in: coordinator.filterRules,
            isFilterBarVisible: coordinator.isFilterBarVisible
        ).count
    }

    private var activeFilterCount: Int {
        coordinator.filterCriteria.activeFilterCount
            + FilterRuleEvaluator.activeRules(
                in: coordinator.filterRules,
                isFilterBarVisible: coordinator.isFilterBarVisible
            ).count
            + (coordinator.activeWorkspace.activeTrafficSignal == nil ? 0 : 1)
            + (coordinator.activeWorkspace.activeFocusSet == nil ? 0 : 1)
            + (coordinator.activeWorkspace.mutedTrafficSources.isEmpty ? 0 : 1)
    }

    private var bottomInspectorVisibility: Binding<Bool> {
        Binding(
            get: { coordinator.isBottomInspectorEffectivelyPresented },
            set: { isPresented in
                // A false transition driven purely by losing the selection (the effective
                // getter collapsing) must not persist a hidden preference — only a manual or
                // native collapse while something is still selected should. Expansions always
                // pass through.
                if !isPresented, !coordinator.hasPayloadInspectorSelection {
                    return
                }
                coordinator.setBottomInspectorVisible(isPresented)
            }
        )
    }

    private var bottomInspectorLayoutMetrics: BottomInspectorLayoutMetrics {
        BottomInspectorLayoutMetrics(appMetrics: displayMetrics)
    }

    private var inspectorWorkspace: some View {
        NativeBottomInspectorSplitView(
            isInspectorPresented: bottomInspectorVisibility,
            autosaveName: Self.bottomInspectorSplitAutosaveName,
            primaryMinimumHeight: bottomInspectorLayoutMetrics.requestListMinimumHeight,
            inspectorMinimumHeight: bottomInspectorLayoutMetrics.inspectorMinimumHeight
        ) {
            tableContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appUIDisplayMetrics(displayMetrics)
        } inspector: {
            InspectorPanelView(
                coordinator: coordinator,
                onOpenToolWindow: onOpenToolWindow
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appUIDisplayMetrics(displayMetrics)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tableContent: some View {
        RequestTableView(
            workspaceID: coordinator.activeWorkspace.id,
            rows: coordinator.filteredRows,
            refreshToken: coordinator.refreshToken,
            isAppendOnly: coordinator.activeWorkspace.lastDeriveWasAppendOnly,
            appendChainOrigin: coordinator.activeWorkspace.appendChainOriginToken,
            selectionIndex: coordinator.activeWorkspace.trafficSelectionIndex,
            revealRequest: coordinator.trafficRevealRequest,
            selectedIDs: $selectedIDs,
            onSelectionChanged: { ids, primaryID in
                coordinator.userDidNavigateTrafficHistory()
                coordinator.selectTransactions(ids, primaryID: primaryID)
            },
            onUserScroll: {
                coordinator.userDidNavigateTrafficHistory()
            },
            mainCoordinator: coordinator,
            headerColumns: coordinator.headerColumnStore.columns
        )
        .overlay {
            // Overlay (not replacement) so the table stays mounted: live append, native column
            // widths, selection, and scroll position survive an empty-then-populated transition.
            RequestListEmptyStateView(
                coordinator: coordinator,
                hasVisibleRows: !coordinator.filteredRows.isEmpty
            )
        }
    }
}
