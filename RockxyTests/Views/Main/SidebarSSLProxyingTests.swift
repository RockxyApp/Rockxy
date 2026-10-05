import Foundation
@testable import Rockxy
import Testing

// MARK: - SidebarSSLProxyingTests

/// Regression tests for the real coordinator sidebar methods in
/// `MainContentCoordinator+SidebarMenu.swift`. Each test seeds
/// `SSLProxyingManager.shared` with known state, calls the coordinator
/// method under test, then cleans up to avoid cross-test pollution.
@Suite(.serialized, .sharedPolicyState)
@MainActor
struct SidebarSSLProxyingTests {
    @Test("Stale toast dismissal keeps the replacement notification visible")
    func staleToastDismissalKeepsReplacement() {
        let coordinator = MainContentCoordinator()
        let first = ToastMessage(style: .success, text: "First")
        let replacement = ToastMessage(style: .success, text: "Replacement")

        coordinator.activeToast = first
        coordinator.activeToast = replacement
        coordinator.dismissToast(id: first.id)

        #expect(coordinator.activeToast?.id == replacement.id)

        coordinator.dismissToast(id: replacement.id)
        #expect(coordinator.activeToast == nil)
    }

    // MARK: - isSSLProxyingEnabled(for:)

    @Test("exclude rule is not treated as enabled by isSSLProxyingEnabled")
    func excludeNotEnabled() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalEnabled = manager.isEnabled
        let rule = SSLProxyingRule(domain: "api.example.com", listType: .exclude)
        manager.addRule(rule)
        manager.setEnabled(true)
        defer {
            manager.removeRule(id: rule.id)
            manager.setEnabled(originalEnabled)
        }

        #expect(!coordinator.isSSLProxyingEnabled(for: "api.example.com"))
    }

    @Test("disabled include rule is not treated as enabled by isSSLProxyingEnabled")
    func disabledIncludeNotEnabled() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalEnabled = manager.isEnabled
        let rule = SSLProxyingRule(domain: "api.example.com", listType: .include)
        manager.addRule(rule)
        manager.toggleRule(id: rule.id)
        manager.setEnabled(true)
        defer {
            manager.removeRule(id: rule.id)
            manager.setEnabled(originalEnabled)
        }

        #expect(!coordinator.isSSLProxyingEnabled(for: "api.example.com"))
    }

    @Test("enabled include rule is treated as enabled by isSSLProxyingEnabled")
    func enabledIncludeIsEnabled() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalEnabled = manager.isEnabled
        let rule = SSLProxyingRule(domain: "api.example.com", listType: .include)
        manager.addRule(rule)
        manager.setEnabled(true)
        defer {
            manager.removeRule(id: rule.id)
            manager.setEnabled(originalEnabled)
        }

        #expect(coordinator.isSSLProxyingEnabled(for: "api.example.com"))
    }

    @Test("matching Tunnel rule prevents the sidebar from claiming Decrypt is enabled")
    func tunnelOverlapIsNotReportedAsDecrypt() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalBypassDomains = manager.bypassDomains
        defer {
            manager.replaceAllRules(originalRules)
            manager.setBypassDomains(originalBypassDomains)
        }

        manager.setBypassDomains("")
        manager.replaceAllRules([
            SSLProxyingRule(domain: "*.example.com", listType: .include),
            SSLProxyingRule(domain: "api.example.com", listType: .exclude),
        ])

        #expect(!coordinator.isSSLProxyingEnabled(for: "api.example.com"))
        #expect(coordinator.isSSLProxyingEnabled(for: "cdn.example.com"))
    }

    @Test("global SSL proxying off reports domain as disabled")
    func globalToggleOffReportsDisabled() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalEnabled = manager.isEnabled
        let rule = SSLProxyingRule(domain: "api.example.com", listType: .include)
        manager.addRule(rule)
        manager.setEnabled(false)
        defer {
            manager.removeRule(id: rule.id)
            manager.setEnabled(originalEnabled)
        }

        #expect(!coordinator.isSSLProxyingEnabled(for: "api.example.com"))
        #expect(!coordinator.isSSLProxyingFullyEnabled(forAppNamed: "Google Chrome", fallbackDomain: "api.example.com"))
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

    @Test("one-host Decrypt replaces only an exact Tunnel rule")
    func decryptHostReplacesExactTunnel() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalEnabled = manager.isEnabled
        let originalBypassDomains = manager.bypassDomains
        defer {
            manager.replaceAllRules(originalRules)
            manager.setEnabled(originalEnabled)
            manager.setBypassDomains(originalBypassDomains)
        }

        manager.setBypassDomains("")
        manager.replaceAllRules([
            SSLProxyingRule(domain: "api.example.com", listType: .exclude)
        ])
        manager.setEnabled(true)

        #expect(coordinator.enableSSLProxyingForDomain(" API.EXAMPLE.COM "))
        #expect(manager.excludeRules.isEmpty)
        #expect(manager.includeRules.count == 1)
        #expect(manager.includeRules[0].domain == "api.example.com")
        #expect(coordinator.isSSLProxyingEnabled(for: "api.example.com"))
    }

    @Test("one-host Decrypt never removes or overrides a broader Tunnel rule")
    func decryptHostPreservesBroaderTunnel() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalBypassDomains = manager.bypassDomains
        defer {
            manager.replaceAllRules(originalRules)
            manager.setBypassDomains(originalBypassDomains)
        }

        manager.setBypassDomains("")
        let wildcardTunnel = SSLProxyingRule(domain: "*.example.com", listType: .exclude)
        manager.replaceAllRules([wildcardTunnel])

        #expect(!coordinator.enableSSLProxyingForDomain("api.example.com"))
        #expect(manager.rules == [wildcardTunnel])
        #expect(coordinator.sslProxyingHostDecryptBlockedReason(for: "api.example.com")?.contains("*.example.com") == true)
    }

    @Test("one-host Decrypt does not re-enable a disabled wildcard rule")
    func decryptHostDoesNotReenableDisabledWildcard() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalBypassDomains = manager.bypassDomains
        defer {
            manager.replaceAllRules(originalRules)
            manager.setBypassDomains(originalBypassDomains)
        }

        manager.setBypassDomains("")
        let disabledWildcard = SSLProxyingRule(
            domain: "*.example.com",
            isEnabled: false,
            listType: .include
        )
        manager.replaceAllRules([disabledWildcard])

        #expect(coordinator.enableSSLProxyingForDomain("api.example.com"))
        #expect(manager.rules.first(where: { $0.id == disabledWildcard.id })?.isEnabled == false)
        #expect(manager.includeRules.contains {
            $0.domain == "api.example.com" && $0.isEnabled
        })
    }

    @Test("application behavior replaces the opposite behavior and applies to future hosts")
    func applicationBehaviorReplacesOpposite() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.applicationRules
        let originalEnabled = manager.isEnabled
        let fallbackHost = "issue305-\(UUID().uuidString).invalid"
        defer {
            manager.replaceAllApplicationRules(originalRules)
            manager.setEnabled(originalEnabled)
            manager.retryInterception(for: fallbackHost)
        }
        let identity = ClientApplicationIdentity.bundle(
            identifier: "com.google.Chrome",
            displayName: "Google Chrome"
        )
        manager.replaceAllApplicationRules([
            ApplicationSSLProxyingRule(identity: identity, listType: .exclude)
        ])
        manager.markHostForPassthrough(fallbackHost)

        #expect(coordinator.setSSLProxyingBehaviorForApplication(
            identity,
            listType: .include,
            fallbackDomain: fallbackHost
        ))
        #expect(manager.applicationExcludeRules.isEmpty)
        #expect(coordinator.isSSLProxyingEnabled(for: identity))
        #expect(!manager.isAutoPassthrough(fallbackHost))
    }

    @Test("application behavior toasts use complete localized messages")
    func applicationBehaviorToastsUseCompleteMessages() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.applicationRules
        defer { manager.replaceAllApplicationRules(originalRules) }
        let identity = ClientApplicationIdentity.bundle(
            identifier: "com.example.ToastApp",
            displayName: "Toast App"
        )

        coordinator.setSSLProxyingFromInspector(for: identity, listType: .include)
        #expect(coordinator.activeToast?.style == .success)
        #expect(coordinator.activeToast?.text ==
            "Set Toast App to decrypt HTTPS. Matching tunneled connections reset automatically — if one stays tunneled, reconnect the app.")

        coordinator.setSSLProxyingFromInspector(for: identity, listType: .exclude)
        #expect(coordinator.activeToast?.text ==
            "Set Toast App to tunnel HTTPS on new connections. Reconnect the app.")
    }

    @Test("app Decrypt inspector warns when the current host stays tunneled but keeps the app rule")
    func appDecryptInspectorWarnsWhenHostBlocked() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalAppRules = manager.applicationRules
        let originalEnabled = manager.isEnabled
        let originalBypassDomains = manager.bypassDomains
        defer {
            manager.replaceAllRules(originalRules)
            manager.replaceAllApplicationRules(originalAppRules)
            manager.setEnabled(originalEnabled)
            manager.setBypassDomains(originalBypassDomains)
        }
        let identity = ClientApplicationIdentity.bundle(
            identifier: "com.example.BlockedHostApp",
            displayName: "Blocked Host App"
        )
        manager.setBypassDomains("")
        // A broader host Tunnel rule outranks the application Decrypt for the current host.
        manager.replaceAllRules([
            SSLProxyingRule(domain: "*.example.com", listType: .exclude)
        ])
        manager.replaceAllApplicationRules([])
        manager.setEnabled(true)

        coordinator.setSSLProxyingFromInspector(
            for: identity,
            listType: .include,
            fallbackDomain: "api.example.com"
        )

        #expect(coordinator.activeToast?.style == .warning)
        #expect(coordinator.activeToast?.text.contains("api.example.com") == true)
        #expect(coordinator.activeToast?.text.contains("*.example.com") == true)
        // The application-wide rule is still installed — a blocked current host does not reject it.
        #expect(coordinator.isSSLProxyingEnabled(for: identity))
    }

    @Test("app Decrypt inspector also warns when an exact host Tunnel remains in force")
    func appDecryptInspectorWarnsForExactHostTunnel() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalAppRules = manager.applicationRules
        let originalEnabled = manager.isEnabled
        let originalBypassDomains = manager.bypassDomains
        defer {
            manager.replaceAllRules(originalRules)
            manager.replaceAllApplicationRules(originalAppRules)
            manager.setEnabled(originalEnabled)
            manager.setBypassDomains(originalBypassDomains)
        }
        let identity = ClientApplicationIdentity.bundle(
            identifier: "com.example.ExactTunnelApp",
            displayName: "Exact Tunnel App"
        )
        manager.setBypassDomains("")
        manager.replaceAllRules([
            SSLProxyingRule(domain: "api.example.com", listType: .exclude)
        ])
        manager.replaceAllApplicationRules([])
        manager.setEnabled(true)

        coordinator.setSSLProxyingFromInspector(
            for: identity,
            listType: .include,
            fallbackDomain: "api.example.com"
        )

        #expect(coordinator.activeToast?.style == .warning)
        #expect(coordinator.activeToast?.text.contains("api.example.com") == true)
        #expect(coordinator.activeToast?.text.contains("Change that host behavior") == true)
        #expect(coordinator.isSSLProxyingEnabled(for: identity))
        #expect(!manager.isDecryptionConfigured(host: "api.example.com", application: identity))
    }

    @Test("application tunnel action wins over a host decrypt rule")
    func applicationTunnelWinsOverHostDecrypt() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalHostRules = manager.rules
        let originalAppRules = manager.applicationRules
        defer {
            manager.replaceAllRules(originalHostRules)
            manager.replaceAllApplicationRules(originalAppRules)
        }
        let identity = ClientApplicationIdentity.bundle(
            identifier: "com.microsoft.VSCode",
            displayName: "Visual Studio Code"
        )
        manager.replaceAllRules([
            SSLProxyingRule(domain: "api.example.com", listType: .include)
        ])
        manager.replaceAllApplicationRules([])

        coordinator.setSSLProxyingBehaviorForApplication(identity, listType: .exclude)

        #expect(!manager.shouldIntercept(host: "api.example.com", application: identity))
        #expect(!coordinator.isSSLProxyingEnabled(for: identity))
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

    @Test("one-host Tunnel preserves wildcard Decrypt for sibling hosts")
    func tunnelHostPreservesWildcardDecrypt() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalBypassDomains = manager.bypassDomains
        defer {
            manager.replaceAllRules(originalRules)
            manager.setBypassDomains(originalBypassDomains)
        }

        manager.setBypassDomains("")
        let wildcardDecrypt = SSLProxyingRule(domain: "*.example.com", listType: .include)
        manager.replaceAllRules([wildcardDecrypt])

        #expect(coordinator.disableSSLProxyingForDomain("api.example.com"))
        #expect(manager.rules.contains(where: { $0.id == wildcardDecrypt.id }))
        #expect(!manager.isDecryptionConfigured(host: "api.example.com"))
        #expect(manager.isDecryptionConfigured(host: "cdn.example.com"))
    }

    @Test("Decrypting a domain row covers the hosts grouped under it")
    func domainGroupDecryptCoversSubdomains() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalEnabled = manager.isEnabled
        let originalBypassDomains = manager.bypassDomains
        defer {
            manager.replaceAllRules(originalRules)
            manager.setEnabled(originalEnabled)
            manager.setBypassDomains(originalBypassDomains)
        }
        manager.setBypassDomains("")
        // An earlier exact Tunnel on one host must not keep it opaque.
        manager.replaceAllRules([SSLProxyingRule(domain: "api.example.org", listType: .exclude)])
        let hosts = ["www.example.org", "api.example.org"]

        #expect(!coordinator.isSSLProxyingEnabled(forDomainGroup: "example.org", hosts: hosts))
        #expect(coordinator.enableSSLProxying(forDomainGroup: "example.org", hosts: hosts))

        #expect(manager.isDecryptionConfigured(host: "example.org"))
        #expect(manager.isDecryptionConfigured(host: "www.example.org"))
        #expect(manager.isDecryptionConfigured(host: "api.example.org"))
        #expect(manager.isDecryptionConfigured(host: "cdn.example.org"))
        #expect(coordinator.isSSLProxyingEnabled(forDomainGroup: "example.org", hosts: hosts))

        #expect(coordinator.disableSSLProxying(forDomainGroup: "example.org", hosts: hosts))
        #expect(!manager.isDecryptionConfigured(host: "www.example.org"))
        #expect(!manager.isDecryptionConfigured(host: "api.example.org"))
        #expect(!coordinator.isSSLProxyingEnabled(forDomainGroup: "example.org", hosts: hosts))
    }

    @Test("A domain row is only shown as decrypted when every grouped host is")
    func domainGroupStatusNeedsEveryHost() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalEnabled = manager.isEnabled
        let originalBypassDomains = manager.bypassDomains
        defer {
            manager.replaceAllRules(originalRules)
            manager.setEnabled(originalEnabled)
            manager.setBypassDomains(originalBypassDomains)
        }
        manager.setBypassDomains("")
        manager.setEnabled(true)
        manager.replaceAllRules([SSLProxyingRule(domain: "example.org", listType: .include)])

        #expect(coordinator.isSSLProxyingEnabled(for: "example.org"))
        #expect(!coordinator.isSSLProxyingEnabled(forDomainGroup: "example.org", hosts: ["www.example.org"]))
    }

    @Test("observedDomainsForApp falls back to matching transactions and current host")
    func observedDomainsForAppFallsBackToTransactions() {
        let coordinator = MainContentCoordinator()
        TrafficDomainSnapshot.shared.reset()
        defer { TrafficDomainSnapshot.shared.reset() }

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
        coordinator.rebuildObservedDomainsByApp()

        let domains = coordinator.observedDomainsForApp(
            named: "Google Chrome",
            fallbackDomain: "api.example.com"
        )

        #expect(domains == ["api.example.com", "cdn.example.com"])
    }

    @Test("name-only inspector scope reuses one unambiguous observed application identity")
    func observedApplicationIdentityIsFailClosed() {
        let coordinator = MainContentCoordinator()
        let chrome = ClientApplicationIdentity.bundle(
            identifier: "com.google.Chrome",
            displayName: "Google Chrome"
        )
        let lookalike = ClientApplicationIdentity.bundle(
            identifier: "com.example.Chrome",
            displayName: "Google Chrome"
        )
        TrafficDomainSnapshot.shared.reset()
        defer { TrafficDomainSnapshot.shared.reset() }

        coordinator.appNodes = [
            AppInfo(name: "Google Chrome", domains: ["api.example.com"], requestCount: 1),
            AppInfo(name: "Google Chrome", domains: ["cdn.example.com"], requestCount: 1, identity: chrome),
        ]
        #expect(coordinator.observedApplicationIdentity(named: " google chrome ") == chrome)

        coordinator.appNodes.append(
            AppInfo(name: "Google Chrome", domains: ["other.example.com"], requestCount: 1, identity: lookalike)
        )
        #expect(coordinator.observedApplicationIdentity(named: "Google Chrome") == nil)
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
                "Added host Decrypt rules for domains observed from Google Chrome. These rules apply to every application."
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
                "Set domains observed from Google Chrome to Tunnel. These host rules apply to every application."
        )
    }

    @Test("disableSSLProxyingFromInspector for domain clears rule and shows toast")
    func disableFromInspectorForDomainShowsToast() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let rule = SSLProxyingRule(domain: "api.example.com", listType: .include)
        manager.addRule(rule)
        defer { manager.replaceAllRules(originalRules) }

        coordinator.disableSSLProxyingFromInspector(for: "api.example.com")

        #expect(!coordinator.isSSLProxyingEnabled(for: "api.example.com"))
        #expect(
            coordinator.activeToast?.text ==
                "Disabled HTTPS Decryption for api.example.com. Requests to it will stay tunneled."
        )
    }

    @Test("inspector warns instead of claiming success under a broader Tunnel rule")
    func inspectorWarnsForBroaderTunnel() {
        let coordinator = MainContentCoordinator()
        let manager = SSLProxyingManager.shared
        let originalRules = manager.rules
        let originalBypassDomains = manager.bypassDomains
        defer {
            manager.replaceAllRules(originalRules)
            manager.setBypassDomains(originalBypassDomains)
        }

        manager.setBypassDomains("")
        manager.replaceAllRules([
            SSLProxyingRule(domain: "*.example.com", listType: .exclude)
        ])

        coordinator.enableSSLProxyingFromInspector(for: "api.example.com")

        #expect(coordinator.activeToast?.style == .warning)
        #expect(coordinator.activeToast?.text.contains("*.example.com") == true)
        #expect(manager.includeRules.isEmpty)
    }
}
