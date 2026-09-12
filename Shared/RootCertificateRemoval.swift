import CommonCrypto
import Foundation
import Security

// Shared rules for removing a Rockxy root CA certificate from the system keychain. The
// privileged helper owns the Security.framework and trust-settings side effects; everything
// that decides *what* is removed, in which order, and when a removal counts as done lives
// here so it can be exercised without a System keychain, a trusted CA, or the real daemon.

// MARK: - SystemKeychainCertificate

/// One certificate item the System keychain returned, paired with the exact bytes that
/// identify it.
///
/// The reference is what a deletion addresses through `kSecMatchItemList`; the DER is what
/// selects it. Neither substitutes for the other: a label or a common name would address
/// certificates nobody inspected, and a freshly constructed reference is not a search
/// constraint on macOS.
///
/// The System keychain adapter puts the item's *persistent* reference here. A transient
/// `SecCertificate` can stop addressing its item while that item is still installed, which
/// surfaced as a spurious `errSecItemNotFound` (-25300) during deletion.
struct SystemKeychainCertificate {
    let reference: AnyObject
    let derData: Data
}

// MARK: - RootCertificateRemovalOperations

/// The privileged keychain and trust-settings work a removal needs.
///
/// Every method is scoped to `System.keychain` and the `.admin` trust domain in production.
/// The root helper never touches a user-domain trust setting: those belong to the console
/// user's session, not to a daemon running as root.
protocol RootCertificateRemovalOperations {
    /// Candidates narrowed by the indexed serial number. An unknown status or a result whose
    /// shape cannot be read throws — it must never be reported as "nothing is installed".
    func systemCertificates(serialNumber: Data) throws -> [SystemKeychainCertificate]

    /// Candidates carrying `label`. Used only by the legacy sweeps, which still discover by
    /// the label they installed under and then remove each certificate by exact DER.
    func systemCertificates(label: String) throws -> [SystemKeychainCertificate]

    /// Whether *any* admin trust settings exist for exactly this certificate, including an
    /// empty array, a defaulted constraints entry, and a deny.
    func hasAdminTrustSettings(derData: Data) throws -> Bool

    /// Removes the admin trust settings for exactly this certificate, or throws.
    func removeAdminTrustSettings(derData: Data) throws

    /// Deletes exactly the items that were already inspected.
    func deleteSystemCertificates(_ certificates: [SystemKeychainCertificate]) throws
}

// MARK: - RootCertificateRemovalError

enum RootCertificateRemovalError: LocalizedError, Equatable {
    case emptyCertificateData
    case oversizedCertificateData(bytes: Int)
    case unreadableCertificateData
    case unexpectedCommonName(String?)
    case notSelfIssued
    case unreadableSerialNumber
    case trustSettingsRemain(fingerprint: String)
    case certificateStillInstalled(fingerprint: String)
    case keychainFailure(operation: String, status: OSStatus)
    case malformedKeychainResult(operation: String)
    case trustRemovalFailed(detail: String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .emptyCertificateData:
            "No certificate data was supplied"
        case let .oversizedCertificateData(bytes):
            "Certificate data too large (\(bytes) bytes) — maximum \(RootCertificateRemover.maximumCertificateByteCount)"
        case .unreadableCertificateData:
            "Invalid certificate data — could not create SecCertificate"
        // Ownership validation is shared by installation and removal, so its diagnostics name
        // the certificate rather than the operation that rejected it.
        case let .unexpectedCommonName(commonName):
            "Not a Rockxy root CA — its common name is \(commonName.map { "\u{201C}\($0)\u{201D}" } ?? "unreadable")"
        case .notSelfIssued:
            "Not a Rockxy root CA — the certificate is not self-issued"
        case .unreadableSerialNumber:
            "Could not read the certificate serial number"
        case let .trustSettingsRemain(fingerprint):
            "Trust settings for certificate \(fingerprint) still exist after removal"
        case let .certificateStillInstalled(fingerprint):
            "Certificate \(fingerprint) is still installed after removal"
        case let .keychainFailure(operation, status):
            "Keychain \(operation) failed: OSStatus \(status)"
        case let .malformedKeychainResult(operation):
            "Keychain \(operation) returned an unreadable result"
        case let .trustRemovalFailed(detail):
            "Failed to remove trust settings: \(detail)"
        }
    }
}

// MARK: - RootCertificateRemover

/// Removes exactly one Rockxy root CA certificate, identified by its DER bytes.
///
/// The ordering is the point. Admin trust settings are stored independently of the keychain
/// item, so the certificate that identifies them is deleted only after the trust removal has
/// been performed *and* verified — deleting first leaves a system that still trusts a root
/// nothing can address any more.
enum RootCertificateRemover {
    // MARK: Internal

    /// What one exact removal actually did.
    struct RemovalOutcome: Equatable {
        let removedCertificateCount: Int
        let removedTrustSettings: Bool
    }

    /// What a legacy label sweep did. Failures never stop the remaining certificates, and the
    /// count reports only removals that completed and verified.
    struct LegacyRemovalOutcome: Equatable {
        let removedCount: Int
        let failures: [String]

        var isComplete: Bool {
            failures.isEmpty
        }

        var failureDetail: String? {
            failures.isEmpty ? nil : failures.joined(separator: "; ")
        }
    }

    /// One validated removal target.
    struct Target: Equatable {
        let derData: Data
        let serialNumber: Data
        let fingerprint: String
    }

    static let maximumCertificateByteCount = 10_000

    /// The legacy subject common name and prefix every Rockxy root CA carries.
    static let expectedCommonName = "Rockxy Root CA"
    static let keySpecificCommonNamePrefix = "\(expectedCommonName) "

    /// Validates that the supplied bytes describe a certificate this helper owns.
    ///
    /// This is an ownership scope, not authentication: a caller that can already reach the
    /// privileged service is authenticated by the connection's caller validation, which is
    /// unchanged. What this adds is a bound on *what* that caller may delete — a well-formed
    /// certificate of Rockxy's own shape — so an unrelated system root can never be passed in
    /// and removed by a privileged process.
    static func validate(derData: Data) throws -> Target {
        guard !derData.isEmpty else {
            throw RootCertificateRemovalError.emptyCertificateData
        }
        guard derData.count < maximumCertificateByteCount else {
            throw RootCertificateRemovalError.oversizedCertificateData(bytes: derData.count)
        }
        guard let certificate = SecCertificateCreateWithData(nil, derData as CFData) else {
            throw RootCertificateRemovalError.unreadableCertificateData
        }

        var copiedCommonName: CFString?
        let commonNameStatus = SecCertificateCopyCommonName(certificate, &copiedCommonName)
        guard commonNameStatus == errSecSuccess, let commonName = copiedCommonName as String? else {
            throw RootCertificateRemovalError.unexpectedCommonName(nil)
        }
        guard ownsCommonName(commonName) else {
            throw RootCertificateRemovalError.unexpectedCommonName(commonName)
        }

        // A Rockxy root is self-issued. Comparing the normalized sequences rejects a leaf that
        // merely borrowed the common name, and does it without a full chain evaluation.
        guard let subject = SecCertificateCopyNormalizedSubjectSequence(certificate) as Data?,
              let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate) as Data?,
              subject == issuer else
        {
            throw RootCertificateRemovalError.notSelfIssued
        }

        guard let serialNumber = SecCertificateCopySerialNumberData(certificate, nil) as Data? else {
            throw RootCertificateRemovalError.unreadableSerialNumber
        }

        return Target(derData: derData, serialNumber: serialNumber, fingerprint: fingerprint(of: derData))
    }

    /// New roots append exactly twelve uppercase hexadecimal characters derived from their
    /// public key. Keep accepting the legacy exact name while rejecting arbitrary lookalikes
    /// that merely begin with the Rockxy prefix.
    private static func ownsCommonName(_ commonName: String) -> Bool {
        guard commonName != expectedCommonName else {
            return true
        }
        guard commonName.hasPrefix(keySpecificCommonNamePrefix) else {
            return false
        }
        let suffix = commonName.dropFirst(keySpecificCommonNamePrefix.count)
        return suffix.count == 12 && suffix.allSatisfy { character in
            "0123456789ABCDEF".contains(character)
        }
    }

    /// Removes exactly the certificate described by `derData`, plus its admin trust settings.
    ///
    /// A target with no installed copy but leftover admin trust is a real state — the
    /// certificate was deleted in Keychain Access while its trust settings survived — so the
    /// trust removal runs whether or not the keychain still holds a copy.
    @discardableResult
    static func removeExactCertificate(
        derData: Data,
        using operations: some RootCertificateRemovalOperations
    )
        throws -> RemovalOutcome
    {
        // Nothing is mutated before the bytes are known to describe a certificate this helper
        // owns, so malformed, oversized, and unrelated input can never reach a delete.
        let target = try validate(derData: derData)

        let installed = try matchingCertificates(for: target, using: operations)

        var removedTrustSettings = false
        if try operations.hasAdminTrustSettings(derData: target.derData) {
            try operations.removeAdminTrustSettings(derData: target.derData)
            guard try !operations.hasAdminTrustSettings(derData: target.derData) else {
                // The certificate is still here to identify the settings that survived, so it
                // must not be deleted.
                throw RootCertificateRemovalError.trustSettingsRemain(fingerprint: target.fingerprint)
            }
            removedTrustSettings = true
        }

        guard !installed.isEmpty else {
            // Orphaned trust settings, or nothing at all: both are complete once the trust
            // state above has been resolved.
            return RemovalOutcome(removedCertificateCount: 0, removedTrustSettings: removedTrustSettings)
        }

        try operations.deleteSystemCertificates(installed)

        guard try matchingCertificates(for: target, using: operations).isEmpty else {
            throw RootCertificateRemovalError.certificateStillInstalled(fingerprint: target.fingerprint)
        }

        return RemovalOutcome(
            removedCertificateCount: installed.count,
            removedTrustSettings: removedTrustSettings
        )
    }

    /// Legacy sweep for the callers that still address certificates by the label they were
    /// installed under.
    ///
    /// Discovery is unchanged — the configured label, never a common-name search that would
    /// widen the sweep to certificates this helper did not install. Each discovered
    /// certificate is then removed through the exact-DER path above, so the ordering and
    /// verification guarantees are identical.
    ///
    /// - Parameter keepingFingerprint: when supplied, the certificate with this SHA-256
    ///   fingerprint is left alone (stale cleanup). `nil` removes every discovered
    ///   certificate.
    static func removeLabeledCertificates(
        label: String,
        keepingFingerprint: String?,
        using operations: some RootCertificateRemovalOperations
    )
        throws -> LegacyRemovalOutcome
    {
        // A discovery failure is not "nothing is installed", so it propagates instead of
        // being reported as a clean sweep.
        let discovered = try operations.systemCertificates(label: label)

        var targets: [Data] = []
        for entry in discovered where !targets.contains(entry.derData) {
            targets.append(entry.derData)
        }

        var removedCount = 0
        var failures: [String] = []
        for derData in targets {
            let digest = fingerprint(of: derData)
            if let keepingFingerprint, digest == keepingFingerprint {
                continue
            }
            do {
                let outcome = try removeExactCertificate(derData: derData, using: operations)
                if outcome.removedCertificateCount > 0 {
                    removedCount += 1
                }
            } catch {
                failures.append("\(digest): \(error.localizedDescription)")
            }
        }

        return LegacyRemovalOutcome(removedCount: removedCount, failures: failures)
    }

    static func fingerprint(of derData: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        derData.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(derData.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    // MARK: Private

    /// The installed items whose bytes are exactly the target's.
    ///
    /// The serial number is only an index: another issuer can mint a certificate with the same
    /// serial, so the DER comparison is what decides.
    private static func matchingCertificates(
        for target: Target,
        using operations: some RootCertificateRemovalOperations
    )
        throws -> [SystemKeychainCertificate]
    {
        try operations.systemCertificates(serialNumber: target.serialNumber)
            .filter { $0.derData == target.derData }
    }
}
