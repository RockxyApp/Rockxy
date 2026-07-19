import Foundation
import os

// Persists and coordinates workspace tabs and the active workspace selection.

@MainActor @Observable
final class WorkspaceStore {
    // MARK: Lifecycle

    init(
        maxWorkspaces: Int = 8,
        layoutPreferences: WorkspaceLayoutPreferences = WorkspaceLayoutPreferences()
    ) {
        self.maxWorkspaces = max(maxWorkspaces, 1)
        self.layoutPreferences = layoutPreferences
        let defaultWorkspace = Self.makeWorkspace(
            title: String(localized: "All Traffic"),
            isClosable: false,
            filter: .empty,
            layoutPreferences: layoutPreferences
        )
        self.workspaces = [defaultWorkspace]
        self.activeWorkspaceID = defaultWorkspace.id
    }

    // MARK: Internal

    let maxWorkspaces: Int

    var workspaces: [WorkspaceState]
    var activeWorkspaceID: UUID

    var activeWorkspace: WorkspaceState {
        workspaces.first { $0.id == activeWorkspaceID } ?? workspaces[0]
    }

    var activeWorkspaceIndex: Int {
        workspaces.firstIndex { $0.id == activeWorkspaceID } ?? 0
    }

    var canCreateWorkspace: Bool {
        workspaces.count < maxWorkspaces
    }

    @discardableResult
    func createWorkspace(
        title: String = String(localized: "New Tab"),
        filter: FilterCriteria = .empty
    )
        -> WorkspaceState
    {
        guard canCreateWorkspace else {
            Self.logger.warning("Maximum workspace count (\(self.maxWorkspaces)) reached")
            return activeWorkspace
        }
        let workspace = Self.makeWorkspace(
            title: title,
            isClosable: true,
            filter: filter,
            layoutPreferences: layoutPreferences
        )
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        Self.logger.info("Created workspace: \(title)")
        return workspace
    }

    func closeWorkspace(id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspace.isClosable else
        {
            return
        }
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
            return
        }

        let wasActive = id == activeWorkspaceID
        workspaces.remove(at: index)

        if wasActive {
            let newIndex = min(index, workspaces.count - 1)
            activeWorkspaceID = workspaces[newIndex].id
        }
        Self.logger.info("Closed workspace: \(workspace.title)")
    }

    func selectWorkspace(id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else {
            return
        }
        activeWorkspaceID = id
    }

    func selectWorkspace(at index: Int) {
        guard index >= 0, index < workspaces.count else {
            return
        }
        activeWorkspaceID = workspaces[index].id
    }

    func selectPreviousWorkspace() {
        let currentIndex = activeWorkspaceIndex
        let newIndex = currentIndex > 0 ? currentIndex - 1 : workspaces.count - 1
        activeWorkspaceID = workspaces[newIndex].id
    }

    func selectNextWorkspace() {
        let currentIndex = activeWorkspaceIndex
        let newIndex = currentIndex < workspaces.count - 1 ? currentIndex + 1 : 0
        activeWorkspaceID = workspaces[newIndex].id
    }

    func moveWorkspace(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < workspaces.count,
              destinationIndex >= 0, destinationIndex < workspaces.count,
              sourceIndex != destinationIndex else
        {
            return
        }
        let workspace = workspaces.remove(at: sourceIndex)
        workspaces.insert(workspace, at: destinationIndex)
    }

    func reorderWorkspaces(toWorkspaceIDs orderedIDs: [UUID]) {
        guard !orderedIDs.isEmpty else {
            return
        }

        var remaining = workspaces
        var reordered: [WorkspaceState] = []
        reordered.reserveCapacity(workspaces.count)

        for id in orderedIDs {
            guard let index = remaining.firstIndex(where: { $0.id == id }) else {
                continue
            }
            reordered.append(remaining.remove(at: index))
        }

        reordered.append(contentsOf: remaining)
        guard reordered.count == workspaces.count else {
            return
        }
        workspaces = reordered
    }

    func duplicateWorkspace(id: UUID) -> WorkspaceState? {
        guard let source = workspaces.first(where: { $0.id == id }),
              canCreateWorkspace else
        {
            return nil
        }
        let duplicate = WorkspaceState(
            title: source.title + " " + String(localized: "Copy"),
            isClosable: true,
            initialFilter: source.filterCriteria
        )
        duplicate.activeMainTab = source.activeMainTab
        duplicate.inspectorLayout = source.inspectorLayout
        duplicate.isContextDockVisible = source.isContextDockVisible
        duplicate.contextDockTab = source.contextDockTab
        duplicate.allowsAutomaticInspectorReveal = source.allowsAutomaticInspectorReveal
        duplicate.focusNavigatorMode = source.focusNavigatorMode
        duplicate.activeTrafficSignal = source.activeTrafficSignal
        duplicate.focusSets = source.focusSets
        duplicate.activeFocusSetID = source.activeFocusSetID
        duplicate.mutedTrafficSources = source.mutedTrafficSources
        duplicate.filterRules = source.filterRules
        duplicate.isFilterBarVisible = source.isFilterBarVisible

        if let sourceIndex = workspaces.firstIndex(where: { $0.id == id }) {
            workspaces.insert(duplicate, at: sourceIndex + 1)
        } else {
            workspaces.append(duplicate)
        }
        activeWorkspaceID = duplicate.id
        return duplicate
    }

    func closeOtherWorkspaces(except id: UUID) {
        workspaces.removeAll { $0.id != id && $0.isClosable }
        if !workspaces.contains(where: { $0.id == activeWorkspaceID }) {
            activeWorkspaceID = workspaces[0].id
        }
    }

    func renameWorkspace(id: UUID, to newTitle: String) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else {
            return
        }
        workspace.title = newTitle
    }

    func rememberBottomInspectorVisibility(_ isVisible: Bool) {
        layoutPreferences.rememberBottomInspectorVisibility(isVisible)
    }

    func rememberContextDockVisibility(_ isVisible: Bool) {
        layoutPreferences.rememberContextDockVisibility(isVisible)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "WorkspaceStore")
    private let layoutPreferences: WorkspaceLayoutPreferences

    private static func makeWorkspace(
        title: String,
        isClosable: Bool,
        filter: FilterCriteria,
        layoutPreferences: WorkspaceLayoutPreferences
    ) -> WorkspaceState {
        let preferredBottomVisibility = layoutPreferences.preferredBottomInspectorVisibility
        return WorkspaceState(
            title: title,
            isClosable: isClosable,
            initialFilter: filter,
            inspectorLayout: preferredBottomVisibility == true ? .bottom : .hidden,
            isContextDockVisible: layoutPreferences.preferredContextDockVisibility,
            allowsAutomaticInspectorReveal: preferredBottomVisibility == nil
        )
    }
}
