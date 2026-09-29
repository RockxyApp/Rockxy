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

    init(tool: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = RockxyIdentity.current.defaultsKey("ruleFolders.\(tool)")
        folders = Self.load(defaults: defaults, key: key)
    }

    // MARK: Internal

    static let mapLocal = RuleFolderStore(tool: "mapLocal")
    static let breakpoint = RuleFolderStore(tool: "breakpoint")

    private(set) var folders: [RuleFolder]

    func folder(containing ruleID: UUID) -> RuleFolder? {
        folders.first { $0.ruleIDs.contains(ruleID) }
    }

    /// Creates a folder holding `ruleIDs`, taking them out of any folder they were in.
    @discardableResult
    func createFolder(named name: String, containing ruleIDs: [UUID] = []) -> UUID {
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
