import SwiftUI

// Renders the main content command actions interface for the main workspace.

// MARK: - MainContentCommandActions

/// Thin facade that exposes coordinator actions to SwiftUI menu commands via `FocusedValue`.
/// Keeps menu command bindings decoupled from the coordinator's full API surface.
@MainActor
struct MainContentCommandActions {
    let coordinator: MainContentCoordinator

    // MARK: - Proxy Control

    var isProxyRunning: Bool {
        coordinator.isProxyRunning
    }

    var hasSelectedTransaction: Bool {
        coordinator.selectedTransaction != nil
    }

    // MARK: - Diff

    var canCompareSelected: Bool {
        coordinator.selectedTransactionIDs.count == 2
    }

    func startProxy() {
        coordinator.startProxy()
    }

    func stopProxy() {
        coordinator.stopProxy()
    }

    func clearSession() {
        coordinator.clearSession()
    }

    func toggleRecording() {
        coordinator.toggleRecording()
    }

    // MARK: - Session I/O

    func saveSession() {
        coordinator.saveSession()
    }

    func openSession() {
        coordinator.openSession()
    }

    func importHAR() {
        coordinator.importHAR()
    }

    func exportHAR() {
        coordinator.exportHAR()
    }

    func copyAsCURL() {
        coordinator.copyAsCURL()
    }

    func copyURL() {
        coordinator.copySelectedURL()
    }

    func replayRequest() {
        coordinator.replaySelectedRequest()
    }

    func editAndRepeat() {
        guard let transaction = coordinator.selectedTransaction else {
            return
        }
        coordinator.editAndReplayTransaction(transaction)
    }

    func addComment() {
        guard let transaction = coordinator.selectedTransaction else {
            return
        }
        coordinator.promptComment(for: transaction)
    }

    func setHighlight(_ color: HighlightColor?) {
        guard let transaction = coordinator.selectedTransaction else {
            return
        }
        coordinator.setHighlight(color, for: transaction)
    }

    func deleteAll() {
        coordinator.clearSession()
    }

    // MARK: - View

    func toggleAutoSelect() {
        coordinator.isAutoSelectEnabled.toggle()
    }

    func toggleSourceList() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }

    func toggleFilterBar() {
        coordinator.isFilterBarVisible.toggle()
        coordinator.recomputeFilteredTransactions()
    }

    func toggleInspectorRight() {
        coordinator.toggleInspectorRight()
    }

    func toggleInspectorBottom() {
        coordinator.toggleInspectorBottom()
    }

    func hideInspector() {
        coordinator.inspectorLayout = .hidden
    }

    func switchTab(_ tab: MainTab) {
        coordinator.activeMainTab = tab
    }

    // MARK: - Selection

    func deleteSelected() {
        coordinator.deleteSelectedTransaction()
    }

    func compareSelected() {
        let ids = coordinator.selectedTransactionIDs
        guard ids.count == 2 else {
            return
        }
        let sorted = ids.sorted()
        let matching = coordinator.filteredTransactions.filter { sorted.contains($0.id) }
        guard matching.count == 2 else {
            return
        }
        coordinator.compareTransactions(matching[0], matching[1])
    }

    // MARK: - Workspace Tabs

    func newWorkspaceTab() {
        let ws = coordinator.workspaceStore.createWorkspace()
        coordinator.recomputeFilteredTransactions(for: ws)
        coordinator.rebuildSidebarIndexes(for: ws)
    }

    func closeWorkspaceTab() {
        coordinator.workspaceStore.closeWorkspace(id: coordinator.activeWorkspace.id)
    }

    func selectWorkspaceTab(at index: Int) {
        coordinator.workspaceStore.selectWorkspace(at: index)
    }

    func previousWorkspaceTab() {
        coordinator.workspaceStore.selectPreviousWorkspace()
    }

    func nextWorkspaceTab() {
        coordinator.workspaceStore.selectNextWorkspace()
    }
}

// MARK: - CommandActionsKey

/// FocusedValue key for propagating command actions through the SwiftUI responder chain,
/// enabling keyboard shortcuts and menu items to reach the active coordinator.
struct CommandActionsKey: FocusedValueKey {
    typealias Value = MainContentCommandActions
}

extension FocusedValues {
    var commandActions: MainContentCommandActions? {
        get { self[CommandActionsKey.self] }
        set { self[CommandActionsKey.self] = newValue }
    }
}
