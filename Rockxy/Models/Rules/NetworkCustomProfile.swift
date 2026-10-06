import Foundation

// MARK: - NetworkCustomProfile

/// Bandwidth and packet loss for the Custom Network Conditions profile. Latency
/// stays in the rule action's `delayMs`, so rules saved before custom limits
/// existed decode as an unlimited, lossless profile.
struct NetworkCustomProfile: Codable, Equatable, Hashable, Sendable {
    // MARK: Lifecycle

    init(downloadKbps: Int? = nil, uploadKbps: Int? = nil, packetLossPercent: Double = 0) {
        self.downloadKbps = downloadKbps
        self.uploadKbps = uploadKbps
        self.packetLossPercent = packetLossPercent
    }

    // MARK: Internal

    static let unlimited = Self()

    /// Loss at or above this fails every retransmission in practice; Offline covers 100%.
    static let maximumPacketLossPercent = 99.0

    /// Download cap in kilobits per second; `nil` or zero means unlimited.
    var downloadKbps: Int?
    /// Upload cap in kilobits per second; `nil` or zero means unlimited.
    var uploadKbps: Int?
    var packetLossPercent: Double

    var isUnlimited: Bool {
        effectiveDownloadKbps == nil && effectiveUploadKbps == nil && packetLossRate == 0
    }

    var effectiveDownloadKbps: Int? {
        downloadKbps.flatMap { $0 > 0 ? $0 : nil }
    }

    var effectiveUploadKbps: Int? {
        uploadKbps.flatMap { $0 > 0 ? $0 : nil }
    }

    var downloadBytesPerSecond: Int? {
        effectiveDownloadKbps.map { max(1, ($0 * 1_000) / 8) }
    }

    var uploadBytesPerSecond: Int? {
        effectiveUploadKbps.map { max(1, ($0 * 1_000) / 8) }
    }

    /// Loss as a fraction, clamped to the supported range.
    var packetLossRate: Double {
        guard packetLossPercent.isFinite else {
            return 0
        }
        return min(max(packetLossPercent, 0), Self.maximumPacketLossPercent) / 100
    }

    /// A user-facing reason the values cannot be saved, or `nil` when they are valid.
    var validationMessage: String? {
        if (downloadKbps ?? 0) < 0 || (uploadKbps ?? 0) < 0 {
            return String(localized: "Bandwidth can't be negative.", bundle: RockxyLocalization.bundle)
        }
        if !packetLossPercent.isFinite || packetLossPercent < 0 || packetLossPercent > Self.maximumPacketLossPercent {
            return String(
                localized: "Packet loss must be from 0 to 99 percent. Use the Offline profile to drop everything.",
                bundle: RockxyLocalization.bundle
            )
        }
        return nil
    }
}
