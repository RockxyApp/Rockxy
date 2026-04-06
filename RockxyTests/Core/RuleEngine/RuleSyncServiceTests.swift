import Foundation
@testable import Rockxy
import Testing

// Regression tests for `RuleSyncService` in the core rule engine layer.

@Suite(.serialized)
@MainActor
struct RuleSyncServiceTests {
    // MARK: Internal

    @Test("addRule adds to RuleEngine.shared")
    func addRuleSync() async {
        let backup = backupRules()
        defer { restoreRules(backup) }

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

    @Test("removeRule removes from RuleEngine.shared")
    func removeRuleSync() async {
        let backup = backupRules()
        defer { restoreRules(backup) }

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

    @Test("updateRule updates in RuleEngine.shared")
    func updateRuleSync() async {
        let backup = backupRules()
        defer { restoreRules(backup) }

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

    // MARK: Private

    private static let rulesPath: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport
            .appendingPathComponent(TestIdentity.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(TestIdentity.rulesPathComponent)
    }()

    private func backupRules() -> Data? {
        try? Data(contentsOf: Self.rulesPath)
    }

    private func restoreRules(_ data: Data?) {
        if let data {
            try? data.write(to: Self.rulesPath)
        } else {
            try? FileManager.default.removeItem(at: Self.rulesPath)
        }
    }
}
