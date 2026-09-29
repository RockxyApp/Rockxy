import Foundation

// Extends `MainContentCoordinator` with split view: a second traffic pane beside a tab.

// MARK: - MainContentCoordinator + SplitView

extension MainContentCoordinator {
    var canUseTrafficSplitView: Bool {
        policy.allowsTrafficSplitView
    }

    /// Whether the selected tab currently shows a second pane.
    var isTrafficSplitViewVisible: Bool {
        workspaceStore.splitCompanion(for: workspaceStore.activeWorkspaceID) != nil
    }

    /// The selected tab's own pane, whichever pane has focus.
    var primaryTrafficPane: WorkspaceState {
        workspaceStore.activeTab
    }

    /// The selected tab's second pane, when split view is open.
    var secondaryTrafficPane: WorkspaceState? {
        workspaceStore.splitCompanion(for: workspaceStore.activeWorkspaceID)
    }

    func toggleTrafficSplitView() {
        if isTrafficSplitViewVisible {
            hideTrafficSplitView()
        } else {
            showTrafficSplitView()
        }
    }

    /// Opens the second pane for the selected tab and focuses it. With a filter, the pane opens
    /// on that source (an app or domain from the sidebar); an open pane is reused, never a third.
    @discardableResult
    func showTrafficSplitView(filter: FilterCriteria = .empty) -> Bool {
        guard canUseTrafficSplitView else {
            activeToast = ToastMessage(
                style: .warning,
                text: AppPolicyViolation.trafficSplitViewUnavailable.errorDescription ?? ""
            )
            return false
        }
        let tabID = workspaceStore.activeWorkspaceID
        let isNew = workspaceStore.splitCompanion(for: tabID) == nil
        guard let pane = workspaceStore.openSplit(for: tabID, filter: filter) else {
            return false
        }
        if isNew || !filter.isEmpty {
            rebuildSidebarIndexes(for: pane)
            recomputeFilteredTransactions(for: pane)
        }
        return true
    }

    /// Closes the second pane; the tab's own pane keeps its filters and selection.
    func hideTrafficSplitView() {
        let tabID = workspaceStore.activeWorkspaceID
        if let pane = workspaceStore.splitCompanion(for: tabID) {
            cancelDebugAssistantTask(for: pane.id)
        }
        workspaceStore.closeSplit(for: tabID)
    }

    /// Makes `pane` the target of filters, the sidebar, commands, and the inspector.
    func focusTrafficPane(_ pane: WorkspaceState) {
        guard pane.id != activeWorkspace.id else {
            return
        }
        workspaceStore.focusPane(pane.id)
    }
}
