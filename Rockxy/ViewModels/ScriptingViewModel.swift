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

// MARK: - ScriptRunStatus

enum ScriptRunStatus: Equatable {
    case idle
    case running
    case success
    case failure
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
        "Rewrite URL": """
        function onRequest(request) {
          if (request.url.includes("/v1/")) {
            request.url = request.url.replace("/v1/", "/v2/");
          }
          return request;
        }

        module.exports = { onRequest };
        """,
        "Conditional Mock JSON": """
        function onRequest(request) {
          if (request.url.includes("/feature-flags")) {
            return {
              statusCode: 200,
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ featureA: true, featureB: false })
            };
          }
          return request;
        }

        module.exports = { onRequest };
        """,
    ]

    var plugins: [PluginInfo] = []
    var selectedPluginID: String?
    var scriptContent: String = ""
    var consoleOutput: [ConsoleEntry] = []
    var isLoading = false
    var runStatus: ScriptRunStatus = .idle
    var runStatusMessage: String?

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

    @discardableResult
    func selectPlugin(id: String) -> Bool {
        selectedPluginID = id
        guard let plugin = plugins.first(where: { $0.id == id }) else {
            return false
        }
        let scriptURL = plugin.bundlePath.appendingPathComponent(plugin.manifest.entryPoints["script"] ?? "index.js")
        do {
            scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)
            return true
        } catch {
            scriptContent = ""
            setRunStatus(.failure, message: "Load failed")
            appendConsole("Load failed: \(error.localizedDescription)", level: .error)
            return false
        }
    }

    @discardableResult
    func saveScript() -> Bool {
        guard let plugin = selectedPlugin else {
            setRunStatus(.failure, message: "No script selected")
            appendConsole("Save failed: No plugin selected.", level: .error)
            return false
        }
        let scriptURL = plugin.bundlePath.appendingPathComponent(plugin.manifest.entryPoints["script"] ?? "index.js")
        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            setRunStatus(.success, message: "Script saved")
            appendConsole("Script saved.", level: .info)
            return true
        } catch {
            setRunStatus(.failure, message: "Save failed")
            appendConsole("Save failed: \(error.localizedDescription)", level: .error)
            return false
        }
    }

    func runTest() async {
        guard let id = selectedPluginID else {
            setRunStatus(.failure, message: "No script selected")
            appendConsole("No plugin selected.", level: .warning)
            return
        }
        guard saveScript() else {
            return
        }
        setRunStatus(.running, message: "Running test…")
        appendConsole("Reloading plugin\u{2026}", level: .info)
        do {
            try await pluginManager.reloadPlugin(id: id)
            plugins = await pluginManager.plugins
            setRunStatus(.success, message: "Test run passed")
            appendConsole("Plugin reloaded and test run complete.", level: .output)
        } catch let error as ScriptRuntimeError {
            plugins = await pluginManager.plugins
            switch error {
            case .executionTimeout:
                setRunStatus(.failure, message: "Timed out")
                appendConsole(
                    "Script timed out after 5 seconds. Check for infinite loops or blocking operations.",
                    level: .error
                )
            case let .jsException(message):
                setRunStatus(.failure, message: "JavaScript exception")
                appendConsole("JavaScript exception: \(message)", level: .error)
            case let .scriptLoadFailed(reason):
                setRunStatus(.failure, message: "Script failed to load")
                appendConsole("Script failed to load: \(reason)", level: .error)
            case let .pluginNotLoaded(pluginID):
                setRunStatus(.failure, message: "Plugin not loaded")
                appendConsole("Plugin not loaded: \(pluginID). Try creating a new script.", level: .error)
            }
        } catch {
            plugins = await pluginManager.plugins
            setRunStatus(.failure, message: "Test failed")
            appendConsole("Test failed: \(error.localizedDescription)", level: .error)
        }
    }

    func createNewScript(templateName: String? = nil) async {
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
            let blankScript = """
            function onRequest(request) {
              return request;
            }

            function onResponse(response) {
              return response;
            }

            module.exports = { onRequest, onResponse };
            """
            let foundTemplate = templateName.flatMap { Self.scriptTemplates[$0] }
            let template = foundTemplate ?? blankScript
            try template.write(to: pluginsDir.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
            await loadPlugins()
            let loadedOK = selectPlugin(id: id)
            if loadedOK {
                let statusMessage: String
                if let name = templateName {
                    if foundTemplate != nil {
                        statusMessage = "Created from \(name)"
                    } else {
                        statusMessage = "Template '\(name)' not found — created blank script"
                        appendConsole("Template '\(name)' not found, falling back to blank script", level: .warning)
                    }
                } else {
                    statusMessage = "Created blank script"
                }
                setRunStatus(.success, message: statusMessage)
            }
            appendConsole("Created new script: \(name)", level: .info)
        } catch {
            setRunStatus(.failure, message: "Create failed")
            appendConsole("Failed to create script: \(error.localizedDescription)", level: .error)
        }
    }

    func togglePlugin(id: String, enabled: Bool) async {
        do {
            if enabled {
                try await pluginManager.enablePlugin(id: id)
                setRunStatus(.success, message: "Plugin enabled")
                appendConsole("Plugin enabled.", level: .info)
            } else {
                await pluginManager.disablePlugin(id: id)
                setRunStatus(.success, message: "Plugin disabled")
                appendConsole("Plugin disabled.", level: .info)
            }
            plugins = await pluginManager.plugins
        } catch let error as ScriptRuntimeError {
            plugins = await pluginManager.plugins
            switch error {
            case let .jsException(message):
                setRunStatus(.failure, message: "JavaScript exception")
                appendConsole("Plugin has a JavaScript error: \(message)", level: .error)
            case let .scriptLoadFailed(reason):
                setRunStatus(.failure, message: "Script failed to load")
                appendConsole("Plugin script failed to load: \(reason)", level: .error)
            default:
                setRunStatus(.failure, message: "Enable failed")
                appendConsole("Enable failed: \(error.localizedDescription)", level: .error)
            }
        } catch {
            plugins = await pluginManager.plugins
            setRunStatus(.failure, message: "Toggle failed")
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
            setRunStatus(.success, message: "Plugin removed")
            appendConsole("Plugin removed.", level: .info)
        } catch {
            setRunStatus(.failure, message: "Delete failed")
            appendConsole("Delete failed: \(error.localizedDescription)", level: .error)
        }
    }

    func clearConsole() {
        consoleOutput.removeAll()
    }

    func applyTemplate(_ name: String) {
        guard let source = Self.scriptTemplates[name] else {
            setRunStatus(.failure, message: "Template not found: \(name)")
            appendConsole("Template '\(name)' not found", level: .warning)
            return
        }
        scriptContent = source
        setRunStatus(.success, message: "Applied template")
    }

    func setRunStatus(_ status: ScriptRunStatus, message: String? = nil) {
        runStatus = status
        runStatusMessage = message
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptingViewModel")

    private let pluginManager = ScriptPluginManager()

    private func appendConsole(_ message: String, level: ConsoleLevel) {
        consoleOutput.append(ConsoleEntry(timestamp: .now, message: message, level: level))
    }
}
