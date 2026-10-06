import Foundation
@testable import Rockxy
import Testing

@MainActor
struct WorkspaceTabCloseTests {
    @Test("Close Other Tabs keeps the clicked tab and the default tab")
    func closeOthers() throws {
        let coordinator = MainContentCoordinator()
        let store = coordinator.workspaceStore
        let first = try #require(store.createWorkspace(title: "One"))
        let second = try #require(store.createWorkspace(title: "Two"))
        let third = try #require(store.createWorkspace(title: "Three"))
        store.selectWorkspace(id: third.id)

        let others = coordinator.closableWorkspaceIDs(otherThan: second.id)
        #expect(others == [first.id, third.id])
        coordinator.closeWorkspaces(others, keeping: second.id)

        #expect(store.workspaces.count == 2)
        #expect(store.workspaces.contains { $0.id == second.id })
        #expect(store.workspaces.contains { !$0.isClosable })
        #expect(store.activeWorkspaceID == second.id)
    }

    @Test("Close Tabs to the Right leaves earlier tabs and the active tab when it is kept")
    func closeToTheRight() throws {
        let coordinator = MainContentCoordinator()
        let store = coordinator.workspaceStore
        let first = try #require(store.createWorkspace(title: "One"))
        let second = try #require(store.createWorkspace(title: "Two"))
        _ = try #require(store.createWorkspace(title: "Three"))
        store.selectWorkspace(id: first.id)

        let right = coordinator.closableWorkspaceIDs(rightOf: first.id)
        #expect(right.count == 2)
        #expect(right.first == second.id)
        coordinator.closeWorkspaces(right, keeping: first.id)

        #expect(store.workspaces.map(\.id).last == first.id)
        #expect(store.activeWorkspaceID == first.id)
        #expect(coordinator.closableWorkspaceIDs(rightOf: first.id).isEmpty)
    }
}
