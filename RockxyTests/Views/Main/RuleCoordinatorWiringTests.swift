import Foundation
@testable import Rockxy
import Testing

// MARK: - RuleCoordinatorWiringTests

/// Tests that coordinator-level rule operations fire through `RulePolicyGate`
/// and surface quota rejections via `activeToast`.
///
/// Uses `RuleEngine.shared.replaceAll()` instead of `RuleSyncService.replaceAllRules()`
/// to avoid disk I/O contention in full-suite parallel runs.
@Suite(.serialized)
@MainActor
struct RuleCoordinatorWiringTests {
    // MARK: - Add Rule

    @Test("addRule success fires notification and sets no toast")
    func addRuleSuccess() async {
        let saved = RulePolicyGate.shared
        let engineSnapshot = await RuleEngine.shared.allRules
        defer {
            RulePolicyGate.shared = saved
            Task { await RuleEngine.shared.replaceAll(engineSnapshot) }
        }
        RulePolicyGate.shared = RulePolicyGate(policy: LargePolicy())

        let coordinator = MainContentCoordinator()
        await RuleEngine.shared.replaceAll([])

        let rule = TestFixtures.makeRule(name: "WiringAdd", action: .block(statusCode: 403))

        // Wait for .rulesDidChange deterministically
        await withCheckedContinuation { continuation in
            var resumed = false
            let observer = NotificationCenter.default.addObserver(
                forName: .rulesDidChange, object: nil, queue: .main
            ) { _ in
                guard !resumed else {
                    return
                }
                resumed = true
                continuation.resume()
            }
            coordinator.addRule(rule)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                guard !resumed else {
                    return
                }
                resumed = true
                NotificationCenter.default.removeObserver(observer)
                continuation.resume()
            }
        }

        #expect(coordinator.activeToast == nil)

        let engineRules = await RuleEngine.shared.allRules
        #expect(engineRules.contains { $0.id == rule.id })
    }

    @Test("addRule at quota sets error toast")
    func addRuleAtQuota() async {
        let saved = RulePolicyGate.shared
        let engineSnapshot = await RuleEngine.shared.allRules
        defer {
            RulePolicyGate.shared = saved
            Task { await RuleEngine.shared.replaceAll(engineSnapshot) }
        }

        await RuleEngine.shared.replaceAll([])
        let existing = TestFixtures.makeRule(name: "Existing", action: .block(statusCode: 403))
        await RuleEngine.shared.addRule(existing)

        RulePolicyGate.shared = RulePolicyGate(policy: TinyRulePolicy())

        let coordinator = MainContentCoordinator()
        let overflow = TestFixtures.makeRule(name: "Overflow", action: .block(statusCode: 403))

        // Rejection path — poll for toast
        coordinator.addRule(overflow)
        for _ in 0 ..< 500 {
            if coordinator.activeToast != nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(coordinator.activeToast != nil)
        #expect(coordinator.activeToast?.style == .error)

        let engineRules = await RuleEngine.shared.allRules
        #expect(!engineRules.contains { $0.id == overflow.id })
    }

    // MARK: - Toggle Rule

    @Test("toggleRule disable fires notification and sets no toast")
    func toggleRuleDisable() async {
        let saved = RulePolicyGate.shared
        let engineSnapshot = await RuleEngine.shared.allRules
        defer {
            RulePolicyGate.shared = saved
            Task { await RuleEngine.shared.replaceAll(engineSnapshot) }
        }
        RulePolicyGate.shared = RulePolicyGate(policy: LargePolicy())

        await RuleEngine.shared.replaceAll([])
        let rule = TestFixtures.makeRule(name: "Toggle", action: .throttle(delayMs: 100))
        await RuleEngine.shared.addRule(rule)

        let coordinator = MainContentCoordinator()

        // Wait for .rulesDidChange deterministically
        await withCheckedContinuation { continuation in
            var resumed = false
            let observer = NotificationCenter.default.addObserver(
                forName: .rulesDidChange, object: nil, queue: .main
            ) { _ in
                guard !resumed else {
                    return
                }
                resumed = true
                continuation.resume()
            }
            coordinator.toggleRule(id: rule.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                guard !resumed else {
                    return
                }
                resumed = true
                NotificationCenter.default.removeObserver(observer)
                continuation.resume()
            }
        }

        #expect(coordinator.activeToast == nil)

        let engineRules = await RuleEngine.shared.allRules
        let toggled = engineRules.first { $0.id == rule.id }
        #expect(toggled?.isEnabled == false)
    }

    @Test("toggleRule enable at quota sets error toast")
    func toggleRuleEnableAtQuota() async {
        let saved = RulePolicyGate.shared
        let engineSnapshot = await RuleEngine.shared.allRules
        defer {
            RulePolicyGate.shared = saved
            Task { await RuleEngine.shared.replaceAll(engineSnapshot) }
        }

        await RuleEngine.shared.replaceAll([])
        let active = TestFixtures.makeRule(name: "Active", action: .throttle(delayMs: 100))
        await RuleEngine.shared.addRule(active)

        var disabled = TestFixtures.makeRule(name: "Disabled", action: .throttle(delayMs: 200))
        disabled.isEnabled = false
        await RuleEngine.shared.addRule(disabled)

        RulePolicyGate.shared = RulePolicyGate(policy: TinyRulePolicy())

        let coordinator = MainContentCoordinator()

        // Poll for toast
        coordinator.toggleRule(id: disabled.id)
        for _ in 0 ..< 500 {
            if coordinator.activeToast != nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(coordinator.activeToast != nil)
        #expect(coordinator.activeToast?.style == .error)

        let engineRules = await RuleEngine.shared.allRules
        let blocked = engineRules.first { $0.id == disabled.id }
        #expect(blocked?.isEnabled == false)
    }
}

// MARK: - TinyRulePolicy

private struct TinyRulePolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 1
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
}

// MARK: - LargePolicy

private struct LargePolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 100
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
}
