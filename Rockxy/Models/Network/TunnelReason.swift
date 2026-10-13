import Foundation

// MARK: - TunnelReason

/// Why Rockxy passed an HTTPS connection through without decrypting it, recorded when the
/// connection was captured. The inspector reads this instead of re-deriving the reason from the
/// current settings, which may have changed since the row was captured.
enum TunnelReason: String, Codable, Sendable {
    /// The host matched the Bypass Proxy list.
    case bypassList
    /// No HTTPS Decryption rule covered the host, or a Tunnel rule applied.
    case noDecryptionRule
    /// An app Tunnel rule was active and the connecting app could not be identified in time.
    case unresolvedApplication
    /// The app rejected Rockxy's certificate earlier, so the host was tunneled automatically.
    case autoPassthrough

    // MARK: Internal

    /// One sentence describing the capture-time decision, shown with the HTTPS prompt.
    var captureNote: String {
        switch self {
        case .bypassList:
            String(
                localized: "When captured, this host was on the Bypass Proxy list.",
                bundle: RockxyLocalization.bundle
            )
        case .noDecryptionRule:
            String(
                localized: "When captured, this host was not set to be decrypted: no HTTPS Decryption rule applied, a Tunnel rule excluded it, or the certificate was not ready.",
                bundle: RockxyLocalization.bundle
            )
        case .unresolvedApplication:
            String(
                localized: "When captured, an app Tunnel rule was active and Rockxy could not identify the app in time, so it kept the connection encrypted.",
                bundle: RockxyLocalization.bundle
            )
        case .autoPassthrough:
            String(
                localized: "When captured, this host was tunneled automatically because the app had rejected Rockxy's certificate before.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}
