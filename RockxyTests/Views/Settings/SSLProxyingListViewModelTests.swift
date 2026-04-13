import Foundation
@testable import Rockxy
import Testing

// MARK: - SSLProxyingListViewModelTests

@MainActor
struct SSLProxyingListViewModelTests {
    // MARK: Internal

    // MARK: - Initial State

    @Test("initial state has include tab selected")
    func initialState() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        #expect(vm.selectedTab == .include)
        #expect(vm.selectedRuleID == nil)
        #expect(vm.isFilterBarVisible == false)
        #expect(vm.filterText.isEmpty)
        #expect(vm.showAddDomainSheet == false)
        #expect(vm.showAddAppSheet == false)
        #expect(vm.showBypassSheet == false)
    }

    // MARK: - Tab Switching

    @Test("switchTab changes tab and clears selection")
    func switchTab() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com")
        vm.selectedRuleID = vm.manager.rules.first?.id
        vm.filterText = "test"

        vm.switchTab(to: .exclude)
        #expect(vm.selectedTab == .exclude)
        #expect(vm.selectedRuleID == nil)
        #expect(vm.filterText.isEmpty)
    }

    // MARK: - currentTabRules

    @Test("currentTabRules filters by tab")
    func currentTabRulesFilters() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "include.com")
        vm.switchTab(to: .exclude)
        vm.addRule(domain: "exclude.com")

        vm.switchTab(to: .include)
        #expect(vm.currentTabRules.count == 1)
        #expect(vm.currentTabRules[0].domain == "include.com")

        vm.switchTab(to: .exclude)
        #expect(vm.currentTabRules.count == 1)
        #expect(vm.currentTabRules[0].domain == "exclude.com")
    }

    @Test("currentTabRules filters by search text")
    func currentTabRulesSearch() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "api.example.com")
        vm.addRule(domain: "cdn.other.com")

        vm.filterText = "example"
        #expect(vm.currentTabRules.count == 1)
        #expect(vm.currentTabRules[0].domain == "api.example.com")
    }

    // MARK: - Rule Count

    @Test("ruleCount returns count for current tab only")
    func ruleCount() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "inc1.com")
        vm.addRule(domain: "inc2.com")
        vm.switchTab(to: .exclude)
        vm.addRule(domain: "exc1.com")

        vm.switchTab(to: .include)
        #expect(vm.ruleCount == 2)

        vm.switchTab(to: .exclude)
        #expect(vm.ruleCount == 1)
    }

    // MARK: - CRUD

    @Test("addRule adds to current tab's list type")
    func addRule() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com")
        #expect(vm.manager.rules.count == 1)
        #expect(vm.manager.rules[0].listType == .include)
        #expect(vm.selectedRuleID == vm.manager.rules[0].id)
    }

    @Test("addRule on exclude tab creates exclude rule")
    func addRuleExcludeTab() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.switchTab(to: .exclude)
        vm.addRule(domain: "excluded.com")
        #expect(vm.manager.rules[0].listType == .exclude)
    }

    @Test("addRule trims whitespace and rejects empty")
    func addRuleTrims() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "  ")
        #expect(vm.manager.rules.isEmpty)

        vm.addRule(domain: "  test.com  ")
        #expect(vm.manager.rules[0].domain == "test.com")
    }

    @Test("updateRule changes domain")
    func updateRule() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "old.com")
        let id = vm.manager.rules[0].id
        vm.updateRule(id: id, domain: "new.com")
        #expect(vm.manager.rules[0].domain == "new.com")
    }

    @Test("updateRule rejects whitespace-only input and preserves original domain")
    func updateRuleRejectsWhitespace() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "old.com")
        let id = vm.manager.rules[0].id
        vm.updateRule(id: id, domain: "  ")
        #expect(vm.manager.rules[0].domain == "old.com")
    }

    @Test("removeSelected removes and clears selection")
    func removeSelected() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com")
        vm.selectedRuleID = vm.manager.rules[0].id
        vm.removeSelected()
        #expect(vm.manager.rules.isEmpty)
        #expect(vm.selectedRuleID == nil)
    }

    @Test("removeSelected does nothing without selection")
    func removeSelectedNoSelection() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com")
        vm.selectedRuleID = nil
        vm.removeSelected()
        #expect(vm.manager.rules.count == 1)
    }

    @Test("toggleRule toggles enabled state")
    func toggleRule() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com")
        let id = vm.manager.rules[0].id
        #expect(vm.manager.rules[0].isEnabled == true)
        vm.toggleRule(id: id)
        #expect(vm.manager.rules[0].isEnabled == false)
    }

    // MARK: - Selection Reconciliation

    @Test("reconcileSelectionAfterRulesChange clears invalid selection")
    func reconcileSelection() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com")
        let id = vm.manager.rules[0].id
        vm.selectedRuleID = id
        vm.manager.removeRule(id: id)
        vm.reconcileSelectionAfterRulesChange()
        #expect(vm.selectedRuleID == nil)
    }

    @Test("reconcileSelectionAfterRulesChange keeps valid selection")
    func reconcileSelectionValid() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com")
        let id = vm.manager.rules[0].id
        vm.selectedRuleID = id
        vm.reconcileSelectionAfterRulesChange()
        #expect(vm.selectedRuleID == id)
    }

    @Test("reconcileSelection clears when rule is hidden by tab switch")
    func reconcileSelectionHiddenByTab() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "include.com")
        let id = vm.manager.rules[0].id
        vm.selectedRuleID = id

        vm.switchTab(to: .exclude)
        vm.selectedRuleID = id
        vm.reconcileSelectionAfterRulesChange()
        #expect(vm.selectedRuleID == nil)
    }

    @Test("reconcileSelection clears when rule is hidden by filter")
    func reconcileSelectionHiddenByFilter() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "api.example.com")
        let id = vm.manager.rules[0].id
        vm.selectedRuleID = id

        vm.filterText = "nomatch"
        vm.reconcileSelectionAfterRulesChange()
        #expect(vm.selectedRuleID == nil)
    }

    @Test("filter change hides selected rule so reconciliation clears it")
    func filterChangeTriggersReconciliation() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "api.example.com")
        vm.addRule(domain: "cdn.other.com")
        let apiID = vm.manager.rules[0].id
        vm.selectedRuleID = apiID

        #expect(vm.currentTabRules.contains(where: { $0.id == apiID }))

        vm.filterText = "other"

        #expect(!vm.currentTabRules.contains(where: { $0.id == apiID }))

        vm.reconcileSelectionAfterRulesChange()
        #expect(vm.selectedRuleID == nil)
    }

    @Test("addRules adds multiple domains and preserves order")
    func addRulesAddsMultipleDomains() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let countBefore = vm.manager.rules.count
        vm.addRules(["a.com", "b.com", "c.com"])
        #expect(vm.manager.rules.count == countBefore + 3)
        let addedDomains = Array(vm.manager.rules[countBefore ..< countBefore + 3]).map(\.domain)
        #expect(addedDomains == ["a.com", "b.com", "c.com"])
    }

    // MARK: - Batch Add

    @Test("addRules adds multiple domains and selects last")
    func addRulesSelectsLast() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRules(["a.com", "b.com", "c.com"])
        #expect(vm.manager.rules.count == 3)
        #expect(vm.selectedRuleID == vm.manager.rules.last?.id)
    }

    @Test("addRules trims and skips empty entries")
    func addRulesBatchTrims() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRules(["  a.com  ", "", "  ", "b.com"])
        #expect(vm.manager.rules.count == 2)
        #expect(vm.manager.rules[0].domain == "a.com")
        #expect(vm.manager.rules[1].domain == "b.com")
    }

    @Test("addRules uses current tab list type")
    func addRulesBatchUsesTab() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.switchTab(to: .exclude)
        vm.addRules(["x.com"])
        #expect(vm.manager.rules[0].listType == .exclude)
    }

    // MARK: - Enable/Disable Label

    @Test("enableDisableLabel returns correct text")
    func enableDisableLabel() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com")
        let id = vm.manager.rules[0].id
        vm.selectedRuleID = id

        #expect(vm.enableDisableLabel == String(localized: "Disable Rule"))
        vm.toggleRule(id: id)
        #expect(vm.enableDisableLabel == String(localized: "Enable Rule"))
    }

    @Test("enableDisableLabel defaults when no selection")
    func enableDisableLabelNoSelection() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        #expect(vm.enableDisableLabel == String(localized: "Enable Rule"))
    }

    // MARK: - Editor

    @Test("presentEditorForSelection sets editing rule")
    func presentEditor() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.addRule(domain: "test.com")
        vm.selectedRuleID = vm.manager.rules[0].id
        vm.presentEditorForSelection()
        #expect(vm.editingRule != nil)
        #expect(vm.editingRule?.domain == "test.com")
        #expect(vm.showAddDomainSheet == true)
    }

    @Test("presentEditorForSelection does nothing without selection")
    func presentEditorNoSelection() {
        let (vm, tempURL) = makeViewModel()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        vm.presentEditorForSelection()
        #expect(vm.editingRule == nil)
        #expect(vm.showAddDomainSheet == false)
    }

    // MARK: Private

    private func makeViewModel() -> (SSLProxyingListViewModel, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-vm-test-\(UUID().uuidString).json")
        let manager = SSLProxyingManager(storageURL: url)
        return (SSLProxyingListViewModel(manager: manager), url)
    }
}
