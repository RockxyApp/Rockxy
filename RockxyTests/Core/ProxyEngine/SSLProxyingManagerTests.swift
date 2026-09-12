import Foundation
@testable import Rockxy
import Testing

private final class MutableDateBox: @unchecked Sendable {
    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }

    private var value: Date
    private let lock = NSLock()
}

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
        manager.addRule(SSLProxyingRule(domain: "anything.com", listType: .include))
        manager.forceGlobalPassthrough = true
        #expect(!manager.shouldIntercept("anything.com"))
        #expect(manager.isDecryptionConfigured(host: "anything.com"))
        manager.forceGlobalPassthrough = false
        #expect(manager.shouldIntercept("anything.com"))
    }

    @Test("TLS bypass query exposes the reason a matching Decrypt rule is ineffective")
    func tlsBypassQuery() {
        let manager = makeManager()
        manager.setBypassDomains("ocsp.example.com,*.private.example")
        manager.addRule(SSLProxyingRule(domain: "ocsp.example.com", listType: .include))

        #expect(manager.isHostInTLSBypassList("OCSP.EXAMPLE.COM"))
        #expect(manager.isHostInTLSBypassList("api.private.example"))
        #expect(!manager.isHostInTLSBypassList("public.example"))
        #expect(!manager.shouldIntercept("ocsp.example.com"))
    }

    @Test("adding include rule clears matching auto passthrough host")
    func addIncludeClearsMatchingAutoPassthrough() {
        let manager = makeManager()
        manager.markHostForPassthrough("api.example.com")
        manager.markHostForPassthrough("other.com")

        manager.addRule(SSLProxyingRule(domain: "*.example.com", listType: .include))

        #expect(!manager.isAutoPassthrough("api.example.com"))
        #expect(manager.isAutoPassthrough("other.com"))
    }

    @Test("enabling SSL tool clears matching auto passthrough for active rules")
    func enablingClearsMatchingAutoPassthrough() {
        let manager = makeManager()
        manager.setEnabled(false)
        manager.addRule(SSLProxyingRule(domain: "api.example.com", listType: .include))
        manager.markHostForPassthrough("api.example.com")
        manager.markHostForPassthrough("other.com")

        manager.setEnabled(true)

        #expect(!manager.isAutoPassthrough("api.example.com"))
        #expect(manager.isAutoPassthrough("other.com"))
    }

    @Test("wildcard include clears all auto passthrough hosts")
    func wildcardIncludeClearsAllAutoPassthrough() {
        let manager = makeManager()
        manager.markHostForPassthrough("api.example.com")
        manager.markHostForPassthrough("other.com")

        manager.addRule(SSLProxyingRule(domain: "*", listType: .include))

        #expect(!manager.isAutoPassthrough("api.example.com"))
        #expect(!manager.isAutoPassthrough("other.com"))
    }

    @Test("retrying interception clears only the requested auto passthrough host")
    func retryInterceptionClearsRequestedHost() {
        let manager = makeManager()
        manager.markHostForPassthrough("API.example.com")
        manager.markHostForPassthrough("other.com")

        #expect(manager.retryInterception(for: "api.example.com"))
        #expect(!manager.isAutoPassthrough("API.example.com"))
        #expect(manager.isAutoPassthrough("other.com"))
        #expect(!manager.retryInterception(for: "missing.example.com"))
    }

    @Test("warning retry clears every failed host for selected clients only")
    func retryInterceptionClearsSelectedClients() {
        let manager = makeManager()
        manager.markHostForPassthrough("one.example", clientIdentifier: "app.one")
        manager.markHostForPassthrough("two.example", clientIdentifier: "APP.ONE")
        manager.markHostForPassthrough("one.example", clientIdentifier: "app.two")
        manager.markHostForPassthrough("unattributed.example", clientIdentifier: nil)

        #expect(manager.retryInterception(clientIdentifiers: [" App.One "]) == 2)
        #expect(!manager.isAutoPassthrough("one.example", clientIdentifier: "app.one"))
        #expect(!manager.isAutoPassthrough("two.example", clientIdentifier: "app.one"))
        #expect(manager.isAutoPassthrough("one.example", clientIdentifier: "app.two"))
        #expect(manager.isAutoPassthrough("unattributed.example", clientIdentifier: nil))
        #expect(manager.retryInterception(clientIdentifiers: []) == 0)
    }

    @Test("certificate rejection passthrough is scoped to the originating application")
    func autoPassthroughIsApplicationScoped() {
        let manager = makeManager()
        let first = ClientApplicationIdentity.bundle(identifier: "app.one", displayName: "One")
        let second = ClientApplicationIdentity.bundle(identifier: "app.two", displayName: "Two")

        manager.markHostForPassthrough("shared.example", application: first)

        #expect(manager.isAutoPassthrough("shared.example", application: first))
        #expect(!manager.isAutoPassthrough("shared.example", application: second))
        #expect(!manager.isAutoPassthrough("shared.example"))
    }

    @Test("certificate rejection passthrough is isolated between remote clients")
    func autoPassthroughIsRemoteClientScoped() {
        let manager = makeManager()

        manager.markHostForPassthrough("shared.example", clientIdentifier: "remote:first")

        #expect(manager.isAutoPassthrough("shared.example", clientIdentifier: "remote:first"))
        #expect(!manager.isAutoPassthrough("shared.example", clientIdentifier: "remote:second"))
        #expect(!manager.isAutoPassthrough("shared.example"))
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
        let url = makeTempURL(prefix: "rockxy-ssl-persistence")
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

    @Test("termination flush persists the latest scoped fallback snapshot")
    func passthroughTerminationFlushPersistsLatestSnapshot() {
        let settingsURL = makeTempURL(prefix: "rockxy-ssl-flush-settings")
        let passthroughURL = makeTempURL(prefix: "rockxy-ssl-flush-passthrough")
        let host = "flush.example"
        let clientIdentifier = "app.flush"
        let manager = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )

        manager.markHostForPassthrough(host, clientIdentifier: clientIdentifier)
        #expect(manager.flushPassthroughPersistence())
        let loaded = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        #expect(loaded.isAutoPassthrough(host, clientIdentifier: clientIdentifier))

        #expect(manager.retryInterception(clientIdentifiers: [clientIdentifier]) == 1)
        #expect(manager.flushPassthroughPersistence())
        let reloaded = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        #expect(!reloaded.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
    }

    @Test("rejection bursts persist only the latest scoped fallback state")
    func passthroughRejectionBurstPersistsLatestState() {
        let settingsURL = makeTempURL(prefix: "rockxy-ssl-burst-settings")
        let passthroughURL = makeTempURL(prefix: "rockxy-ssl-burst-passthrough")
        let manager = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        let retainedHosts = (0..<32).map { "retained-\($0).example" }
        let retriedHosts = (0..<32).map { "retried-\($0).example" }

        for host in retainedHosts + retriedHosts {
            manager.markHostForPassthrough(host, clientIdentifier: "app.burst")
        }
        for host in retriedHosts {
            #expect(manager.retryInterception(for: host))
        }

        #expect(manager.flushPassthroughPersistence())
        let reloaded = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        for host in retainedHosts {
            #expect(reloaded.isAutoPassthrough(host, clientIdentifier: "app.burst"))
        }
        for host in retriedHosts {
            #expect(!reloaded.isAutoPassthrough(host, clientIdentifier: "app.burst"))
        }
    }

    @Test("transient TLS fallback expires, stays scoped, and never survives relaunch")
    func transientPassthroughIsMemoryOnly() {
        let settingsURL = makeTempURL(prefix: "rockxy-ssl-transient-settings")
        let passthroughURL = makeTempURL(prefix: "rockxy-ssl-transient-passthrough")
        let clock = MutableDateBox(Date(timeIntervalSince1970: 1_000))
        let manager = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL,
            passthroughNowProvider: clock.now
        )

        manager.markHostForTransientPassthrough("transient.example", clientIdentifier: "app.one")
        manager.markHostForTransientPassthrough("unresolved.example", clientIdentifier: nil)

        #expect(manager.isAutoPassthrough("transient.example", clientIdentifier: "app.one"))
        #expect(!manager.isAutoPassthrough("transient.example", clientIdentifier: "app.two"))
        #expect(manager.isAutoPassthrough("unresolved.example", clientIdentifier: nil))
        #expect(!manager.isAutoPassthrough("unresolved.example", clientIdentifier: "app.one"))
        clock.advance(by: 61)
        #expect(!manager.isAutoPassthrough("transient.example", clientIdentifier: "app.one"))
        #expect(!manager.isAutoPassthrough("unresolved.example", clientIdentifier: nil))
        #expect(manager.flushPassthroughPersistence())
        let reloaded = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        #expect(!reloaded.isAutoPassthrough("transient.example", clientIdentifier: "app.one"))
        #expect(!reloaded.isAutoPassthrough("unresolved.example", clientIdentifier: nil))
    }

    @Test("clock rollback expires future-dated persistent and transient fallbacks")
    func passthroughClockRollbackCannotExtendFallback() {
        let settingsURL = makeTempURL(prefix: "rockxy-ssl-clock-settings")
        let passthroughURL = makeTempURL(prefix: "rockxy-ssl-clock-passthrough")
        let clock = MutableDateBox(Date(timeIntervalSince1970: 10_000))
        let manager = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL,
            passthroughNowProvider: clock.now
        )

        manager.markHostForPassthrough("persistent.example", clientIdentifier: "app.clock")
        manager.markHostForTransientPassthrough("transient.example", clientIdentifier: "app.clock")
        clock.advance(by: -3_600)

        #expect(!manager.isAutoPassthrough("persistent.example", clientIdentifier: "app.clock"))
        #expect(!manager.isAutoPassthrough("transient.example", clientIdentifier: "app.clock"))
        #expect(manager.flushPassthroughPersistence())
        let reloaded = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL,
            passthroughNowProvider: clock.now
        )
        #expect(!reloaded.isAutoPassthrough("persistent.example", clientIdentifier: "app.clock"))
    }

    @Test("trust restoration across relaunch clears fallbacks from the untrusted epoch")
    func trustRestorationAcrossRelaunchClearsFallback() {
        let settingsURL = makeTempURL(prefix: "rockxy-ssl-trust-settings")
        let passthroughURL = makeTempURL(prefix: "rockxy-ssl-trust-passthrough")
        let firstRun = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        firstRun.reconcileCertificateState(isTrusted: false, fingerprint: "root-a")
        firstRun.markHostForPassthrough("stale.example", clientIdentifier: "app.one")
        #expect(firstRun.flushPassthroughPersistence())

        let relaunched = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        #expect(relaunched.isAutoPassthrough("stale.example", clientIdentifier: "app.one"))
        relaunched.reconcileCertificateState(isTrusted: true, fingerprint: "root-a")

        #expect(!relaunched.isAutoPassthrough("stale.example", clientIdentifier: "app.one"))
        #expect(relaunched.flushPassthroughPersistence())
        let verified = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        #expect(!verified.isAutoPassthrough("stale.example", clientIdentifier: "app.one"))
    }

    @Test("relaunch in the same trusted CA epoch preserves pinned-client fallback")
    func trustedRelaunchPreservesFallback() {
        let settingsURL = makeTempURL(prefix: "rockxy-ssl-pinned-settings")
        let passthroughURL = makeTempURL(prefix: "rockxy-ssl-pinned-passthrough")
        let firstRun = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        firstRun.reconcileCertificateState(isTrusted: true, fingerprint: "root-a")
        firstRun.markHostForPassthrough("pinned.example", clientIdentifier: "app.one")
        #expect(firstRun.flushPassthroughPersistence())

        let relaunched = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        relaunched.reconcileCertificateState(isTrusted: true, fingerprint: "ROOT-A")

        #expect(relaunched.isAutoPassthrough("pinned.example", clientIdentifier: "app.one"))
    }

    @Test("fallback files from before trust epoch metadata remain readable")
    func legacyFallbackWithoutTrustMetadataStillLoads() throws {
        let settingsURL = makeTempURL(prefix: "rockxy-ssl-legacy-trust-settings")
        let passthroughURL = makeTempURL(prefix: "rockxy-ssl-legacy-trust-passthrough")
        let writer = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        writer.markHostForPassthrough("legacy.example", clientIdentifier: "app.one")
        #expect(writer.flushPassthroughPersistence())

        let data = try Data(contentsOf: passthroughURL)
        var payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload.removeValue(forKey: "lastObservedSystemTrustValidated")
        payload.removeValue(forKey: "lastObservedCertificateFingerprint")
        try JSONSerialization.data(withJSONObject: payload).write(to: passthroughURL, options: .atomic)

        let reader = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        #expect(reader.isAutoPassthrough("legacy.example", clientIdentifier: "app.one"))
    }

    @Test("blank hosts are ignored and blank client identities stay memory-only")
    func passthroughRejectsBlankScopes() {
        let settingsURL = makeTempURL(prefix: "rockxy-ssl-blank-settings")
        let passthroughURL = makeTempURL(prefix: "rockxy-ssl-blank-passthrough")
        let manager = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )

        manager.markHostForPassthrough("   ", clientIdentifier: "app.blank")
        manager.markHostForPassthrough(" unresolved.example ", clientIdentifier: "   ")

        #expect(!manager.isAutoPassthrough("", clientIdentifier: "app.blank"))
        #expect(manager.isAutoPassthrough("unresolved.example", clientIdentifier: nil))
        #expect(manager.flushPassthroughPersistence())
        let reloaded = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        #expect(!reloaded.isAutoPassthrough("unresolved.example", clientIdentifier: nil))
    }

    @Test("missing active settings recover from an earlier app namespace")
    func namespaceMigrationRecoversHTTPSSettings() {
        let legacyURL = makeTempURL(prefix: "rockxy-ssl-earlier-namespace")
        let activeURL = makeTempURL(prefix: "rockxy-ssl-active-namespace")
        let legacyManager = SSLProxyingManager(
            storageURL: legacyURL,
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-earlier-passthrough")
        )
        legacyManager.addRule(SSLProxyingRule(domain: "recovered.example", listType: .include))
        legacyManager.setBypassDomains("custom-bypass.example")

        let migratedManager = SSLProxyingManager(
            storageURL: activeURL,
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-active-passthrough"),
            migrationStorageURLs: [legacyURL]
        )

        #expect(migratedManager.rules.map(\.domain) == ["recovered.example"])
        #expect(migratedManager.bypassDomains == "custom-bypass.example")
        #expect(FileManager.default.fileExists(atPath: activeURL.path))
    }

    @Test("existing active settings are never replaced by another namespace")
    func namespaceMigrationPreservesExistingSettings() {
        let legacyURL = makeTempURL(prefix: "rockxy-ssl-earlier-existing")
        let activeURL = makeTempURL(prefix: "rockxy-ssl-active-existing")
        let legacyManager = SSLProxyingManager(
            storageURL: legacyURL,
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-earlier-existing-passthrough")
        )
        legacyManager.addRule(SSLProxyingRule(domain: "legacy.example"))
        let activeManager = SSLProxyingManager(
            storageURL: activeURL,
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-active-existing-passthrough")
        )
        activeManager.addRule(SSLProxyingRule(domain: "active.example"))

        let loadedManager = SSLProxyingManager(
            storageURL: activeURL,
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-loaded-existing-passthrough"),
            migrationStorageURLs: [legacyURL]
        )

        #expect(loadedManager.rules.map(\.domain) == ["active.example"])
    }

    @Test("corrupt active settings recover from a valid earlier namespace")
    func namespaceMigrationRecoversCorruptActiveSettings() throws {
        let legacyURL = makeTempURL(prefix: "rockxy-ssl-earlier-corrupt")
        let activeURL = makeTempURL(prefix: "rockxy-ssl-active-corrupt")
        let legacyManager = SSLProxyingManager(
            storageURL: legacyURL,
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-earlier-corrupt-passthrough")
        )
        legacyManager.addRule(SSLProxyingRule(domain: "recovered-from-corruption.example"))
        try Data("truncated".utf8).write(to: activeURL)

        let migratedManager = SSLProxyingManager(
            storageURL: activeURL,
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-active-corrupt-passthrough"),
            migrationStorageURLs: [legacyURL]
        )

        #expect(migratedManager.rules.map(\.domain) == ["recovered-from-corruption.example"])
        let reloadedManager = SSLProxyingManager(
            storageURL: activeURL,
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-reloaded-corrupt-passthrough")
        )
        #expect(reloadedManager.rules.map(\.domain) == ["recovered-from-corruption.example"])
    }

    @Test("load migrates legacy v1 format")
    func legacyMigration() throws {
        let url = makeTempURL(prefix: "rockxy-ssl-legacy")
        let legacyRules = [
            SSLProxyingRule(domain: "legacy1.com"),
            SSLProxyingRule(domain: "legacy2.com"),
        ]
        let data = try JSONEncoder().encode(legacyRules)
        try data.write(to: url)

        let manager = SSLProxyingManager(storageURL: url)
        #expect(manager.rules.count == 2)
        #expect(manager.rules.allSatisfy { $0.listType == SSLProxyingListType.include })
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

    @Test("export preserves master state and TLS exceptions when there are no rules")
    func exportImportSettingsWithoutRules() throws {
        let manager1 = makeManager()
        manager1.setEnabled(false)
        manager1.setBypassDomains("custom.example.com,::1")
        let data = try #require(manager1.exportRules())

        let manager2 = makeManager()
        try manager2.importRules(from: data)

        #expect(manager2.rules.isEmpty)
        #expect(!manager2.isEnabled)
        #expect(manager2.bypassDomains == "custom.example.com,::1")
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
        let url = makeTempURL(prefix: "rockxy-ssl-disabled")
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
        SSLProxyingManager(
            storageURL: makeTempURL(prefix: "rockxy-ssl-test"),
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-passthrough-test")
        )
    }

    private func makeTempURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }
}
