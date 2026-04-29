import SwiftUI

// Renders the center content interface for traffic list presentation.

// MARK: - CenterContentView

/// Primary content area composing the protocol filter bar, optional advanced filter bar,
/// the NSTableView-backed request list, an optional inspector panel (right or bottom split),
/// and the status bar. Manages the bridge between NSTableView selection (Set<UUID>) and the
/// coordinator's single-selection model.
struct CenterContentView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

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
                )
            )

            if coordinator.isFilterBarVisible {
                AdvancedFilterBar(
                    rules: Binding(
                        get: { coordinator.filterRules },
                        set: {
                            coordinator.filterRules = $0
                            coordinator.recomputeFilteredTransactions()
                        }
                    )
                )
            }

            ActiveFilterSummaryBar(coordinator: coordinator)

            inspectorWorkspace

            StatusBarView(
                totalCount: coordinator.filteredTransactions.count,
                selectedCount: selectedIDs.count,
                isProxyRunning: coordinator.isProxyRunning,
                totalDataSize: coordinator.totalDataSize,
                uploadSpeed: coordinator.uploadSpeed,
                downloadSpeed: coordinator.downloadSpeed,
                isProxyOverridden: coordinator.isProxyOverridden,
                isAllowListActive: allowListManager.isActive,
                isNoCachingActive: isNoCachingEnabled,
                isAutoSelectEnabled: coordinator.isAutoSelectEnabled,
                isFilterBarVisible: coordinator.isFilterBarVisible,
                activeFilterCount: coordinator.filterCriteria.activeFilterCount,
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
                onAutoSelect: { coordinator.isAutoSelectEnabled.toggle() }
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
    }

    // MARK: Private

    @AppStorage(NoCacheHeaderMutator.userDefaultsKey) private var isNoCachingEnabled = false

    @State private var selectedIDs: Set<UUID> = []

    /// Stable reference to the Allow List singleton so SwiftUI's Observation framework
    /// tracks access to `isActive` inside `body` and re-renders the status bar when
    /// the master toggle changes.
    private let allowListManager = AllowListManager.shared

    private var inspectorWorkspace: some View {
        GeometryReader { proxy in
            switch coordinator.inspectorLayout {
            case .hidden:
                tableContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .right:
                HSplitView {
                    tableContent
                        .frame(
                            minWidth: Self.minimumRightPaneWidth,
                            idealWidth: max(Self.minimumRightPaneWidth, proxy.size.width * 0.5)
                        )
                    InspectorPanelView(coordinator: coordinator)
                        .frame(
                            minWidth: Self.minimumRightPaneWidth,
                            idealWidth: max(Self.minimumRightPaneWidth, proxy.size.width * 0.5)
                        )
                }
                .id("right-inspector-split")
            case .bottom:
                VSplitView {
                    tableContent
                        .frame(
                            minHeight: Self.minimumBottomTableHeight,
                            idealHeight: max(Self.minimumBottomTableHeight, proxy.size.height / 3)
                        )
                    InspectorPanelView(coordinator: coordinator)
                        .frame(
                            minHeight: Self.minimumBottomInspectorHeight,
                            idealHeight: max(Self.minimumBottomInspectorHeight, proxy.size.height * 2 / 3)
                        )
                }
                .id("bottom-inspector-split")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let minimumRightPaneWidth: CGFloat = 300
    private static let minimumBottomTableHeight: CGFloat = 200
    private static let minimumBottomInspectorHeight: CGFloat = 200

    private var tableContent: some View {
        RequestTableView(
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
