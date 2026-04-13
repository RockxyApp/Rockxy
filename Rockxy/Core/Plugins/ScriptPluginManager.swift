import Foundation
import os

// Defines `ScriptPluginManager`, which coordinates script plugin behavior in the plugin
// and scripting subsystem.

// MARK: - ScriptPluginError

enum ScriptPluginError: Error, LocalizedError {
    case pluginNotFound(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .pluginNotFound(id):
            "Plugin not found: \(id)"
        }
    }
}

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
            let id = plugins[i].id
            do {
                try await runtime.loadPlugin(plugins[i])
                // Re-resolve after await — another caller may have mutated plugins
                if let j = plugins.firstIndex(where: { $0.id == id }) {
                    plugins[j].status = .active
                }
            } catch {
                if let j = plugins.firstIndex(where: { $0.id == id }) {
                    plugins[j].status = .error(error.localizedDescription)
                }
                Self.logger.error("Failed to load plugin \(id): \(error.localizedDescription)")
            }
        }
        Self.logger.info("Loaded \(self.plugins.count) plugins")
    }

    /// Atomically check quota, claim the enabled slot, load the runtime, and
    /// commit or roll back. The count check + isEnabled = true happen before
    /// the first await, so concurrent callers see the claimed slot.
    func enablePluginIfAllowed(id: String, maxEnabled: Int) async throws -> Bool {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            throw ScriptPluginError.pluginNotFound(id)
        }

        let enabledCount = plugins.filter(\.isEnabled).count
        guard enabledCount < maxEnabled else {
            return false
        }

        // Claim before first await — atomic with count check above
        plugins[index].isEnabled = true

        do {
            try await runtime.loadPlugin(plugins[index])
            // Re-resolve after await
            if let j = plugins.firstIndex(where: { $0.id == id }) {
                plugins[j].status = .active
            }
            UserDefaults.standard.set(true, forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
            Self.logger.info("Enabled plugin: \(id)")
            return true
        } catch {
            // Roll back — re-resolve in case index shifted
            if let j = plugins.firstIndex(where: { $0.id == id }) {
                plugins[j].isEnabled = false
                plugins[j].status = .error(error.localizedDescription)
            }
            throw error
        }
    }

    func disablePlugin(id: String) async {
        guard plugins.contains(where: { $0.id == id }) else {
            return
        }
        await runtime.unloadPlugin(id: id)
        // Re-resolve after await
        if let index = plugins.firstIndex(where: { $0.id == id }) {
            plugins[index].isEnabled = false
            plugins[index].status = .disabled
        }
        UserDefaults.standard.set(false, forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
        Self.logger.info("Disabled plugin: \(id)")
    }

    func reloadPlugin(id: String) async throws {
        guard plugins.contains(where: { $0.id == id }) else {
            return
        }
        await runtime.unloadPlugin(id: id)
        // Re-resolve after await
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        try await runtime.loadPlugin(plugins[index])
        // Re-resolve again after second await
        if let j = plugins.firstIndex(where: { $0.id == id }) {
            plugins[j].status = .active
        }
        Self.logger.info("Reloaded plugin: \(id)")
    }

    func uninstallPlugin(id: String) async throws {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        let bundlePath = plugins[index].bundlePath
        await runtime.unloadPlugin(id: id)
        try await discovery.uninstallPlugin(bundlePath: bundlePath)
        // Re-resolve after awaits — remove by ID, not stale index
        if let j = plugins.firstIndex(where: { $0.id == id }) {
            plugins.remove(at: j)
        }
        UserDefaults.standard.removeObject(forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
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
