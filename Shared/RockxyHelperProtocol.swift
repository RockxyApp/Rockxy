import Foundation

/// XPC protocol shared between the Rockxy macOS app and RockxyHelperTool.
/// All methods use the `withReply:` pattern required by NSXPCConnection.
@objc
protocol RockxyHelperProtocol {
    /// Override system HTTP+HTTPS proxy to 127.0.0.1:<port> and associate it
    /// with the owning Rockxy app process for crash cleanup.
    func overrideSystemProxy(port: Int, ownerPID: Int32, withReply reply: @escaping (Bool, String?) -> Void)

    /// Restore original proxy settings saved before override.
    func restoreSystemProxy(withReply reply: @escaping (Bool, String?) -> Void)

    /// Check current proxy state: (isOverridden, currentPort).
    func getProxyStatus(withReply reply: @escaping (Bool, Int) -> Void)

    /// Return structured helper info: binaryVersion, buildNumber, protocolVersion.
    func getHelperInfo(withReply reply: @escaping (String, Int, Int) -> Void)

    /// Uninstall: restore proxy + prepare for removal.
    func prepareForUninstall(withReply reply: @escaping (Bool) -> Void)

    /// Prepare an already registered bundled daemon to be replaced by the executable in the
    /// current app bundle. Added in protocol version 3. The helper replies first, then exits
    /// cleanly; launchd resolves `BundleProgram` again when the app opens the next connection.
    /// This preserves the user's Background Items approval because the service is never
    /// unregistered.
    func prepareForExecutableRefresh(withReply reply: @escaping (Bool) -> Void)

    /// Install the supplied root CA certificate in the system keychain and trust it for SSL.
    ///
    /// Kept for compatibility with app builds that dispatch it; the current app does not. Adding
    /// the certificate works here, but a trust write requiring new approval cannot obtain it:
    /// `.admin` authorization needs an interactive session that this launchd daemon lacks.
    /// The write can therefore be denied even as root — leaving an
    /// installed, untrusted certificate. Trust is therefore established in the app's own GUI
    /// process, and this selector is not a way around the user's approval.
    ///
    /// The selector is as old as protocol 1, but its contract changed at protocol 2: the operation
    /// is now purely additive and verified by the certificate's own bytes, where protocol 1 swept
    /// every certificate carrying the root CA label before adding the new one. Any caller must
    /// therefore confirm through `HelperCompatibilityPolicy.supportsSafeCertificateInstall` that
    /// the *connected* helper speaks protocol 2 before sending this. A build number never implies
    /// the newer behaviour.
    func installRootCertificate(_ derData: Data, withReply reply: @escaping (Bool, String?) -> Void)

    /// Remove Rockxy root CA certificates and trust settings from the system keychain by the
    /// label they were installed under.
    ///
    /// Superseded by `removeRootCertificateMatching(_:withReply:)` and kept only so app builds
    /// that predate protocol version 2 keep working. Current builds never send it.
    func removeRootCertificate(withReply reply: @escaping (Bool, String?) -> Void)

    /// Remove exactly the root CA certificate whose DER bytes are supplied, together with its
    /// admin trust settings.
    ///
    /// Added in protocol version 2. The bytes name one certificate, so a caller can remove the
    /// copy it is actually replacing without sweeping up everything that happens to share a
    /// label or a common name. Requires `HelperCompatibilityPolicy` to confirm the connected
    /// helper speaks protocol 2 before it is sent.
    ///
    /// What this contributes is the System keychain delete, which the app cannot perform. Clearing
    /// the certificate's admin trust settings needs interactive authorization the daemon cannot
    /// obtain, so the app clears them in its own process *before* sending this; a caller that
    /// deletes first would strand trust settings for a certificate no keychain holds any more.
    func removeRootCertificateMatching(_ derData: Data, withReply reply: @escaping (Bool, String?) -> Void)

    /// Verify that a certificate with the given SHA-256 fingerprint is trusted.
    func verifyRootCertificateTrusted(_ fingerprint: String, withReply reply: @escaping (Bool) -> Void)

    /// Remove stale Rockxy Root CA certificates, keeping only the one matching activeFingerprint. Returns count
    /// removed.
    func cleanupStaleCertificates(_ activeFingerprint: String, withReply reply: @escaping (Int, String?) -> Void)

    /// Set the system proxy bypass domain list on all enabled network services.
    func setBypassDomains(_ domains: [String], withReply reply: @escaping (Bool, String?) -> Void)
}
