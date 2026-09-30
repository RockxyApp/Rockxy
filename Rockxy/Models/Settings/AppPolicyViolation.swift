import Foundation

// MARK: - AppPolicyViolation

enum AppPolicyViolation: LocalizedError, Equatable {
    case upstreamProxySOCKS5Unavailable
    case upstreamProxyAuthenticationUnavailable
    case upstreamProxyBypassEntryLimitReached(limit: Int)
    case protobufSchemaUploadUnavailable
    case protobufSchemaLimitReached(limit: Int)
    case trafficSplitViewUnavailable
    case ruleFolderLimitReached(limit: Int)
    case reverseProxyLimitReached(limit: Int)
    case dnsSpoofingLimitReached(limit: Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .upstreamProxySOCKS5Unavailable:
            String(localized: "SOCKS5 upstream proxy is unavailable in this build.", bundle: RockxyLocalization.bundle)
        case .upstreamProxyAuthenticationUnavailable:
            String(
                localized: "Upstream proxy authentication is unavailable in this build.",
                bundle: RockxyLocalization.bundle
            )
        case let .upstreamProxyBypassEntryLimitReached(limit):
            String(
                localized: "Upstream proxy bypass list is limited to \(limit) entries in this build.",
                bundle: RockxyLocalization.bundle
            )
        case .protobufSchemaUploadUnavailable:
            String(localized: "Protobuf schema upload is unavailable in this build.", bundle: RockxyLocalization.bundle)
        case .trafficSplitViewUnavailable:
            String(localized: "Split view is unavailable in this build.", bundle: RockxyLocalization.bundle)
        case let .ruleFolderLimitReached(limit):
            String(
                localized: "Each rule tool is limited to \(limit) folders in this build.",
                bundle: RockxyLocalization.bundle
            )
        case let .reverseProxyLimitReached(limit):
            String(
                localized: "Reverse Proxy is limited to \(limit) rules in this build.",
                bundle: RockxyLocalization.bundle
            )
        case let .dnsSpoofingLimitReached(limit):
            String(
                localized: "DNS Spoofing is limited to \(limit) rules in this build.",
                bundle: RockxyLocalization.bundle
            )
        case let .protobufSchemaLimitReached(limit):
            String(
                localized: "Protobuf schema storage is limited to \(limit) schemas in this build.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}
