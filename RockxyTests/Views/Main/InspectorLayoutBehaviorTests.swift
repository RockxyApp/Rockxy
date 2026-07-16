import Foundation
@testable import Rockxy
import Testing

@MainActor
struct InspectorLayoutBehaviorTests {
    // MARK: Internal

    @Test("First transaction selection reveals the bottom inspector")
    func firstSelectionReveal() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)

        #expect(coordinator.inspectorLayout == .hidden)
        #expect(!coordinator.isContextDockVisible)

        coordinator.selectTransaction(TestFixtures.makeTransaction())

        #expect(coordinator.inspectorLayout == .bottom)
        #expect(!coordinator.isContextDockVisible)
    }

    @Test("Direct coordinator selection cannot bypass automatic reveal")
    func forwardedSelectionReveal() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)

        coordinator.selectedTransaction = TestFixtures.makeTransaction()

        #expect(coordinator.inspectorLayout == .bottom)
        #expect(!coordinator.isContextDockVisible)
    }

    @Test("Manual hide prevents automatic reopen and persists across launch")
    func manualHideWins() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)
        let transaction = TestFixtures.makeTransaction()
        coordinator.selectTransaction(transaction)

        coordinator.toggleInspectorBottom()
        coordinator.selectTransaction(nil)
        coordinator.selectTransaction(transaction)

        #expect(coordinator.inspectorLayout == .hidden)
        #expect(!coordinator.activeWorkspace.allowsAutomaticInspectorReveal)

        let relaunched = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)
        #expect(relaunched.inspectorLayout == .hidden)
        #expect(!relaunched.activeWorkspace.allowsAutomaticInspectorReveal)
    }

    @Test("Manual panel choices become defaults for later workspaces and launches")
    func manualChoicesPersist() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)

        coordinator.toggleInspectorBottom()
        coordinator.toggleInspectorRight()
        let newWorkspace = coordinator.workspaceStore.createWorkspace()

        #expect(newWorkspace.inspectorLayout == .bottom)
        #expect(newWorkspace.isContextDockVisible)
        #expect(!newWorkspace.allowsAutomaticInspectorReveal)

        let relaunched = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)
        #expect(relaunched.inspectorLayout == .bottom)
        #expect(relaunched.isContextDockVisible)
    }

    @Test("Hiding Context Dock persists for later workspaces and launches")
    func contextDockHidePersists() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)

        coordinator.toggleInspectorRight()
        coordinator.toggleInspectorRight()
        let newWorkspace = coordinator.workspaceStore.createWorkspace()

        #expect(!newWorkspace.isContextDockVisible)

        let relaunched = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)
        #expect(!relaunched.isContextDockVisible)
    }

    // MARK: Private

    private func makeEnvironment() throws -> (
        defaults: UserDefaults,
        suiteName: String,
        preferences: WorkspaceLayoutPreferences
    ) {
        let suiteName = "InspectorLayoutBehaviorTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName, WorkspaceLayoutPreferences(defaults: defaults))
    }
}
