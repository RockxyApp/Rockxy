import Foundation
import os

// MARK: - ScriptListRowID

/// Row identifier in the Scripting List window. Folders and scripts coexist in
/// one flat displayed list.
enum ScriptListRowID: Hashable {
    case folder(UUID)
    case script(String)
}

// MARK: - ScriptListDisplayRow

/// One row the list view renders. Flattens the `ScriptFolderIndex` tree into a
/// sequence the native `List` can bind against.
struct ScriptListDisplayRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder(ScriptFolder)
        case script(PluginInfoSnapshot)
    }

    let id: ScriptListRowID
    let indent: Int
    let kind: Kind
}

// MARK: - PluginInfoSnapshot

/// Plain value snapshot of a script plugin for list rendering — pulled off
/// the actor + folder store onto the MainActor viewmodel.
struct PluginInfoSnapshot: Equatable {
    let id: String
    let name: String
    let isEnabled: Bool
    let method: String?
    let urlPattern: String?
    let statusText: String
}

// MARK: - ScriptListFilterColumn

/// Filter column for the slide-up filter bar — mirrors AllowList / BlockList idiom.
enum ScriptListFilterColumn: String, CaseIterable, Identifiable {
    case name
    case method
    case urlPattern

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .method: String(localized: "Method")
        case .urlPattern: String(localized: "Matching Rule")
        }
    }
}

// MARK: - ScriptingListViewModel

@MainActor
@Observable
final class ScriptingListViewModel {
    // MARK: Lifecycle

    init(
        pluginManager: ScriptPluginManager = PluginManager.shared.scriptManager,
        folderStore: ScriptFolderStore = .shared
    ) {
        self.pluginManager = pluginManager
        self.folderStore = folderStore
    }

    // MARK: Internal

    var plugins: [PluginInfoSnapshot] = []

    var selectedRowID: ScriptListRowID?
    var renamingFolderID: UUID?
    var renamingFolderText: String = ""
    var isFilterVisible: Bool = false
    var filterText: String = ""
    var filterColumn: ScriptListFilterColumn = .name
    var advanceAllowSystemEnvVars: Bool = false
    var advanceAllowChaining: Bool = false
    /// True when the master "Enable Scripting Tool" toggle is on.
    var toolEnabled: Bool = true

    /// Identity of the underlying ScriptPluginManager — exposed for tests that
    /// need to verify multiple view models share the same backing actor.
    var pluginManagerIdentity: ObjectIdentifier {
        pluginManager.identity
    }

    var displayRows: [ScriptListDisplayRow] {
        buildDisplayRows(pluginSnapshots: plugins, folderIndex: folderStore.index)
    }

    var filteredDisplayRows: [ScriptListDisplayRow] {
        guard isFilterVisible, !filterText.isEmpty else {
            return displayRows
        }
        return buildFilteredRows(
            pluginSnapshots: plugins,
            folderIndex: folderStore.index,
            filterText: filterText,
            filterColumn: filterColumn
        )
    }

    /// Alias kept for test compatibility with the previous `ScriptingViewModel`
    /// name. Prefer `refresh()` in new code.
    func loadPlugins() async {
        await refresh()
    }

    /// Refresh `plugins` snapshot from the actor + reconcile folder index.
    func refresh() async {
        let current = await pluginManager.plugins
        plugins = current.map { Self.snapshot(from: $0) }
        folderStore.reconcile(with: plugins.map(\.id))
        applySettingsSnapshot()
    }

    /// Load-on-first-appear for the window.
    func load() async {
        await pluginManager.ensureLoadedOnce()
        await refresh()
    }

    // MARK: - Enable toggles

    func setToolEnabled(_ enabled: Bool) {
        toolEnabled = enabled
        var settings = AppSettingsStorage.load()
        settings.scriptingToolEnabled = enabled
        AppSettingsStorage.save(settings)
    }

    func setAdvanceAllowSystemEnvVars(_ allow: Bool) {
        advanceAllowSystemEnvVars = allow
        var settings = AppSettingsStorage.load()
        settings.allowSystemEnvVars = allow
        AppSettingsStorage.save(settings)
    }

    func setAdvanceAllowChaining(_ allow: Bool) {
        advanceAllowChaining = allow
        var settings = AppSettingsStorage.load()
        settings.allowMultipleScriptsPerRequest = allow
        AppSettingsStorage.save(settings)
    }

    // MARK: - Script CRUD

    @discardableResult
    func createNewScript() async -> String? {
        let id = UUID().uuidString.lowercased()
        let name = "Untitled Script \(plugins.count + 1)"
        let pluginsDir = RockxyIdentity.current
            .appSupportPath("Plugins")
            .appendingPathComponent(id, isDirectory: true)
        var createdDirectory = false
        do {
            try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
            createdDirectory = true

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
                scriptBehavior: ScriptBehavior.defaults()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: pluginsDir.appendingPathComponent("plugin.json"))
            try ScriptTemplates.defaultSource.write(
                to: pluginsDir.appendingPathComponent("index.js"),
                atomically: true,
                encoding: .utf8
            )
            await pluginManager.loadAllPlugins()
            await refresh()
            selectedRowID = .script(id)
            ScriptEditorSession.shared.setPending(.edit(pluginID: id))
            return id
        } catch {
            if createdDirectory, FileManager.default.fileExists(atPath: pluginsDir.path) {
                do {
                    try FileManager.default.removeItem(at: pluginsDir)
                } catch {
                    Self.logger.error("Create script cleanup failed: \(error.localizedDescription)")
                }
            }
            Self.logger.error("Create script failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Create an empty folder ready to rename-in-place.
    func createNewFolder() {
        let id = folderStore.createFolder()
        renamingFolderID = id
        renamingFolderText = String(localized: "Untitled")
        selectedRowID = .folder(id)
    }

    func commitFolderRename() {
        guard let id = renamingFolderID else {
            return
        }
        let trimmed = renamingFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            folderStore.renameFolder(id: id, to: trimmed)
        }
        renamingFolderID = nil
        renamingFolderText = ""
    }

    func cancelFolderRename() {
        renamingFolderID = nil
        renamingFolderText = ""
    }

    func beginRenameSelectedFolder() {
        guard case let .folder(id) = selectedRowID,
              let folder = folderStore.index.folders.first(where: { $0.id == id }) else
        {
            return
        }
        renamingFolderID = folder.id
        renamingFolderText = folder.name
    }

    func deleteSelection() async {
        guard let selection = selectedRowID else {
            return
        }
        switch selection {
        case let .folder(id):
            folderStore.deleteFolder(id: id)
        case let .script(id):
            do {
                try await pluginManager.uninstallPlugin(id: id)
            } catch {
                Self.logger.error("Delete script failed: \(error.localizedDescription)")
            }
            await refresh()
        }
        selectedRowID = nil
    }

    func duplicateSelection() async {
        guard case let .script(id) = selectedRowID,
              let source = plugins.first(where: { $0.id == id }) else
        {
            return
        }
        let newID = UUID().uuidString.lowercased()
        let sourceDir = RockxyIdentity.current
            .appSupportPath("Plugins")
            .appendingPathComponent(id, isDirectory: true)
        let destDir = RockxyIdentity.current
            .appSupportPath("Plugins")
            .appendingPathComponent(newID, isDirectory: true)
        var createdDestination = false
        do {
            try FileManager.default.copyItem(at: sourceDir, to: destDir)
            createdDestination = true
            // Rewrite plugin.json with new id + name
            let manifestURL = destDir.appendingPathComponent("plugin.json")
            let data = try Data(contentsOf: manifestURL)
            var manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
            let newName = source.name + " " + String(localized: "(Copy)")
            let copy = PluginManifest(
                id: newID,
                name: newName,
                version: manifest.version,
                author: manifest.author,
                description: manifest.description,
                types: manifest.types,
                entryPoints: manifest.entryPoints,
                capabilities: manifest.capabilities,
                configuration: manifest.configuration,
                minRockxyVersion: manifest.minRockxyVersion,
                homepage: manifest.homepage,
                license: manifest.license,
                scriptBehavior: manifest.scriptBehavior
            )
            _ = manifest
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(copy).write(to: manifestURL)
            await pluginManager.loadAllPlugins()
            await refresh()
            selectedRowID = .script(newID)
        } catch {
            if createdDestination, FileManager.default.fileExists(atPath: destDir.path) {
                do {
                    try FileManager.default.removeItem(at: destDir)
                } catch {
                    Self.logger.error("Duplicate cleanup failed: \(error.localizedDescription)")
                }
            }
            Self.logger.error("Duplicate failed: \(error.localizedDescription)")
        }
    }

    func toggleScript(id: String) async {
        guard let plugin = plugins.first(where: { $0.id == id }) else {
            return
        }
        if plugin.isEnabled {
            await pluginManager.disablePlugin(id: id)
        } else {
            do {
                try await ScriptPolicyGate.shared.enablePlugin(id: id, using: pluginManager)
            } catch {
                Self.logger.error("Enable failed: \(error.localizedDescription)")
            }
        }
        await refresh()
    }

    func setScriptsEnabled(ids: [String], enabled: Bool) async {
        let requestedIDs = Set(ids)
        let targets = plugins.filter { requestedIDs.contains($0.id) && $0.isEnabled != enabled }
        guard !targets.isEmpty else {
            return
        }
        for plugin in targets {
            if enabled {
                do {
                    try await ScriptPolicyGate.shared.enablePlugin(id: plugin.id, using: pluginManager)
                } catch {
                    Self.logger.error("Enable failed: \(error.localizedDescription)")
                }
            } else {
                await pluginManager.disablePlugin(id: plugin.id)
            }
        }
        await refresh()
    }

    func toggleFolder(id: UUID) {
        guard let folder = folderStore.index.folders.first(where: { $0.id == id }) else {
            return
        }
        folderStore.setExpanded(folderID: id, expanded: !folder.expanded)
    }

    // MARK: - Editor open

    func openEditorForSelection() {
        guard case let .script(id) = selectedRowID else {
            return
        }
        ScriptEditorSession.shared.setPending(.edit(pluginID: id))
    }

    func openEditor(for pluginID: String) {
        ScriptEditorSession.shared.setPending(.edit(pluginID: pluginID))
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ScriptingListViewModel"
    )

    private let pluginManager: ScriptPluginManager
    private let folderStore: ScriptFolderStore

    private static func snapshot(from info: PluginInfo) -> PluginInfoSnapshot {
        let behavior = info.manifest.scriptBehavior ?? ScriptBehavior.defaults()
        let method = behavior.matchCondition?.method?.uppercased()
        let pattern = behavior.matchCondition?.urlPattern
        return PluginInfoSnapshot(
            id: info.id,
            name: info.manifest.name,
            isEnabled: info.isEnabled,
            method: method,
            urlPattern: pattern,
            statusText: info.statusText
        )
    }

    private func applySettingsSnapshot() {
        let s = AppSettingsStorage.load()
        toolEnabled = s.scriptingToolEnabled
        advanceAllowSystemEnvVars = s.allowSystemEnvVars
        advanceAllowChaining = s.allowMultipleScriptsPerRequest
    }

    private func buildDisplayRows(
        pluginSnapshots: [PluginInfoSnapshot],
        folderIndex: ScriptFolderIndex
    )
        -> [ScriptListDisplayRow]
    {
        let pluginByID = Dictionary(uniqueKeysWithValues: pluginSnapshots.map { ($0.id, $0) })
        let folderByID = Dictionary(uniqueKeysWithValues: folderIndex.folders.map { ($0.id, $0) })
        var rows: [ScriptListDisplayRow] = []
        for entry in folderIndex.rootOrder {
            switch entry {
            case let .folder(folderID):
                guard let folder = folderByID[folderID] else {
                    continue
                }
                rows.append(ScriptListDisplayRow(id: .folder(folder.id), indent: 0, kind: .folder(folder)))
                if folder.expanded {
                    for scriptID in folder.scriptIDs {
                        if let info = pluginByID[scriptID] {
                            rows.append(ScriptListDisplayRow(id: .script(info.id), indent: 1, kind: .script(info)))
                        }
                    }
                }
            case let .script(scriptID):
                if let info = pluginByID[scriptID] {
                    rows.append(ScriptListDisplayRow(id: .script(info.id), indent: 0, kind: .script(info)))
                }
            }
        }
        return rows
    }

    private func buildFilteredRows(
        pluginSnapshots: [PluginInfoSnapshot],
        folderIndex: ScriptFolderIndex,
        filterText: String,
        filterColumn: ScriptListFilterColumn
    )
        -> [ScriptListDisplayRow]
    {
        let pluginByID = Dictionary(uniqueKeysWithValues: pluginSnapshots.map { ($0.id, $0) })
        let folderByID = Dictionary(uniqueKeysWithValues: folderIndex.folders.map { ($0.id, $0) })
        let needle = filterText.lowercased()
        var rows: [ScriptListDisplayRow] = []

        for entry in folderIndex.rootOrder {
            switch entry {
            case let .folder(folderID):
                guard let folder = folderByID[folderID] else {
                    continue
                }
                let matchingScripts = folder.scriptIDs.compactMap { pluginByID[$0] }.filter {
                    scriptMatches($0, needle: needle, column: filterColumn)
                }
                let folderMatches = filterColumn == .name && folder.name.lowercased().contains(needle)
                guard folderMatches || !matchingScripts.isEmpty else {
                    continue
                }
                rows.append(ScriptListDisplayRow(id: .folder(folder.id), indent: 0, kind: .folder(folder)))
                for script in matchingScripts {
                    rows.append(ScriptListDisplayRow(id: .script(script.id), indent: 1, kind: .script(script)))
                }

            case let .script(scriptID):
                guard let script = pluginByID[scriptID],
                      scriptMatches(script, needle: needle, column: filterColumn) else
                {
                    continue
                }
                rows.append(ScriptListDisplayRow(id: .script(script.id), indent: 0, kind: .script(script)))
            }
        }
        return rows
    }

    private func scriptMatches(
        _ script: PluginInfoSnapshot,
        needle: String,
        column: ScriptListFilterColumn
    )
        -> Bool
    {
        switch column {
        case .name:
            script.name.lowercased().contains(needle)
        case .method:
            (script.method ?? "").lowercased().contains(needle)
        case .urlPattern:
            (script.urlPattern ?? "").lowercased().contains(needle)
        }
    }
}
