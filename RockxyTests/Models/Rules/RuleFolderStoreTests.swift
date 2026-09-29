import Foundation
@testable import Rockxy
import Testing

// MARK: - RuleFolderStoreTests

@MainActor
struct RuleFolderStoreTests {
    // MARK: Internal

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
