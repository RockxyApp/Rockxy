import Foundation

/// Named presets for common Network Conditions profiles.
enum NetworkConditionPreset: String, CaseIterable, Codable {
    case threeG
    case edge
    case lte
    case veryBadNetwork
    case wifi
    case custom

    // MARK: Internal

    var displayName: String {
        switch self {
        // Cellular/network standard names render verbatim regardless of language.
        case .threeG: "3G"
        case .edge: "EDGE"
        case .lte: "LTE"
        case .wifi: "WiFi"
        case .veryBadNetwork: String(localized: "Very Bad Network", bundle: RockxyLocalization.bundle)
        case .custom: String(localized: "Custom", bundle: RockxyLocalization.bundle)
        }
    }

    var defaultLatencyMs: Int {
        switch self {
        case .threeG: 400
        case .edge: 850
        case .lte: 50
        case .veryBadNetwork: 2_000
        case .wifi: 2
        case .custom: 0
        }
    }

    /// Download bandwidth cap in kilobits per second. `nil` means the profile does
    /// not apply a bandwidth cap, which is currently only true for Custom.
    var downloadBandwidthKbps: Int? {
        switch self {
        case .threeG: 780
        case .edge: 240
        case .lte: 50_000
        case .veryBadNetwork: 1_000
        case .wifi: 40_000
        case .custom: nil
        }
    }

    /// Upload bandwidth cap in kilobits per second. `nil` means the profile does
    /// not apply a bandwidth cap, which is currently only true for Custom.
    var uploadBandwidthKbps: Int? {
        switch self {
        case .threeG: 330
        case .edge: 200
        case .lte: 10_000
        case .veryBadNetwork: 1_000
        case .wifi: 30_000
        case .custom: nil
        }
    }

    var downloadBandwidthLabel: String {
        Self.bandwidthLabel(for: downloadBandwidthKbps)
    }

    var uploadBandwidthLabel: String {
        Self.bandwidthLabel(for: uploadBandwidthKbps)
    }

    var packetLossLabel: String {
        String(format: "%.1f%%", packetLossRate)
    }

    var downloadBytesPerSecond: Int? {
        downloadBandwidthKbps.map { ($0 * 1_000) / 8 }
    }

    var uploadBytesPerSecond: Int? {
        uploadBandwidthKbps.map { ($0 * 1_000) / 8 }
    }

    /// Packet loss remains disabled until the proxy engine has packet-dropping
    /// semantics for HTTP body chunks and WebSocket frames.
    var packetLossRate: Double {
        0.0
    }

    var systemImage: String {
        switch self {
        case .threeG: "antenna.radiowaves.left.and.right"
        case .edge: "antenna.radiowaves.left.and.right"
        case .lte: "cellularbars"
        case .veryBadNetwork: "wifi.slash"
        case .wifi: "wifi"
        case .custom: "slider.horizontal.3"
        }
    }

    static func from(delayMs: Int) -> NetworkConditionPreset {
        for preset in allCases where preset != .custom {
            if preset.defaultLatencyMs == delayMs {
                return preset
            }
        }
        return .custom
    }

    static func makeRule(
        preset: NetworkConditionPreset,
        latencyMs: Int,
        name: String,
        matchCondition: RuleMatchCondition
    )
        -> ProxyRule
    {
        ProxyRule(
            name: name,
            matchCondition: matchCondition,
            action: .networkCondition(preset: preset, delayMs: latencyMs)
        )
    }

    // MARK: Private

    private static func bandwidthLabel(for kbps: Int?) -> String {
        guard let kbps else {
            return "Unlimited"
        }
        if kbps >= 1_000, kbps.isMultiple(of: 1_000) {
            return "< \(kbps / 1_000) Mbps"
        }
        return "< \(kbps) kbps"
    }
}
