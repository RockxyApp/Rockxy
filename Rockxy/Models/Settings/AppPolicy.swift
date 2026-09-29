import Foundation

// MARK: - AppPolicy

/// Defines app-level capacity and feature limits.
///
/// The public baseline is ``DefaultAppPolicy``. Community-vs-capability
/// decisions flow through this protocol at app/model boundaries so Core
/// engines stay reusable and edition-neutral.
protocol AppPolicy: Sendable {
    var maxWorkspaceTabs: Int { get }
    var maxProjects: Int { get }
    var maxDomainFavorites: Int { get }
    var maxActiveRulesPerTool: Int { get }
    var maxEnabledScripts: Int { get }
    /// Maximum in-memory traffic history retained independently by each Project.
    /// The overall bound is this value multiplied by the bounded Project capacity.
    var maxLiveHistoryEntries: Int { get }
    var upstreamProxyAllowsSOCKS5: Bool { get }
    var upstreamProxyAllowsAuthentication: Bool { get }
    var maxUpstreamProxyBypassEntries: Int { get }
    var protobufDecodingAllowsSchemaUpload: Bool { get }
    var maxProtobufSchemas: Int { get }
    /// Whether a traffic tab can show a second pane beside it (split view).
    var allowsTrafficSplitView: Bool { get }
}

extension AppPolicy {
    /// Public default project capacity. Clamped to the repository's structural
    /// range (``ProjectStructuralLimits/projectCountRange``) by ``ProjectStore``.
    /// Capacity is product policy; structural safety limits are not.
    var maxProjects: Int {
        ProjectStructuralLimits.defaultProjectCapacity
    }

    var upstreamProxyAllowsSOCKS5: Bool {
        false
    }

    var upstreamProxyAllowsAuthentication: Bool {
        false
    }

    var maxUpstreamProxyBypassEntries: Int {
        3
    }

    var protobufDecodingAllowsSchemaUpload: Bool {
        false
    }

    var maxProtobufSchemas: Int {
        0
    }

    var allowsTrafficSplitView: Bool {
        false
    }
}

// MARK: - DefaultAppPolicy

/// The public open-source default policy. All values are hardcoded here
/// and represent the baseline experience.
struct DefaultAppPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxProjects = 3
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
    let upstreamProxyAllowsSOCKS5 = false
    let upstreamProxyAllowsAuthentication = false
    let maxUpstreamProxyBypassEntries = 3
    let protobufDecodingAllowsSchemaUpload = false
    let maxProtobufSchemas = 0
    let allowsTrafficSplitView = false
}
