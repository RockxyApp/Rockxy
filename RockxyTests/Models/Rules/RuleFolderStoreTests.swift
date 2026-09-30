import Foundation
@testable import Rockxy
import Testing

// MARK: - RuleFolderStoreTests

@MainActor
struct RuleFolderStoreTests {
    // MARK: Internal

    @Test("Every folder-capable tool is part of settings backups under a unique name")
    func backupCoversAllFolderTools() {
        let tools = RuleFolderStore.backupStores.map(\.tool)
        #expect(Set(tools).count == tools.count)
        #expect(Set(tools) == ["mapLocal", "breakpoint", "mapRemote", "blockList"])
    }

    @Test("Folders group rules, persist across relaunch, and give their rules back when deleted")
    func folderLifecycle() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = UUID()
        let b = UUID()
        let c = UUID()

        let store = RuleFolderStore(tool: "test", defaults: defaults)
        let staging = store.createFolder(named: "  Staging ", containing: [a, b])
        let prod = store.createFolder(named: "", containing: [b])
        store.rename(folderID: prod, to: "Production")

        #expect(store.folders.map(\.name) == ["Staging", "Production"])
        #expect(store.folder(containing: a)?.id == staging)
        #expect(store.folder(containing: b)?.id == prod, "a rule lives in one folder at a time")

        store.move(ruleIDs: [c], toFolder: staging)
        store.move(ruleIDs: [a], toFolder: nil)
        let reloaded = RuleFolderStore(tool: "test", defaults: defaults)
        #expect(reloaded.folders.first { $0.id == staging }?.ruleIDs == [c])
        #expect(reloaded.folder(containing: a) == nil)

        reloaded.reconcile(existingRuleIDs: [b])
        #expect(reloaded.folders.first { $0.id == staging }?.ruleIDs.isEmpty == true)
        reloaded.deleteFolder(id: prod)
        #expect(reloaded.folder(containing: b) == nil)
        #expect(RuleFolderStore(tool: "other", defaults: defaults).folders.isEmpty)
    }

    @Test("Rows list folders first with their rules in rule order, then loose rules; search is flat")
    func rowsGroupByFolder() {
        let rules = (0 ..< 4).map { ProxyRule(name: "r\($0)", matchCondition: RuleMatchCondition(), action: .breakpoint()) }
        let folder = RuleFolder(id: UUID(), name: "F", ruleIDs: [rules[2].id, rules[0].id])

        let rows = RuleListRow.rows(rules: rules, folders: [folder], flat: false)
        #expect(rows.map(\.id) == [folder.id, rules[1].id, rules[3].id])
        #expect(rows.first?.children?.map(\.id) == [rules[0].id, rules[2].id])

        let flat = RuleListRow.rows(rules: rules, folders: [folder], flat: true)
        #expect(flat.map(\.id) == rules.map(\.id))
        #expect(flat.allSatisfy { $0.children == nil })
    }

    @Test("Selecting a Map Local folder selects every rule inside it")
    func mapLocalFolderSelection() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RuleFolderStore(tool: "mapLocal-test", defaults: defaults)
        let viewModel = MapLocalViewModel(isToolEnabled: true, folderStore: store)
        let rules = (0 ..< 3).map {
            ProxyRule(name: "m\($0)", matchCondition: RuleMatchCondition(), action: .mapLocal(filePath: "/tmp/x"))
        }
        viewModel.allRules = rules
        let folderID = store.createFolder(named: "Group", containing: [rules[0].id, rules[1].id])

        viewModel.selectedRuleIDs = [folderID, rules[2].id]

        #expect(viewModel.selectedRuleIDsIncludingFolders == Set(rules.map(\.id)))
        #expect(viewModel.rows.first?.folder?.id == folderID)
    }

    // MARK: Private

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "rule-folders-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }
}

// MARK: - RuleFolderDragTests

@MainActor
struct RuleFolderDragTests {
    @Test("Dragging a selected rule carries the whole selection")
    func payloadUsesSelection() {
        let first = UUID()
        let second = UUID()
        let other = UUID()
        let payload = RuleFolderDrag.payload(for: first, selection: [first, second])
        #expect(RuleFolderDrag.ruleIDs(from: [payload]) == [first, second])
        #expect(RuleFolderDrag.ruleIDs(from: [RuleFolderDrag.payload(for: other, selection: [first])]) == [other])
        #expect(RuleFolderDrag.ruleIDs(from: ["not-an-id"]).isEmpty)
    }

    @Test("Dropping onto a folder moves rules in; onto a loose rule moves them to the top level")
    func dropTargets() throws {
        let suite = "RuleFolderDragTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RuleFolderStore(tool: "dragTest", defaults: defaults)
        let rules = (0 ..< 3).map { index in
            ProxyRule(name: "Rule \(index)", matchCondition: RuleMatchCondition(urlPattern: ".*"), action: .block(statusCode: 403))
        }
        let known = Set(rules.map(\.id))
        let folderID = store.createFolder(named: "Mocks", containing: [rules[0].id])
        let rows = RuleListRow.rows(rules: rules, folders: store.folders, flat: false)
        let folderRow = try #require(rows.first { $0.folder != nil })
        let looseRow = try #require(rows.first { $0.rule?.id == rules[2].id })

        #expect(store.drop([rules[1].id.uuidString], onto: folderRow, knownRuleIDs: known))
        #expect(store.folder(containing: rules[1].id)?.id == folderID)

        #expect(store.drop([rules[0].id.uuidString], onto: looseRow, knownRuleIDs: known))
        #expect(store.folder(containing: rules[0].id) == nil)

        // A folder id or an unknown rule is never moved.
        #expect(!store.drop([folderID.uuidString, UUID().uuidString], onto: folderRow, knownRuleIDs: known))
    }
}
