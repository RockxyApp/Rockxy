import SwiftUI

// Renders the center content interface for traffic list presentation.

// MARK: - CenterContentView

/// Primary content area composing the protocol filter bar, optional advanced filter bar,
/// the NSTableView-backed request list, an optional bottom inspector panel,
/// and the status bar. Manages the bridge between NSTableView selection (Set<UUID>) and the
/// coordinator's single-selection model.
struct CenterContentView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let onOpenToolWindow: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProtocolFilterBar(
                activeFilters: Binding(
                    get: { coordinator.filterCriteria.activeProtocolFilters },
                    set: {
                        coordinator.filterCriteria.activeProtocolFilters = $0
                        coordinator.recomputeFilteredTransactions()
                    }
                )
            )

            SearchFilterBar(
                searchText: Binding(
                    get: { coordinator.filterCriteria.searchText },
                    set: {
                        coordinator.filterCriteria.searchText = $0
                        coordinator.recomputeFilteredTransactions()
                    }
                ),
                filterField: Binding(
                    get: { coordinator.filterCriteria.searchField },
                    set: {
                        coordinator.filterCriteria.searchField = $0
                        coordinator.recomputeFilteredTransactions()
                    }
                ),
                isEnabled: Binding(
                    get: { coordinator.filterCriteria.isSearchEnabled },
                    set: {
                        coordinator.filterCriteria.isSearchEnabled = $0
                        coordinator.recomputeFilteredTransactions()
                    }
                ),
                isAdvancedFilterVisible: coordinator.isFilterBarVisible,
                advancedFilterCount: advancedRuleCount,
                onAddFilter: coordinator.addAdvancedFilterRule,
                onToggleAdvancedFilters: {
                    coordinator.isFilterBarVisible.toggle()
                    coordinator.recomputeFilteredTransactions()
                }
            )

            if coordinator.isFilterBarVisible {
                AdvancedFilterBar(
                    rules: Binding(
                        get: { coordinator.filterRules },
                        set: {
                            coordinator.filterRules = $0
                            coordinator.recomputeFilteredTransactions()
                        }
                    ),
                    presetStore: coordinator.filterPresetStore
                )
            }

            ActiveFilterSummaryBar(coordinator: coordinator)

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
                isAutoSelectEnabled: coordinator.isAutoSelectEnabled,
                isFilterBarVisible: coordinator.isFilterBarVisible,
                activeFilterCount: activeFilterCount,
                errorCount: coordinator.errorCount,
                proxyStartedAt: coordinator.proxyStartedAt,
                selectedRequestInfo: coordinator.selectedTransaction.map {
                    "\($0.request.method) \($0.request.path)"
                },
                sessionProvenance: coordinator.sessionProvenance,
                onClear: {
                    Task { @MainActor in
                        await coordinator.clearSession()
                    }
                },
                onFilter: {
                    coordinator.isFilterBarVisible.toggle()
                    coordinator.recomputeFilteredTransactions()
                },
                onAutoSelect: {
                    coordinator.isAutoSelectEnabled.toggle()
                },
                onSwitchOffProxyOverride: {
                    coordinator.switchOffSystemProxyOverride()
                },
                onOpenToolWindow: onOpenToolWindow
            )
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

    private static let minimumBottomTableHeight: CGFloat = 200
    private static let minimumBottomInspectorHeight: CGFloat = 200

    @AppStorage(NoCacheHeaderMutator.userDefaultsKey) private var isNoCachingEnabled = false

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

    private var inspectorWorkspace: some View {
        GeometryReader { proxy in
            if coordinator.inspectorLayout == .hidden {
                tableContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VSplitView {
                    tableContent
                        .frame(
                            minHeight: Self.minimumBottomTableHeight,
                            idealHeight: max(Self.minimumBottomTableHeight, proxy.size.height * 0.58)
                        )
                    InspectorPanelView(coordinator: coordinator)
                        .frame(
                            minHeight: Self.minimumBottomInspectorHeight,
                            idealHeight: max(Self.minimumBottomInspectorHeight, proxy.size.height * 0.42)
                        )
                }
                .id("horizontal-inspector-split")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tableContent: some View {
        RequestTableView(
            workspaceID: coordinator.activeWorkspace.id,
            rows: coordinator.filteredRows,
            refreshToken: coordinator.refreshToken,
            isAppendOnly: coordinator.activeWorkspace.lastDeriveWasAppendOnly,
            selectedIDs: $selectedIDs,
            onSelectionChanged: { ids in
                coordinator.selectedTransactionIDs = ids
                if let firstID = ids.first,
                   let transaction = coordinator.transaction(for: firstID)
                {
                    coordinator.selectTransaction(transaction)
                } else {
                    coordinator.selectTransaction(nil)
                }
            },
            mainCoordinator: coordinator
        )
    }
}
