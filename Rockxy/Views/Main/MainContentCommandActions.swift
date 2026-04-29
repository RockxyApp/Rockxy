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

    var canCreateWorkspaceTab: Bool {
        coordinator.workspaceStore.canCreateWorkspace
    }

    var canCloseWorkspaceTab: Bool {
        coordinator.workspaceStore.activeWorkspace.isClosable
    }

    var canRenameWorkspaceTab: Bool {
        coordinator.workspaceStore.workspaces.contains { $0.id == coordinator.workspaceStore.activeWorkspaceID }
    }

    func startProxy() {
        coordinator.startProxy()
    }

    func stopProxy() {
        coordinator.stopProxy()
    }

    func clearSession() {
        Task { @MainActor in
            await coordinator.clearSession()
        }
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
        Task { @MainActor in
            await coordinator.clearSession()
        }
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
        guard coordinator.workspaceStore.canCreateWorkspace else {
            return
        }
        let ws = coordinator.workspaceStore.createWorkspace()
        RockxyWorkspaceWindowManager.shared.openWorkspaceTab(coordinator: coordinator, workspaceID: ws.id)
        RockxyWorkspaceWindowManager.shared.prepareWorkspaceContent(ws, coordinator: coordinator)
    }

    func closeWorkspaceTab() {
        RockxyWorkspaceWindowManager.shared.closeCurrentWorkspaceTab(coordinator: coordinator)
    }

    func renameWorkspaceTab() {
        NotificationCenter.default.post(
            name: .renameWorkspaceTabRequested,
            object: nil,
            userInfo: ["workspaceID": coordinator.workspaceStore.activeWorkspaceID]
        )
    }

    func selectWorkspaceTab(at index: Int) {
        RockxyWorkspaceWindowManager.shared.selectWorkspaceTab(at: index, coordinator: coordinator)
    }

    func previousWorkspaceTab() {
        RockxyWorkspaceWindowManager.shared.selectPreviousWorkspaceTab(coordinator: coordinator)
    }

    func nextWorkspaceTab() {
        RockxyWorkspaceWindowManager.shared.selectNextWorkspaceTab(coordinator: coordinator)
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
