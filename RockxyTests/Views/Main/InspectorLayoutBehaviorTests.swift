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

        coordinator.selectTransaction(TestFixtures.makeTransaction())
        // Establish an explicit visible preference through the same persistence seam the
        // native split item drives while the inspector has content.
        coordinator.setBottomInspectorVisible(true)
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

    @Test("Native inspector binding persists its collapsed state")
    func nativeInspectorBindingPersists() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)

        coordinator.setContextDockVisible(true)
        coordinator.setContextDockVisible(false)

        #expect(!coordinator.isContextDockVisible)
        #expect(!coordinator.workspaceStore.createWorkspace().isContextDockVisible)
        #expect(!MainContentCoordinator(
            workspaceLayoutPreferences: environment.preferences
        ).isContextDockVisible)
    }

    @Test("Native bottom inspector binding persists its collapsed state")
    func nativeBottomInspectorBindingPersists() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)

        coordinator.setBottomInspectorVisible(true)
        coordinator.setBottomInspectorVisible(false)

        #expect(coordinator.inspectorLayout == .hidden)
        #expect(coordinator.workspaceStore.createWorkspace().inspectorLayout == .hidden)
        #expect(MainContentCoordinator(
            workspaceLayoutPreferences: environment.preferences
        ).inspectorLayout == .hidden)
    }

    @Test("Deselecting collapses the bottom inspector without losing the layout preference")
    func deselectCollapsesWithoutPreferenceLoss() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)
        let transaction = TestFixtures.makeTransaction()
        coordinator.selectTransaction(transaction)

        #expect(coordinator.isBottomInspectorEffectivelyPresented)
        #expect(coordinator.hasPayloadInspectorSelection)

        coordinator.selectTransaction(nil)

        #expect(!coordinator.isBottomInspectorEffectivelyPresented)
        #expect(!coordinator.hasPayloadInspectorSelection)
        #expect(coordinator.inspectorLayout == .bottom)
    }

    @Test("Reselecting restores the effective bottom inspector after a deselect")
    func reselectRestoresEffectivePresentation() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)
        coordinator.selectTransaction(TestFixtures.makeTransaction())
        coordinator.selectTransaction(nil)

        #expect(!coordinator.isBottomInspectorEffectivelyPresented)

        coordinator.selectTransaction(TestFixtures.makeTransaction())

        #expect(coordinator.isBottomInspectorEffectivelyPresented)
        #expect(coordinator.inspectorLayout == .bottom)
    }

    @Test("An explicit hide wins over the effective presentation across deselect and reselect")
    func explicitHideWinsOverEffectivePresentation() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)
        let transaction = TestFixtures.makeTransaction()
        coordinator.selectTransaction(transaction)

        coordinator.toggleInspectorBottom()

        #expect(coordinator.inspectorLayout == .hidden)
        #expect(!coordinator.isBottomInspectorEffectivelyPresented)

        coordinator.selectTransaction(nil)
        coordinator.selectTransaction(transaction)

        #expect(coordinator.inspectorLayout == .hidden)
        #expect(!coordinator.isBottomInspectorEffectivelyPresented)
    }

    @Test("A multi-selection is eligible for and presents the bottom inspector")
    func multiSelectionIsEligible() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)
        let first = TestFixtures.makeTransaction()
        let second = TestFixtures.makeTransaction()
        coordinator.selectTransaction(first)

        coordinator.selectedTransactionIDs = [first.id, second.id]

        #expect(coordinator.bottomInspectorContent == .summary)
        #expect(coordinator.hasPayloadInspectorSelection)
        #expect(coordinator.canToggleBottomInspector)
        #expect(coordinator.isBottomInspectorEffectivelyPresented)
    }

    @Test("With no selection the bottom inspector toggle is disabled and a no-op")
    func toggleDisabledWithoutSelection() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let coordinator = MainContentCoordinator(workspaceLayoutPreferences: environment.preferences)

        #expect(!coordinator.hasPayloadInspectorSelection)
        #expect(!coordinator.canToggleBottomInspector)
        #expect(coordinator.inspectorLayout == .hidden)

        coordinator.toggleInspectorBottom()

        #expect(coordinator.inspectorLayout == .hidden)
        #expect(!coordinator.isBottomInspectorEffectivelyPresented)
    }

    // MARK: Private

    private func makeEnvironment() throws -> (
        defaults: UserDefaults,
        suiteName: String,
        preferences: WorkspaceLayoutPreferences
    ) {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "InspectorLayoutBehaviorTests-")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName, WorkspaceLayoutPreferences(defaults: defaults))
    }
}
