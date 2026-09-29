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

    var canToggleSystemProxyOverride: Bool {
        coordinator.isProxyRunning
    }

    var canToggleRecording: Bool {
        coordinator.isProxyRunning
    }

    var isRecording: Bool {
        coordinator.isRecording
    }

    var hasSelectedTransaction: Bool {
        coordinator.selectedTransaction != nil
    }

    var hasVisibleTransactions: Bool {
        !coordinator.filteredTransactions.isEmpty
    }

    var isBottomInspectorVisible: Bool {
        coordinator.isBottomInspectorEffectivelyPresented
    }

    var canToggleBottomInspector: Bool {
        coordinator.canToggleBottomInspector
    }

    var isContextDockVisible: Bool {
        coordinator.isContextDockVisible
    }

    var canExportOpenAPI: Bool {
        coordinator.transactions.contains(where: OpenAPIExporter.isEligible)
            || coordinator.filteredTransactions.contains(where: OpenAPIExporter.isEligible)
            || coordinator.resolveSelectedTransactions().contains(where: OpenAPIExporter.isEligible)
    }

    var canPublishGist: Bool {
        !coordinator.resolveSelectedTransactions().isEmpty
    }

    // MARK: - Diff

    var canCompareSelected: Bool {
        coordinator.selectedTransactionIDs.count == 2
    }

    var canCreateWorkspaceTab: Bool {
        coordinator.workspaceStore.canCreateWorkspace
    }

    var canCloseWorkspaceTab: Bool {
        coordinator.workspaceStore.activeTab.isClosable
    }

    var canRenameWorkspaceTab: Bool {
        coordinator.workspaceStore.workspaces.contains { $0.id == coordinator.workspaceStore.activeWorkspaceID }
    }

    var projects: [Project] {
        coordinator.projectStore.projects
    }

    var activeProjectID: UUID {
        coordinator.projectStore.activeProjectID
    }

    var canCreateProject: Bool {
        coordinator.projectStore.canCreateProject && !coordinator.isClearingSession
    }

    var canEditProjects: Bool {
        coordinator.projectStore.isMutable && !coordinator.isClearingSession
    }

    var projectsNeedRecovery: Bool {
        if case .failed = coordinator.projectStore.loadState {
            return true
        }
        return false
    }

    // MARK: - View

    var isFollowingLiveTraffic: Bool {
        coordinator.isFollowingLiveTraffic
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

    func clearCaptureAndFilters() {
        Task { @MainActor in
            await coordinator.clearCaptureAndFilters()
        }
    }

    func toggleRecording() {
        coordinator.toggleRecording()
    }

    func toggleSystemProxyOverride() {
        coordinator.toggleSystemProxyOverride()
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

    func exportCSV() {
        coordinator.exportCSV()
    }

    func exportRockxySession() {
        coordinator.exportRockxySession()
    }

    var isTrafficSplitViewVisible: Bool {
        coordinator.isTrafficSplitViewVisible
    }

    func toggleTrafficSplitView() {
        coordinator.toggleTrafficSplitView()
    }

    func exportOpenAPIYAML() {
        coordinator.exportOpenAPIYAML()
    }

    func exportOpenAPIHTML() {
        coordinator.exportOpenAPIHTML()
    }

    func publishSelectedToGist() {
        coordinator.publishSelectedTransactionsToGist()
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

    func composeFreshRequest() {
        ComposeStore.shared.requestBlankDraft()
        NotificationCenter.default.post(name: .openComposeWindow, object: nil)
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

    func setFollowingLiveTraffic(_ isEnabled: Bool) {
        coordinator.setFollowingLiveTraffic(isEnabled)
    }

    func toggleSourceList() {
        _ = withAnimation(.smooth(duration: 0.18)) {
            NSApp.keyWindow?.firstResponder?.tryToPerform(
                #selector(NSSplitViewController.toggleSidebar(_:)),
                with: nil
            )
        }
    }

    func toggleFilterBar() {
        coordinator.isFilterBarVisible.toggle()
        coordinator.recomputeFilteredTransactions()
    }

    var isFilterBarVisible: Bool {
        coordinator.isFilterBarVisible
    }

    var advancedFiltersMenuTitle: String {
        isFilterBarVisible
            ? String(localized: "Hide Advanced Filters", bundle: RockxyLocalization.bundle)
            : String(localized: "Show Advanced Filters", bundle: RockxyLocalization.bundle)
    }

    /// Reveals the sidebar if needed and moves keyboard focus to its app/domain search field.
    func focusSidebarSearchField() {
        NotificationCenter.default.post(name: .focusSidebarSearchField, object: nil)
    }

    func focusSearchField() {
        coordinator.filterCriteria.isSearchEnabled = true
        NotificationCenter.default.post(name: .focusMainSearchField, object: nil)
    }

    func toggleInspectorRight() {
        coordinator.toggleInspectorRight()
    }

    func toggleInspectorBottom() {
        coordinator.toggleInspectorBottom()
    }

    func hideInspector() {
        coordinator.hideInspector()
    }

    func switchTab(_ tab: MainTab) {
        coordinator.activeMainTab = tab
    }

    var isShowingTrafficInsights: Bool {
        coordinator.isShowingTrafficInsights
    }

    func toggleTrafficInsights() {
        coordinator.toggleTrafficInsights()
    }

    // MARK: - Selection

    func deleteSelected() {
        coordinator.deleteSelectedTransaction()
    }

    func selectFirstTransaction() {
        coordinator.selectFirstFilteredTransaction()
    }

    func selectLastTransaction() {
        coordinator.selectLastFilteredTransaction()
    }

    func addBreakpointRuleForSelection() {
        guard let transaction = coordinator.selectedTransaction else {
            return
        }
        coordinator.createBreakpointRule(for: transaction)
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
        RockxyWorkspaceWindowManager.shared.beginRenameForActiveWorkspace(coordinator: coordinator)
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

    // MARK: - Projects

    func newProject() {
        coordinator.presentNewProjectEditor()
    }

    func renameActiveProject() {
        coordinator.presentRenameProjectEditor(id: coordinator.projectStore.activeProjectID)
    }

    func manageProjects() {
        coordinator.isProjectManagerPresented = true
    }

    func showProjectRecovery() {
        coordinator.isProjectRecoveryPresented = true
    }

    func exportProjectConfiguration() {
        _ = coordinator.exportActiveProjectConfiguration()
    }

    func importProjectConfiguration() {
        guard coordinator.importProjectConfiguration() else {
            return
        }
        RockxyWorkspaceWindowManager.shared.projectDidChange(coordinator: coordinator)
    }

    func switchProject(id: UUID) {
        guard coordinator.switchToProject(id: id) else {
            return
        }
        RockxyWorkspaceWindowManager.shared.projectDidChange(coordinator: coordinator)
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
