import Foundation
@testable import Rockxy
import Testing

// MARK: - SSLProxyingManagerApplicationRulesTests

@MainActor
struct SSLProxyingManagerApplicationRulesTests {
    // MARK: Internal

    // MARK: - App-vs-host conflicts

    @Test("application Decrypt rule enables interception for a never-before-seen host")
    func appDecryptEnablesNewHost() {
        let manager = makeManager()
        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))

        #expect(manager.shouldIntercept(host: "brand.new.example.com", application: appA))
        // No host rule and no identity ⇒ tunnel.
        #expect(!manager.shouldIntercept(host: "brand.new.example.com", application: nil))
        // A different application does not inherit the decision.
        #expect(!manager.shouldIntercept(host: "brand.new.example.com", application: appB))
    }

    @Test("application Tunnel rule beats a matching host Decrypt rule")
    func appTunnelBeatsHostDecrypt() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "*.example.com", listType: .include))
        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .exclude))

        #expect(!manager.shouldIntercept(host: "api.example.com", application: appA))
        // Without the excluded app, the host include still intercepts.
        #expect(manager.shouldIntercept(host: "api.example.com", application: appB))
        #expect(manager.shouldIntercept(host: "api.example.com", application: nil))
    }

    @Test("host Tunnel rule beats a matching application Decrypt rule")
    func hostTunnelBeatsAppDecrypt() {
        let manager = makeManager()
        manager.addRule(SSLProxyingRule(domain: "secret.example.com", listType: .exclude))
        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))

        #expect(!manager.shouldIntercept(host: "secret.example.com", application: appA))
        #expect(manager.shouldIntercept(host: "other.example.com", application: appA))
    }

    @Test("global disable forces tunnel even with an application Decrypt rule")
    func globalDisableForcesTunnel() {
        let manager = makeManager()
        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))
        manager.setEnabled(false)
        #expect(!manager.shouldIntercept(host: "api.example.com", application: appA))
    }

    @Test("bypass domain forces tunnel even with an application Decrypt rule")
    func bypassForcesTunnel() {
        let manager = makeManager()
        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))
        manager.setBypassDomains("dns.google")
        #expect(!manager.shouldIntercept(host: "dns.google", application: appA))
    }

    @Test("disabled application rule does not participate")
    func disabledAppRuleIgnored() {
        let manager = makeManager()
        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))
        manager.toggleApplicationRule(id: manager.applicationRules[0].id)
        #expect(!manager.shouldIntercept(host: "api.example.com", application: appA))
    }

    @Test("adding an application Decrypt rule retries that application's rejected hosts only")
    func appDecryptClearsMatchingApplicationPassthrough() {
        let manager = makeManager()
        manager.markHostForPassthrough("shared.example", application: appA)
        manager.markHostForPassthrough("shared.example", application: appB)

        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))

        #expect(!manager.isAutoPassthrough("shared.example", application: appA))
        #expect(manager.isAutoPassthrough("shared.example", application: appB))
    }

    // MARK: - hasEnabledApplicationRules gate

    @Test("hasEnabledApplicationRules reflects enabled app rules and global state")
    func hasEnabledApplicationRulesGate() {
        let manager = makeManager()
        #expect(!manager.hasEnabledApplicationRules())

        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))
        #expect(manager.hasEnabledApplicationRules())

        manager.setEnabled(false)
        #expect(!manager.hasEnabledApplicationRules())

        manager.setEnabled(true)
        manager.toggleApplicationRule(id: manager.applicationRules[0].id)
        #expect(!manager.hasEnabledApplicationRules())
    }

    @Test("application Tunnel capability gate ignores Decrypt and disabled rules")
    func hasEnabledApplicationTunnelRulesGate() throws {
        let manager = makeManager()
        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))
        #expect(!manager.hasEnabledApplicationTunnelRules())

        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appB, listType: .exclude))
        #expect(manager.hasEnabledApplicationTunnelRules())

        let tunnelRuleID = try #require(manager.applicationRules.first(where: { $0.listType == .exclude })?.id)
        manager.setApplicationRuleEnabled(id: tunnelRuleID, enabled: false)
        #expect(!manager.hasEnabledApplicationTunnelRules())
    }

    @Test("default identity provider resolves local clients even before an application rule exists")
    func defaultIdentityProviderAlwaysScopesLocalClients() {
        let manager = makeManager()
        let provider = ProxyServer.defaultClientIdentityHandleProvider(sslProxyingManager: manager)
        let descriptor = ProxyConnectionDescriptor(
            acceptedAt: .now(),
            clientHost: "127.0.0.1",
            clientPort: 54_321,
            proxyHost: "127.0.0.1",
            proxyPort: 9_090
        )

        #expect(provider(descriptor) != nil)

        let remoteDescriptor = ProxyConnectionDescriptor(
            acceptedAt: .now(),
            clientHost: "192.0.2.10",
            clientPort: 54_321,
            proxyHost: "0.0.0.0",
            proxyPort: 9_090
        )
        #expect(provider(remoteDescriptor) == nil)
    }

    // MARK: - CRUD

    @Test("application rule CRUD add/update/remove")
    func appRuleCRUD() {
        let manager = makeManager()
        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))
        #expect(manager.applicationRules.count == 1)

        var rule = manager.applicationRules[0]
        rule.listType = .exclude
        manager.updateApplicationRule(rule)
        #expect(manager.applicationExcludeRules.count == 1)
        #expect(manager.applicationIncludeRules.isEmpty)

        manager.removeApplicationRule(id: rule.id)
        #expect(manager.applicationRules.isEmpty)
    }

    // MARK: - Persistence (schema v3)

    @Test("save and load roundtrip preserves application rules")
    func persistenceRoundtrip() {
        let url = makeTempURL(prefix: "rockxy-ssl-app-persist")
        let passthrough = makeTempURL(prefix: "rockxy-ssl-app-passthrough")
        let manager1 = SSLProxyingManager(storageURL: url, passthroughStorageURL: passthrough)
        manager1.addRule(SSLProxyingRule(domain: "host.example.com", listType: .include))
        manager1.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))
        manager1.addApplicationRule(ApplicationSSLProxyingRule(identity: appB, listType: .exclude))

        let manager2 = SSLProxyingManager(storageURL: url, passthroughStorageURL: passthrough)
        #expect(manager2.rules.count == 1)
        #expect(manager2.applicationRules.count == 2)
        #expect(manager2.shouldIntercept(host: "unseen.example.org", application: appA))
        #expect(!manager2.shouldIntercept(host: "unseen.example.org", application: appB))
    }

    @Test("export payload is schema v3 and carries the application-rules sibling key")
    func exportIsSchemaV3() throws {
        let manager = makeManager()
        manager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))
        let data = try #require(manager.exportRules())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 3)
        #expect(object["applicationRules"] != nil)
    }

    @Test("export/import roundtrip preserves application rules")
    func exportImportRoundtrip() throws {
        let manager1 = makeManager()
        manager1.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))
        let data = try #require(manager1.exportRules())

        let manager2 = makeManager()
        manager2.markHostForPassthrough("x.example.com", application: appA)
        #expect(manager2.isAutoPassthrough("x.example.com", application: appA))
        try manager2.importRules(from: data)
        #expect(manager2.applicationRules.count == 1)
        #expect(manager2.shouldIntercept(host: "x.example.com", application: appA))
        #expect(!manager2.isAutoPassthrough("x.example.com", application: appA))
    }

    @Test("legacy v2 payload without app-rules key loads host rules with empty app rules")
    func loadV2WithoutAppRulesKey() throws {
        let url = makeTempURL(prefix: "rockxy-ssl-app-v2")
        let json = """
        {"schemaVersion":2,"isEnabled":true,"bypassDomains":"dns.google",
        "rules":[{"id":"\(UUID().uuidString)","domain":"legacy.example.com","isEnabled":true,"listType":"include"}]}
        """
        try Data(json.utf8).write(to: url)

        let manager = SSLProxyingManager(
            storageURL: url,
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-app-v2-pt")
        )
        #expect(manager.rules.count == 1)
        #expect(manager.rules[0].domain == "legacy.example.com")
        #expect(manager.applicationRules.isEmpty)
    }

    // MARK: Private

    private let appA = ClientApplicationIdentity.bundle(identifier: "com.example.AppA", displayName: "App A")
    private let appB = ClientApplicationIdentity.bundle(identifier: "com.example.AppB", displayName: "App B")

    private func makeManager() -> SSLProxyingManager {
        SSLProxyingManager(
            storageURL: makeTempURL(prefix: "rockxy-ssl-app-test"),
            passthroughStorageURL: makeTempURL(prefix: "rockxy-ssl-app-passthrough-test")
        )
    }

    private func makeTempURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }
}
