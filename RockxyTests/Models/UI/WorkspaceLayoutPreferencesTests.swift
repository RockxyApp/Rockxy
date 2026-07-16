import Foundation
@testable import Rockxy
import Testing

struct WorkspaceLayoutPreferencesTests {
    // MARK: Internal

    @Test("Fresh preferences keep both secondary panels hidden")
    func freshDefaults() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }

        #expect(environment.preferences.preferredBottomInspectorVisibility == nil)
        #expect(!environment.preferences.preferredContextDockVisibility)
    }

    @Test("Explicit inspector choices persist across preference instances")
    func persistence() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }

        environment.preferences.rememberBottomInspectorVisibility(true)
        environment.preferences.rememberContextDockVisibility(true)
        let reloaded = WorkspaceLayoutPreferences(defaults: environment.defaults)

        #expect(reloaded.preferredBottomInspectorVisibility == true)
        #expect(reloaded.preferredContextDockVisibility)
    }

    @MainActor
    @Test("Workspace defaults inherit explicit user preferences")
    func workspaceInheritance() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        environment.preferences.rememberBottomInspectorVisibility(true)
        environment.preferences.rememberContextDockVisibility(true)

        let store = WorkspaceStore(layoutPreferences: environment.preferences)
        let workspace = store.createWorkspace()

        #expect(store.workspaces[0].inspectorLayout == .bottom)
        #expect(store.workspaces[0].isContextDockVisible)
        #expect(!store.workspaces[0].allowsAutomaticInspectorReveal)
        #expect(workspace.inspectorLayout == .bottom)
        #expect(workspace.isContextDockVisible)
        #expect(!workspace.allowsAutomaticInspectorReveal)
    }

    @MainActor
    @Test("New workspaces stay automatic while no explicit preference exists")
    func automaticWorkspaceDefaults() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }

        let store = WorkspaceStore(layoutPreferences: environment.preferences)
        let workspace = store.createWorkspace()

        #expect(workspace.inspectorLayout == .hidden)
        #expect(!workspace.isContextDockVisible)
        #expect(workspace.allowsAutomaticInspectorReveal)
    }

    // MARK: Private

    private func makeEnvironment() throws -> (
        defaults: UserDefaults,
        suiteName: String,
        preferences: WorkspaceLayoutPreferences
    ) {
        let suiteName = "WorkspaceLayoutPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName, WorkspaceLayoutPreferences(defaults: defaults))
    }
}
