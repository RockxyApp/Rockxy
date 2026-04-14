import Foundation
@testable import Rockxy
import Testing

// MARK: - RuleQuotaTests

/// Tests ``RulePolicyGate`` per-category active rule limits.
///
/// Counts pre-existing rules in the shared ``RuleEngine`` before seeding,
/// so tests are immune to cross-suite singleton pollution.
@Suite(.serialized)
@MainActor
struct RuleQuotaTests {
    // MARK: Internal

    // MARK: - Add / Toggle Quota

    @Test("Adding rule at quota is rejected")
    func addAtQuotaRejected() async {
        let baseline = await activeCount(for: "throttle")
        let gate = RulePolicyGate(policy: PolicyWithLimit(baseline + 2))

        let ids = await seedThrottleRules(count: 2)

        let rejected = await gate.addRule(makeThrottle())
        #expect(!rejected)

        await removeRules(ids)
    }

    @Test("Toggle-enable at quota is rejected")
    func toggleEnableAtQuota() async {
        let baseline = await activeCount(for: "throttle")
        let gate = RulePolicyGate(policy: PolicyWithLimit(baseline + 2))

        let ids = await seedThrottleRules(count: 2)

        var disabled = makeThrottle()
        disabled.isEnabled = false
        await RuleEngine.shared.addRule(disabled)

        let toggled = await gate.toggleRule(id: disabled.id)
        #expect(!toggled)

        await RuleEngine.shared.removeRule(id: disabled.id)
        await removeRules(ids)
    }

    @Test("Disabled rules do not count toward quota")
    func disabledRulesExcluded() async {
        let baseline = await activeCount(for: "throttle")
        let ids = await seedThrottleRules(count: 2)

        var disabled = makeThrottle()
        disabled.isEnabled = false
        await RuleEngine.shared.addRule(disabled)

        let allRules = await RuleEngine.shared.allRules
        let activeThrottle = allRules.filter { $0.isEnabled && $0.action.toolCategory == "throttle" }.count
        #expect(activeThrottle == baseline + 2)

        await RuleEngine.shared.removeRule(id: disabled.id)
        await removeRules(ids)
    }

    @Test("toolCategory mapping")
    func toolCategoryMapping() {
        #expect(RuleAction.block(statusCode: 403).toolCategory == "block")
        #expect(RuleAction.breakpoint().toolCategory == "breakpoint")
        #expect(RuleAction.mapLocal(filePath: "").toolCategory == "mapLocal")
        #expect(RuleAction.mapRemote(configuration: .init()).toolCategory == "mapRemote")
        #expect(RuleAction.modifyHeader(operations: []).toolCategory == "modifyHeader")
        #expect(RuleAction.throttle(delayMs: 100).toolCategory == "throttle")
        #expect(RuleAction.networkCondition(preset: .custom, delayMs: 0).toolCategory == "networkCondition")
    }

    // MARK: - Atomic Concurrent Enables

    @Test("Concurrent rule enables through engine are serialized")
    func concurrentRuleEnablesAreSerialized() async {
        let baseline = await activeCount(for: "throttle")
        let ids = await seedThrottleRules(count: 2)
        let limit = baseline + 3

        // Add 5 disabled throttle rules
        var disabledIDs: [UUID] = []
        for _ in 0 ..< 5 {
            var rule = makeThrottle()
            rule.isEnabled = false
            await RuleEngine.shared.addRule(rule)
            disabledIDs.append(rule.id)
        }

        // Try to enable all 5 concurrently — only 1 should succeed (limit = baseline+3, already have baseline+2)
        await withTaskGroup(of: Bool.self) { group in
            for id in disabledIDs {
                group.addTask {
                    await RuleEngine.shared.toggleRuleIfAllowed(id: id, maxPerCategory: limit)
                }
            }
            var accepted = 0
            for await ok in group where ok {
                accepted += 1
            }
            #expect(accepted == 1)
        }

        for id in disabledIDs {
            await RuleEngine.shared.removeRule(id: id)
        }
        await removeRules(ids)
    }

    // MARK: - Bulk Replace

    @Test("capEnabledPerCategory preserves already-enabled rules first")
    func bulkReplacePreservesAlreadyEnabled() {
        let ruleA = makeNamedRule(name: "A", action: .mapLocal(filePath: "/a"), enabled: true)
        let ruleB = makeNamedRule(name: "B", action: .mapLocal(filePath: "/b"), enabled: true)
        let ruleC = makeNamedRule(name: "C", action: .mapLocal(filePath: "/c"), enabled: false)

        let baseline: [ProxyRule] = [ruleA, ruleB, ruleC]

        // Bulk enable all 3
        var replacement = baseline
        replacement[2].isEnabled = true

        let capped = RulePolicyGate.capEnabledPerCategory(replacement, limit: 2, baseline: baseline)
        let enabledIDs = Set(capped.filter(\.isEnabled).map(\.id))

        // A and B were already enabled — they should survive. C is newly enabled — trimmed.
        #expect(enabledIDs.contains(ruleA.id))
        #expect(enabledIDs.contains(ruleB.id))
        #expect(!enabledIDs.contains(ruleC.id))
    }

    @Test("capEnabledPerCategory does not touch unrelated categories")
    func bulkReplacePreservesUnrelatedCategories() {
        let block = makeNamedRule(name: "B1", action: .block(statusCode: 403), enabled: true)
        let throttle = makeNamedRule(name: "T1", action: .throttle(delayMs: 100), enabled: true)

        let baseline: [ProxyRule] = [block, throttle]

        // Add 2 more blocks (exceeds limit of 2)
        var replacement = baseline
        replacement.append(makeNamedRule(name: "B2", action: .block(statusCode: 403), enabled: true))
        replacement.append(makeNamedRule(name: "B3", action: .block(statusCode: 403), enabled: true))

        let capped = RulePolicyGate.capEnabledPerCategory(replacement, limit: 2, baseline: baseline)
        let enabledBlocks = capped.filter { $0.isEnabled && $0.action.toolCategory == "block" }.count
        let enabledThrottles = capped.filter { $0.isEnabled && $0.action.toolCategory == "throttle" }.count

        #expect(enabledBlocks == 2)
        #expect(enabledThrottles == 1) // Untouched
    }

    // MARK: - Policy Injection (no cross-test pollution)

    @Test("Custom policy takes effect through .shared assignment")
    func customPolicyInjectable() {
        let saved = RulePolicyGate.shared
        defer { RulePolicyGate.shared = saved }

        RulePolicyGate.shared = RulePolicyGate(policy: PolicyWithLimit(5))
        #expect(RulePolicyGate.shared.policy.maxActiveRulesPerTool == 5)

        RulePolicyGate.shared = RulePolicyGate(policy: PolicyWithLimit(99))
        #expect(RulePolicyGate.shared.policy.maxActiveRulesPerTool == 99)
    }

    @Test("Coordinator construction does not pollute shared gate")
    func coordinatorDoesNotPolluteGate() {
        let saved = RulePolicyGate.shared
        defer { RulePolicyGate.shared = saved }

        RulePolicyGate.shared = RulePolicyGate(policy: PolicyWithLimit(42))

        // Creating a coordinator should NOT overwrite the shared gate
        _ = MainContentCoordinator(policy: PolicyWithLimit(7))
        #expect(RulePolicyGate.shared.policy.maxActiveRulesPerTool == 42)
    }

    // MARK: - Exclusive Network Condition Quota

    @Test("Exclusive network-condition enable respects injected quota")
    func exclusiveNetworkConditionRespectsQuota() async {
        // Create a gate with limit = 0 — no rules should be enableable
        let gate = RulePolicyGate(policy: PolicyWithLimit(0))

        let rule = ProxyRule(
            name: "NetCond",
            isEnabled: false,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .networkCondition(preset: .custom, delayMs: 100)
        )
        await RuleEngine.shared.addRule(rule)

        let accepted = await gate.enableExclusiveNetworkCondition(id: rule.id)
        #expect(!accepted)

        // Rule should still be disabled in the engine
        let allRules = await RuleEngine.shared.allRules
        let found = allRules.first { $0.id == rule.id }
        #expect(found?.isEnabled == false)

        await RuleEngine.shared.removeRule(id: rule.id)
    }

    @Test("Switching exclusive network conditions succeeds at limit = 1")
    func exclusiveNetworkConditionSwitchAtLimitOne() async {
        let gate = RulePolicyGate(policy: PolicyWithLimit(1))

        let ruleA = ProxyRule(
            name: "NetCondA",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*a.*"),
            action: .networkCondition(preset: .custom, delayMs: 100)
        )
        let ruleB = ProxyRule(
            name: "NetCondB",
            isEnabled: false,
            matchCondition: RuleMatchCondition(urlPattern: ".*b.*"),
            action: .networkCondition(preset: .custom, delayMs: 200)
        )
        await RuleEngine.shared.addRule(ruleA)
        await RuleEngine.shared.addRule(ruleB)

        // With limit=1 and ruleA already active, switching to ruleB must succeed
        // because the exclusive enable disables ruleA first → post-switch count is 1
        let accepted = await gate.enableExclusiveNetworkCondition(id: ruleB.id)
        #expect(accepted)

        let allRules = await RuleEngine.shared.allRules
        let activeA = allRules.first { $0.id == ruleA.id }
        let activeB = allRules.first { $0.id == ruleB.id }
        #expect(activeA?.isEnabled == false)
        #expect(activeB?.isEnabled == true)

        await RuleEngine.shared.removeRule(id: ruleA.id)
        await RuleEngine.shared.removeRule(id: ruleB.id)
    }

    // MARK: - setEnabledIfAllowed No-Op Success

    @Test("Enabling an already-enabled rule is a no-op success")
    func setEnabledAlreadyEnabledIsNoOp() async {
        let baseline = await activeCount(for: "throttle")
        let ids = await seedThrottleRules(count: 1)
        let limit = baseline + 1

        // Rule is already enabled; setEnabledIfAllowed(enabled: true) must succeed
        let accepted = await RuleEngine.shared.setEnabledIfAllowed(
            id: ids[0],
            enabled: true,
            maxPerCategory: limit
        )
        #expect(accepted)

        await removeRules(ids)
    }

    // MARK: - addNetworkConditionExclusiveIfAllowed Regression

    @Test("Adding enabled network condition with one already active at limit 1 succeeds")
    func addNetworkConditionExclusiveReplacesAtLimit() async {
        let ruleA = ProxyRule(
            name: "NetCondA",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*a.*"),
            action: .networkCondition(preset: .custom, delayMs: 100)
        )
        await RuleEngine.shared.addRule(ruleA)

        let ruleB = ProxyRule(
            name: "NetCondB",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*b.*"),
            action: .networkCondition(preset: .custom, delayMs: 200)
        )

        let accepted = await RuleEngine.shared.addNetworkConditionExclusiveIfAllowed(
            ruleB,
            maxPerCategory: 1
        )
        #expect(accepted)

        let allRules = await RuleEngine.shared.allRules
        let activeA = allRules.first { $0.id == ruleA.id }
        let activeB = allRules.first { $0.id == ruleB.id }
        #expect(activeA?.isEnabled == false)
        #expect(activeB?.isEnabled == true)

        await RuleEngine.shared.removeRule(id: ruleA.id)
        await RuleEngine.shared.removeRule(id: ruleB.id)
    }

    // MARK: - capEnabledPerCategory Baseline-Over-Limit Regression

    @Test("capEnabledPerCategory caps when baseline already exceeds limit")
    func capWhenBaselineAlreadyOverLimit() {
        // Baseline has 3 enabled mapLocal rules, limit is 2
        let ruleA = makeNamedRule(name: "A", action: .mapLocal(filePath: "/a"), enabled: true)
        let ruleB = makeNamedRule(name: "B", action: .mapLocal(filePath: "/b"), enabled: true)
        let ruleC = makeNamedRule(name: "C", action: .mapLocal(filePath: "/c"), enabled: true)
        let baseline: [ProxyRule] = [ruleA, ruleB, ruleC]

        // New set is same as baseline (still 3 enabled, still over limit of 2)
        let capped = RulePolicyGate.capEnabledPerCategory(baseline, limit: 2, baseline: baseline)
        let enabledCount = capped.filter { $0.isEnabled && $0.action.toolCategory == "mapLocal" }.count
        #expect(enabledCount == 2)
    }

    // MARK: - Rule Loading Race Regression

    @Test("ruleLoadTask is nil on fresh coordinator")
    func ruleLoadTaskInitialState() {
        let coordinator = MainContentCoordinator()
        #expect(coordinator.ruleLoadTask == nil)
        #expect(!coordinator.rulesLoaded)
    }

    @Test("loadInitialRules fires async load without blocking")
    func loadInitialRulesIsAsync() {
        let coordinator = MainContentCoordinator()
        coordinator.loadInitialRules()
        // Task is stored but not yet completed
        #expect(coordinator.ruleLoadTask != nil)
        #expect(!coordinator.rulesLoaded)
    }

    // MARK: Private

    private func activeCount(for category: String) async -> Int {
        await RuleEngine.shared.allRules
            .filter { $0.isEnabled && $0.action.toolCategory == category }.count
    }

    private func makeThrottle() -> ProxyRule {
        ProxyRule(
            name: "QuotaTest",
            matchCondition: RuleMatchCondition(urlPattern: ".*quota-test-throttle.*"),
            action: .throttle(delayMs: 999)
        )
    }

    private func makeNamedRule(name: String, action: RuleAction, enabled: Bool) -> ProxyRule {
        var rule = ProxyRule(
            name: name,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: action
        )
        rule.isEnabled = enabled
        return rule
    }

    private func seedThrottleRules(count: Int) async -> [UUID] {
        var ids: [UUID] = []
        for _ in 0 ..< count {
            let rule = makeThrottle()
            await RuleEngine.shared.addRule(rule)
            ids.append(rule.id)
        }
        return ids
    }

    private func removeRules(_ ids: [UUID]) async {
        for id in ids {
            await RuleEngine.shared.removeRule(id: id)
        }
    }
}

// MARK: - PolicyWithLimit

private struct PolicyWithLimit: AppPolicy {
    // MARK: Lifecycle

    init(_ maxRules: Int) {
        maxActiveRulesPerTool = maxRules
    }

    // MARK: Internal

    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool: Int
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
}
