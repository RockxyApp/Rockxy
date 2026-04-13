import Foundation
@testable import Rockxy
import Testing

// MARK: - SSLProxyingManagerTests

@MainActor
struct SSLProxyingManagerTests {
    // MARK: Internal

    // MARK: - CRUD

    @Test("addRule appends and persists")
    func addRule() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "example.com"))
        #expect(manager.rules.count == 1)
        #expect(manager.rules[0].domain == "example.com")
    }

    @Test("addRule with include type")
    func addRuleInclude() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "inc.com", listType: .include))
        #expect(manager.includeRules.count == 1)
        #expect(manager.excludeRules.isEmpty)
    }

    @Test("addRule with exclude type")
    func addRuleExclude() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "exc.com", listType: .exclude))
        #expect(manager.excludeRules.count == 1)
        #expect(manager.includeRules.isEmpty)
    }

    @Test("removeRule removes by ID")
    func removeRule() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "test.com"))
        let id = manager.rules[0].id
        manager.removeRule(id: id)
        #expect(manager.rules.isEmpty)
    }

    @Test("removeRules batch removes by IDs")
    func batchRemove() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "a.com"))
        manager.addRule(SSLProxyingRule(domain: "b.com"))
        manager.addRule(SSLProxyingRule(domain: "c.com"))
        let ids = Set(manager.rules.prefix(2).map(\.id))
        manager.removeRules(ids: ids)
        #expect(manager.rules.count == 1)
        #expect(manager.rules[0].domain == "c.com")
    }

    @Test("toggleRule toggles isEnabled")
    func toggleRule() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "test.com"))
        let id = manager.rules[0].id
        #expect(manager.rules[0].isEnabled == true)
        manager.toggleRule(id: id)
        #expect(manager.rules[0].isEnabled == false)
        manager.toggleRule(id: id)
        #expect(manager.rules[0].isEnabled == true)
    }

    @Test("updateRule replaces rule in-place")
    func updateRule() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "old.com"))
        var rule = manager.rules[0]
        rule.domain = "new.com"
        manager.updateRule(rule)
        #expect(manager.rules[0].domain == "new.com")
        #expect(manager.rules.count == 1)
    }

    @Test("replaceAllRules replaces entire list")
    func replaceAllRules() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "old.com"))
        let newRules = [
            SSLProxyingRule(domain: "new1.com"),
            SSLProxyingRule(domain: "new2.com"),
        ]
        manager.replaceAllRules(newRules)
        #expect(manager.rules.count == 2)
        #expect(manager.rules[0].domain == "new1.com")
    }

    // MARK: - Enable/Disable

    @Test("setEnabled toggles isEnabled state")
    func setEnabled() {
        let manager = makeManager()
        #expect(manager.isEnabled == true)
        manager.setEnabled(false)
        #expect(manager.isEnabled == false)
        manager.setEnabled(true)
        #expect(manager.isEnabled == true)
    }

    // MARK: - shouldIntercept

    @Test("shouldIntercept returns false when include list is empty (opt-in)")
    func interceptEmptyList() {
        let manager = makeManager()
        #expect(!manager.shouldIntercept("anything.com"))
    }

    @Test("shouldIntercept returns true for matching include rule")
    func interceptIncludeMatch() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "*.example.com", listType: .include))
        #expect(manager.shouldIntercept("api.example.com"))
    }

    @Test("shouldIntercept returns false for non-matching include rule")
    func interceptIncludeNoMatch() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "*.example.com", listType: .include))
        #expect(!manager.shouldIntercept("other.com"))
    }

    @Test("shouldIntercept returns false for exclude rule even with include match")
    func interceptExcludeOverridesInclude() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "*.example.com", listType: .include))
        manager.addRule(SSLProxyingRule(domain: "secret.example.com", listType: .exclude))
        #expect(!manager.shouldIntercept("secret.example.com"))
        #expect(manager.shouldIntercept("api.example.com"))
    }

    @Test("shouldIntercept returns false when disabled")
    func interceptDisabled() {
        let manager = makeManager()
        manager.setEnabled(false)
        #expect(!manager.shouldIntercept("anything.com"))
    }

    @Test("shouldIntercept skips disabled include rules")
    func interceptDisabledRule() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "disabled.com", listType: .include))
        manager.addRule(SSLProxyingRule(domain: "enabled.com", listType: .include))
        manager.toggleRule(id: manager.rules[0].id)
        #expect(!manager.shouldIntercept("disabled.com"))
        #expect(manager.shouldIntercept("enabled.com"))
    }

    @Test("shouldIntercept returns false when forceGlobalPassthrough is set")
    func interceptGlobalPassthrough() {
        let manager = makeManager()
        manager.forceGlobalPassthrough = true
        #expect(!manager.shouldIntercept("anything.com"))
        manager.forceGlobalPassthrough = false
    }

    // MARK: - Bypass Domains

    @Test("shouldIntercept returns false for bypass domain")
    func interceptBypassDomain() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        manager.setBypassDomains("dns.google,ocsp.digicert.com")
        #expect(!manager.shouldIntercept("dns.google"))
        #expect(!manager.shouldIntercept("ocsp.digicert.com"))
        #expect(manager.shouldIntercept("other.com"))
    }

    @Test("setBypassDomains persists")
    func setBypassDomains() {
        let manager = makeManager()
        manager.setBypassDomains("custom.com,other.com")
        #expect(manager.bypassDomains == "custom.com,other.com")
    }

    @Test("resetBypassToDefault restores defaults")
    func resetBypassToDefault() {
        let manager = makeManager()
        manager.setBypassDomains("custom.com")
        manager.resetBypassToDefault()
        #expect(manager.bypassDomains == SSLProxyingManager.defaultBypassDomains)
    }

    // MARK: - Include/Exclude Computed Properties

    @Test("includeRules returns only include type")
    func includeRulesFilter() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "inc.com", listType: .include))
        manager.addRule(SSLProxyingRule(domain: "exc.com", listType: .exclude))
        #expect(manager.includeRules.count == 1)
        #expect(manager.includeRules[0].domain == "inc.com")
    }

    @Test("excludeRules returns only exclude type")
    func excludeRulesFilter() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "inc.com", listType: .include))
        manager.addRule(SSLProxyingRule(domain: "exc.com", listType: .exclude))
        #expect(manager.excludeRules.count == 1)
        #expect(manager.excludeRules[0].domain == "exc.com")
    }

    // MARK: - Persistence

    @Test("save and load roundtrip preserves rules and settings")
    func persistenceRoundtrip() {
        let url = makeTempURL()
        let manager1 = SSLProxyingManager(storageURL: url)
        manager1.addRule(SSLProxyingRule(domain: "persisted.com", listType: .include))
        manager1.addRule(SSLProxyingRule(domain: "excluded.com", listType: .exclude))
        manager1.setEnabled(false)
        manager1.setBypassDomains("custom.bypass.com")

        let manager2 = SSLProxyingManager(storageURL: url)
        #expect(manager2.rules.count == 2)
        #expect(manager2.isEnabled == false)
        #expect(manager2.bypassDomains == "custom.bypass.com")
        #expect(manager2.includeRules[0].domain == "persisted.com")
        #expect(manager2.excludeRules[0].domain == "excluded.com")
    }

    @Test("load migrates legacy v1 format")
    func legacyMigration() throws {
        let url = makeTempURL()
        let legacyRules = [
            SSLProxyingRule(domain: "legacy1.com"),
            SSLProxyingRule(domain: "legacy2.com"),
        ]
        let data = try JSONEncoder().encode(legacyRules)
        try data.write(to: url)

        let manager = SSLProxyingManager(storageURL: url)
        #expect(manager.rules.count == 2)
        #expect(manager.rules.allSatisfy { $0.listType == .include })
        #expect(manager.isEnabled == true)
        #expect(manager.bypassDomains == SSLProxyingManager.defaultBypassDomains)
    }

    // MARK: - Export/Import

    @Test("export and import roundtrip")
    func exportImportRoundtrip() throws {
        let manager1 = makeManager()
        manager1.addRule(SSLProxyingRule(domain: "a.com", listType: .include))
        manager1.addRule(SSLProxyingRule(domain: "b.com", listType: .exclude))
        manager1.setEnabled(false)

        guard let data = manager1.exportRules() else {
            #expect(Bool(false), "Export returned nil")
            return
        }

        let manager2 = makeManager()
        try manager2.importRules(from: data)
        #expect(manager2.rules.count == 2)
        #expect(manager2.isEnabled == false)
        #expect(manager2.includeRules[0].domain == "a.com")
        #expect(manager2.excludeRules[0].domain == "b.com")
    }

    @Test("import legacy array format")
    func importLegacyArray() throws {
        let legacyRules = [SSLProxyingRule(domain: "old.com")]
        let data = try JSONEncoder().encode(legacyRules)

        let manager = makeManager()
        try manager.importRules(from: data)
        #expect(manager.rules.count == 1)
        #expect(manager.rules[0].listType == .include)
    }

    // MARK: - Presets

    @Test("addPresets adds default domains")
    func addPresets() {
        let manager = makeManager()
        manager.addPresets()
        #expect(!manager.rules.isEmpty)
        #expect(manager.rules.allSatisfy { $0.listType == .include })
    }

    @Test("addPresets does not duplicate existing")
    func addPresetsNoDuplicate() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "*.googleapis.com"))
        let countBefore = manager.rules.count
        manager.addPresets()
        let googleapis = manager.rules.filter { $0.domain == "*.googleapis.com" }
        #expect(googleapis.count == 1)
        #expect(manager.rules.count > countBefore)
    }

    // MARK: - Persisted Enable-State (Fix 1 regression)

    @Test("persisted isEnabled=false is reflected in shouldIntercept after reload")
    func persistedDisabledState() {
        let url = makeTempURL()
        let manager1 = SSLProxyingManager(storageURL: url)
        manager1.addRule(SSLProxyingRule(domain: "test.com", listType: .include))
        manager1.setEnabled(false)

        let manager2 = SSLProxyingManager(storageURL: url)
        #expect(manager2.isEnabled == false)
        #expect(!manager2.shouldIntercept("test.com"))
    }

    // MARK: - Wildcard Match-All (Fix 3 regression)

    @Test("rule with domain * matches every host")
    func wildcardMatchAll() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        #expect(manager.shouldIntercept("anything.example.com"))
        #expect(manager.shouldIntercept("localhost"))
        #expect(manager.shouldIntercept("192.168.1.1"))
    }

    // MARK: - Disabled Exclude Rule (Fix 4 regression)

    @Test("disabled exclude rule does not block interception")
    func disabledExcludeDoesNotBlock() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "*.example.com", listType: .include))
        manager.addRule(SSLProxyingRule(domain: "secret.example.com", listType: .exclude))
        manager.toggleRule(id: manager.excludeRules[0].id)
        #expect(manager.shouldIntercept("secret.example.com"))
    }

    // MARK: - Sidebar Include/Exclude Semantics (Fix 4 regression)

    @Test("exclude rule is not treated as enabled include for sidebar query")
    func excludeRuleNotTreatedAsEnabled() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "api.example.com", listType: .exclude))
        let enabledIncludes = manager.includeRules.filter { $0.isEnabled && $0.matches("api.example.com") }
        #expect(enabledIncludes.isEmpty)
    }

    @Test("disabled include rule is not treated as enabled for sidebar query")
    func disabledIncludeNotTreatedAsEnabled() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "api.example.com", listType: .include))
        manager.toggleRule(id: manager.rules[0].id)
        let enabledIncludes = manager.includeRules.filter { $0.isEnabled && $0.matches("api.example.com") }
        #expect(enabledIncludes.isEmpty)
    }

    @Test("removing matching include rules preserves exclude rules")
    func removeIncludePreservesExclude() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "api.example.com", listType: .include))
        manager.addRule(SSLProxyingRule(domain: "api.example.com", listType: .exclude))

        let includeIDs = Set(manager.includeRules.filter { $0.matches("api.example.com") }.map(\.id))
        manager.removeRules(ids: includeIDs)

        #expect(manager.includeRules.isEmpty)
        #expect(manager.excludeRules.count == 1)
        #expect(manager.excludeRules[0].domain == "api.example.com")
    }

    // MARK: Private

    private func makeManager() -> SSLProxyingManager {
        SSLProxyingManager(storageURL: makeTempURL())
    }

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-ssl-test-\(UUID().uuidString).json")
    }
}
