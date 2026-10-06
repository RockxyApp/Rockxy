import Foundation

// MARK: - ScriptPluginFactory

/// Writes a new user script plugin (`plugin.json` + `index.js`) into the plugins directory.
/// Shared by the Scripting window and MCP clients so both produce the same layout.
enum ScriptPluginFactory {
    /// Creates the plugin directory and files, removing the partial directory on failure.
    /// Returns the new plugin id.
    @discardableResult
    static func create(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        source: String,
        behavior: ScriptBehavior = .defaults(),
        in pluginsRoot: URL,
        fileManager: FileManager = .default
    )
        throws -> String
    {
        let directory = pluginsRoot.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let manifest = PluginManifest(
                id: id,
                name: name,
                version: "1.0.0",
                author: PluginAuthor(name: "User", url: nil),
                description: "",
                types: [.script],
                entryPoints: ["script": "index.js"],
                capabilities: ["modifyRequest", "modifyResponse"],
                configuration: nil,
                minRockxyVersion: nil,
                homepage: nil,
                license: nil,
                scriptBehavior: behavior
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
            try source.write(to: directory.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
            return id
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    static var defaultPluginsRoot: URL {
        RockxyIdentity.current.appSupportPath("Plugins")
    }
}
