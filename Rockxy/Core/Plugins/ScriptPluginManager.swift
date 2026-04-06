import Foundation
import os

// Defines `ScriptPluginManager`, which coordinates script plugin behavior in the plugin
// and scripting subsystem.

// MARK: - ScriptPluginManager

actor ScriptPluginManager {
    // MARK: Internal

    private(set) var plugins: [PluginInfo] = []

    var pluginsDirectoryURL: URL {
        get async { await discovery.pluginsDirectoryURL }
    }

    func loadAllPlugins() async {
        plugins = await discovery.discoverPlugins()
        for i in plugins.indices where plugins[i].isEnabled {
            do {
                try await runtime.loadPlugin(plugins[i])
                plugins[i].status = .active
            } catch {
                plugins[i].status = .error(error.localizedDescription)
                Self.logger.error("Failed to load plugin \(self.plugins[i].id): \(error.localizedDescription)")
            }
        }
        Self.logger.info("Loaded \(self.plugins.count) plugins")
    }

    func enablePlugin(id: String) async throws {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        try await runtime.loadPlugin(plugins[index])
        plugins[index].isEnabled = true
        plugins[index].status = .active
        UserDefaults.standard.set(true, forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
        Self.logger.info("Enabled plugin: \(id)")
    }

    func disablePlugin(id: String) async {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        await runtime.unloadPlugin(id: id)
        plugins[index].isEnabled = false
        plugins[index].status = .disabled
        UserDefaults.standard.set(false, forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
        Self.logger.info("Disabled plugin: \(id)")
    }

    func reloadPlugin(id: String) async throws {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        await runtime.unloadPlugin(id: id)
        try await runtime.loadPlugin(plugins[index])
        plugins[index].status = .active
        Self.logger.info("Reloaded plugin: \(id)")
    }

    func uninstallPlugin(id: String) async throws {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        await runtime.unloadPlugin(id: id)
        try await discovery.uninstallPlugin(bundlePath: plugins[index].bundlePath)
        UserDefaults.standard.removeObject(forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
        plugins.remove(at: index)
        Self.logger.info("Uninstalled plugin: \(id)")
    }

    func updateConfig(pluginID: String, key: String, value: Any) async {
        let configKey = RockxyIdentity.current.pluginConfigPrefix(pluginID: pluginID) + key
        UserDefaults.standard.set(value, forKey: configKey)
    }

    // MARK: - Pipeline Hooks

    func runRequestHooks(on request: HTTPRequestData) async -> HTTPRequestData {
        var modified = request
        for plugin in plugins where plugin.isEnabled && plugin.status == .active {
            guard plugin.manifest.entryPoints["script"] != nil else {
                continue
            }
            let context = ScriptRequestContext(from: modified)
            do {
                let result = try await runtime.callOnRequest(pluginID: plugin.id, context: context)
                result.apply(to: &modified)
            } catch {
                Self.logger.error("Plugin \(plugin.id) onRequest failed: \(error.localizedDescription)")
            }
        }
        return modified
    }

    func runResponseHooks(request: HTTPRequestData, response: HTTPResponseData) async {
        for plugin in plugins where plugin.isEnabled && plugin.status == .active {
            guard plugin.manifest.entryPoints["script"] != nil else {
                continue
            }
            let context = ScriptResponseContext(request: request, response: response)
            do {
                try await runtime.callOnResponse(pluginID: plugin.id, context: context)
            } catch {
                Self.logger.error("Plugin \(plugin.id) onResponse failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptPluginManager")

    private let discovery = PluginDiscovery()
    private let runtime = ScriptRuntime()
}
