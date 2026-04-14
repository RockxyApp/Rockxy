import Foundation
@testable import Rockxy
import Testing

// Regression tests for `RuleSyncService` in the core rule engine layer.

@Suite(.serialized)
struct RuleSyncServiceTests {
    // MARK: Internal

    @Test("addRule adds to RuleEngine.shared")
    func addRuleSync() async {
        let backup = await backupRules()

        await RuleSyncService.replaceAllRules([])

        let rule = ProxyRule(
            name: "Test Rule",
            matchCondition: RuleMatchCondition(urlPattern: ".*test.*"),
            action: .block(statusCode: 403)
        )
        await RuleSyncService.addRule(rule)

        let allRules = await RuleEngine.shared.allRules
        #expect(allRules.contains(where: { $0.id == rule.id }))

        await restoreRules(backup)
    }

    @Test("removeRule removes from RuleEngine.shared")
    func removeRuleSync() async {
        let backup = await backupRules()

        let rule = ProxyRule(
            name: "Temp",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .block(statusCode: 403)
        )
        await RuleSyncService.replaceAllRules([rule])

        await RuleSyncService.removeRule(id: rule.id)

        let allRules = await RuleEngine.shared.allRules
        #expect(!allRules.contains(where: { $0.id == rule.id }))

        await restoreRules(backup)
    }

    @Test("updateRule updates in RuleEngine.shared")
    func updateRuleSync() async {
        let backup = await backupRules()

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

        await restoreRules(backup)
    }

    // MARK: Private

    private struct RulesBackup {
        let diskData: Data?
        let engineRules: [ProxyRule]
    }

    private static let rulesPath: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport
            .appendingPathComponent(TestIdentity.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(TestIdentity.rulesPathComponent)
    }()

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
}
