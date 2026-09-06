import Foundation

// MARK: - HelperCompatibilityDecision

/// How an installed helper compares to what this app build expects.
enum HelperCompatibilityDecision: Equatable {
    /// The installed helper supports every user-facing operation required by this app.
    case compatible
    /// Still usable for the operations it already implements, but it has to be updated before
    /// anything newer can be asked of it.
    case outdated
    /// Nothing may be assumed about this helper, so no operation is attempted.
    case incompatible
}

// MARK: - HelperCompatibilityPolicy

/// Decides what an installed helper may be asked to do, from the protocol version it
/// advertises over XPC.
///
/// The build number never infers a capability. Shipped copies of Rockxy exist whose embedded
/// helper carries a build number at or above the one in this checkout while still speaking
/// protocol 1, so a `build >= N` threshold would advertise a selector that helper does not
/// implement — the app would send it and the message would fail at the XPC boundary. The
/// protocol version is the only value that describes the interface, so every capability
/// decision is made from it alone.
enum HelperCompatibilityPolicy {
    // MARK: Internal

    /// The protocol version that introduced DER-specific root certificate removal.
    ///
    /// The selector was added additively: protocol 1 helpers keep answering every operation
    /// they already implemented.
    static let exactCertificateRemovalProtocolVersion = 2

    /// The protocol version whose `installRootCertificate` is non-destructive.
    ///
    /// The selector itself is as old as protocol 1, so its presence proves nothing. What changed
    /// at protocol 2 is the behaviour behind it: the older helper deletes every certificate
    /// carrying the root CA label before adding the new one, which destroys a root the user may
    /// still be relying on and cannot be undone by the app. Only a helper known to speak
    /// protocol 2 may be asked to install; anything else is told nothing and the app installs
    /// its own copy instead.
    static let safeCertificateInstallProtocolVersion = 2

    /// The protocol version that introduced approval-preserving executable refresh.
    static let executableRefreshProtocolVersion = 3

    /// Classifies an installed helper without ever reading a capability out of the build
    /// number.
    ///
    /// - A protocol older than expected, but still one this app knows how to talk to, is
    ///   `.outdated` regardless of its build unless the exact transition is explicitly declared
    ///   maintenance-only. Certificate operations have their own protocol capability gates.
    /// - The exact expected protocol falls through to the normal build comparison.
    /// - A nonpositive, unknown, or newer-than-expected protocol fails closed.
    static func classify(
        installedProtocolVersion: Int,
        installedBuildNumber: Int,
        expectedProtocolVersion: Int,
        bundledBuildNumber: Int
    )
        -> HelperCompatibilityDecision
    {
        guard knownProtocolVersions.contains(installedProtocolVersion),
              knownProtocolVersions.contains(expectedProtocolVersion)
        else {
            // A missing or unreadable protocol version describes nothing.
            return .incompatible
        }
        guard installedProtocolVersion <= expectedProtocolVersion else {
            // A protocol newer than this build knows cannot be reasoned about either.
            return .incompatible
        }
        if maintenanceOnlyUpgradePairs.contains(ProtocolPair(
            installed: installedProtocolVersion,
            expected: expectedProtocolVersion
        )) {
            return .compatible
        }
        if installedProtocolVersion < expectedProtocolVersion {
            return backwardCompatibleProtocolVersions.contains(installedProtocolVersion)
                ? .outdated
                : .incompatible
        }
        return installedBuildNumber >= bundledBuildNumber ? .compatible : .outdated
    }

    /// Whether the helper on the other end of a live connection implements the DER-specific
    /// removal selector.
    ///
    /// Fail-closed by design: only the protocol version that introduced the selector qualifies.
    /// A protocol this build does not know about may have changed the selector's contract, and
    /// guessing would send privileged removal bytes to an interface nobody here has seen. Raise
    /// this alongside `exactCertificateRemovalProtocolVersion` when the protocol moves on.
    static func supportsExactCertificateRemoval(protocolVersion: Int) -> Bool {
        certificateMutationProtocolVersions.contains(protocolVersion)
    }

    /// Whether the helper on the other end of a live connection installs non-destructively.
    ///
    /// Fail-closed for the same reason as removal, and for one more: the build number cannot
    /// stand in here either. Shipped app copies embed a helper whose build number is at or above
    /// this checkout's while it still speaks protocol 1 and still sweeps the label on install.
    static func supportsSafeCertificateInstall(protocolVersion: Int) -> Bool {
        certificateMutationProtocolVersions.contains(protocolVersion)
    }

    /// Whether the helper can exit on request so launchd starts the executable from the updated
    /// app bundle without unregistering the approved service.
    static func supportsExecutableRefresh(protocolVersion: Int) -> Bool {
        protocolVersion == executableRefreshProtocolVersion
    }

    // MARK: Private

    /// Every helper protocol whose contract this app can reason about.
    private static let knownProtocolVersions: Set<Int> = [1, 2, 3]

    /// Older protocol versions whose already-implemented operations stay safe to call.
    private static let backwardCompatibleProtocolVersions: Set<Int> = [1, 2]

    /// Protocol 3 adds a selector without changing the protocol-2 certificate contracts.
    private static let certificateMutationProtocolVersions: Set<Int> = [2, 3]

    /// Protocol 3 adds only an approval-preserving maintenance operation. A protocol-2 helper
    /// remains fully operational and must not turn onboarding incomplete or demand reinstall
    /// after an app update. Fresh installs gain protocol 3; protocol-3 build refreshes then happen
    /// silently without weakening protocol-based capability checks.
    private static let maintenanceOnlyUpgradePairs: Set<ProtocolPair> = [
        ProtocolPair(installed: 2, expected: 3),
    ]

    private struct ProtocolPair: Hashable {
        let installed: Int
        let expected: Int
    }
}
