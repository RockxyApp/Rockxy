import Foundation
import os

/// Coordinates rule mutations between the shared `RuleEngine` actor, disk persistence
/// via `RuleStore`, `BreakpointWindowModel` refresh, and UI notification via
/// `NotificationCenter`. All rule changes should flow through this service.
enum RuleSyncService {
    // MARK: Internal

    static func addRule(_ rule: ProxyRule) async {
        await RuleEngine.shared.addRule(rule)
        await syncAll()
    }

    static func removeRule(id: UUID) async {
        await RuleEngine.shared.removeRule(id: id)
        await syncAll()
    }

    static func toggleRule(id: UUID) async {
        await RuleEngine.shared.toggleRule(id: id)
        await syncAll()
    }

    static func updateRule(_ rule: ProxyRule) async {
        await RuleEngine.shared.updateRule(rule)
        await syncAll()
    }

    static func replaceAllRules(_ rules: [ProxyRule]) async {
        await RuleEngine.shared.replaceAll(rules)
        await syncAll()
    }

    static func setRuleEnabled(id: UUID, enabled: Bool) async {
        await RuleEngine.shared.setEnabled(id: id, enabled: enabled)
        await syncAll()
    }

    static func addNetworkConditionExclusive(_ rule: ProxyRule) async {
        await RuleEngine.shared.addNetworkConditionExclusive(rule)
        await syncAll()
    }

    static func enableExclusiveNetworkCondition(id: UUID) async {
        await RuleEngine.shared.enableExclusiveNetworkCondition(id: id)
        await syncAll()
    }

    static func disableAllNetworkConditions() async {
        await RuleEngine.shared.disableAllNetworkConditions()
        await syncAll()
    }

    static func loadFromDisk() async {
        try? await RuleEngine.shared.loadRules(from: RuleStore())
        await syncAll()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "RuleSyncService")

    private static func syncAll() async {
        let allRules = await RuleEngine.shared.allRules
        try? RuleStore().saveRules(allRules)
        await BreakpointWindowModel.shared.refreshBreakpointRules(from: allRules)
        NotificationCenter.default.post(name: .rulesDidChange, object: allRules)
        logger.debug("Rules synced: \(allRules.count) rules")
    }
}
