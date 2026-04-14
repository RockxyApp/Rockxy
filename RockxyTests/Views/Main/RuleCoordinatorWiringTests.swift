import Foundation
@testable import Rockxy
import Testing

// MARK: - RuleCoordinatorWiringTests

/// Tests that coordinator-level rule operations fire through `RulePolicyGate`
/// and surface quota rejections via `activeToast`. Uses `Task.sleep` for
/// cooperative yield following the same convention as `AllowListCoordinatorWiringTests`.
@Suite(.serialized)
@MainActor
struct RuleCoordinatorWiringTests {
    // MARK: - Add Rule

    @Test("addRule success fires notification and sets no toast")
    func addRuleSuccess() async {
        let saved = RulePolicyGate.shared
        defer { RulePolicyGate.shared = saved }
        RulePolicyGate.shared = RulePolicyGate(policy: LargePolicy())

        let coordinator = MainContentCoordinator()
        await RuleSyncService.replaceAllRules([])

        let rule = TestFixtures.makeRule(name: "WiringAdd", action: .block(statusCode: 403))

        // Wait for .rulesDidChange deterministically instead of fixed sleep
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
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

        await RuleSyncService.replaceAllRules([])
    }

    @Test("addRule at quota sets error toast")
    func addRuleAtQuota() async {
        let saved = RulePolicyGate.shared
        defer { RulePolicyGate.shared = saved }

        await RuleSyncService.replaceAllRules([])
        let existing = TestFixtures.makeRule(name: "Existing", action: .block(statusCode: 403))
        _ = await RulePolicyGate.shared.addRule(existing)

        RulePolicyGate.shared = RulePolicyGate(policy: TinyRulePolicy())

        let coordinator = MainContentCoordinator()
        let overflow = TestFixtures.makeRule(name: "Overflow", action: .block(statusCode: 403))

        // Rejection path does NOT call syncAll — poll for toast
        coordinator.addRule(overflow)
        for _ in 0 ..< 200 {
            if coordinator.activeToast != nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(coordinator.activeToast != nil)
        #expect(coordinator.activeToast?.style == .error)

        let engineRules = await RuleEngine.shared.allRules
        #expect(!engineRules.contains { $0.id == overflow.id })

        await RuleSyncService.replaceAllRules([])
    }

    // MARK: - Toggle Rule

    @Test("toggleRule disable fires notification and sets no toast")
    func toggleRuleDisable() async {
        let saved = RulePolicyGate.shared
        defer { RulePolicyGate.shared = saved }
        RulePolicyGate.shared = RulePolicyGate(policy: LargePolicy())

        await RuleSyncService.replaceAllRules([])
        let rule = TestFixtures.makeRule(name: "Toggle", action: .throttle(delayMs: 100))
        _ = await RulePolicyGate.shared.addRule(rule)

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
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

        await RuleSyncService.replaceAllRules([])
    }

    @Test("toggleRule enable at quota sets error toast")
    func toggleRuleEnableAtQuota() async {
        let saved = RulePolicyGate.shared
        defer { RulePolicyGate.shared = saved }

        await RuleSyncService.replaceAllRules([])
        let active = TestFixtures.makeRule(name: "Active", action: .throttle(delayMs: 100))
        _ = await RulePolicyGate.shared.addRule(active)

        var disabled = TestFixtures.makeRule(name: "Disabled", action: .throttle(delayMs: 200))
        disabled.isEnabled = false
        await RuleEngine.shared.addRule(disabled)

        RulePolicyGate.shared = RulePolicyGate(policy: TinyRulePolicy())

        let coordinator = MainContentCoordinator()

        // Poll for toast (deterministic, no timing dependency)
        coordinator.toggleRule(id: disabled.id)
        for _ in 0 ..< 200 {
            if coordinator.activeToast != nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(coordinator.activeToast != nil)
        #expect(coordinator.activeToast?.style == .error)

        // Verify the blocked rule stayed disabled in the engine
        let engineRules = await RuleEngine.shared.allRules
        let blocked = engineRules.first { $0.id == disabled.id }
        #expect(blocked?.isEnabled == false)

        await RuleSyncService.replaceAllRules([])
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
