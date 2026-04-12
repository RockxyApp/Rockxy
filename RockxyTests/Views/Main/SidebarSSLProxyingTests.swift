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
}
