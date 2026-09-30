import Foundation
@testable import Rockxy
import Testing

// MARK: - ToolCapacityPolicyTests

/// Rule folders, Reverse Proxy rules and DNS Spoofing rules are limited by the injected policy;
/// a policy with larger limits lifts them without any change in the stores.
@MainActor
struct ToolCapacityPolicyTests {
    // MARK: Internal

    @Test("The default policy caps folders, Reverse Proxy rules and DNS Spoofing rules")
    func defaultLimits() {
        let policy = DefaultAppPolicy()
        #expect(policy.maxRuleFoldersPerTool == 3)
        #expect(policy.maxReverseProxyRules == 2)
        #expect(policy.maxDNSSpoofingRules == 5)
    }

    @Test("A folder past the limit is refused with an explanation; existing folders stay")
    func folderLimit() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RuleFolderStore(tool: "cap", defaults: defaults, maxFolders: { 2 })

        #expect(store.createFolder(named: "A") != nil)
        #expect(store.createFolder(named: "B") != nil)
        #expect(store.canCreateFolder == false)
        #expect(store.createFolder(named: "C") == nil)
        #expect(store.folders.count == 2)
        #expect(store.limitMessage?.contains("2") == true)

        let raised = RuleFolderStore(tool: "cap", defaults: defaults, maxFolders: { 10 })
        #expect(raised.createFolder(named: "C") != nil, "a larger policy limit lifts the cap")
        #expect(raised.folders.count == 3)
    }

    @Test("Reverse Proxy refuses a new rule at the limit but still edits existing ones")
    func reverseProxyLimit() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReverseProxyStore(defaults: defaults, maxRules: { 1 })
        var first = ReverseProxyRule(
            name: "One",
            localPort: 10_000,
            remoteScheme: .https,
            remoteHost: "a.example.com",
            remotePort: 443
        )
        let second = ReverseProxyRule(
            name: "Two",
            localPort: 10_001,
            remoteScheme: .https,
            remoteHost: "b.example.com",
            remotePort: 443
        )
        #expect(store.upsert(first))
        #expect(store.upsert(second) == false)
        #expect(store.rules.count == 1)
        first.name = "Renamed"
        #expect(store.upsert(first), "editing a rule is never blocked by the limit")
        #expect(store.rules.first?.name == "Renamed")
    }

    @Test("DNS Spoofing refuses a new rule at the limit but still edits existing ones")
    func dnsSpoofingLimit() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DNSSpoofingStore(defaults: defaults, table: DNSSpoofingTable(), maxRules: { 1 })
        var first = DNSSpoofingRule(host: "a.example.com", address: "127.0.0.1")
        let second = DNSSpoofingRule(host: "b.example.com", address: "127.0.0.1")
        #expect(store.upsert(first))
        #expect(store.upsert(second) == false)
        first.address = "127.0.0.2"
        #expect(store.upsert(first))
        #expect(store.rules.count == 1)
    }

    @Test("Limits come from the injected policy, not from an edition check")
    func gateFollowsPolicy() {
        let previous = ToolCapacityGate.shared
        defer { ToolCapacityGate.shared = previous }
        ToolCapacityGate.shared = ToolCapacityGate(policy: UnlimitedPolicy())
        #expect(ToolCapacityGate.shared.maxRuleFoldersPerTool == .max)
        #expect(ToolCapacityGate.shared.maxReverseProxyRules == .max)
        #expect(ToolCapacityGate.shared.maxDNSSpoofingRules == .max)
    }

    // MARK: Private

    private struct UnlimitedPolicy: AppPolicy {
        let maxWorkspaceTabs = Int.max
        let maxDomainFavorites = Int.max
        let maxActiveRulesPerTool = Int.max
        let maxEnabledScripts = Int.max
        let maxLiveHistoryEntries = Int.max
        let maxRuleFoldersPerTool = Int.max
        let maxReverseProxyRules = Int.max
        let maxDNSSpoofingRules = Int.max
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "ToolCapacityPolicyTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }
}
