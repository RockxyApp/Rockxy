import Foundation

// MARK: - SSLProxyingListViewModel

/// View model for the SSL Proxying List window. Follows the AllowListWindowViewModel pattern.
@MainActor @Observable
final class SSLProxyingListViewModel {
    // MARK: Lifecycle

    init(manager: SSLProxyingManager = .shared) {
        self.manager = manager
    }

    // MARK: Internal

    let manager: SSLProxyingManager

    var selectedRuleID: UUID?
    var selectedTab: SSLProxyingListType = .include
    var isFilterBarVisible = false
    var filterText = ""
    var showAddDomainSheet = false
    var showAddAppSheet = false
    var showBypassSheet = false
    var editingRule: SSLProxyingRule?

    var isSSLProxyingEnabled: Bool {
        manager.isEnabled
    }

    var currentTabRules: [SSLProxyingRule] {
        let tabRules = selectedTab == .include ? manager.includeRules : manager.excludeRules
        guard !filterText.isEmpty else {
            return tabRules
        }
        return tabRules.filter { $0.domain.localizedCaseInsensitiveContains(filterText) }
    }

    var ruleCount: Int {
        let tabRules = selectedTab == .include ? manager.includeRules : manager.excludeRules
        return tabRules.count
    }

    var enableDisableLabel: String {
        guard let id = selectedRuleID,
              let rule = manager.rules.first(where: { $0.id == id }) else
        {
            return String(localized: "Enable Rule")
        }
        return rule.isEnabled
            ? String(localized: "Disable Rule")
            : String(localized: "Enable Rule")
    }

    func setEnabled(_ enabled: Bool) {
        manager.setEnabled(enabled)
    }

    func addRules(_ domains: [String]) {
        let rules = domains.compactMap { domain -> SSLProxyingRule? in
            let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            return SSLProxyingRule(domain: trimmed, listType: selectedTab)
        }
        guard !rules.isEmpty else {
            return
        }
        selectedRuleID = rules.last?.id
        manager.addRules(rules)
    }

    func addRule(domain: String) {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let rule = SSLProxyingRule(domain: trimmed, listType: selectedTab)
        selectedRuleID = rule.id
        manager.addRule(rule)
    }

    func updateRule(id: UUID, domain: String) {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard var rule = manager.rules.first(where: { $0.id == id }) else {
            return
        }
        rule.domain = trimmed
        manager.updateRule(rule)
        selectedRuleID = rule.id
    }

    func removeSelected() {
        guard let id = selectedRuleID else {
            return
        }
        manager.removeRule(id: id)
        selectedRuleID = nil
    }

    func selectRule(id: UUID) {
        selectedRuleID = id
    }

    func toggleRule(id: UUID) {
        manager.toggleRule(id: id)
    }

    func setRuleEnabled(id: UUID, enabled: Bool) {
        manager.setRuleEnabled(id: id, enabled: enabled)
    }

    func reconcileSelectionAfterRulesChange() {
        guard let id = selectedRuleID else {
            return
        }
        if !currentTabRules.contains(where: { $0.id == id }) {
            selectedRuleID = nil
        }
    }

    func switchTab(to tab: SSLProxyingListType) {
        selectedTab = tab
        selectedRuleID = nil
        filterText = ""
    }

    func presentEditor(for id: UUID) {
        guard let rule = manager.rules.first(where: { $0.id == id }) else {
            return
        }
        editingRule = rule
        showAddDomainSheet = true
    }

    func presentEditorForSelection() {
        guard let id = selectedRuleID else {
            return
        }
        presentEditor(for: id)
    }

    func removeRule(id: UUID) {
        manager.removeRule(id: id)
        if selectedRuleID == id {
            selectedRuleID = nil
        }
    }
}
