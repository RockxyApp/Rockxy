import Foundation
import os

// MARK: - RuleSyncService

/// Coordinates rule mutations between the shared `RuleEngine` actor, disk persistence
/// via `RuleStore`, and UI notification via `NotificationCenter`.
/// All rule changes should flow through this service.
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

    static func enableExclusiveNetworkConditionIfAllowed(
        id: UUID,
        maxPerCategory: Int
    )
        async -> Bool
    {
        let accepted = await RuleEngine.shared.enableExclusiveNetworkConditionIfAllowed(
            id: id,
            maxPerCategory: maxPerCategory
        )
        if accepted {
            await syncAll()
        }
        return accepted
    }

    // MARK: - Atomic Quota-Checked Operations

    static func addRuleIfAllowed(_ rule: ProxyRule, maxPerCategory: Int) async -> Bool {
        let accepted = await RuleEngine.shared.addRuleIfAllowed(rule, maxPerCategory: maxPerCategory)
        if accepted {
            await syncAll()
        }
        return accepted
    }

    static func toggleRuleIfAllowed(id: UUID, maxPerCategory: Int) async -> Bool {
        let accepted = await RuleEngine.shared.toggleRuleIfAllowed(id: id, maxPerCategory: maxPerCategory)
        if accepted {
            await syncAll()
        }
        return accepted
    }

    static func setEnabledIfAllowed(id: UUID, enabled: Bool, maxPerCategory: Int) async -> Bool {
        let accepted = await RuleEngine.shared.setEnabledIfAllowed(
            id: id,
            enabled: enabled,
            maxPerCategory: maxPerCategory
        )
        if accepted {
            await syncAll()
        }
        return accepted
    }

    static func addNetworkConditionExclusiveIfAllowed(
        _ rule: ProxyRule,
        maxPerCategory: Int
    )
        async -> Bool
    {
        let accepted = await RuleEngine.shared.addNetworkConditionExclusiveIfAllowed(
            rule,
            maxPerCategory: maxPerCategory
        )
        if accepted {
            await syncAll()
        }
        return accepted
    }

    static func setBreakpointToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "breakpointToolEnabled")
        await RuleEngine.shared.setBreakpointToolEnabled(enabled)
    }

    static func setBlockListToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "blockListToolEnabled")
        await RuleEngine.shared.setBlockListToolEnabled(enabled)
    }

    static func setMapLocalToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "mapLocalToolEnabled")
        await RuleEngine.shared.setMapLocalToolEnabled(enabled)
    }

    static func setMapRemoteToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "mapRemoteToolEnabled")
        await RuleEngine.shared.setMapRemoteToolEnabled(enabled)
    }

    static func setNetworkConditionsToolEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "networkConditionsToolEnabled")
        await RuleEngine.shared.setNetworkConditionsToolEnabled(enabled)
    }

    static func loadFromDisk() async {
        // Read and apply the breakpoint-tool flag BEFORE loading rules so the
        // rule engine has the correct evaluation gate in place when rules are
        // first compiled and become live.
        let blockListEnabled = UserDefaults.standard.object(forKey: "blockListToolEnabled") as? Bool ?? true
        await RuleEngine.shared.setBlockListToolEnabled(blockListEnabled)
        let bpEnabled = UserDefaults.standard.object(forKey: "breakpointToolEnabled") as? Bool ?? true
        await RuleEngine.shared.setBreakpointToolEnabled(bpEnabled)
        let mapLocalEnabled = UserDefaults.standard.object(forKey: "mapLocalToolEnabled") as? Bool ?? true
        await RuleEngine.shared.setMapLocalToolEnabled(mapLocalEnabled)
        let mapRemoteEnabled = UserDefaults.standard.object(forKey: "mapRemoteToolEnabled") as? Bool ?? true
        await RuleEngine.shared.setMapRemoteToolEnabled(mapRemoteEnabled)
        let networkConditionsEnabled = UserDefaults.standard.object(
            forKey: "networkConditionsToolEnabled"
        ) as? Bool ?? true
        await RuleEngine.shared.setNetworkConditionsToolEnabled(networkConditionsEnabled)
        do {
            try await RuleEngine.shared.loadRules(from: RuleStore())
            await syncAll()
        } catch {
            logger.error("Failed to load rules from disk: \(error.localizedDescription)")
            await publishAll()
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "RuleSyncService")
    private static let persistenceQueue = RulePersistenceQueue()

    private static func syncAll() async {
        let allRules = await RuleEngine.shared.allRules
        await persistenceQueue.save(allRules)
        await publish(allRules)
        logger.debug("Rules synced: \(allRules.count) rules")
    }

    private static func publishAll() async {
        let allRules = await RuleEngine.shared.allRules
        await publish(allRules)
        logger.debug("Rules published without persistence: \(allRules.count) rules")
    }

    private static func publish(_ allRules: [ProxyRule]) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .rulesDidChange, object: allRules)
        }
    }
}

// MARK: - RulePersistenceQueue

private actor RulePersistenceQueue {
    func save(_ rules: [ProxyRule]) {
        try? RuleStore().saveRules(rules)
    }
}
