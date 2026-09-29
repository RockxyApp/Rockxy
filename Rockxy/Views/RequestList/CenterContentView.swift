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

            if coordinator.activeMainTab == .insights {
                TrafficInsightsReportView(coordinator: coordinator)
                    .id(coordinator.activeWorkspace.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                inspectorWorkspace
            }

            StatusBarView(
                totalCount: coordinator.filteredTransactions.count,
                selectedCount: coordinator.selectedTransactionIDs.count,
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
                blockListToolEnabled: blockListToolEnabled,
                modifyHeaderToolEnabled: modifyHeaderToolEnabled,
                networkConditionsToolEnabled: networkConditionsToolEnabled,
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
    }

    // MARK: Private

    private static let bottomInspectorSplitAutosaveName = RockxyIdentity.current.defaultsKey(
        // v2 applies the taller payload-first default once, then preserves every subsequent
        // user-adjusted divider position normally again.
        "workspaceBottomInspectorSplit.payloadFirst.v2"
    )

    /// The second split-view pane keeps its own inspector divider position.
    private static let splitPaneInspectorAutosaveName = RockxyIdentity.current.defaultsKey(
        "workspaceBottomInspectorSplit.secondPane"
    )

    @AppStorage(NoCacheHeaderMutator.userDefaultsKey) private var isNoCachingEnabled = false
    @AppStorage("mapLocalToolEnabled") private var mapLocalToolEnabled = true
    @AppStorage("mapRemoteToolEnabled") private var mapRemoteToolEnabled = true
    @AppStorage("breakpointToolEnabled") private var breakpointToolEnabled = true
    @AppStorage("networkConditionsToolEnabled") private var networkConditionsToolEnabled = true
    @AppStorage("blockListToolEnabled") private var blockListToolEnabled = true
    @AppStorage("modifyHeaderToolEnabled") private var modifyHeaderToolEnabled = true

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

    private var inspectorWorkspace: some View {
        Group {
            if coordinator.secondaryTrafficPane != nil {
                HSplitView {
                    pane(.primary, isSplit: true, autosaveName: Self.bottomInspectorSplitAutosaveName)
                        .frame(minWidth: 360)
                    pane(.secondary, isSplit: true, autosaveName: Self.splitPaneInspectorAutosaveName)
                        .frame(minWidth: 360)
                }
            } else {
                pane(.primary, isSplit: false, autosaveName: Self.bottomInspectorSplitAutosaveName)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pane(_ role: TrafficPaneView.Role, isSplit: Bool, autosaveName: String) -> some View {
        TrafficPaneView(
            coordinator: coordinator,
            role: role,
            isSplit: isSplit,
            inspectorAutosaveName: autosaveName,
            onOpenToolWindow: onOpenToolWindow
        )
    }
}
