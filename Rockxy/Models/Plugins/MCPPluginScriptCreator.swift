import Foundation

// MARK: - MCPPluginScriptCreator

/// Creates MCP-requested scripts in the app's plugin directory and enables them through
/// `ScriptPolicyGate`, so the enabled-script limit applies exactly as in the Scripting window.
struct MCPPluginScriptCreator: MCPScriptCreating {
    var pluginsRoot: URL = ScriptPluginFactory.defaultPluginsRoot

    func createScript(name: String, source: String, behavior: ScriptBehavior, enable: Bool) async
        -> MCPScriptCreationResult
    {
        let id: String
        do {
            id = try ScriptPluginFactory.create(name: name, source: source, behavior: behavior, in: pluginsRoot)
        } catch {
            return .failed(message: error.localizedDescription)
        }
        let manager = await MainActor.run { PluginManager.shared.scriptManager }
        await manager.loadAllPlugins()
        guard enable else {
            return .created(id: id, isEnabled: false)
        }
        do {
            try await ScriptPolicyGate.shared.enablePlugin(id: id, using: manager)
            return .created(id: id, isEnabled: true)
        } catch let ScriptQuotaError.limitReached(max) {
            return .createdButLimitReached(id: id, limit: max)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}
