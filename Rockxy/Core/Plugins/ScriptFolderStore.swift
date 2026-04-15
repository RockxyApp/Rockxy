import Foundation
import os

/// `@MainActor @Observable` singleton that owns the user's `ScriptFolderIndex`
/// (folders + top-level ordering). Persisted as a single JSON blob in
/// UserDefaults — no per-folder file on disk. Mutations publish via Observation
/// so views auto-refresh.
@MainActor
@Observable
final class ScriptFolderStore {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.index = Self.load(from: defaults)
    }

    // MARK: Internal

    static let shared = ScriptFolderStore()

    private(set) var index: ScriptFolderIndex

    /// Reconcile the persisted index against the live plugin id list.
    /// - Removes folder entries pointing at missing scripts.
    /// - Removes root-order entries pointing at missing scripts/folders.
    /// - Appends any plugin id that's not yet referenced anywhere as a loose
    ///   `.script(id)` entry at the end of `rootOrder` (migration backfill).
    func reconcile(with knownScriptIDs: [String]) {
        let known = Set(knownScriptIDs)
        var folders = index.folders
        var rootOrder = index.rootOrder

        // Drop missing scripts from each folder's children
        for folderIdx in 0 ..< folders.count {
            folders[folderIdx].scriptIDs.removeAll { !known.contains($0) }
        }

        // Drop root entries pointing at missing folders/scripts
        let folderIDs = Set(folders.map(\.id))
        rootOrder.removeAll { entry in
            switch entry {
            case let .folder(id): !folderIDs.contains(id)
            case let .script(id): !known.contains(id)
            }
        }

        // Heal orphaned folders that still exist in `folders` but somehow fell
        // out of `rootOrder` so they remain reachable in the list UI.
        let existingFolderIDs = Set(rootOrder.compactMap { entry -> UUID? in
            if case let .folder(id) = entry {
                return id
            }
            return nil
        })
        for id in folders.map(\.id) where !existingFolderIDs.contains(id) {
            rootOrder.append(.folder(id))
        }

        // Append undeclared scripts as loose entries
        let referenced = Set(folders.flatMap(\.scriptIDs)) // ids inside any folder
        var rootScriptIDs: Set<String> = []
        for entry in rootOrder {
            if case let .script(id) = entry {
                rootScriptIDs.insert(id)
            }
        }
        let placed = referenced.union(rootScriptIDs)
        for id in knownScriptIDs.sorted() where !placed.contains(id) {
            rootOrder.append(.script(id))
        }

        let next = ScriptFolderIndex(folders: folders, rootOrder: rootOrder)
        if next != index {
            index = next
            persist()
        }
    }

    /// Create a new folder; appends it to root order at the end. Returns the new folder's id.
    @discardableResult
    func createFolder(name: String = String(localized: "Untitled")) -> UUID {
        var next = index
        let folder = ScriptFolder(name: name)
        next.folders.append(folder)
        next.rootOrder.append(.folder(folder.id))
        index = next
        persist()
        return folder.id
    }

    func renameFolder(id: UUID, to newName: String) {
        guard let idx = index.folders.firstIndex(where: { $0.id == id }) else {
            return
        }
        var next = index
        next.folders[idx].name = newName
        index = next
        persist()
    }

    func deleteFolder(id: UUID) {
        var next = index
        // Move folder children back to root order in place of the folder entry
        if let folder = next.folders.first(where: { $0.id == id }) {
            if let pos = next.rootOrder.firstIndex(of: .folder(id)) {
                let inserts = folder.scriptIDs.map { ScriptFolderIndex.Entry.script($0) }
                next.rootOrder.replaceSubrange(pos ... pos, with: inserts)
            }
        }
        next.folders.removeAll { $0.id == id }
        index = next
        persist()
    }

    func setExpanded(folderID: UUID, expanded: Bool) {
        guard let idx = index.folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }
        var next = index
        next.folders[idx].expanded = expanded
        index = next
        persist()
    }

    func addScript(_ scriptID: String, toFolder folderID: UUID) {
        var next = index
        // Remove from all other folders + root if currently placed
        for fIdx in 0 ..< next.folders.count {
            next.folders[fIdx].scriptIDs.removeAll { $0 == scriptID }
        }
        next.rootOrder.removeAll { $0 == .script(scriptID) }
        guard let target = next.folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }
        next.folders[target].scriptIDs.append(scriptID)
        index = next
        persist()
    }

    func removeScriptFromFolder(_ scriptID: String) {
        var next = index
        var removed = false
        for fIdx in 0 ..< next.folders.count {
            let before = next.folders[fIdx].scriptIDs.count
            next.folders[fIdx].scriptIDs.removeAll { $0 == scriptID }
            if next.folders[fIdx].scriptIDs.count != before {
                removed = true
            }
        }
        var appendedLooseEntry = false
        if removed, !next.rootOrder.contains(.script(scriptID)) {
            next.rootOrder.append(.script(scriptID))
            appendedLooseEntry = true
        }
        guard removed || appendedLooseEntry else {
            return
        }
        index = next
        persist()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptFolderStore")

    private static let defaultsKey = RockxyIdentity.current.defaultsKey("scripting.folderIndex")

    private let defaults: UserDefaults

    private static func load(from defaults: UserDefaults) -> ScriptFolderIndex {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(ScriptFolderIndex.self, from: data)
        } catch {
            logger.warning("Failed to decode folder index: \(error.localizedDescription) — starting fresh")
            return .empty
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(index)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            Self.logger.error("Failed to persist folder index: \(error.localizedDescription)")
        }
    }
}
