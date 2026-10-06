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

// MARK: - ScriptListRuntimeStatus

enum ScriptListRuntimeStatus: Equatable {
    case active
    case disabled
    case error
    case loading

    // MARK: Lifecycle

    init(_ status: PluginStatus) {
        switch status {
        case .active:
            self = .active
        case .disabled:
            self = .disabled
        case .error:
            self = .error
        case .loading:
            self = .loading
        }
    }

    // MARK: Internal

    var title: String {
        switch self {
        case .active:
            String(localized: "Active", bundle: RockxyLocalization.bundle)
        case .disabled:
            String(localized: "Disabled", bundle: RockxyLocalization.bundle)
        case .error:
            String(localized: "Error", bundle: RockxyLocalization.bundle)
        case .loading:
            String(localized: "Loading…", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - PluginInfoSnapshot

/// Plain value snapshot of a script plugin for list rendering — pulled off
/// the actor + folder store onto the MainActor viewmodel.
struct PluginInfoSnapshot: Equatable {
    // MARK: Lifecycle

    init(
        id: String,
        name: String,
        isEnabled: Bool,
        method: String?,
        urlPattern: String?,
        runtimeStatus: ScriptListRuntimeStatus,
        statusDetail: String? = nil,
        bundlePath: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.method = method
        self.urlPattern = urlPattern
        self.runtimeStatus = runtimeStatus
        self.statusDetail = statusDetail
        self.bundlePath = bundlePath
    }

    // MARK: Internal

    let id: String
    let name: String
    let isEnabled: Bool
    let method: String?
    let urlPattern: String?
    let runtimeStatus: ScriptListRuntimeStatus
    let statusDetail: String?
    let bundlePath: URL?
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
        case .name: String(localized: "Name", bundle: RockxyLocalization.bundle)
        case .method: String(localized: "Method", bundle: RockxyLocalization.bundle)
        case .urlPattern: String(localized: "Matching Rule", bundle: RockxyLocalization.bundle)
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
        folderStore: ScriptFolderStore? = nil,
        pluginsDirectory: URL? = nil
    ) {
        self.pluginManager = pluginManager
        self.folderStore = folderStore ?? .shared
        self.pluginsDirectoryOverride = pluginsDirectory
    }

    // MARK: Internal

    var plugins: [PluginInfoSnapshot] = []

    var selectedRowID: ScriptListRowID?
    var renamingFolderID: UUID?
    var renamingFolderText: String = ""
    var filterText: String = ""
    var filterColumn: ScriptListFilterColumn = .name
    var advanceAllowSystemEnvVars: Bool = false
    var advanceAllowChaining: Bool = false
    /// True when the master "Enable Scripting Tool" toggle is on.
    var toolEnabled: Bool = true
    /// Last user-visible failure from a create/duplicate/delete/enable operation.
    /// The window surfaces it through a single alert and clears it on dismiss.
    var operationError: String?
    private(set) var mutatingScriptIDs: Set<String> = []
    private(set) var isCreatingOrDuplicating = false

    /// Identity of the underlying ScriptPluginManager — exposed for tests that
    /// need to verify multiple view models share the same backing actor.
    var pluginManagerIdentity: ObjectIdentifier {
        pluginManager.identity
    }

    var displayRows: [ScriptListDisplayRow] {
        buildDisplayRows(pluginSnapshots: plugins, folderIndex: folderStore.index)
    }

    var filteredDisplayRows: [ScriptListDisplayRow] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return displayRows
        }
        return buildFilteredRows(
            pluginSnapshots: plugins,
            folderIndex: folderStore.index,
            filterText: query,
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
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let current = await pluginManager.plugins
        guard generation == refreshGeneration else {
            let targetGeneration = refreshGeneration
            while appliedRefreshGeneration < targetGeneration {
                await Task.yield()
            }
            return
        }
        plugins = current.map { Self.snapshot(from: $0) }
        folderStore.reconcile(with: plugins.map(\.id))
        reconcileSelectionAfterRefresh()
        reconcileSelectionWithVisibleRows()
        applySettingsSnapshot()
        appliedRefreshGeneration = generation
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
        guard !isCreatingOrDuplicating else {
            return nil
        }
        isCreatingOrDuplicating = true
        defer { isCreatingOrDuplicating = false }
        let selectionBeforeCreate = selectedRowID
        operationError = nil
        let id = UUID().uuidString.lowercased()
        let name = "Untitled Script \(plugins.count + 1)"
        let pluginsDir = pluginDir(for: id)
        do {
            try ScriptPluginFactory.create(
                id: id,
                name: name,
                source: ScriptTemplates.defaultSource,
                in: pluginsDir.deletingLastPathComponent()
            )
            await pluginManager.loadAllPlugins()
            await refresh()
            filterText = ""
            filterColumn = .name
            if selectedRowID == selectionBeforeCreate {
                selectedRowID = .script(id)
            }
            ScriptEditorSession.shared.setPending(.edit(pluginID: id))
            return id
        } catch {
            Self.logger.error("Create script failed: \(error.localizedDescription)")
            operationError = String(
                localized: "Could not create the script. \(error.localizedDescription)",
                bundle: RockxyLocalization.bundle
            )
            return nil
        }
    }

    /// Create an empty folder ready to rename-in-place.
    func createNewFolder() {
        filterText = ""
        filterColumn = .name
        let id = folderStore.createFolder()
        renamingFolderID = id
        renamingFolderText = String(localized: "Untitled", bundle: RockxyLocalization.bundle)
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
        reconcileSelectionWithVisibleRows()
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
        operationError = nil
        switch selection {
        case let .folder(id):
            folderStore.deleteFolder(id: id)
            selectedRowID = nil
        case let .script(id):
            guard !mutatingScriptIDs.contains(id) else {
                return
            }
            mutatingScriptIDs.insert(id)
            defer { mutatingScriptIDs.remove(id) }
            do {
                try await pluginManager.uninstallPlugin(id: id)
                if selectedRowID == selection {
                    selectedRowID = nil
                }
            } catch {
                Self.logger.error("Delete script failed: \(error.localizedDescription)")
                operationError = String(
                    localized: "Could not delete the script. \(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
                do {
                    try await pluginManager.reloadPlugin(id: id)
                } catch {
                    Self.logger.error("Restore after failed delete failed: \(error.localizedDescription)")
                    operationError = String(
                        localized:
                        "Could not delete the script, and Rockxy could not restore its runtime. \(error.localizedDescription)",
                        bundle: RockxyLocalization.bundle
                    )
                }
            }
            await refresh()
        }
    }

    func duplicateSelection() async {
        guard case let .script(id) = selectedRowID,
              let source = plugins.first(where: { $0.id == id }),
              !isCreatingOrDuplicating else
        {
            return
        }
        isCreatingOrDuplicating = true
        defer { isCreatingOrDuplicating = false }
        let selectionBeforeDuplicate = selectedRowID
        operationError = nil
        let newID = UUID().uuidString.lowercased()
        let sourceDir = pluginDir(for: id)
        let destDir = pluginDir(for: newID)
        var createdDestination = false
        do {
            try FileManager.default.copyItem(at: sourceDir, to: destDir)
            createdDestination = true
            // Rewrite plugin.json with new id + name
            let manifestURL = destDir.appendingPathComponent("plugin.json")
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
            let newName = source.name + " " + String(localized: "(Copy)", bundle: RockxyLocalization.bundle)
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(copy).write(to: manifestURL)
            await pluginManager.loadAllPlugins()
            await refresh()
            if selectedRowID == selectionBeforeDuplicate {
                selectedRowID = .script(newID)
                reconcileSelectionWithVisibleRows()
            }
        } catch {
            if createdDestination, FileManager.default.fileExists(atPath: destDir.path) {
                do {
                    try FileManager.default.removeItem(at: destDir)
                } catch {
                    Self.logger.error("Duplicate cleanup failed: \(error.localizedDescription)")
                }
            }
            Self.logger.error("Duplicate failed: \(error.localizedDescription)")
            operationError = String(
                localized: "Could not duplicate the script. \(error.localizedDescription)",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    func setScriptEnabled(id: String, enabled: Bool) async {
        guard !mutatingScriptIDs.contains(id),
              let plugin = plugins.first(where: { $0.id == id }),
              plugin.isEnabled != enabled else
        {
            return
        }
        mutatingScriptIDs.insert(id)
        defer { mutatingScriptIDs.remove(id) }
        operationError = nil
        if enabled {
            do {
                try await ScriptPolicyGate.shared.enablePlugin(id: id, using: pluginManager)
            } catch {
                Self.logger.error("Enable failed: \(error.localizedDescription)")
                operationError = String(
                    localized: "Could not enable the script. \(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            }
        } else {
            await pluginManager.disablePlugin(id: id)
        }
        await refresh()
    }

    func toggleScript(id: String) async {
        guard let plugin = plugins.first(where: { $0.id == id }) else {
            return
        }
        await setScriptEnabled(id: id, enabled: !plugin.isEnabled)
    }

    func setScriptsEnabled(ids: [String], enabled: Bool) async {
        operationError = nil
        let requestedIDs = Set(ids)
        let targets = plugins.filter {
            requestedIDs.contains($0.id)
                && !mutatingScriptIDs.contains($0.id)
                && $0.isEnabled != enabled
        }
        guard !targets.isEmpty else {
            return
        }
        mutatingScriptIDs.formUnion(targets.map(\.id))
        defer { mutatingScriptIDs.subtract(targets.map(\.id)) }
        for plugin in targets {
            if enabled {
                do {
                    try await ScriptPolicyGate.shared.enablePlugin(id: plugin.id, using: pluginManager)
                } catch {
                    Self.logger.error("Enable failed: \(error.localizedDescription)")
                    operationError = String(
                        localized: "Could not enable the script. \(error.localizedDescription)",
                        bundle: RockxyLocalization.bundle
                    )
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
        reconcileSelectionWithVisibleRows()
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

    func reconcileSelectionWithVisibleRows() {
        guard let selectedRowID else {
            return
        }
        if !filteredDisplayRows.contains(where: { $0.id == selectedRowID }) {
            self.selectedRowID = nil
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ScriptingListViewModel"
    )

    private let pluginManager: ScriptPluginManager
    private let folderStore: ScriptFolderStore
    private let pluginsDirectoryOverride: URL?
    private var refreshGeneration: UInt = 0
    private var appliedRefreshGeneration: UInt = 0

    private static func snapshot(from info: PluginInfo) -> PluginInfoSnapshot {
        let behavior = info.manifest.scriptBehavior ?? ScriptBehavior.defaults()
        let method = behavior.matchCondition?.method?.uppercased()
        let pattern = ScriptEditorViewModel.editorPattern(for: behavior.matchCondition).pattern
        return PluginInfoSnapshot(
            id: info.id,
            name: info.manifest.name,
            isEnabled: info.isEnabled,
            method: method,
            urlPattern: pattern.isEmpty ? nil : pattern,
            runtimeStatus: ScriptListRuntimeStatus(info.status),
            statusDetail: statusDetail(from: info),
            bundlePath: info.bundlePath
        )
    }

    private static func statusDetail(from info: PluginInfo) -> String? {
        if case let .error(message) = info.status {
            return message.isEmpty ? info.lastError : message
        }
        return nil
    }

    private func reconcileSelectionAfterRefresh() {
        guard let selectedRowID else {
            return
        }
        switch selectedRowID {
        case let .script(id):
            if !plugins.contains(where: { $0.id == id }) {
                self.selectedRowID = nil
            }
        case let .folder(id):
            if !folderStore.index.folders.contains(where: { $0.id == id }) {
                self.selectedRowID = nil
            }
        }
    }

    private func pluginDir(for id: String) -> URL {
        if let bundlePath = plugins.first(where: { $0.id == id })?.bundlePath {
            return bundlePath
        }
        let root = pluginsDirectoryOverride ?? RockxyIdentity.current.appSupportPath("Plugins")
        return root.appendingPathComponent(id, isDirectory: true)
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
            (script.method ?? "ANY").lowercased().contains(needle)
        case .urlPattern:
            (script.urlPattern ?? "").lowercased().contains(needle)
        }
    }
}
