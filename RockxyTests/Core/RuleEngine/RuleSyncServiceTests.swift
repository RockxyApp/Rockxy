import Foundation
@testable import Rockxy
import Testing

// Regression tests for `RuleSyncService` in the core rule engine layer.

@Suite(.serialized)
struct RuleSyncServiceTests {
    // MARK: Internal

    @Test("addRule adds to RuleEngine.shared")
    func addRuleSync() async {
        // Swift's `defer` cannot await, so cleanup is handled through a wrapper that
        // always restores shared state and releases the lock after the body — including
        // if the body records an `Issue` or future revisions add throwing paths.
        await withRuleTestLock { [self] in
            await RuleSyncService.replaceAllRules([])

            let rule = ProxyRule(
                name: "Test Rule",
                matchCondition: RuleMatchCondition(urlPattern: ".*test.*"),
                action: .block(statusCode: 403)
            )
            await RuleSyncService.addRule(rule)

            let allRules = await RuleEngine.shared.allRules
            #expect(allRules.contains(where: { $0.id == rule.id }))
        }
    }

    @Test("removeRule removes from RuleEngine.shared")
    func removeRuleSync() async {
        await withRuleTestLock { [self] in
            let rule = ProxyRule(
                name: "Temp",
                matchCondition: RuleMatchCondition(urlPattern: ".*"),
                action: .block(statusCode: 403)
            )
            await RuleSyncService.replaceAllRules([rule])

            await RuleSyncService.removeRule(id: rule.id)

            let allRules = await RuleEngine.shared.allRules
            #expect(!allRules.contains(where: { $0.id == rule.id }))
        }
    }

    @Test("updateRule updates in RuleEngine.shared")
    func updateRuleSync() async {
        await withRuleTestLock { [self] in
            var rule = ProxyRule(
                name: "Original",
                matchCondition: RuleMatchCondition(urlPattern: ".*"),
                action: .block(statusCode: 403)
            )
            await RuleSyncService.replaceAllRules([rule])

            rule.name = "Updated"
            await RuleSyncService.updateRule(rule)

            let allRules = await RuleEngine.shared.allRules
            let found = allRules.first(where: { $0.id == rule.id })
            #expect(found?.name == "Updated")
        }
    }

    @Test("setNetworkConditionsToolEnabled persists UserDefaults and updates evaluation gate")
    func setNetworkConditionsToolEnabledPersistsAndUpdatesGate() async throws {
        await withRuleTestLock { [self] in
            let defaultsBackup = backupNetworkConditionsToolDefault()
            let networkRule = ProxyRule(
                name: "3G API",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
                action: .networkCondition(preset: .threeG, delayMs: 400)
            )
            let throttleRule = ProxyRule(
                name: "Fallback",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
                action: .throttle(delayMs: 250)
            )
            await RuleSyncService.replaceAllRules([networkRule, throttleRule])

            await RuleSyncService.setNetworkConditionsToolEnabled(false)

            #expect(UserDefaults.standard.object(forKey: Self.networkConditionsToolEnabledKey) as? Bool == false)
            guard let url = URL(string: "https://example.com/test") else {
                Issue.record("Expected test URL to be valid")
                restoreNetworkConditionsToolDefault(defaultsBackup)
                return
            }
            let disabledResult = await RuleEngine.shared.evaluate(method: "GET", url: url, headers: [])
            if case let .throttle(delayMs) = disabledResult {
                #expect(delayMs == 250)
            } else {
                Issue.record("Expected fallback throttle rule while Network Conditions tool is disabled")
            }

            await RuleSyncService.setNetworkConditionsToolEnabled(true)
            #expect(UserDefaults.standard.object(forKey: Self.networkConditionsToolEnabledKey) as? Bool == true)

            restoreNetworkConditionsToolDefault(defaultsBackup)
        }
    }

    @Test("loadFromDisk applies persisted Network Conditions tool gate")
    func loadFromDiskAppliesNetworkConditionsToolEnabled() async {
        await withRuleTestLock { [self] in
            let defaultsBackup = backupNetworkConditionsToolDefault()
            let networkRule = ProxyRule(
                name: "3G API",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
                action: .networkCondition(preset: .threeG, delayMs: 400)
            )
            let throttleRule = ProxyRule(
                name: "Fallback",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
                action: .throttle(delayMs: 250)
            )
            await RuleSyncService.replaceAllRules([networkRule, throttleRule])
            UserDefaults.standard.set(false, forKey: Self.networkConditionsToolEnabledKey)

            await RuleEngine.shared.setNetworkConditionsToolEnabled(true)
            await RuleSyncService.loadFromDisk()
            await RuleEngine.shared.replaceAll([networkRule, throttleRule])

            guard let url = URL(string: "https://example.com/test") else {
                Issue.record("Expected test URL to be valid")
                restoreNetworkConditionsToolDefault(defaultsBackup)
                return
            }
            let result = await RuleEngine.shared.evaluate(method: "GET", url: url, headers: [])
            if case let .throttle(delayMs) = result {
                #expect(delayMs == 250)
            } else {
                Issue.record("Expected persisted disabled gate to skip network condition after load")
            }

            restoreNetworkConditionsToolDefault(defaultsBackup)
            await RuleEngine.shared.setNetworkConditionsToolEnabled(true)
        }
    }

    @Test("loadFromDisk does not overwrite persisted rules when decoding fails")
    func loadFromDiskPreservesPersistedRulesOnDecodeFailure() async {
        await withRuleTestLock { [self] in
            let invalidData = Data(#"{"not":"a rule list"}"#.utf8)
            try? FileManager.default.createDirectory(
                at: Self.rulesPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? invalidData.write(to: Self.rulesPath, options: .atomic)
            await RuleEngine.shared.replaceAll([])

            await RuleSyncService.loadFromDisk()

            let storedData = try? Data(contentsOf: Self.rulesPath)
            let engineRules = await RuleEngine.shared.allRules
            #expect(storedData == invalidData)
            #expect(engineRules.isEmpty)
        }
    }

    @Test("setBreakpointToolEnabled persists UserDefaults and updates breakpoint matcher gate")
    func setBreakpointToolEnabledPersistsAndUpdatesGate() async {
        await withRuleTestLock { [self] in
            let defaultsBackup = backupBreakpointToolDefault()
            let breakpointRule = ProxyRule(
                name: "Auth Profile Breakpoint",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com/profile.*", method: "GET"),
                action: .breakpoint(phase: .both)
            )
            await RuleSyncService.replaceAllRules([breakpointRule])

            guard let url = URL(string: "https://example.com/profile") else {
                Issue.record("Expected test URL to be valid")
                restoreBreakpointToolDefault(defaultsBackup)
                await RuleEngine.shared.setBreakpointToolEnabled(true)
                return
            }

            await RuleSyncService.setBreakpointToolEnabled(false)

            #expect(UserDefaults.standard.object(forKey: Self.breakpointToolEnabledKey) as? Bool == false)
            let disabledResult = await RuleEngine.shared.evaluateBreakpointRule(method: "GET", url: url, headers: [])
            #expect(disabledResult == nil)

            await RuleSyncService.setBreakpointToolEnabled(true)

            #expect(UserDefaults.standard.object(forKey: Self.breakpointToolEnabledKey) as? Bool == true)
            let enabledResult = await RuleEngine.shared.evaluateBreakpointRule(method: "GET", url: url, headers: [])
            #expect(enabledResult?.id == breakpointRule.id)

            restoreBreakpointToolDefault(defaultsBackup)
            await RuleEngine.shared.setBreakpointToolEnabled(defaultsBackup ?? true)
        }
    }

    // MARK: Private

    private struct RulesBackup {
        let diskData: Data?
        let engineRules: [ProxyRule]
    }

    private static let breakpointToolEnabledKey = "breakpointToolEnabled"
    private static let networkConditionsToolEnabledKey = "networkConditionsToolEnabled"

    private static let rulesPath = RockxyIdentity.current.appSupportPath(TestIdentity.rulesPathComponent)

    private func backupRules() async -> RulesBackup {
        let diskData = try? Data(contentsOf: Self.rulesPath)
        let engineRules = await RuleEngine.shared.allRules
        return RulesBackup(diskData: diskData, engineRules: engineRules)
    }

    private func restoreRules(_ backup: RulesBackup) async {
        if let data = backup.diskData {
            try? data.write(to: Self.rulesPath)
        } else {
            try? FileManager.default.removeItem(at: Self.rulesPath)
        }
        await RuleEngine.shared.replaceAll(backup.engineRules)
    }

    private func backupNetworkConditionsToolDefault() -> Bool? {
        UserDefaults.standard.object(forKey: Self.networkConditionsToolEnabledKey) as? Bool
    }

    private func restoreNetworkConditionsToolDefault(_ value: Bool?) {
        if let value {
            UserDefaults.standard.set(value, forKey: Self.networkConditionsToolEnabledKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.networkConditionsToolEnabledKey)
        }
    }

    private func backupBreakpointToolDefault() -> Bool? {
        UserDefaults.standard.object(forKey: Self.breakpointToolEnabledKey) as? Bool
    }

    private func restoreBreakpointToolDefault(_ value: Bool?) {
        if let value {
            UserDefaults.standard.set(value, forKey: Self.breakpointToolEnabledKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.breakpointToolEnabledKey)
        }
    }

    /// Runs `body` between `RuleTestLock` acquire/release with shared rule state
    /// backed up and restored afterwards. Swift's `defer` cannot await, so the
    /// cleanup is inlined here and executed unconditionally after the body returns.
    private func withRuleTestLock(_ body: () async -> Void) async {
        await RuleTestLock.shared.acquire()
        let backup = await backupRules()
        await body()
        await restoreRules(backup)
        await RuleTestLock.shared.release()
    }
}
