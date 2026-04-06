import Foundation
import os

// Implements plugin discovery behavior for the plugin and scripting subsystem.

// MARK: - PluginDiscovery

actor PluginDiscovery {
    // MARK: Internal

    enum PluginInstallError: LocalizedError {
        case sourceNotDirectory(URL)
        case missingManifest(URL)
        case invalidName

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case let .sourceNotDirectory(url):
                "Plugin source is not a directory: \(url.lastPathComponent)"
            case let .missingManifest(url):
                "Plugin directory missing plugin.json: \(url.lastPathComponent)"
            case .invalidName:
                "Plugin directory name is invalid."
            }
        }
    }

    var pluginsDirectoryURL: URL {
        let pluginsDir = RockxyIdentity.current.appSupportPath("Plugins", fileManager: .default)

        if !FileManager.default.fileExists(atPath: pluginsDir.path) {
            do {
                try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
            } catch {
                Self.logger.error("Failed to create plugins directory: \(error.localizedDescription)")
            }
        }

        return pluginsDir
    }

    func discoverPlugins() async -> [PluginInfo] {
        let directory = pluginsDirectoryURL
        var discovered: [PluginInfo] = []

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            Self.logger.info("No plugins directory contents found")
            return []
        }

        for item in contents {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let manifestURL = item.appendingPathComponent("plugin.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                Self.logger.warning("Plugin directory \(item.lastPathComponent) missing plugin.json")
                continue
            }

            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

                guard validateManifest(manifest, bundlePath: item) else {
                    continue
                }

                let isEnabled = UserDefaults.standard.bool(forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: manifest.id))

                let info = PluginInfo(
                    id: manifest.id,
                    manifest: manifest,
                    bundlePath: item,
                    isEnabled: isEnabled,
                    status: isEnabled ? .active : .disabled
                )
                discovered.append(info)
                Self.logger.debug("Discovered plugin: \(manifest.name) (\(manifest.id))")
            } catch {
                Self.logger
                    .error("Failed to parse plugin.json in \(item.lastPathComponent): \(error.localizedDescription)")
            }
        }

        Self.logger.info("Discovered \(discovered.count) plugins")
        return discovered
    }

    func installPlugin(from sourceURL: URL) async throws {
        let resolved = sourceURL.resolvingSymlinksInPath()

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else {
            throw PluginInstallError.sourceNotDirectory(resolved)
        }

        let manifestURL = resolved.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PluginInstallError.missingManifest(resolved)
        }

        let safeName = resolved.lastPathComponent
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "/", with: "")
        guard !safeName.isEmpty else {
            throw PluginInstallError.invalidName
        }

        let destination = pluginsDirectoryURL.appendingPathComponent(safeName)
        try FileManager.default.copyItem(at: resolved, to: destination)
        Self.logger.info("Installed plugin from \(safeName)")
    }

    func uninstallPlugin(bundlePath: URL) async throws {
        try FileManager.default.removeItem(at: bundlePath)
        Self.logger.info("Uninstalled plugin at \(bundlePath.lastPathComponent)")
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "PluginDiscovery")

    private func validateManifest(_ manifest: PluginManifest, bundlePath: URL) -> Bool {
        guard !manifest.id.isEmpty, !manifest.name.isEmpty, !manifest.version.isEmpty else {
            Self.logger.warning("Plugin manifest missing required fields in \(bundlePath.lastPathComponent)")
            return false
        }

        let allowedIDCharacters = CharacterSet.alphanumerics.union(.init(charactersIn: "-_."))
        guard manifest.id.unicodeScalars.allSatisfy({ allowedIDCharacters.contains($0) }) else {
            Self.logger.warning("Plugin ID contains invalid characters: \(manifest.id)")
            return false
        }

        for (_, path) in manifest.entryPoints {
            let entryURL = bundlePath.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: entryURL.path) else {
                Self.logger.warning("Plugin \(manifest.id) entry point \(path) not found")
                return false
            }
        }

        return true
    }
}
