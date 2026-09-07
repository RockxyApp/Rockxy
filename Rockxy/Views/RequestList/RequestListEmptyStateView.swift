import SwiftUI

// Renders the truthful, recoverable empty state for the main request list.

// MARK: - RequestListEmptyStateView

/// Native `ContentUnavailableView` overlay describing why the request list has no visible rows,
/// with the nearest safe recovery action. Renders nothing when rows are visible, so it can sit as
/// an overlay above the still-mounted `RequestTableView` without disturbing its state.
///
/// All state derives from observable coordinator properties, so the overlay updates live as the
/// proxy starts/stops/pauses, traffic arrives, or the workspace, scope, or filters change.
struct RequestListEmptyStateView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    /// Whether the current view has any visible rows. Passed in so both the NSTableView-backed
    /// list (`filteredRows`) and the SwiftUI fallback (`filteredTransactions`) resolve identically.
    let hasVisibleRows: Bool

    var body: some View {
        if let state = resolvedState {
            let copy = RequestListEmptyStateCopy(state)
            ContentUnavailableView {
                Label(copy.title, systemImage: copy.systemImage)
            } description: {
                Text(copy.description)
            } actions: {
                if let action = copy.action, let actionTitle = copy.actionTitle {
                    Button(actionTitle) { perform(action) }
                        .accessibilityLabel(Text(actionTitle))
                        .help(copy.actionHelp ?? actionTitle)
                }
            }
        }
    }

    // MARK: Private

    private var resolvedState: RequestListEmptyState? {
        RequestListEmptyState.resolve(
            hasVisibleRows: hasVisibleRows,
            availableCount: coordinator.availableTransactionCountForCurrentScope,
            hasActiveFilters: coordinator.hasActiveWorkspaceFilters,
            scope: coordinator.filterCriteria.sidebarScope,
            proxyState: coordinator.proxyDisplayState,
            isSystemProxyConfigured: coordinator.isSystemProxyConfigured,
            isSystemRoutingExpected: coordinator.readiness.systemRoutingExpected,
            captureHealth: coordinator.readiness.captureHealth,
            allowListCapturesNothing: AllowListManager.shared.isActive
                && !AllowListManager.shared.hasEffectiveRules
        )
    }

    private func perform(_ action: RequestListEmptyStateAction) {
        switch action {
        case .clearFilters,
             .showAllTraffic:
            coordinator.clearAllWorkspaceFilters()
        case .startProxy:
            coordinator.startProxy()
        case .resumeRecording:
            coordinator.toggleRecording()
        case .retrySystemProxy:
            coordinator.retrySystemProxy()
        case .retryCaptureCheck:
            coordinator.runCaptureHealthCheck()
        case .openAllowList:
            NotificationCenter.default.post(name: .openAllowListWindow, object: nil)
        }
    }
}
