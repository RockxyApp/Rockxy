import Foundation
@testable import Rockxy
import Testing

// MARK: - SidebarSSLProxyingTests

/// Regression tests for the real coordinator sidebar methods in
/// `MainContentCoordinator+SidebarMenu.swift`. Each test seeds
/// `SSLProxyingManager.shared` with known state, calls the coordinator
/// method under test, then cleans up to avoid cross-test pollution.
@Suite(.serialized)
@MainActor
struct SidebarSSLProxyingTests {
    // MARK: - isSSLProxyingEnabled(for:)

    @Test("exclude rule is not treated as enabled by isSSLProxyingEnabled")
    func excludeNotEnabled() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let rule = SSLProxyingRule(domain: "api.example.com", listType: .exclude)
        manager.addRule(rule)
        defer { manager.removeRule(id: rule.id) }

        #expect(!coordinator.isSSLProxyingEnabled(for: "api.example.com"))
    }

    @Test("disabled include rule is not treated as enabled by isSSLProxyingEnabled")
    func disabledIncludeNotEnabled() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let rule = SSLProxyingRule(domain: "api.example.com", listType: .include)
        manager.addRule(rule)
        manager.toggleRule(id: rule.id)
        defer { manager.removeRule(id: rule.id) }

        #expect(!coordinator.isSSLProxyingEnabled(for: "api.example.com"))
    }

    @Test("enabled include rule is treated as enabled by isSSLProxyingEnabled")
    func enabledIncludeIsEnabled() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let rule = SSLProxyingRule(domain: "api.example.com", listType: .include)
        manager.addRule(rule)
        defer { manager.removeRule(id: rule.id) }

        #expect(coordinator.isSSLProxyingEnabled(for: "api.example.com"))
    }

    @Test("enableSSLProxyingForDomain turns the tool back on and re-enables existing rules")
    func enableForDomainReenablesExistingRule() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalEnabled = manager.isEnabled
        defer {
            manager.replaceAllRules(originalRules)
            manager.setEnabled(originalEnabled)
        }

        let disabledRule = SSLProxyingRule(
            domain: "api.example.com",
            isEnabled: false,
            listType: .include
        )
        manager.replaceAllRules([disabledRule])
        manager.setEnabled(false)

        coordinator.enableSSLProxyingForDomain("api.example.com")

        #expect(manager.isEnabled)
        #expect(manager.includeRules.count == 1)
        #expect(manager.includeRules.first?.isEnabled == true)
    }

    // MARK: - disableSSLProxyingForDomain(_:)

    @Test("disableSSLProxyingForDomain removes include rules and preserves exclude rules")
    func disablePreservesExclude() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let includeRule = SSLProxyingRule(domain: "api.example.com", listType: .include)
        let excludeRule = SSLProxyingRule(domain: "api.example.com", listType: .exclude)
        manager.addRule(includeRule)
        manager.addRule(excludeRule)
        defer {
            manager.removeRule(id: includeRule.id)
            manager.removeRule(id: excludeRule.id)
        }

        coordinator.disableSSLProxyingForDomain("api.example.com")

        #expect(!manager.rules.contains(where: { $0.id == includeRule.id }))
        #expect(manager.rules.contains(where: { $0.id == excludeRule.id }))
    }

    @Test("disableSSLProxyingForDomain is no-op for exclude-only domain")
    func disableNoOpForExcludeOnly() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let excludeRule = SSLProxyingRule(domain: "api.example.com", listType: .exclude)
        manager.addRule(excludeRule)
        defer { manager.removeRule(id: excludeRule.id) }

        let countBefore = manager.rules.count
        coordinator.disableSSLProxyingForDomain("api.example.com")

        #expect(manager.rules.count == countBefore)
        #expect(manager.rules.contains(where: { $0.id == excludeRule.id }))
    }

    @Test("observedDomainsForApp falls back to matching transactions and current host")
    func observedDomainsForAppFallsBackToTransactions() {
        let coordinator = MainContentCoordinator()

        let connect = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )
        connect.clientApp = "Google Chrome"

        let second = TestFixtures.makeTransaction(url: "https://cdn.example.com/assets.js")
        second.clientApp = "Google Chrome"

        coordinator.transactions = [connect, second]
        coordinator.appNodes = []
        TrafficDomainSnapshot.shared.reset()

        let domains = coordinator.observedDomainsForApp(
            named: "Google Chrome",
            fallbackDomain: "api.example.com"
        )

        #expect(domains == ["api.example.com", "cdn.example.com"])
    }

    @Test("enableSSLProxyingFromInspector for app enables fallback host when cache is empty")
    func enableFromInspectorForAppUsesFallbackHost() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalEnabled = manager.isEnabled
        defer {
            manager.replaceAllRules(originalRules)
            manager.setEnabled(originalEnabled)
            TrafficDomainSnapshot.shared.reset()
        }

        manager.replaceAllRules([])
        manager.setEnabled(false)
        coordinator.transactions = []
        coordinator.appNodes = []
        TrafficDomainSnapshot.shared.reset()

        coordinator.enableSSLProxyingFromInspector(
            forAppNamed: "Google Chrome",
            fallbackDomain: "api.example.com"
        )

        #expect(manager.isEnabled)
        #expect(coordinator.isSSLProxyingEnabled(for: "api.example.com"))
        #expect(
            coordinator.activeToast?.text ==
                "Enabled SSL Proxying for domains from Google Chrome. Make the request again to inspect them."
        )
    }

    @Test("isSSLProxyingFullyEnabled for app requires every observed domain to be enabled")
    func appSSLProxyingRequiresFullCoverage() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        defer {
            manager.replaceAllRules(originalRules)
            TrafficDomainSnapshot.shared.reset()
        }

        manager.replaceAllRules([
            SSLProxyingRule(domain: "api.example.com", listType: .include)
        ])
        coordinator.transactions = []
        coordinator.appNodes = [
            AppInfo(name: "Google Chrome", domains: ["api.example.com", "cdn.example.com"], requestCount: 2)
        ]

        #expect(!coordinator.isSSLProxyingFullyEnabled(forAppNamed: "Google Chrome"))

        manager.addRule(SSLProxyingRule(domain: "cdn.example.com", listType: .include))
        #expect(coordinator.isSSLProxyingFullyEnabled(forAppNamed: "Google Chrome"))
    }

    @Test("disableSSLProxyingFromInspector for app removes fallback host rule")
    func disableFromInspectorForAppUsesFallbackHost() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalEnabled = manager.isEnabled
        defer {
            manager.replaceAllRules(originalRules)
            manager.setEnabled(originalEnabled)
            TrafficDomainSnapshot.shared.reset()
        }

        manager.replaceAllRules([SSLProxyingRule(domain: "api.example.com", listType: .include)])
        manager.setEnabled(true)
        coordinator.transactions = []
        coordinator.appNodes = []
        TrafficDomainSnapshot.shared.reset()

        coordinator.disableSSLProxyingFromInspector(
            forAppNamed: "Google Chrome",
            fallbackDomain: "api.example.com"
        )

        #expect(!coordinator.isSSLProxyingEnabled(for: "api.example.com"))
        #expect(
            coordinator.activeToast?.text ==
                "Disabled SSL Proxying for domains from Google Chrome. Requests from it will stay tunneled."
        )
    }

    @Test("disableSSLProxyingFromInspector for domain clears rule and shows toast")
    func disableFromInspectorForDomainShowsToast() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let rule = SSLProxyingRule(domain: "api.example.com", listType: .include)
        manager.addRule(rule)
        defer { manager.removeRule(id: rule.id) }

        coordinator.disableSSLProxyingFromInspector(for: "api.example.com")

        #expect(!coordinator.isSSLProxyingEnabled(for: "api.example.com"))
        #expect(
            coordinator.activeToast?.text ==
                "Disabled SSL Proxying for api.example.com. Requests to it will stay tunneled."
        )
    }
}
