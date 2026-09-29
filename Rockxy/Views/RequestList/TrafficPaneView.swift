import SwiftUI

// MARK: - TrafficPaneView

/// One traffic pane: the request table over its bottom payload inspector, bound to a single
/// `WorkspaceState`. The main window shows one pane per tab, or two in split view, where each
/// pane keeps its own filters and selection and clicking a pane gives it focus.
struct TrafficPaneView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let pane: WorkspaceState
    /// Whether another pane is shown beside this one.
    let isSplit: Bool
    let inspectorAutosaveName: String
    let onOpenToolWindow: (String) -> Void

    var body: some View {
        NativeBottomInspectorSplitView(
            isInspectorPresented: inspectorVisibility,
            autosaveName: inspectorAutosaveName,
            primaryMinimumHeight: layoutMetrics.requestListMinimumHeight,
            inspectorMinimumHeight: layoutMetrics.inspectorMinimumHeight
        ) {
            tableContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appUIDisplayMetrics(displayMetrics)
        } inspector: {
            InspectorPanelView(
                coordinator: coordinator,
                workspace: pane,
                onOpenToolWindow: onOpenToolWindow
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appUIDisplayMetrics(displayMetrics)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if isSplit, isFocused {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isSplit ? paneAccessibilityLabel : "")
        .onAppear {
            selectedIDs = pane.selectedTransactionIDs
        }
        .onChange(of: pane.selectedTransaction?.id) { _, newID in
            // Only sync single selection to multi-selection IDs when not actively multi-selecting
            if pane.selectedTransactionIDs.count <= 1 {
                selectedIDs = newID.map { [$0] } ?? []
            }
        }
        .onChange(of: pane.selectedTransactionIDs) { _, ids in
            // Insights can select a whole time bin before the table is remounted. Sync the
            // full set, not just the primary transaction, into the NSTableView binding.
            selectedIDs = ids
        }
        .onChange(of: pane.id) {
            selectedIDs = pane.selectedTransactionIDs
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var displayMetrics
    @State private var selectedIDs: Set<UUID> = []

    private var isFocused: Bool {
        coordinator.activeWorkspace.id == pane.id
    }

    private var paneAccessibilityLabel: String {
        isFocused
            ? String(localized: "Focused traffic pane", bundle: RockxyLocalization.bundle)
            : String(localized: "Traffic pane", bundle: RockxyLocalization.bundle)
    }

    private var layoutMetrics: BottomInspectorLayoutMetrics {
        BottomInspectorLayoutMetrics(appMetrics: displayMetrics)
    }

    private var inspectorVisibility: Binding<Bool> {
        Binding(
            get: { coordinator.isBottomInspectorEffectivelyPresented(for: pane) },
            set: { isPresented in
                // A false transition driven purely by losing the selection (the effective
                // getter collapsing) must not persist a hidden preference — only a manual or
                // native collapse while something is still selected should. Expansions always
                // pass through.
                if !isPresented, coordinator.bottomInspectorContent(for: pane) == .none {
                    return
                }
                coordinator.focusTrafficPane(pane)
                coordinator.setBottomInspectorVisible(isPresented)
            }
        )
    }

    private var tableContent: some View {
        RequestTableView(
            workspaceID: pane.id,
            rows: pane.filteredRows,
            refreshToken: pane.refreshToken,
            isAppendOnly: pane.lastDeriveWasAppendOnly,
            appendChainOrigin: pane.appendChainOriginToken,
            selectionIndex: pane.trafficSelectionIndex,
            revealRequest: pane.trafficRevealRequest,
            selectedIDs: $selectedIDs,
            onSelectionChanged: { ids, primaryID in
                pane.isFollowingLiveTraffic = false
                coordinator.selectTransactions(ids, primaryID: primaryID, in: pane)
            },
            onUserScroll: {
                pane.isFollowingLiveTraffic = false
            },
            onActivate: isSplit ? { coordinator.focusTrafficPane(pane) } : nil,
            mainCoordinator: coordinator,
            headerColumns: coordinator.headerColumnStore.columns
        )
        .overlay {
            // Overlay (not replacement) so the table stays mounted: live append, native column
            // widths, selection, and scroll position survive an empty-then-populated transition.
            if isFocused {
                RequestListEmptyStateView(
                    coordinator: coordinator,
                    hasVisibleRows: !pane.filteredRows.isEmpty
                )
            } else if pane.filteredRows.isEmpty {
                Text(String(localized: "No matching requests", bundle: RockxyLocalization.bundle))
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
    }
}
