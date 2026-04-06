import Foundation
import os

// Owns console output, script templates, and editor state for the scripting window.

// MARK: - ConsoleEntry

struct ConsoleEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let level: ConsoleLevel
}

// MARK: - ConsoleLevel

enum ConsoleLevel {
    case info
    case warning
    case error
    case output
}

// MARK: - ScriptingViewModel

@MainActor @Observable
final class ScriptingViewModel {
    // MARK: Internal

    // MARK: Internal Static

    static let scriptTemplates: [String: String] = [
        "Modify Headers": """
        function onRequest(request) {
          request.setHeader("X-Custom", "value");
          return request;
        }

        module.exports = { onRequest };
        """,
        "Log Requests": """
        function onRequest(request) {
          console.log(`[${request.method}] ${request.url}`);
          return request;
        }

        module.exports = { onRequest };
        """,
        "Block Pattern": """
        function onRequest(request) {
          if (request.url.includes("analytics")) {
            return null;
          }
          return request;
        }

        module.exports = { onRequest };
        """,
        "Custom Response": """
        function onRequest(request) {
          return {
            statusCode: 200,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ mock: true })
          };
        }

        module.exports = { onRequest };
        """,
    ]

    var plugins: [PluginInfo] = []
    var selectedPluginID: String?
    var scriptContent: String = ""
    var consoleOutput: [ConsoleEntry] = []
    var isLoading = false

    var selectedPlugin: PluginInfo? {
        guard let id = selectedPluginID else {
            return nil
        }
        return plugins.first { $0.id == id }
    }

    func loadPlugins() async {
        isLoading = true
        defer { isLoading = false }
        await pluginManager.loadAllPlugins()
        plugins = await pluginManager.plugins

        let errorPlugins = plugins.filter {
            if case .error = $0.status {
                return true
            }
            return false
        }
        for plugin in errorPlugins {
            if case let .error(message) = plugin.status {
                appendConsole("\(plugin.manifest.name): \(message)", level: .error)
            }
        }
    }

    func selectPlugin(id: String) {
        selectedPluginID = id
        guard let plugin = plugins.first(where: { $0.id == id }) else {
            return
        }
        let scriptURL = plugin.bundlePath.appendingPathComponent(plugin.manifest.entryPoints["script"] ?? "index.js")
        do {
            scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)
        } catch {
            scriptContent = ""
            appendConsole("Failed to load script: \(error.localizedDescription)", level: .error)
        }
    }

    func saveScript() {
        guard let plugin = selectedPlugin else {
            return
        }
        let scriptURL = plugin.bundlePath.appendingPathComponent(plugin.manifest.entryPoints["script"] ?? "index.js")
        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            appendConsole("Script saved.", level: .info)
        } catch {
            appendConsole("Save failed: \(error.localizedDescription)", level: .error)
        }
    }

    func runTest() async {
        guard let id = selectedPluginID else {
            appendConsole("No plugin selected.", level: .warning)
            return
        }
        saveScript()
        appendConsole("Reloading plugin\u{2026}", level: .info)
        do {
            try await pluginManager.reloadPlugin(id: id)
            plugins = await pluginManager.plugins
            appendConsole("Plugin reloaded and test run complete.", level: .output)
        } catch let error as ScriptRuntimeError {
            plugins = await pluginManager.plugins
            switch error {
            case .executionTimeout:
                appendConsole(
                    "Script timed out after 5 seconds. Check for infinite loops or blocking operations.",
                    level: .error
                )
            case let .jsException(message):
                appendConsole("JavaScript exception: \(message)", level: .error)
            case let .scriptLoadFailed(reason):
                appendConsole("Script failed to load: \(reason)", level: .error)
            case let .pluginNotLoaded(pluginID):
                appendConsole("Plugin not loaded: \(pluginID). Try creating a new script.", level: .error)
            }
        } catch {
            plugins = await pluginManager.plugins
            appendConsole("Test failed: \(error.localizedDescription)", level: .error)
        }
    }

    func createNewScript() async {
        let name = "Untitled Script \(plugins.count + 1)"
        let id = UUID().uuidString.lowercased()
        do {
            let pluginsDir = RockxyIdentity.current
                .appSupportPath("Plugins")
                .appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
            let manifest = """
            {"id":"\(id)","name":"\(
                name
            )","version":"1.0.0","author":{"name":"User"},"description":"","types":["script"],"entryPoints":{"script":"index.js"},"capabilities":["modifyRequest"]}
            """
            try manifest.write(to: pluginsDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
            let template = "function onRequest(request) {\n  return request;\n}\n\nfunction onResponse(response) {\n  return response;\n}\n"
            try template.write(to: pluginsDir.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
            await loadPlugins()
            selectPlugin(id: id)
            appendConsole("Created new script: \(name)", level: .info)
        } catch {
            appendConsole("Failed to create script: \(error.localizedDescription)", level: .error)
        }
    }

    func togglePlugin(id: String, enabled: Bool) async {
        do {
            if enabled {
                try await pluginManager.enablePlugin(id: id)
                appendConsole("Plugin enabled.", level: .info)
            } else {
                await pluginManager.disablePlugin(id: id)
                appendConsole("Plugin disabled.", level: .info)
            }
            plugins = await pluginManager.plugins
        } catch let error as ScriptRuntimeError {
            plugins = await pluginManager.plugins
            switch error {
            case let .jsException(message):
                appendConsole("Plugin has a JavaScript error: \(message)", level: .error)
            case let .scriptLoadFailed(reason):
                appendConsole("Plugin script failed to load: \(reason)", level: .error)
            default:
                appendConsole("Enable failed: \(error.localizedDescription)", level: .error)
            }
        } catch {
            plugins = await pluginManager.plugins
            appendConsole("Toggle failed: \(error.localizedDescription)", level: .error)
        }
    }

    func deletePlugin(id: String) async {
        do {
            try await pluginManager.uninstallPlugin(id: id)
            plugins = await pluginManager.plugins
            if selectedPluginID == id {
                selectedPluginID = nil
                scriptContent = ""
            }
            appendConsole("Plugin removed.", level: .info)
        } catch {
            appendConsole("Delete failed: \(error.localizedDescription)", level: .error)
        }
    }

    func clearConsole() {
        consoleOutput.removeAll()
    }

    func applyTemplate(_ name: String) {
        guard let source = Self.scriptTemplates[name] else {
            return
        }
        scriptContent = source
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptingViewModel")

    private let pluginManager = ScriptPluginManager()

    private func appendConsole(_ message: String, level: ConsoleLevel) {
        consoleOutput.append(ConsoleEntry(timestamp: .now, message: message, level: level))
    }
}
