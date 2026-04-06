import Foundation
import os

// Persists and coordinates workspace tabs and the active workspace selection.

@MainActor @Observable
final class WorkspaceStore {
    // MARK: Lifecycle

    init() {
        let defaultWorkspace = WorkspaceState(
            title: String(localized: "All Traffic"),
            isClosable: false
        )
        self.workspaces = [defaultWorkspace]
        self.activeWorkspaceID = defaultWorkspace.id
    }

    // MARK: Internal

    static let maxWorkspaces = 20

    var workspaces: [WorkspaceState]
    var activeWorkspaceID: UUID

    var activeWorkspace: WorkspaceState {
        workspaces.first { $0.id == activeWorkspaceID } ?? workspaces[0]
    }

    var activeWorkspaceIndex: Int {
        workspaces.firstIndex { $0.id == activeWorkspaceID } ?? 0
    }

    @discardableResult
    func createWorkspace(
        title: String = String(localized: "New Tab"),
        filter: FilterCriteria = .empty
    )
        -> WorkspaceState
    {
        guard workspaces.count < Self.maxWorkspaces else {
            Self.logger.warning("Maximum workspace count (\(Self.maxWorkspaces)) reached")
            return activeWorkspace
        }
        let workspace = WorkspaceState(
            title: title,
            isClosable: true,
            initialFilter: filter
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

    func duplicateWorkspace(id: UUID) -> WorkspaceState? {
        guard let source = workspaces.first(where: { $0.id == id }),
              workspaces.count < Self.maxWorkspaces else
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

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "WorkspaceStore")
}
