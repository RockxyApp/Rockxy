import Foundation
import Observation

// MARK: - RuleFolder

/// A named group of rules in one tool window. Folders only organize the list: rules keep
/// their place in Rockxy's global first-match order, and a folder's checkbox enables or
/// disables the rules inside it.
struct RuleFolder: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var ruleIDs: [UUID]
}

// MARK: - RuleFolderStore

/// Persists the folders of one rule tool (for example Map Local or Breakpoint) in UserDefaults.
@MainActor @Observable
final class RuleFolderStore {
    // MARK: Lifecycle

    init(
        tool: String,
        defaults: UserDefaults = .standard,
        maxFolders: @escaping @MainActor () -> Int = { ToolCapacityGate.shared.maxRuleFoldersPerTool }
    ) {
        self.defaults = defaults
        self.maxFolders = maxFolders
        key = RockxyIdentity.current.defaultsKey("ruleFolders.\(tool)")
        folders = Self.load(defaults: defaults, key: key)
    }

    // MARK: Internal

    static let mapLocal = RuleFolderStore(tool: "mapLocal")
    static let breakpoint = RuleFolderStore(tool: "breakpoint")
    static let mapRemote = RuleFolderStore(tool: "mapRemote")
    static let blockList = RuleFolderStore(tool: "blockList")

    /// Every tool that supports folders, keyed by the name used in settings backups.
    static var backupStores: [(tool: String, store: RuleFolderStore)] {
        [
            ("mapLocal", mapLocal),
            ("breakpoint", breakpoint),
            ("mapRemote", mapRemote),
            ("blockList", blockList),
        ]
    }

    private(set) var folders: [RuleFolder]

    /// Set when a folder could not be created because the tool is at its folder limit; the
    /// window shows it as an alert and clears it.
    var limitMessage: String?

    /// Folders that may still be created (existing folders are never removed by a lower limit).
    var canCreateFolder: Bool {
        folders.count < maxFolders()
    }

    func folder(containing ruleID: UUID) -> RuleFolder? {
        folders.first { $0.ruleIDs.contains(ruleID) }
    }

    /// Creates a folder holding `ruleIDs`, taking them out of any folder they were in. Returns nil
    /// (and sets ``limitMessage``) when the tool already has as many folders as the policy allows.
    @discardableResult
    func createFolder(named name: String, containing ruleIDs: [UUID] = []) -> UUID? {
        guard canCreateFolder else {
            limitMessage = AppPolicyViolation.ruleFolderLimitReached(limit: maxFolders()).errorDescription
            return nil
        }
        let id = UUID()
        removeFromFolders(Set(ruleIDs))
        folders.append(RuleFolder(id: id, name: Self.cleanName(name), ruleIDs: ruleIDs))
        persist()
        return id
    }

    func rename(folderID: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }
        folders[index].name = Self.cleanName(name)
        persist()
    }

    /// Deletes the folder only; its rules move back to the top level.
    func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        persist()
    }

    func move(ruleIDs: Set<UUID>, toFolder folderID: UUID?) {
        removeFromFolders(ruleIDs)
        if let folderID, let index = folders.firstIndex(where: { $0.id == folderID }) {
            folders[index].ruleIDs.append(contentsOf: ruleIDs.sorted { $0.uuidString < $1.uuidString })
        }
        persist()
    }

    /// Applies folders from a settings backup. Replacing swaps the whole set; adding keeps the
    /// existing folders and only brings in folders it does not already have.
    func importFolders(_ incoming: [RuleFolder], replacing: Bool) {
        guard replacing || !incoming.isEmpty else {
            return
        }
        if replacing {
            folders = incoming
        } else {
            let known = Set(folders.map(\.id))
            for folder in incoming where !known.contains(folder.id) {
                removeFromFolders(Set(folder.ruleIDs))
                folders.append(folder)
            }
        }
        persist()
    }

    /// Drops rule ids that no longer exist, e.g. after rules were deleted elsewhere.
    func reconcile(existingRuleIDs: Set<UUID>) {
        var changed = false
        for index in folders.indices {
            let kept = folders[index].ruleIDs.filter { existingRuleIDs.contains($0) }
            if kept.count != folders[index].ruleIDs.count {
                folders[index].ruleIDs = kept
                changed = true
            }
        }
        if changed {
            persist()
        }
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
    private let maxFolders: @MainActor () -> Int

    private static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Folder", bundle: RockxyLocalization.bundle) : trimmed
    }

    private static func load(defaults: UserDefaults, key: String) -> [RuleFolder] {
        guard let data = defaults.data(forKey: key),
              let folders = try? JSONDecoder().decode([RuleFolder].self, from: data) else
        {
            return []
        }
        return folders
    }

    private func removeFromFolders(_ ruleIDs: Set<UUID>) {
        for index in folders.indices {
            folders[index].ruleIDs.removeAll { ruleIDs.contains($0) }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - RuleListRow

/// One row of a rule table: a folder (with its rules as children) or a rule.
struct RuleListRow: Identifiable {
    enum Kind {
        case folder(RuleFolder)
        case rule(ProxyRule)
    }

    let kind: Kind
    var children: [RuleListRow]?

    var id: UUID {
        switch kind {
        case let .folder(folder): folder.id
        case let .rule(rule): rule.id
        }
    }

    var rule: ProxyRule? {
        if case let .rule(rule) = kind {
            return rule
        }
        return nil
    }

    var folder: RuleFolder? {
        if case let .folder(folder) = kind {
            return folder
        }
        return nil
    }

    /// Folders first (in creation order, each listing its rules in rule order), then loose rules.
    /// While searching the list is flat so every match is visible.
    static func rows(rules: [ProxyRule], folders: [RuleFolder], flat: Bool) -> [RuleListRow] {
        guard !flat else {
            return rules.map { RuleListRow(kind: .rule($0)) }
        }
        let foldered = Set(folders.flatMap(\.ruleIDs))
        let folderRows = folders.map { folder in
            let members = Set(folder.ruleIDs)
            let children = rules.filter { members.contains($0.id) }.map { RuleListRow(kind: .rule($0)) }
            return RuleListRow(kind: .folder(folder), children: children)
        }
        let loose = rules.filter { !foldered.contains($0.id) }.map { RuleListRow(kind: .rule($0)) }
        return folderRows + loose
    }
}

// MARK: - RuleFolderDrag

/// Drag and drop between rule folders. A dragged rule carries its own id, or every selected
/// rule id when it is part of the selection, as comma-separated text.
enum RuleFolderDrag {
    static func payload(for ruleID: UUID, selection: Set<UUID>) -> String {
        let ids = selection.contains(ruleID) ? selection.sorted { $0.uuidString < $1.uuidString } : [ruleID]
        return ids.map(\.uuidString).joined(separator: ",")
    }

    static func ruleIDs(from payloads: [String]) -> Set<UUID> {
        Set(payloads.flatMap { $0.split(separator: ",") }.compactMap { UUID(uuidString: String($0)) })
    }
}

extension RuleFolderStore {
    /// Moves dropped rules into the folder row they land on, or next to the rule row they
    /// land on (into its folder, or the top level). Folder ids and unknown ids are ignored.
    @discardableResult
    func drop(_ payloads: [String], onto row: RuleListRow, knownRuleIDs: Set<UUID>) -> Bool {
        let ruleIDs = RuleFolderDrag.ruleIDs(from: payloads).intersection(knownRuleIDs)
        guard !ruleIDs.isEmpty else {
            return false
        }
        let target: UUID? = switch row.kind {
        case let .folder(folder): folder.id
        case let .rule(rule): folder(containing: rule.id)?.id
        }
        move(ruleIDs: ruleIDs, toFolder: target)
        return true
    }
}
