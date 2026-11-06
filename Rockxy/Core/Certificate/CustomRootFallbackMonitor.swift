import Foundation
import os
import X509

// MARK: - CustomRootFallbackMonitor

/// Resolves the user's custom root for `CertificateManager` and keeps the one fact that must never
/// be silent: whether Rockxy is signing with its own root *instead of* the one the user configured.
///
/// A custom root whose private key is unreadable -- removed from Keychain, written by a different
/// app identity, or saved in a form the parser rejects -- used to propagate out of
/// `certificateForHost`, which made the TLS pipeline abandon interception and relay the connection
/// as an opaque raw tunnel, stopping decryption for every host. Rockxy's own root can sign for the
/// host perfectly well, so the fallback keeps intercepting. The cost of that choice is that the
/// user keeps trusting a root that is not the one in use; `reason` is how that is discovered.
///
/// `activeRootIssuerSnapshot` keeps throwing for the certificate UI, which reports the broken root
/// itself. This type only decides what the proxy does about it, and says so.
nonisolated final class CustomRootFallbackMonitor: @unchecked Sendable {
    // MARK: Lifecycle

    init(customCertificates: CustomCertificateManager) {
        self.customCertificates = customCertificates
    }

    // MARK: Internal

    typealias Issuer = (certificate: Certificate, privateKey: Certificate.PrivateKey, fingerprintSHA256: String)

    /// Why the custom root is not the one signing host certificates, or `nil` while it is in use
    /// or none is configured. Set when it cannot be loaded; cleared as soon as it loads again or
    /// is removed. `.customRootFallbackDidChange` is posted (object: this monitor) on every change.
    var reason: String? {
        lock.withLock { current }
    }

    /// The active custom root, or `nil` when there is none *or* it cannot be used. Runs per
    /// intercepted connection; a healthy root is memoized by `CustomCertificateManager`.
    func resolve() -> Issuer? {
        do {
            let snapshot = try customCertificates.activeRootIssuerSnapshot()
            update(nil)
            return snapshot
        } catch {
            let message = String(
                localized: "Your custom root certificate could not be loaded (\(error.localizedDescription)). Rockxy is signing with its own root instead, so your custom root is not in use.",
                bundle: RockxyLocalization.bundle
            )
            // Logged once per distinct reason: a broken root stays broken until it is replaced.
            // No privacy specifier: the reason is parser text, so the default redaction keeps
            // anything it echoed out of the persisted log.
            if update(message) {
                Self.logger.error(
                    "Custom root CA is unusable (\(error.localizedDescription)) — signing host certificates with Rockxy's own root instead"
                )
            }
            return nil
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "CustomRootFallback"
    )

    private let customCertificates: CustomCertificateManager
    private let lock = NSLock()
    private var current: String?

    /// Returns true when the reason changed, after posting the change notification.
    @discardableResult
    private func update(_ reason: String?) -> Bool {
        let changed = lock.withLock {
            guard current != reason else {
                return false
            }
            current = reason
            return true
        }
        if changed {
            NotificationCenter.default.post(name: .customRootFallbackDidChange, object: self)
        }
        return changed
    }
}

extension Notification.Name {
    /// Posted by `CustomRootFallbackMonitor` when its `reason` changes.
    static let customRootFallbackDidChange = Notification.Name("RockxyCustomRootFallbackDidChange")
}
