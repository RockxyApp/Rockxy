import Foundation
import os

/// App-layer quota gate for rule mutations. Wraps `RuleSyncService` with
/// per-category active rule limits. All rule-creating UI surfaces route
/// add, toggle, and enable calls through this gate.
///
/// Quota-checked operations use atomic methods on ``RuleEngine`` (actor)
/// that count + mutate in a single synchronous block, preventing
/// concurrent enables from both passing.
final class RulePolicyGate: @unchecked Sendable {
    // MARK: Lifecycle

    init(policy: any AppPolicy = DefaultAppPolicy()) {
        self.policy = policy
    }

    // MARK: Internal

    /// Shared gate used by all rule-mutating surfaces.
    ///
    /// **Mutability contract:** `shared` is a `var` because `MainContentCoordinator.configureSharedGates()`
    /// rebinds it once at app startup to inject the runtime `AppPolicy`, and serialized tests
    /// (`@Suite(.serialized)`) rebind it inside `defer { ... }` blocks to exercise alternate policies.
    /// Reassignment is safe only under these controlled conditions — the final store wins and
    /// there is no concurrent rule evaluation racing with the swap. Do not reassign from
    /// parallel tests or from arbitrary runtime paths.
    static var shared = RulePolicyGate()

    let policy: any AppPolicy

    /// Cap enabled rules only in categories that grew beyond the limit compared
    /// to the `baseline`. Already-enabled rules in the baseline are preserved
    /// first; only newly-enabled overflow is trimmed.
    static func capEnabledPerCategory(
        _ rules: [ProxyRule],
        limit: Int,
        baseline: [ProxyRule]
    )
        -> [ProxyRule]
    {
        let baselineEnabled = enabledIDsByCategory(in: baseline)
        let newCounts = enabledCounts(in: rules)

        var categoriesToCap: Set<String> = []
        for (cat, count) in newCounts where count > limit {
            categoriesToCap.insert(cat)
        }

        guard !categoriesToCap.isEmpty else {
            return rules
        }

        var result = rules
        var running: [String: Int] = [:]

        // First pass: count baseline-enabled rules, disable excess beyond limit
        for index in result.indices where result[index].isEnabled {
            let cat = result[index].action.toolCategory
            guard categoriesToCap.contains(cat) else {
                continue
            }
            if baselineEnabled[cat]?.contains(result[index].id) == true {
                let count = running[cat, default: 0]
                if count >= limit {
                    result[index].isEnabled = false
                } else {
                    running[cat] = count + 1
                }
            }
        }

        // Second pass: disable newly-enabled rules that overflow
        for index in result.indices where result[index].isEnabled {
            let cat = result[index].action.toolCategory
            guard categoriesToCap.contains(cat) else {
                continue
            }
            if baselineEnabled[cat]?.contains(result[index].id) == true {
                continue // Already counted in first pass
            }
            let count = running[cat, default: 0]
            if count >= limit {
                result[index].isEnabled = false
            } else {
                running[cat] = count + 1
            }
        }

        return result
    }

    // MARK: - Atomic Quota-Checked Operations

    @discardableResult
    func addRule(_ rule: ProxyRule) async -> Bool {
        let accepted = await RuleSyncService.addRuleIfAllowed(rule, maxPerCategory: policy.maxActiveRulesPerTool)
        if !accepted {
            Self.logger.info("Rule quota reached for \(rule.action.toolCategory)")
        }
        return accepted
    }

    @discardableResult
    func toggleRule(id: UUID) async -> Bool {
        let accepted = await RuleSyncService.toggleRuleIfAllowed(
            id: id,
            maxPerCategory: policy.maxActiveRulesPerTool
        )
        if !accepted {
            Self.logger.info("Cannot toggle rule — quota reached")
        }
        return accepted
    }

    @discardableResult
    func setRuleEnabled(id: UUID, enabled: Bool) async -> Bool {
        let accepted = await RuleSyncService.setEnabledIfAllowed(
            id: id,
            enabled: enabled,
            maxPerCategory: policy.maxActiveRulesPerTool
        )
        if !accepted {
            Self.logger.info("Cannot enable rule — quota reached")
        }
        return accepted
    }

    func addNetworkConditionExclusive(_ rule: ProxyRule) async -> Bool {
        let accepted = await RuleSyncService.addNetworkConditionExclusiveIfAllowed(
            rule,
            maxPerCategory: policy.maxActiveRulesPerTool
        )
        if !accepted {
            Self.logger.info("Rule quota reached for networkCondition")
        }
        return accepted
    }

    // MARK: - Pass-Through Operations (no quota impact)

    func removeRule(id: UUID) async {
        await RuleSyncService.removeRule(id: id)
    }

    func updateRule(_ rule: ProxyRule) async {
        await RuleSyncService.updateRule(rule)
    }

    @discardableResult
    func enableExclusiveNetworkCondition(id: UUID) async -> Bool {
        let accepted = await RuleSyncService.enableExclusiveNetworkConditionIfAllowed(
            id: id,
            maxPerCategory: policy.maxActiveRulesPerTool
        )
        if !accepted {
            Self.logger.info("Cannot enable network condition — quota reached")
        }
        return accepted
    }

    func disableAllNetworkConditions() async {
        await RuleSyncService.disableAllNetworkConditions()
    }

    func replaceAllRules(_ rules: [ProxyRule]) async {
        let baseline = await RuleEngine.shared.allRules
        let capped = Self.capEnabledPerCategory(rules, limit: policy.maxActiveRulesPerTool, baseline: baseline)
        await RuleSyncService.replaceAllRules(capped)
    }

    func setBreakpointToolEnabled(_ enabled: Bool) async {
        await RuleSyncService.setBreakpointToolEnabled(enabled)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "RulePolicyGate"
    )

    private static func enabledCounts(in rules: [ProxyRule]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for rule in rules where rule.isEnabled {
            counts[rule.action.toolCategory, default: 0] += 1
        }
        return counts
    }

    private static func enabledIDsByCategory(in rules: [ProxyRule]) -> [String: Set<UUID>] {
        var result: [String: Set<UUID>] = [:]
        for rule in rules where rule.isEnabled {
            result[rule.action.toolCategory, default: []].insert(rule.id)
        }
        return result
    }
}
