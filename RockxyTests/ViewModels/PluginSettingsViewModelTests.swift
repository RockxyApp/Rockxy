import Foundation
@testable import Rockxy
import Testing

// Regression tests for `PluginSettingsViewModel` in the view models layer.

/// Serialized: mutates shared plugin directory and UserDefaults plugin-enabled keys.
@Suite(.serialized)
@MainActor
struct PluginSettingsViewModelTests {
    // MARK: Internal

    @Test("Default selectedPluginID is nil")
    func defaultSelectedPluginIDIsNil() {
        let viewModel = PluginSettingsViewModel()
        #expect(viewModel.selectedPluginID == nil)
    }

    @Test("Default searchText is empty")
    func defaultSearchTextIsEmpty() {
        let viewModel = PluginSettingsViewModel()
        #expect(viewModel.searchText.isEmpty)
    }

    @Test("Default selectedCategory is nil")
    func defaultSelectedCategoryIsNil() {
        let viewModel = PluginSettingsViewModel()
        #expect(viewModel.selectedCategory == nil)
    }

    @Test("filteredPlugins returns all when no filter is applied")
    func filteredPluginsReturnsAllWhenNoFilter() {
        let viewModel = PluginSettingsViewModel()
        viewModel.plugins = [
            makePlugin(id: "a", name: "Alpha", types: [.script]),
            makePlugin(id: "b", name: "Beta", types: [.inspector]),
            makePlugin(id: "c", name: "Gamma", types: [.exporter]),
        ]

        #expect(viewModel.filteredPlugins.count == 3)
    }

    @Test("filteredPlugins filters by category inspector")
    func filteredPluginsByCategoryInspector() {
        let viewModel = PluginSettingsViewModel()
        viewModel.plugins = [
            makePlugin(id: "a", name: "Alpha", types: [.script]),
            makePlugin(id: "b", name: "Beta", types: [.inspector]),
            makePlugin(id: "c", name: "Gamma", types: [.inspector, .exporter]),
        ]
        viewModel.selectedCategory = .inspector

        let filtered = viewModel.filteredPlugins
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.manifest.types.contains(.inspector) })
    }

    @Test("filteredPlugins filters by search text matching name")
    func filteredPluginsBySearchText() {
        let viewModel = PluginSettingsViewModel()
        viewModel.plugins = [
            makePlugin(id: "a", name: "JSON Viewer", types: [.inspector]),
            makePlugin(id: "b", name: "HAR Exporter", types: [.exporter]),
            makePlugin(id: "c", name: "JSON Formatter", types: [.script]),
        ]
        viewModel.searchText = "json"

        let filtered = viewModel.filteredPlugins
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.manifest.name.lowercased().contains("json") })
    }

    @Test("filteredPlugins applies both search and category filters")
    func filteredPluginsBySearchAndCategory() {
        let viewModel = PluginSettingsViewModel()
        viewModel.plugins = [
            makePlugin(id: "a", name: "JSON Viewer", types: [.inspector]),
            makePlugin(id: "b", name: "JSON Exporter", types: [.exporter]),
            makePlugin(id: "c", name: "HAR Exporter", types: [.exporter]),
        ]
        viewModel.searchText = "json"
        viewModel.selectedCategory = .exporter

        let filtered = viewModel.filteredPlugins
        #expect(filtered.count == 1)
        #expect(filtered[0].id == "b")
    }

    @Test("selectedPlugin returns correct plugin for matching ID")
    func selectedPluginReturnsCorrectPlugin() {
        let viewModel = PluginSettingsViewModel()
        viewModel.plugins = [
            makePlugin(id: "a", name: "Alpha", types: [.script]),
            makePlugin(id: "b", name: "Beta", types: [.inspector]),
        ]
        viewModel.selectedPluginID = "b"

        #expect(viewModel.selectedPlugin?.id == "b")
        #expect(viewModel.selectedPlugin?.manifest.name == "Beta")
    }

    @Test("selectedPlugin returns nil for unknown ID")
    func selectedPluginReturnsNilForUnknownID() {
        let viewModel = PluginSettingsViewModel()
        viewModel.plugins = [
            makePlugin(id: "a", name: "Alpha", types: [.script]),
        ]
        viewModel.selectedPluginID = "nonexistent"

        #expect(viewModel.selectedPlugin == nil)
    }

    // MARK: - Runtime-Backed Toggle Tests

    @Test("togglePlugin disable with real plugin refreshes correctly")
    func toggleDisableRefreshes() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }

        let id = "toggle-disable-\(UUID().uuidString.prefix(8))"
        _ = try TestFixtures.createTempPlugin(id: id, enabled: true, in: env.pluginsDir, defaults: env.defaults)

        await env.manager.loadAllPlugins()

        let viewModel = PluginSettingsViewModel(pluginManager: env.manager)
        viewModel.plugins = await env.manager.plugins
        #expect(viewModel.plugins.first { $0.id == id }?.isEnabled == true)

        await viewModel.togglePlugin(id: id)

        #expect(viewModel.plugins.first { $0.id == id }?.isEnabled == false)
        let managerPlugins = await env.manager.plugins
        #expect(managerPlugins.first { $0.id == id }?.isEnabled == false)
    }

    @Test("togglePlugin enable for unloadable plugin surfaces error")
    func toggleEnableUnloadablePluginSurfacesError() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }

        let id = "broken-\(UUID().uuidString.prefix(8))"
        let pluginDir = try TestFixtures.createTempPlugin(
            id: id,
            enabled: false,
            in: env.pluginsDir,
            defaults: env.defaults
        )

        await env.manager.loadAllPlugins()

        let plugins = await env.manager.plugins
        #expect(plugins.contains { $0.id == id })
        #expect(plugins.first { $0.id == id }?.isEnabled == false)

        // Delete the script file after discovery so runtime.loadPlugin will fail
        try FileManager.default.removeItem(at: pluginDir.appendingPathComponent("index.js"))

        let viewModel = PluginSettingsViewModel(pluginManager: env.manager)
        viewModel.plugins = plugins

        await viewModel.togglePlugin(id: id)

        // Error should be surfaced to the UI
        #expect(viewModel.lastEnableError != nil)

        // Manager state is authoritative — plugin should be rolled back to disabled
        let managerPlugins = await env.manager.plugins
        #expect(managerPlugins.first { $0.id == id }?.isEnabled == false)

        // VM plugins must also reflect the rolled-back manager state (not stale UI)
        #expect(viewModel.plugins.first { $0.id == id }?.isEnabled == false)

        // The refreshed status must show the error, not stale .disabled or .active
        if case .error = viewModel.plugins.first(where: { $0.id == id })?.status {
            // Expected — status reflects the load failure
        } else {
            Issue.record(
                "Expected .error status, got \(String(describing: viewModel.plugins.first { $0.id == id }?.status))"
            )
        }
    }

    @Test("togglePlugin enable with real plugin updates state")
    func toggleEnableRefreshes() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }

        let id = "toggle-enable-\(UUID().uuidString.prefix(8))"
        _ = try TestFixtures.createTempPlugin(id: id, enabled: false, in: env.pluginsDir, defaults: env.defaults)

        await env.manager.loadAllPlugins()

        let viewModel = PluginSettingsViewModel(pluginManager: env.manager)
        viewModel.plugins = await env.manager.plugins
        #expect(viewModel.plugins.first { $0.id == id }?.isEnabled == false)

        await viewModel.togglePlugin(id: id)

        #expect(viewModel.plugins.first { $0.id == id }?.isEnabled == true)
        #expect(viewModel.lastEnableError == nil)
    }

    @Test("Both ViewModels share same ScriptPluginManager instance")
    func sharedManagerState() {
        let manager = ScriptPluginManager()
        let settings = PluginSettingsViewModel(pluginManager: manager)
        let scripting = ScriptingViewModel(pluginManager: manager)

        // Without loading from disk, both start with the same empty state
        #expect(settings.plugins.isEmpty)
        #expect(scripting.plugins.isEmpty)
    }

    // MARK: - Config/Install Environment Isolation

    @Test("updateConfig writes to manager's injected defaults")
    func configUsesInjectedDefaults() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }

        let id = "config-test-\(UUID().uuidString.prefix(8))"
        _ = try TestFixtures.createTempPlugin(id: id, enabled: false, in: env.pluginsDir, defaults: env.defaults)

        await env.manager.loadAllPlugins()
        let viewModel = PluginSettingsViewModel(pluginManager: env.manager)

        viewModel.updateConfig(pluginID: id, key: "testKey", value: "testValue")

        let key = RockxyIdentity.current.pluginConfigPrefix(pluginID: id) + "testKey"
        let stored = env.defaults.string(forKey: key)
        #expect(stored == "testValue")

        // Must NOT be in standard defaults
        #expect(UserDefaults.standard.string(forKey: key) == nil)
    }

    @Test("configValue reads from manager's injected defaults")
    func configValueUsesInjectedDefaults() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }

        let id = "config-read-\(UUID().uuidString.prefix(8))"
        _ = try TestFixtures.createTempPlugin(id: id, enabled: false, in: env.pluginsDir, defaults: env.defaults)

        await env.manager.loadAllPlugins()

        let key = RockxyIdentity.current.pluginConfigPrefix(pluginID: id) + "readKey"
        env.defaults.set("isolated", forKey: key)

        let viewModel = PluginSettingsViewModel(pluginManager: env.manager)
        let value = viewModel.configValue(pluginID: id, key: "readKey") as? String
        #expect(value == "isolated")
    }

    // MARK: Private

    private func makePlugin(
        id: String,
        name: String,
        types: [PluginType],
        enabled: Bool = true
    )
        -> PluginInfo
    {
        PluginInfo(
            id: id,
            manifest: PluginManifest(
                id: id,
                name: name,
                version: "1.0.0",
                author: PluginAuthor(name: "Test", url: nil),
                description: "Test plugin \(name)",
                types: types,
                entryPoints: ["script": "index.js"],
                capabilities: [],
                configuration: nil
            ),
            bundlePath: FileManager.default.temporaryDirectory.appendingPathComponent(id),
            isEnabled: enabled,
            status: enabled ? .active : .disabled
        )
    }
}
