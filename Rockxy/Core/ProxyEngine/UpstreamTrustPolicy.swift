import Foundation
import NIOSSL

// Decides how strictly upstream server certificates are validated during HTTPS interception.

// MARK: - UpstreamTrustPolicy

/// Rockxy verifies upstream certificates against the system trust store by default, so a
/// forged origin cannot hide behind the proxy. Staging and internal servers often run on
/// self-signed or private-CA certificates that only the mobile app trusts; the opt-in
/// policy lets those connections be decrypted instead of failing the handshake. It is a
/// user-visible setting (Settings > Tools) and never changes the client-facing certificate.
enum UpstreamTrustPolicy {
    /// The UserDefaults key matching the `@AppStorage` toggle in ToolsSettingsTab.
    static let userDefaultsKey = RockxyIdentity.current.defaultsKey("acceptUntrustedUpstreamCertificates")

    /// `true` when the user chose to accept upstream certificates that fail validation.
    ///
    /// Read live, deliberately, unlike the cached snapshots `NoCacheHeaderMutator` and
    /// `HTTP2ProxyOptions` keep. Those cost a `UserDefaults` lock acquisition on an event
    /// loop too, and the same `didChangeNotification` refresh would work here — but the
    /// notification orders the flip against later reads only, so a cached `true` can outlive
    /// the moment the user turns verification back on, and the one connection that catches
    /// that window is decrypted without checking the origin's certificate. That is the guard
    /// the default exists to provide (`security.md`: a forged origin must not hide behind the
    /// proxy), and it is not recoverable on the next request the way a stale cache-control
    /// header or ALPN offer is. This is read once per intercepted connection, not per
    /// request, so the contention it avoids is not worth that window.
    nonisolated static var acceptsUntrustedCertificates: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// The verification mode to apply to a client TLS configuration under the current policy.
    nonisolated static func certificateVerification(acceptingUntrusted: Bool) -> CertificateVerification {
        acceptingUntrusted ? .none : .fullVerification
    }
}
