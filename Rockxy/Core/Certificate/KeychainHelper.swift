import Crypto
import Foundation
import os
import Security

// Implements keychain helper behavior for the certificate and trust pipeline.

// MARK: - KeychainReadOutcome

/// How a Keychain read status must be interpreted when looking for the root CA private key.
/// Only `absent` may advance to the next storage shape or report "no key at all"; every other
/// failure has to propagate, so a locked or otherwise unavailable Keychain can never be
/// mistaken for an absent key and silently rotate the root the user already trusted.
nonisolated enum KeychainReadOutcome: Equatable {
    case found
    case absent
    case failure
}

// MARK: - KeychainHelper

/// Thin wrapper around Security.framework's keychain APIs for storing the root CA
/// private key and installing the root CA certificate. Root key material is stored as a
/// generic-password item in the user's login Keychain.
///
/// Certificate trust uses the `.admin` domain for clients using the macOS trust store.
/// Runtimes with independent trust stores still need their own CA configuration.
/// Changes require administrator authorization through the macOS authentication dialog.
nonisolated enum KeychainHelper {
    // MARK: Internal

    /// One certificate found by label, paired with the DER bytes that identify it exactly.
    struct LabeledCertificate {
        let certificate: SecCertificate
        let derData: Data
    }

    // MARK: - Private Key Operations

    /// Classifies a `SecItemCopyMatching` status for the root CA private key.
    ///
    /// Anything that is not an outright "no such item" describes the Keychain's availability
    /// rather than the key's existence, so it must surface as `failure`. Reading such a status
    /// as absence is what would silently regenerate a trusted root CA.
    ///
    /// - Parameter toleratesMalformedShape: set only for the historical `kSecClassKey` shapes.
    ///   Security.framework rejects that attribute combination outright on some systems, and
    ///   that rejection describes the query shape, not the Keychain, so it means "this shape
    ///   holds nothing".
    static func classifyReadStatus(
        _ status: OSStatus,
        toleratesMalformedShape: Bool = false
    )
        -> KeychainReadOutcome
    {
        if status == errSecSuccess {
            return .found
        }
        if status == errSecItemNotFound {
            return .absent
        }
        if toleratesMalformedShape, status == errSecNoSuchAttr || status == errSecParam {
            return .absent
        }
        return .failure
    }

    /// Stores the serialized root CA private key as generic-password data in the login
    /// Keychain.
    ///
    /// Two earlier shapes are superseded here. A `kSecClassKey` item carrying a raw X9.63 EC
    /// blob and a string `kSecAttrApplicationLabel` is rejected by Security.framework with
    /// `errSecNoSuchAttr`, so the root CA key never actually persisted and every relaunch
    /// generated a new CA. A generic-password item in the login Keychain persists for both
    /// development and Developer ID builds. Do not opt this item into the Data Protection
    /// keychain: the shipped non-sandboxed signing configuration receives
    /// `errSecMissingEntitlement` for that API and would fail certificate initialization.
    ///
    /// The service and account are derived from the same label callers already pass, so the
    /// storage identity stays stable across launches.
    static func savePrivateKey(_ keyData: Data, label: String) throws {
        try writePrivateKeyItem(keyData, label: label)

        // Superseded copies are removed only once the new item has been read back and compared
        // byte for byte. Deleting before that could destroy the only surviving copy of the
        // root CA private key.
        guard try readPrivateKeyItem(label: label, shape: .genericPassword) == keyData else {
            logger.error("Root CA private key readback did not match the value just written")
            throw KeychainError.readbackMismatch
        }

        logger.debug("Saved private key for label: \(label)")
        deleteSupersededPrivateKeyItems(label: label)
    }

    static func loadPrivateKey(label: String) throws -> Data? {
        try loadPrivateKey(label: label, isUsable: { !$0.isEmpty })
    }

    /// Reads the root CA private key, preferring generic-password storage and then falling
    /// through every shape an older build could have written. Anything found in a legacy
    /// shape is migrated before it is returned, so the next launch has a single source of
    /// truth.
    ///
    /// - Parameter isUsable: rejects blobs that cannot produce a working key. An unusable item
    ///   is neither adopted nor deleted — the search simply continues with the remaining
    ///   sources. Reporting `nil` when nothing usable exists lets the caller regenerate exactly
    ///   once instead of failing on every launch.
    static func loadPrivateKey(label: String, isUsable: (Data) -> Bool) throws -> Data? {
        if let data = try readPrivateKeyItem(label: label, shape: .genericPassword) {
            if isUsable(data) {
                return data
            }
            logger.error(
                "Root CA private key in generic-password storage is invalid or does not match the requested certificate — trying recovery sources"
            )
        }

        for shape in PrivateKeyShape.migrationSources {
            guard let data = try readPrivateKeyItem(label: label, shape: shape), isUsable(data) else {
                continue
            }

            do {
                try savePrivateKey(data, label: label)
                logger.info("Migrated root CA private key (\(shape.rawValue)) into generic-password storage")
            } catch {
                // The migration source is untouched, so this launch stays usable and the next
                // one retries. Never drop a recoverable key just because the copy failed.
                logger.error("Failed to migrate root CA private key: \(error.localizedDescription)")
            }
            return data
        }

        return nil
    }

    /// Reads every historical Keychain shape without rewriting or deleting any of them.
    ///
    /// Readiness and status checks use this path so observing whether the active root still
    /// matches durable storage cannot opportunistically migrate a legacy item. Explicit setup
    /// and recovery actions continue to use `loadPrivateKey(label:isUsable:)`, which owns that
    /// mutation after it has selected a usable source.
    static func loadPrivateKeyWithoutMigration(
        label: String,
        isUsable: (Data) -> Bool
    )
        throws -> Data?
    {
        let shapes = [PrivateKeyShape.genericPassword] + PrivateKeyShape.migrationSources
        for shape in shapes {
            if let data = try readPrivateKeyItem(label: label, shape: shape), isUsable(data) {
                return data
            }
        }
        return nil
    }

    static func deletePrivateKey(label: String) throws {
        var firstFailure: OSStatus?
        let shapes = [PrivateKeyShape.genericPassword] + PrivateKeyShape.migrationSources

        // Reset must cover every shape an older build could have written. Attempt them all
        // even after one failure so a partially cleaned reset cannot resurrect a legacy key
        // on the next launch, then surface the first real Security.framework failure.
        for shape in shapes {
            let status = SecItemDelete(privateKeyQuery(label: label, shape: shape) as CFDictionary)
            let isAbsent = status == errSecItemNotFound
                || (shape.toleratesMalformedShape && (status == errSecNoSuchAttr || status == errSecParam))
            guard status == errSecSuccess || isAbsent else {
                logger.error("Failed to delete private key (\(shape.rawValue)): \(status)")
                if firstFailure == nil {
                    firstFailure = status
                }
                continue
            }
        }

        if let firstFailure {
            throw KeychainError.deleteFailed(firstFailure)
        }
    }

    // MARK: - Generic Secure Data Operations

    static func saveSecureData(_ data: Data, service: String, account: String) throws {
        try deleteSecureData(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Failed to save secure data: \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    static func loadSecureData(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            logger.error("Failed to load secure data: \(status)")
            throw KeychainError.loadFailed(status)
        }

        return result as? Data
    }

    static func deleteSecureData(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to delete secure data: \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Certificate Operations

    /// Adds exactly these bytes under `label` and proves they are installed.
    ///
    /// Nothing is deleted first. The label sweep this used to run removed every certificate
    /// carrying the label — including the root a user was still relying on — for the sake of an
    /// add that had not happened yet and might still fail. `errSecDuplicateItem` is resolved by
    /// reading the keychain, not by deleting and retrying: the item that collides may be the
    /// System keychain copy the helper installed, which this process must not touch.
    static func installCertificate(_ certData: Data, label: String) throws {
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw KeychainError.invalidCertificateData
        }

        do {
            try addLabeledCertificate(certificate, label: label)
        } catch let KeychainError.saveFailed(status) where status == errSecDuplicateItem {
            guard try isCertificateInstalledStrict(certData: certData) else {
                throw KeychainError.saveFailed(status)
            }
            logger.info("Certificate already installed — keeping the existing copy")
        }

        guard try isCertificateInstalledStrict(certData: certData) else {
            throw KeychainError.certificateInstallIncomplete
        }

        logger.info("Installed certificate with label: \(label)")
    }

    /// Fail-closed presence check for callers that can only take a boolean. An unreadable
    /// Keychain answers `false`, which is never used to authorize a mutation — the strict
    /// variant is what install, removal, and status resolution ask.
    static func isCertificateInstalled(label: String) -> Bool {
        (try? isCertificateInstalledStrict(label: label)) ?? false
    }

    /// Presence of *any* certificate carrying `label`, or a throw when the lookup itself failed.
    ///
    /// Only `errSecItemNotFound` is absence. A locked Keychain answering `false` here is what
    /// makes an installed root look missing and asks the user to approve it again.
    static func isCertificateInstalledStrict(label: String) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return false
        }
        guard status == errSecSuccess else {
            logger.error("Failed to search for certificates with label \(label): \(status)")
            throw KeychainError.loadFailed(status)
        }
        return true
    }

    static func removeCertificate(label: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to remove certificate: \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Certificate Trust Operations

    /// Installs the root CA certificate in the login keychain and marks it as a trusted root for
    /// TLS in the admin (system-wide) trust domain. This triggers a macOS authentication dialog —
    /// unavoidable by Apple's design, as modifying admin-level trust settings requires
    /// authorization.
    ///
    /// Nothing is removed. The previous shape deleted every certificate carrying the label first,
    /// and fell back to "continue anyway" when the keychain refused the delete; both the delete
    /// and the fallback were destructive guesses made before the add had happened. A duplicate is
    /// resolved by reading the keychain, and trust is then applied to the copy that is there.
    ///
    /// Both postconditions are proved before returning: the exact bytes are installed, and the
    /// admin domain records *positive* trust for them. Presence of settings is not the question —
    /// a deny and an unreadable entry are settings that exist, and the previous shape logged a
    /// failed verification and returned successfully anyway, which is how a dismissed dialog was
    /// reported as an installed, trusted root.
    ///
    /// - Parameter cancellationCheck: consulted before the add and again before the trust write,
    ///   the two steps that can reach Authorization Services. It is never consulted inside one:
    ///   an approval already granted has been applied whether or not the caller is still waiting.
    ///   The default never cancels, so a caller with no cancellation of its own is unaffected.
    static func installRootCAWithTrust(
        _ certData: Data,
        label: String,
        cancellationCheck: () throws -> Void = {}
    )
        throws
    {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            logger.error("Failed to create SecCertificate from DER data")
            throw KeychainError.invalidCertificateData
        }

        try cancellationCheck()

        do {
            try addLabeledCertificate(secCert, label: label)
        } catch let KeychainError.saveFailed(status) where status == errSecDuplicateItem {
            guard try isCertificateInstalledStrict(certData: certData) else {
                throw KeychainError.saveFailed(status)
            }
            // The colliding copy may live in a keychain this process cannot write, including the
            // System keychain the helper installs into. Trust is applied to it as it stands.
            logger.info("Root CA already in keychain — applying trust settings to the existing copy")
        }

        guard try isCertificateInstalledStrict(certData: certData) else {
            throw KeychainError.certificateInstallIncomplete
        }

        // The certificate is installed and nothing interactive has run yet, so an abandoned
        // request stops here rather than raising the dialog the trust write needs.
        try cancellationCheck()

        // .admin applies to clients using the macOS trust store. macOS handles administrator
        // authentication for the change.
        let trustSettings: [[String: Any]] = [
            [kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue]
        ]

        let trustStatus = SecTrustSettingsSetTrustSettings(
            secCert,
            .admin,
            trustSettings as CFTypeRef
        )

        guard trustStatus == errSecSuccess else {
            logger.error("Failed to set trust settings: \(trustStatus)")
            throw KeychainError.trustSettingsFailed(trustStatus)
        }

        guard try trustsRootInDomain(secCert, domain: .admin) else {
            logger.error("Post-install verification: admin trust settings are absent or denied")
            throw KeychainError.trustNotApplied
        }
        guard try isCertificateInstalledStrict(certData: certData) else {
            // Writing trust settings rewrites the keychain item. Positive trust recorded for
            // bytes that are no longer installed is not an installation.
            throw KeychainError.certificateInstallIncomplete
        }

        logger.info("Installed and trusted root CA certificate")
    }

    /// Removes trust settings and then the certificates carrying `label`.
    ///
    /// The certificate is what identifies its trust settings, so it is deleted only once every
    /// trust removal has actually succeeded. The previous shape logged a failed lookup and a
    /// failed trust removal and deleted the certificate anyway, leaving admin trust settings
    /// behind with nothing left to address them by.
    ///
    /// Scope is unchanged — the certificates this label already addresses — and each delete
    /// targets exactly one item that was just inspected. A label that addresses nothing is an
    /// idempotent no-op, as is a certificate that carries no trust settings in a domain, so an
    /// untrusted fixture never reaches the authorization-backed write.
    static func removeRootCATrust(label: String) throws {
        let entries = try findLabeledCertificates(label: label)
        guard !entries.isEmpty else {
            logger.info("No certificate carries the root CA label — trust removal is already complete")
            return
        }

        for entry in entries {
            try removeTrustSettingsIfPresent(entry.certificate, domain: .admin)
            try removeTrustSettingsIfPresent(entry.certificate, domain: .user)
        }

        for entry in entries {
            let deleteStatus = SecItemDelete(
                exactItemDeleteQuery(certificateReferences: [entry.certificate]) as CFDictionary
            )
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                logger.error("Failed to remove certificate: \(deleteStatus)")
                throw KeychainError.deleteFailed(deleteStatus)
            }
        }

        logger.info("Removed root CA trust and certificate")
    }

    /// Removes exactly this certificate's admin and user trust settings, and nothing else.
    ///
    /// Split out of `removeRootCATrust(certData:)` because the trust write is the only part of a
    /// removal that needs interactive authorization, and it has to run in the GUI app before a
    /// privileged daemon deletes the keychain item: `SecTrustSettingsRemoveTrustSettings(.admin)`
    /// needs an authorization session a headless launchd daemon cannot obtain, so it is denied
    /// there even as root, and a delete that succeeded first would leave admin trust settings for
    /// a certificate no keychain holds any more — addressable only through the saved DER.
    ///
    /// Scope and strictness are unchanged from the caller it came from: exactly these bytes, both
    /// domains, a domain that holds no settings left alone so the removal is idempotent and
    /// prompt-free, and an unreadable domain propagating instead of passing for "nothing there".
    ///
    /// - Parameter cancellationCheck: consulted before each domain, so an abandoned removal stops
    ///   between the two rather than raising the dialog the second one may need. The default never
    ///   cancels.
    static func removeRootCATrustSettings(
        certData: Data,
        cancellationCheck: () throws -> Void = {}
    )
        throws
    {
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw KeychainError.invalidCertificateData
        }
        try cancellationCheck()
        try removeTrustSettingsIfPresent(certificate, domain: .admin)
        try cancellationCheck()
        try removeTrustSettingsIfPresent(certificate, domain: .user)
    }

    /// Deletes only the snapshotted DER's keychain items, and proves them gone — without calling a
    /// trust-settings API at all.
    ///
    /// The non-interactive half of a removal, for a caller that has already completed its one
    /// authorization phase. Reaching for `removeRootCATrustSettings` again here is what could
    /// raise a second dialog: trust settings live independently of the keychain item, so settings
    /// restored or re-added between the two steps would send this cleanup back through
    /// Authorization Services for an approval the user already answered.
    ///
    /// It therefore fails closed instead. Absence of admin and user settings is verified strictly
    /// first, and a certificate that still carries them — or whose domains cannot be read — is
    /// left installed: the item is the only thing that still addresses those settings from the UI.
    ///
    /// Selection is unchanged: the indexed serial number narrows the search, the exact bytes
    /// decide, deletion goes through the persistent references paired with those bytes, and a
    /// strict absence check follows. A label is never a deletion selector.
    ///
    /// - Parameter trustSettingsPresent: the strict presence read, injectable so a test can model
    ///   settings that reappeared or a domain that became unreadable without mutating host trust.
    static func removeExactCertificateItems(
        certData: Data,
        trustSettingsPresent: (Data) throws -> Bool = { try KeychainHelper.hasAnyTrustSettings(certData: $0) }
    )
        throws
    {
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData),
              let serial = SecCertificateCopySerialNumberData(certificate, nil) else
        {
            throw KeychainError.invalidCertificateData
        }

        // Present settings and an unreadable domain are both "not proved absent", and neither may
        // become a deletion.
        guard try !trustSettingsPresent(certData) else {
            logger.error("Refusing to delete a certificate that still carries trust settings")
            throw KeychainError.trustSettingsStillPresent
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrSerialNumber as String: serial,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnPersistentRef as String: true,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let references: [Data]
        if status == errSecSuccess {
            guard let items = result as? [[String: Any]], !items.isEmpty else {
                throw KeychainError.invalidCertificateData
            }
            references = try exactCertificateRemovalReferences(from: items, matching: certData)
        } else if status == errSecItemNotFound {
            references = []
        } else {
            throw KeychainError.loadFailed(status)
        }

        logger.debug("Exact root removal lookup: status \(status), matching references \(references.count)")

        var deleteStatus = errSecItemNotFound
        if !references.isEmpty {
            // Transient SecCertificate references can become unaddressable on macOS even
            // while the exact item remains installed. Use the persistent identity returned
            // alongside the verified DER, never a reconstructed certificate or label sweep.
            var deleteQuery = exactItemDeleteQuery(certificateReferences: references.map { $0 as NSData })
            deleteQuery[kSecAttrSerialNumber as String] = serial
            deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                throw KeychainError.deleteFailed(deleteStatus)
            }
        }
        // A native success/not-found status is not proof of absence. Check even when the
        // discovery found nothing; an unavailable Keychain must propagate instead of pass.
        guard try !isCertificateInstalledStrict(certData: certData) else {
            throw KeychainError.certificateRemovalIncomplete(deleteStatus)
        }
    }

    /// Removes only the snapshotted DER, including legacy login-keychain labels and orphan
    /// trust settings. A common name is never a deletion selector.
    ///
    /// The whole removal for a caller that owns both halves of it, composed from them in the only
    /// order that is safe: the interactive trust clearing first — the public DER still identifies
    /// settings after the item is gone, and a domain that holds nothing is left alone, so an
    /// untrusted certificate costs no authorization prompt — and then the exact-item deletion,
    /// which refuses to run while any setting survives. Callers that have already completed their
    /// authorization phase use `removeExactCertificateItems` instead, so the second half never
    /// prompts again.
    static func removeRootCATrust(certData: Data) throws {
        try removeRootCATrustSettings(certData: certData)
        try removeExactCertificateItems(certData: certData)
    }

    /// Keeps native item identity paired with its verified bytes before any trust mutation.
    /// Reject malformed discovery results rather than falling back to a wider selector.
    static func exactCertificateRemovalReferences(
        from items: [[String: Any]],
        matching certData: Data
    )
        throws -> [Data]
    {
        var references: [Data] = []
        for item in items {
            guard let data = item[kSecValueData as String] as? Data,
                  let reference = item[kSecValueRef as String],
                  CFGetTypeID(reference as CFTypeRef) == SecCertificateGetTypeID(),
                  let persistent = item[kSecValuePersistentRef as String] as? Data,
                  !persistent.isEmpty else
            {
                throw KeychainError.invalidCertificateData
            }
            // swiftlint:disable:next force_cast
            let certificate = reference as! SecCertificate
            guard SecCertificateCopyData(certificate) as Data == data else {
                throw KeychainError.invalidCertificateData
            }
            if data == certData {
                references.append(persistent)
            }
        }
        return references
    }

    /// Fail-closed admin-domain trust check by label, for callers that can only take a boolean.
    static func isRootCATrusted(label: String) -> Bool {
        (try? adminTrustsRootStrict(label: label)) ?? false
    }

    /// Whether the certificate carrying `label` is marked as a trusted root in the admin
    /// (system-wide) domain, or a throw when the lookup or the domain could not be read.
    ///
    /// Admin-only by policy: `.user` trust is not system-wide, so it is logged as a diagnostic
    /// and never promoted into a positive answer — least of all when the admin domain is the
    /// part that could not be read.
    static func adminTrustsRootStrict(label: String) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let findStatus = SecItemCopyMatching(query as CFDictionary, &result)
        if findStatus == errSecItemNotFound {
            return false
        }
        guard findStatus == errSecSuccess else {
            logger.error("Failed to search for certificates with label \(label): \(findStatus)")
            throw KeychainError.loadFailed(findStatus)
        }
        // A returned value that is not a certificate describes nothing this can classify.
        guard let secCert = result, CFGetTypeID(secCert as CFTypeRef) == SecCertificateGetTypeID() else {
            throw KeychainError.invalidCertificateData
        }

        // swiftlint:disable:next force_cast
        let cert = secCert as! SecCertificate
        return try adminTrustsRootStrict(certificate: cert)
    }

    /// Whether exactly these bytes are marked as a trusted root in the admin (system-wide)
    /// domain, or a throw when that domain could not be read.
    static func adminTrustsRootStrict(certData: Data) throws -> Bool {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw KeychainError.invalidCertificateData
        }
        return try adminTrustsRootStrict(certificate: secCert)
    }

    /// Checks if certificate exists in any searched keychain using its DER data directly,
    /// bypassing label-based lookup. Works for certs in the system keychain.
    static func isCertificateInstalled(certData: Data) -> Bool {
        (try? isCertificateInstalledStrict(certData: certData)) ?? false
    }

    /// Destructive callers must distinguish absence from an unavailable Keychain.
    static func isCertificateInstalledStrict(certData: Data) throws -> Bool {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData),
              let serialNumber = SecCertificateCopySerialNumberData(secCert, nil) else
        {
            throw KeychainError.invalidCertificateData
        }

        // A freshly constructed kSecValueRef is not a macOS certificate search constraint.
        // Narrow by the indexed serial number, then compare DER so another certificate
        // (including one with the same serial from another issuer) cannot satisfy this check.
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrSerialNumber as String: serialNumber,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return false
        }
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        guard let matches = result as? [Data], !matches.isEmpty else {
            throw KeychainError.invalidCertificateData
        }
        return matches.contains(certData)
    }

    /// Presence of *any* user/admin settings, including deny or empty/default trust arrays.
    /// This is deliberately not the positive-trust prefilter used to render readiness.
    static func hasAnyTrustSettings(certData: Data) throws -> Bool {
        guard let cert = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw KeychainError.invalidCertificateData
        }
        for domain in [SecTrustSettingsDomain.admin, .user] {
            var settings: CFArray?
            let status = SecTrustSettingsCopyTrustSettings(cert, domain, &settings)
            if try trustSettingsExist(status: status) {
                return true
            }
        }
        return false
    }

    static func trustSettingsExist(status: OSStatus) throws -> Bool {
        switch status {
        case errSecSuccess: true
        case errSecItemNotFound,
             errSecNoTrustSettings: false
        default: throw KeychainError.trustSettingsFailed(status)
        }
    }

    /// Fail-closed trust check using certificate DER data directly — works regardless of which
    /// keychain holds the certificate or what label it has. Returns true ONLY for
    /// admin (system-wide) domain trust, which is required for production use.
    ///
    /// Shares `TrustSettingsInterpreter` with the label-based reader so both report the same
    /// metadata for the same certificate. The answer is a prefilter, not proof of trust.
    static func isRootCATrusted(certData: Data) -> Bool {
        (try? adminTrustsRootStrict(certData: certData)) ?? false
    }

    /// Returns trust presence in both admin and user domains for diagnostic purposes.
    /// Admin trust = system-wide (required for production). User trust = per-user only
    /// (insufficient for all TLS clients to honor it).
    static func trustDomainDiagnostic(certData: Data) -> (adminTrust: Bool, userTrust: Bool) {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            return (adminTrust: false, userTrust: false)
        }

        // Diagnostic only, so an unreadable domain reports as "not trusted here" rather than
        // failing the caller. Nothing authorizes a mutation from this pair.
        let adminTrust = (try? trustsRootInDomain(secCert, domain: .admin)) ?? false
        let userTrust = (try? trustsRootInDomain(secCert, domain: .user)) ?? false

        logger.info("Trust domain diagnostic: admin=\(adminTrust), user=\(userTrust)")
        return (adminTrust: adminTrust, userTrust: userTrust)
    }

    // MARK: - Fingerprint & Stale Certificate Cleanup

    static func computeFingerprintSHA256(_ certData: Data) -> String {
        let digest = SHA256.hash(data: certData)
        return digest.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// Builds the discovery query for Rockxy root CA certificates.
    ///
    /// - Parameter searchList: when supplied, `kSecMatchSearchList` restricts the search to
    ///   exactly those keychains, which is the only real scope boundary `SecItem.h` offers.
    ///   `nil` keeps the default search list (every keychain the user can see).
    static func rockxyCertificateQuery(label: String, searchList: [SecKeychain]?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnData as String: true
        ]
        if let searchList {
            query[kSecMatchSearchList as String] = searchList
        }
        return query
    }

    /// Builds a deletion query addressing exactly the items already returned by a discovery
    /// query.
    ///
    /// `SecItem.h` documents `kSecMatchItemList` as the macOS way to reference specific items;
    /// `kSecValueRef` is the iOS shape, and a class-and-label query would delete every match
    /// in every searched keychain instead of the one item that was inspected.
    static func exactItemDeleteQuery(
        certificateReferences: [AnyObject],
        searchList: [SecKeychain]? = nil
    )
        -> [String: Any]
    {
        var query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecMatchItemList as String: certificateReferences
        ]
        if let searchList {
            query[kSecMatchSearchList as String] = searchList
        }
        return query
    }

    /// Certificate imports on classic macOS return a one-element array even when only
    /// one SecCertificate was supplied. Accept both documented result shapes, never guess
    /// which item to mutate if more than one reference was returned.
    static func certificatePersistentReference(from result: Any?) -> Data? {
        if let reference = result as? Data, !reference.isEmpty {
            return reference
        }
        guard let references = result as? [Data], references.count == 1,
              let reference = references.first, !reference.isEmpty else
        {
            return nil
        }
        return reference
    }

    /// Resolves the user's existing login keychain, or `nil` when there is none to open.
    ///
    /// `SecKeychainOpen` succeeds for a path that does not exist, so the file is checked
    /// first: callers must skip a keychain-scoped cleanup rather than silently widening it to
    /// every keychain — including `System.keychain`, where the helper installs the trusted
    /// copy of the very certificate being cleaned up.
    static func openLoginKeychain(fileManager: FileManager = .default) -> SecKeychain? {
        let keychainsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Keychains", isDirectory: true)

        for name in loginKeychainFilenames {
            let path = keychainsDirectory.appendingPathComponent(name).path
            guard fileManager.fileExists(atPath: path) else {
                continue
            }
            var keychain: SecKeychain?
            guard SecKeychainOpen(path, &keychain) == errSecSuccess, let keychain else {
                continue
            }
            return keychain
        }
        return nil
    }

    /// Finds every certificate carrying `label`, or throws when the lookup itself failed.
    ///
    /// An empty result means the label addresses nothing. `enumerateRockxyCertificates` cannot
    /// tell those apart, which is acceptable for a best-effort cleanup but not for a removal
    /// that would otherwise delete the certificate identifying the remaining trust settings.
    static func findLabeledCertificates(
        label: String,
        searchList: [SecKeychain]? = nil
    )
        throws -> [LabeledCertificate]
    {
        let query = rockxyCertificateQuery(label: label, searchList: searchList)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            logger.error("Failed to search for certificates with label \(label): \(status)")
            throw KeychainError.loadFailed(status)
        }
        guard let items = result as? [[String: Any]] else {
            throw KeychainError.invalidCertificateData
        }

        var certs: [LabeledCertificate] = []
        for item in items {
            guard let certData = item[kSecValueData as String] as? Data,
                  let reference = item[kSecValueRef as String],
                  CFGetTypeID(reference as CFTypeRef) == SecCertificateGetTypeID() else
            {
                throw KeychainError.invalidCertificateData
            }
            // swiftlint:disable:next force_cast
            let certRef = item[kSecValueRef as String] as! SecCertificate
            certs.append(LabeledCertificate(certificate: certRef, derData: certData))
        }
        return certs
    }

    static func enumerateRockxyCertificates(
        label: String,
        searchList: [SecKeychain]? = nil
    )
        -> [(certificate: SecCertificate, derData: Data, fingerprint: String)]
    {
        guard let entries = try? findLabeledCertificates(label: label, searchList: searchList) else {
            return []
        }
        return entries.map { entry in
            (
                certificate: entry.certificate,
                derData: entry.derData,
                fingerprint: computeFingerprintSHA256(entry.derData)
            )
        }
    }

    /// Removes the Rockxy root CA certificates that carry `label` in the *login* keychain.
    ///
    /// This is an explicit cleanup, never a step inside an installation. Folding it into an
    /// install is what made a routine reinstall destroy certificates the user had not asked to
    /// remove, and the destructive half of that pairing is exactly what this operation is.
    ///
    /// Discovery is constrained to the login keychain with `kSecMatchSearchList`, and each
    /// removal goes through the exact-DER path: trust settings first, then the item, addressed by
    /// the persistent reference paired with its verified bytes and serial number, with a strict
    /// absence check afterwards. A certificate whose trust settings could not be removed is left
    /// installed, because the certificate is the only thing that can still address those settings.
    ///
    /// - Returns: how many certificates were removed *and verified gone*. A failure is logged and
    ///   excluded from the count rather than folded into it; the count is not a success claim
    ///   about the ones that failed.
    @discardableResult
    static func removeAllRockxyCertsFromLoginKeychain(label: String) -> Int {
        guard let loginKeychain = openLoginKeychain() else {
            logger.info("Login keychain unavailable — skipping login-only Rockxy certificate cleanup")
            return 0
        }

        let entries: [LabeledCertificate]
        do {
            entries = try findLabeledCertificates(label: label, searchList: [loginKeychain])
        } catch {
            // A failed lookup is not "nothing is installed", so nothing is reported as removed.
            logger.error("Login-keychain certificate discovery failed: \(error.localizedDescription)")
            return 0
        }

        var removedCount = 0
        for entry in entries {
            do {
                try removeExactCertificate(entry.derData, from: loginKeychain)
                removedCount += 1
            } catch {
                logger.warning(
                    "Failed to remove login-keychain cert \(computeFingerprintSHA256(entry.derData)): \(error.localizedDescription)"
                )
            }
        }

        if removedCount > 0 {
            logger.info("Removed \(removedCount) Rockxy root cert(s) from the login keychain")
        }
        return removedCount
    }

    // MARK: Private

    /// Every storage shape the root CA private key has ever been written under, in read and
    /// cleanup priority order.
    nonisolated private enum PrivateKeyShape: String {
        /// Current shape: generic password in the user's login Keychain.
        case genericPassword = "generic-password"
        /// `kSecClassKey` with a string `kSecAttrApplicationLabel`.
        case legacyKeyStringLabel = "legacy-key-string-label"
        /// `kSecClassKey` with a data `kSecAttrApplicationLabel`. Both label encodings produce
        /// a separately addressable item, so both have to be searched and cleaned up.
        case legacyKeyDataLabel = "legacy-key-data-label"

        // MARK: Internal

        /// Everything that is not the current shape, in the order it is migrated from.
        static let migrationSources: [PrivateKeyShape] = [
            .legacyKeyStringLabel,
            .legacyKeyDataLabel
        ]

        /// `kSecClassKey` items combine attributes Security.framework rejects on some systems.
        var toleratesMalformedShape: Bool {
            self == .legacyKeyStringLabel || self == .legacyKeyDataLabel
        }
    }

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "KeychainHelper")

    /// Account component for the root CA private key item. The service component is the
    /// caller's label, so one label always maps to exactly one stored key.
    private static let privateKeyAccount = "root-ca-private-key"

    /// Login keychain filenames in resolution order: the SQLite-backed form current macOS
    /// creates, then the pre-Sierra file kept by long-lived upgraded accounts.
    private static let loginKeychainFilenames = ["login.keychain-db", "login.keychain"]

    /// Classic macOS Keychain imports certificates through a reference and may ignore the
    /// label supplied with SecItemAdd. Set the label on the newly created persistent item;
    /// never relabel an existing duplicate (which may belong to System.keychain).
    private static func addLabeledCertificate(_ certificate: SecCertificate, label: String) throws {
        guard let loginKeychain = openLoginKeychain() else {
            throw KeychainError.loginKeychainUnavailable
        }
        guard let serialNumber = SecCertificateCopySerialNumberData(certificate, nil) else {
            throw KeychainError.invalidCertificateData
        }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecUseKeychain as String: loginKeychain,
            kSecReturnPersistentRef as String: true
        ]
        var addedItem: CFTypeRef?
        let addStatus = SecItemAdd(addQuery as CFDictionary, &addedItem)
        guard addStatus == errSecSuccess else {
            throw KeychainError.saveFailed(addStatus)
        }
        let returnedReferences: [Data] = if let reference = addedItem as? Data {
            reference.isEmpty ? [] : [reference]
        } else {
            (addedItem as? [Data] ?? []).filter { !$0.isEmpty }
        }
        var itemQuery = exactItemDeleteQuery(
            certificateReferences: returnedReferences.map { $0 as NSData },
            searchList: [loginKeychain]
        )
        // Defense in depth: even a platform that mishandles the reference constraint
        // must never broaden an update to every certificate in a keychain.
        itemQuery[kSecAttrSerialNumber as String] = serialNumber
        // Leave a partially imported certificate in place on failure. Installation has no
        // deletion authority, even over an item this call just added; a retry can identify it
        // by DER without risking a concurrent caller's completed trust operation.
        guard certificatePersistentReference(from: addedItem) != nil else {
            throw KeychainError.readbackMismatch
        }
        let updateStatus = SecItemUpdate(
            itemQuery as CFDictionary,
            [kSecAttrLabel as String: label] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw KeychainError.certificateLabelFailed(updateStatus)
        }
        var readQuery = itemQuery
        readQuery[kSecReturnAttributes as String] = true
        var attributes: CFTypeRef?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &attributes)
        guard readStatus == errSecSuccess,
              (attributes as? [String: Any])?[kSecAttrLabel as String] as? String == label else
        {
            throw KeychainError.readbackMismatch
        }
    }

    /// The persistent references for exactly `certData` inside one keychain.
    ///
    /// Scoped by `kSecMatchSearchList`, narrowed by the indexed serial number, and decided by the
    /// bytes — another issuer can mint a certificate with the same serial. A status that is
    /// neither success nor "no such item" describes the keychain, so it propagates instead of
    /// reading as absence.
    private static func persistentReferences(
        for certData: Data,
        serialNumber: Data,
        in keychain: SecKeychain
    )
        throws -> [Data]
    {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrSerialNumber as String: serialNumber,
            kSecMatchSearchList as String: [keychain],
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnPersistentRef as String: true,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        guard let items = result as? [[String: Any]] else {
            throw KeychainError.invalidCertificateData
        }
        return try exactCertificateRemovalReferences(from: items, matching: certData)
    }

    /// Removes exactly `certData` from one keychain, trust settings first, and proves it is gone.
    ///
    /// Discovery, deletion, and the absence check all name the same keychain, so a cleanup meant
    /// for the login keychain can never reach the System keychain copy the helper installed. The
    /// certificate is deleted only after its trust settings have actually been removed: it is the
    /// only thing that can still address them.
    private static func removeExactCertificate(_ certData: Data, from keychain: SecKeychain) throws {
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData),
              let serialNumber = SecCertificateCopySerialNumberData(certificate, nil) as Data? else
        {
            throw KeychainError.invalidCertificateData
        }

        let references = try persistentReferences(for: certData, serialNumber: serialNumber, in: keychain)

        try removeTrustSettingsIfPresent(certificate, domain: .admin)
        try removeTrustSettingsIfPresent(certificate, domain: .user)

        var deleteStatus = errSecItemNotFound
        if !references.isEmpty {
            // Persistent identity, never a transient reference: a transient SecCertificate can
            // stop addressing its item while the item is still installed.
            var deleteQuery = exactItemDeleteQuery(
                certificateReferences: references.map { $0 as NSData },
                searchList: [keychain]
            )
            deleteQuery[kSecAttrSerialNumber as String] = serialNumber
            deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                throw KeychainError.deleteFailed(deleteStatus)
            }
        }

        // A status is a report, not proof. An unavailable keychain propagates rather than passing.
        guard try persistentReferences(for: certData, serialNumber: serialNumber, in: keychain).isEmpty else {
            throw KeychainError.certificateRemovalIncomplete(deleteStatus)
        }
    }

    private static func privateKeyQuery(label: String, shape: PrivateKeyShape) -> [String: Any] {
        switch shape {
        case .genericPassword:
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: label,
                kSecAttrAccount as String: privateKeyAccount
            ]
        case .legacyKeyStringLabel:
            [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationLabel as String: label
            ]
        case .legacyKeyDataLabel:
            [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationLabel as String: Data(label.utf8)
            ]
        }
    }

    private static func writePrivateKeyItem(_ keyData: Data, label: String) throws {
        let query = privateKeyQuery(label: label, shape: .genericPassword)

        // Update-or-add, never delete-then-add: a failed add after a delete would destroy
        // the only copy of the root CA private key.
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: keyData] as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = keyData
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(addQuery as CFDictionary, nil)

            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: keyData] as CFDictionary)
            }
        }

        guard status == errSecSuccess else {
            logger.error("Failed to save private key: \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    /// Reads one storage shape. `nil` means that shape holds nothing; a transient Keychain
    /// failure throws instead, so it can never be confused with absence.
    private static func readPrivateKeyItem(label: String, shape: PrivateKeyShape) throws -> Data? {
        var query = privateKeyQuery(label: label, shape: shape)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch classifyReadStatus(status, toleratesMalformedShape: shape.toleratesMalformedShape) {
        case .found:
            // The item exists. A payload that is not data describes a Keychain this process
            // cannot read, not an absent key, so it must never fall through to regeneration.
            guard let data = result as? Data else {
                logger.error("Root CA private key item (\(shape.rawValue)) did not return data")
                throw KeychainError.privateKeyItemUnreadable
            }
            return data
        case .absent:
            return nil
        case .failure:
            logger.error("Failed to load private key (\(shape.rawValue)): \(status)")
            throw KeychainError.loadFailed(status)
        }
    }

    /// Best-effort cleanup of superseded storage shapes. Only reached once the generic-password
    /// item has been read back and byte-compared, and a failure here never blocks the
    /// authoritative copy.
    private static func deleteSupersededPrivateKeyItems(label: String) {
        for shape in PrivateKeyShape.migrationSources {
            let status = SecItemDelete(privateKeyQuery(label: label, shape: shape) as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound {
                logger.debug("Superseded private key delete (\(shape.rawValue)) returned \(status)")
            }
        }
    }

    /// Whether one certificate carries positive trustRoot settings in the admin domain, with the
    /// `.user` domain reported as a diagnostic only.
    ///
    /// The user domain is read only after the admin domain answered a *known* negative. Reading
    /// it when the admin domain is unavailable would let per-user trust stand in for the
    /// system-wide answer this app requires.
    private static func adminTrustsRootStrict(certificate: SecCertificate) throws -> Bool {
        if try trustsRootInDomain(certificate, domain: .admin) {
            logger.debug("Root CA trusted in .admin domain (system-wide)")
            return true
        }

        if (try? trustsRootInDomain(certificate, domain: .user)) == true {
            logger.warning("Root CA trusted at .user level only — re-trust needed for system-wide .admin domain")
        }

        return false
    }

    /// Whether one certificate carries positive trustRoot settings in one domain, or a throw
    /// when the domain could not be read.
    ///
    /// Absence is a real negative; an unreadable domain is not. Collapsing the two is what let a
    /// locked Keychain or a denied authorization present a trusted root as untrusted.
    private static func trustsRootInDomain(
        _ secCert: SecCertificate,
        domain: SecTrustSettingsDomain
    )
        throws -> Bool
    {
        var trustSettings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(secCert, domain, &trustSettings)

        switch TrustSettingsInterpreter.read(status: status, settings: trustSettings) {
        case let .entries(entries):
            return TrustSettingsInterpreter.indicatesTrustedRoot(settings: entries)
        case .absent:
            return false
        case let .unreadable(status):
            logger.error("Failed to read trust settings: \(status)")
            throw KeychainError.trustSettingsUnreadable(status)
        case .malformed:
            logger.error("Trust settings copy returned a value that is not an array of entries")
            throw KeychainError.trustSettingsUnreadable(nil)
        }
    }

    /// Removes one certificate's trust settings in one domain, and reports a failure instead of
    /// logging it.
    ///
    /// A certificate that has no settings in the domain is left alone, so the removal is
    /// idempotent and an untrusted certificate never reaches the authorization-backed write
    /// that `SecTrustSettingsRemoveTrustSettings` performs for the admin domain.
    private static func removeTrustSettingsIfPresent(
        _ secCert: SecCertificate,
        domain: SecTrustSettingsDomain
    )
        throws
    {
        var existing: CFArray?
        let copyStatus = SecTrustSettingsCopyTrustSettings(secCert, domain, &existing)
        if try !trustSettingsExist(status: copyStatus) {
            return
        }

        let removeStatus = SecTrustSettingsRemoveTrustSettings(secCert, domain)
        guard removeStatus == errSecSuccess || removeStatus == errSecItemNotFound
            || removeStatus == errSecNoTrustSettings else
        {
            logger.error("Failed to remove trust settings: \(removeStatus)")
            throw KeychainError.trustSettingsFailed(removeStatus)
        }
        var remaining: CFArray?
        let verifyStatus = SecTrustSettingsCopyTrustSettings(secCert, domain, &remaining)
        guard try !trustSettingsExist(status: verifyStatus) else {
            throw KeychainError.trustSettingsFailed(errSecInternalComponent)
        }
    }
}

// MARK: - KeychainError

nonisolated enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case certificateRemovalIncomplete(OSStatus)
    case certificateInstallIncomplete
    case trustNotApplied
    case readbackMismatch
    case invalidCertificateData
    case loginKeychainUnavailable
    case certificateLabelFailed(OSStatus)
    case trustSettingsFailed(OSStatus)
    /// A non-interactive cleanup found trust settings that were supposed to be gone already, so
    /// it deleted nothing: the certificate is what still addresses them.
    case trustSettingsStillPresent
    /// The trust domain could not be read at all. `nil` means the copy reported success and
    /// returned a value that is not an array of trust-settings entries.
    case trustSettingsUnreadable(OSStatus?)
    case privateKeyItemUnreadable

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .saveFailed(status):
            "Keychain save failed with status: \(status)"
        case let .loadFailed(status):
            "Keychain load failed with status: \(status)"
        case let .deleteFailed(status):
            "Keychain delete failed with status: \(status)"
        case let .certificateRemovalIncomplete(status):
            "The exact certificate is still installed after removal (status: \(status))."
        case .certificateInstallIncomplete:
            "The certificate is not installed after the keychain reported a successful add."
        case .trustNotApplied:
            "Trust settings were not applied. The authorization prompt may have been dismissed — try again."
        case .readbackMismatch:
            "Keychain readback did not match the value that was just written"
        case .invalidCertificateData:
            "Invalid certificate data — could not create SecCertificate"
        case .loginKeychainUnavailable:
            "The login keychain is unavailable. Unlock it and try the certificate installation again."
        case let .certificateLabelFailed(status):
            "Failed to label the imported certificate (status: \(status))"
        case let .trustSettingsFailed(status):
            "Failed to set certificate trust settings with status: \(status)"
        case .trustSettingsStillPresent:
            "The certificate still has system trust settings, so it was kept in the keychain. Remove its trust settings, then try again."
        case let .trustSettingsUnreadable(status):
            "Rockxy could not read the certificate's system trust settings\(status.map { " (status: \($0))" } ?? ""). Unlock your keychain or restore access, then check the status again."
        case .privateKeyItemUnreadable:
            "The stored root CA private key could not be read from the keychain."
        }
    }
}
