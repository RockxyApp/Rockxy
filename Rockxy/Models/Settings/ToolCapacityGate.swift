import Foundation

// MARK: - ToolCapacityGate

/// Capacity limits for organizing and multiplying tool configuration (rule folders, Reverse Proxy
/// rules, DNS Spoofing rules). The limits come from the injected ``AppPolicy``; the stores that
/// enforce them never look at which edition is running.
@MainActor
final class ToolCapacityGate {
    // MARK: Lifecycle

    init(policy: any AppPolicy = DefaultAppPolicy()) {
        self.policy = policy
    }

    // MARK: Internal

    /// Shared gate. `MainContentCoordinator.configureSharedGates()` rebinds it once at startup to
    /// inject the runtime policy; serialized tests may rebind it and must restore it in `defer`.
    static var shared = ToolCapacityGate()

    let policy: any AppPolicy

    var maxRuleFoldersPerTool: Int {
        policy.maxRuleFoldersPerTool
    }

    var maxReverseProxyRules: Int {
        policy.maxReverseProxyRules
    }

    var maxDNSSpoofingRules: Int {
        policy.maxDNSSpoofingRules
    }
}
