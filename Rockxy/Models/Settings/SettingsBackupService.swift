import Foundation
import os

// Reads every debugging tool's settings into a backup and applies an imported backup to the
// app's stores.

// MARK: - SettingsBackupImportReport

struct SettingsBackupImportReport: Equatable {
    var ruleCount = 0
    var scriptCount = 0
    var skippedCount = 0
}

// MARK: - SettingsBackupService

@MainActor
enum SettingsBackupService {
    // MARK: Internal

    /// Largest Map Local body carried in a backup, and the total for all bodies.
    static let maxMapLocalFileSize = 8 * 1_024 * 1_024
    static let maxMapLocalTotalSize = 24 * 1_024 * 1_024

    nonisolated static var mapLocalRoot: URL {
        RockxyIdentity.current.appSupportDirectory().appendingPathComponent("map-local", isDirectory: true)
    }

    static func currentSettings() async -> SettingsBackupSnapshot {
        let ssl = SSLProxyingManager.shared
        let allowList = AllowListManager.shared
        var toolsEnabled: [String: Bool] = [:]
        for key in SettingsBackupSnapshot.toolSwitchKeys {
            toolsEnabled[key] = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        }
        return await SettingsBackupSnapshot(
            rules: RuleEngine.shared.allRules,
            toolsEnabled: toolsEnabled,
            sslProxying: SSLProxyingBackup(
                isEnabled: ssl.isEnabled,
                bypassDomains: ssl.bypassDomains,
                rules: ssl.rules,
                applicationRules: ssl.applicationRules
            ),
            allowList: AllowListBackup(isActive: allowList.isActive, rules: allowList.rules),
            bypassDomains: BypassProxyManager.shared.domains,
            reverseProxies: ReverseProxyStore.shared.rules,
            dnsSpoofing: DNSSpoofingStore.shared.rules,
            noCaching: UserDefaults.standard.bool(forKey: NoCacheHeaderMutator.userDefaultsKey),
            ruleFolders: Dictionary(
                uniqueKeysWithValues: RuleFolderStore.backupStores.map { ($0.tool, $0.store.folders) }
            )
        )
    }

    static func makeBackup(onlyEnabledRules: Bool) async -> SettingsBackupDocument {
        let current = await currentSettings()
        let settings = onlyEnabledRules ? current.enabledOnly() : current
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return SettingsBackupDocument(
            appVersion: version,
            onlyEnabledRules: onlyEnabledRules,
            settings: settings,
            mapLocalFiles: mapLocalFiles(for: settings.rules),
            scripts: scripts(onlyEnabled: onlyEnabledRules)
        )
    }

    static func importBackup(
        _ document: SettingsBackupDocument,
        mode: SettingsBackupImportMode,
        proxyPort: Int
    )
        async -> SettingsBackupImportReport
    {
        var backup = document.settings
        backup.rules = relocateMapLocalFiles(document.mapLocalFiles, rules: backup.rules)
        let current = await currentSettings()
        let merged = SettingsBackupMerger.merge(backup, into: current, mode: mode, proxyPort: proxyPort)
        let settings = merged.settings

        await RulePolicyGate.shared.replaceAllRules(settings.rules)
        if mode == .replace {
            await applyToolSwitches(settings.toolsEnabled)
            if let noCaching = settings.noCaching {
                UserDefaults.standard.set(noCaching, forKey: NoCacheHeaderMutator.userDefaultsKey)
            }
        }
        if backup.sslProxying != nil, let ssl = settings.sslProxying {
            let manager = SSLProxyingManager.shared
            manager.setEnabled(ssl.isEnabled)
            manager.setBypassDomains(ssl.bypassDomains)
            manager.replaceAllApplicationRules(ssl.applicationRules)
            manager.replaceAllRules(ssl.rules)
        }
        if backup.allowList != nil, let allowList = settings.allowList {
            AllowListManager.shared.replaceAll(allowList.rules)
            AllowListManager.shared.setActive(allowList.isActive)
        }
        if let data = try? JSONEncoder().encode(settings.bypassDomains) {
            do {
                try BypassProxyManager.shared.importDomains(from: data)
            } catch {
                logger.error("Bypass domains from the backup were not applied: \(error.localizedDescription)")
            }
        }
        // Backups made before folders were recorded have no entry and leave folders untouched.
        for (tool, store) in RuleFolderStore.backupStores {
            if let folders = backup.ruleFolders[tool] {
                store.importFolders(folders, replacing: mode == .replace)
            }
        }
        ReverseProxyStore.shared.replaceAll(settings.reverseProxies)
        DNSSpoofingStore.shared.replaceAll(settings.dnsSpoofing)

        let scriptCount = installScripts(document.scripts)
        if scriptCount > 0 {
            await PluginManager.shared.scriptManager.loadAllPlugins()
        }
        return SettingsBackupImportReport(
            ruleCount: merged.addedRuleCount,
            scriptCount: scriptCount,
            skippedCount: merged.skippedCount + document.scripts.count - scriptCount
        )
    }

    /// Carries the body files of Map Local rules that live in Rockxy's own Map Local folder.
    /// Files chosen elsewhere on disk stay as paths only.
    static func mapLocalFiles(for rules: [ProxyRule], root: URL = mapLocalRoot) -> [SettingsBackupFile] {
        var files: [SettingsBackupFile] = []
        var total = 0
        var seen: Set<String> = []
        for rule in rules {
            guard case let .mapLocal(filePath, _, isDirectory, _, _) = rule.action, !isDirectory,
                  let name = relativeName(of: filePath, in: root), seen.insert(name).inserted,
                  let data = try? Data(contentsOf: root.appendingPathComponent(name)),
                  data.count <= maxMapLocalFileSize, total + data.count <= maxMapLocalTotalSize else
            {
                continue
            }
            total += data.count
            files.append(SettingsBackupFile(name: name, data: data))
        }
        return files
    }

    /// Writes carried Map Local bodies into this Mac's Map Local folder and points the rules at
    /// them. A name that already holds different content gets a fresh name instead.
    static func relocateMapLocalFiles(
        _ files: [SettingsBackupFile],
        rules: [ProxyRule],
        root: URL = mapLocalRoot
    )
        -> [ProxyRule]
    {
        guard !files.isEmpty else {
            return rules
        }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var placed: [String: String] = [:]
        for file in files {
            guard let safeName = safeFileName(file.name) else {
                continue
            }
            var destination = root.appendingPathComponent(safeName)
            if let existing = try? Data(contentsOf: destination), existing != file.data {
                let stem = (safeName as NSString).deletingPathExtension
                let ext = (safeName as NSString).pathExtension
                let unique = "\(stem)-\(UUID().uuidString.prefix(8).lowercased())"
                destination = root.appendingPathComponent(ext.isEmpty ? unique : "\(unique).\(ext)")
            }
            do {
                try file.data.write(to: destination, options: .atomic)
                placed[file.name] = destination.path
            } catch {
                logger.error("Could not write a Map Local body from the backup: \(error.localizedDescription)")
            }
        }
        return rules.map { rule in
            guard case let .mapLocal(filePath, statusCode, isDirectory, delayMs, headers) = rule.action,
                  let name = relativeName(of: filePath, marker: root.lastPathComponent),
                  let newPath = placed[name] else
            {
                return rule
            }
            var updated = rule
            updated.action = .mapLocal(
                filePath: newPath,
                statusCode: statusCode,
                isDirectory: isDirectory,
                delayMs: delayMs,
                responseHeaders: headers
            )
            return updated
        }
    }

    /// Script plugins with their source, read from the plugins folder.
    static func scripts(
        onlyEnabled: Bool,
        root: URL = ScriptPluginFactory.defaultPluginsRoot,
        defaults: UserDefaults = .standard
    )
        -> [SettingsBackupScript]
    {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return folders.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { folder in
            guard let manifestData = try? Data(contentsOf: folder.appendingPathComponent("plugin.json")),
                  let manifest = try? JSONDecoder().decode(PluginManifest.self, from: manifestData),
                  manifest.types.contains(.script),
                  let entry = manifest.entryPoints["script"], safeFileName(entry) == entry,
                  let source = try? String(contentsOf: folder.appendingPathComponent(entry), encoding: .utf8) else
            {
                return nil
            }
            if onlyEnabled, !defaults.bool(forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: manifest.id)) {
                return nil
            }
            return SettingsBackupScript(name: manifest.name, source: source, behavior: manifest.scriptBehavior)
        }
    }

    /// Adds each script as a new plugin. Imported scripts start turned off so nothing from a
    /// file runs until the user reviews and enables it.
    static func installScripts(
        _ scripts: [SettingsBackupScript],
        root: URL = ScriptPluginFactory.defaultPluginsRoot
    )
        -> Int
    {
        var installed = 0
        for script in scripts where script.source.utf8.count <= maxScriptSize {
            let name = script.name.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                try ScriptPluginFactory.create(
                    name: name.isEmpty ? String(localized: "Imported Script", bundle: RockxyLocalization.bundle) : name,
                    source: script.source,
                    behavior: script.behavior ?? .defaults(),
                    in: root
                )
                installed += 1
            } catch {
                logger.error("Could not add a script from the backup: \(error.localizedDescription)")
            }
        }
        return installed
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "SettingsBackup")
    private static let maxScriptSize = 1_024 * 1_024

    private static func applyToolSwitches(_ switches: [String: Bool]) async {
        let gate = RulePolicyGate.shared
        for (key, enabled) in switches {
            switch key {
            case "breakpointToolEnabled": await gate.setBreakpointToolEnabled(enabled)
            case "mapLocalToolEnabled": await gate.setMapLocalToolEnabled(enabled)
            case "mapRemoteToolEnabled": await gate.setMapRemoteToolEnabled(enabled)
            case "blockListToolEnabled": await gate.setBlockListToolEnabled(enabled)
            case "networkConditionsToolEnabled": await gate.setNetworkConditionsToolEnabled(enabled)
            case "modifyHeaderToolEnabled": await gate.setModifyHeaderToolEnabled(enabled)
            default: break
            }
        }
    }

    /// Path of `filePath` below `root`, or `nil` when the file lives elsewhere.
    private static func relativeName(of filePath: String, in root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path + "/"
        let path = URL(fileURLWithPath: filePath).standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            return nil
        }
        return safeFileName(String(path.dropFirst(rootPath.count)))
    }

    /// Path after the last `/<marker>/` component, which is how a body recorded on another Mac
    /// is recognized regardless of that Mac's home folder.
    private static func relativeName(of filePath: String, marker: String) -> String? {
        guard let range = filePath.range(of: "/\(marker)/", options: .backwards) else {
            return nil
        }
        return safeFileName(String(filePath[range.upperBound...]))
    }

    /// A single path component without traversal, or `nil`.
    private static func safeFileName(_ name: String) -> String? {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != "..",
              !name.hasPrefix(".") else
        {
            return nil
        }
        return name
    }
}
