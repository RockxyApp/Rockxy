import Crypto
import Foundation
import os
import Security

// Implements keychain helper behavior for the certificate and trust pipeline.

// MARK: - KeychainHelper

/// Thin wrapper around Security.framework's keychain APIs for storing the root CA
/// private key and installing the root CA certificate. Uses `kSecAttrAccessibleWhenUnlocked`
/// for private keys so they are only available when the user is logged in.
///
/// Certificate trust uses the `.admin` domain (system-wide) so all TLS clients
/// (Safari, URLSession, system services) honor the trust setting. This requires
/// admin authorization via macOS authentication dialog.
nonisolated enum KeychainHelper {
    // MARK: Internal

    // MARK: - Private Key Operations

    static func savePrivateKey(_ keyData: Data, label: String) throws {
        // Delete-then-add avoids errSecDuplicateItem without a separate existence check
        try deletePrivateKey(label: label)

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationLabel as String: label,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Failed to save private key: \(status)")
            throw KeychainError.saveFailed(status)
        }

        logger.debug("Saved private key with label: \(label)")
    }

    static func loadPrivateKey(label: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationLabel as String: label,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            logger.error("Failed to load private key: \(status)")
            throw KeychainError.loadFailed(status)
        }

        guard let data = result as? Data else {
            return nil
        }

        return data
    }

    static func deletePrivateKey(label: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationLabel as String: label
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to delete private key: \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Certificate Operations

    static func installCertificate(_ certData: Data, label: String) throws {
        try removeCertificate(label: label)

        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecValueData as String: certData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Failed to install certificate: \(status)")
            throw KeychainError.saveFailed(status)
        }

        logger.info("Installed certificate with label: \(label)")
    }

    static func isCertificateInstalled(label: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
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

    /// Installs the root CA certificate in the login keychain and marks it as a
    /// trusted root for TLS using the admin trust domain (system-wide). This triggers
    /// a macOS authentication dialog — unavoidable by Apple's design, as modifying
    /// admin-level trust settings requires authorization.
    static func installRootCAWithTrust(_ certData: Data, label: String) throws {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            logger.error("Failed to create SecCertificate from DER data")
            throw KeychainError.invalidCertificateData
        }

        // Try to remove existing cert (best-effort — may be in system keychain we can't touch)
        do {
            try removeCertificate(label: label)
        } catch let KeychainError.deleteFailed(status) where status == errSecWrPerm {
            logger.info(
                "Root CA exists in a non-writable keychain; continuing with trust update instead of deleting"
            )
        }

        // Add certificate to the login keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecValueRef as String: secCert
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Certificate already exists in another keychain (e.g. system) — this is fine,
            // proceed to apply trust settings to the existing copy
            logger.info("Root CA already in keychain — applying trust settings to existing copy")
        } else if addStatus != errSecSuccess {
            logger.error("Failed to add root CA certificate to login keychain: \(addStatus)")
            throw KeychainError.saveFailed(addStatus)
        }

        // Set trust settings to mark as trusted root CA.
        // Uses .admin domain (system-wide trust) so all TLS clients honor the setting.
        // macOS prompts for admin password to authorize this change.
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

        logger.info("Installed and trusted root CA certificate")

        // Verify trust was actually applied (catches dismissed auth dialog)
        var verifyTrustSettings: CFArray?
        let verifyStatus = SecTrustSettingsCopyTrustSettings(secCert, .admin, &verifyTrustSettings)
        if verifyStatus == errSecSuccess {
            logger.info("Post-install verification: admin trust settings confirmed")
        } else {
            logger.warning(
                "Post-install verification: admin trust settings NOT found (status: \(verifyStatus)) — user may have dismissed auth dialog"
            )
        }
    }

    /// Removes trust settings and the certificate from the keychain.
    static func removeRootCATrust(label: String) throws {
        // Find the SecCertificate reference first for trust removal
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let findStatus = SecItemCopyMatching(query as CFDictionary, &result)

        if findStatus == errSecSuccess, let secCert = result {
            // swiftlint:disable:next force_cast
            let cert = secCert as! SecCertificate
            let trustStatus = SecTrustSettingsRemoveTrustSettings(cert, .admin)
            if trustStatus != errSecSuccess, trustStatus != errSecItemNotFound {
                logger.warning("Failed to remove trust settings: \(trustStatus)")
            }
        }

        try removeCertificate(label: label)
        logger.info("Removed root CA trust and certificate")
    }

    /// Checks whether the root CA certificate has been marked as a trusted root
    /// in the admin (system-wide) trust settings domain. Returns true ONLY for
    /// admin domain trust, which is required for production use.
    static func isRootCATrusted(label: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let findStatus = SecItemCopyMatching(query as CFDictionary, &result)

        guard findStatus == errSecSuccess, let secCert = result else {
            return false
        }

        // swiftlint:disable:next force_cast
        let cert = secCert as! SecCertificate

        // Check .admin domain first (system-wide trust — required for production)
        if hasTrustRootInDomain(cert, domain: .admin) {
            logger.debug("Root CA trusted in .admin domain (system-wide)")
            return true
        }

        // Check .user domain for diagnostic logging only — not sufficient for production
        if hasTrustRootInDomain(cert, domain: .user) {
            logger.warning("Root CA trusted at .user level only — re-trust needed for system-wide .admin domain")
        }

        return false
    }

    /// Checks if certificate exists in any searched keychain using its DER data directly,
    /// bypassing label-based lookup. Works for certs in the system keychain.
    static func isCertificateInstalled(certData: Data) -> Bool {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secCert,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    /// Checks trust using certificate DER data directly — works regardless of which
    /// keychain holds the certificate or what label it has. Returns true ONLY for
    /// admin (system-wide) domain trust, which is required for production use.
    static func isRootCATrusted(certData: Data) -> Bool {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            return false
        }

        // Check .admin domain first (system-wide trust — required for production)
        var adminTrustSettings: CFArray?
        let adminStatus = SecTrustSettingsCopyTrustSettings(secCert, .admin, &adminTrustSettings)

        if adminStatus == errSecSuccess, let settings = adminTrustSettings as? [[String: Any]] {
            for entry in settings {
                if let resultValue = entry[kSecTrustSettingsResult as String] as? UInt32,
                   resultValue == SecTrustSettingsResult.trustRoot.rawValue
                {
                    logger.debug("Root CA trusted in .admin domain (system-wide)")
                    return true
                }
            }
        }

        // Check .user domain for diagnostic logging only — not sufficient for production
        var userTrustSettings: CFArray?
        let userStatus = SecTrustSettingsCopyTrustSettings(secCert, .user, &userTrustSettings)
        if userStatus == errSecSuccess {
            logger.warning("Root CA trusted at .user level only — re-trust needed for system-wide .admin domain")
        }

        return false
    }

    /// Returns trust presence in both admin and user domains for diagnostic purposes.
    /// Admin trust = system-wide (required for production). User trust = per-user only
    /// (insufficient for all TLS clients to honor it).
    static func trustDomainDiagnostic(certData: Data) -> (adminTrust: Bool, userTrust: Bool) {
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            return (adminTrust: false, userTrust: false)
        }

        let adminTrust = hasTrustRootInDomain(secCert, domain: .admin)
        let userTrust = hasTrustRootInDomain(secCert, domain: .user)

        logger.info("Trust domain diagnostic: admin=\(adminTrust), user=\(userTrust)")
        return (adminTrust: adminTrust, userTrust: userTrust)
    }

    // MARK: - Fingerprint & Stale Certificate Cleanup

    static func computeFingerprintSHA256(_ certData: Data) -> String {
        let digest = SHA256.hash(data: certData)
        return digest.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    static func enumerateRockxyCertificates(
        label: String
    )
        -> [(certificate: SecCertificate, derData: Data, fingerprint: String)]
    {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }

        var certs: [(certificate: SecCertificate, derData: Data, fingerprint: String)] = []
        for item in items {
            guard let certData = item[kSecValueData as String] as? Data else {
                continue
            }
            // swiftlint:disable:next force_cast
            let certRef = item[kSecValueRef as String] as! SecCertificate
            let fingerprint = computeFingerprintSHA256(certData)
            certs.append((certificate: certRef, derData: certData, fingerprint: fingerprint))
        }
        return certs
    }

    static func cleanupStaleRockxyCerts(activeFingerprint: String, label: String) {
        let certs = enumerateRockxyCertificates(label: label)
        var removedCount = 0

        for entry in certs where entry.fingerprint != activeFingerprint {
            let trustStatus = SecTrustSettingsRemoveTrustSettings(entry.certificate, .admin)
            if trustStatus != errSecSuccess, trustStatus != errSecItemNotFound {
                logger.warning("Failed to remove trust for stale cert \(entry.fingerprint): \(trustStatus)")
            }

            let userTrustStatus = SecTrustSettingsRemoveTrustSettings(entry.certificate, .user)
            if userTrustStatus != errSecSuccess, userTrustStatus != errSecItemNotFound {
                logger.debug("No user-level trust to remove for stale cert \(entry.fingerprint)")
            }

            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecValueRef as String: entry.certificate
            ]
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            if deleteStatus == errSecSuccess {
                removedCount += 1
                logger.info("Removed stale Rockxy root cert: \(entry.fingerprint)")
            } else if deleteStatus != errSecItemNotFound {
                logger.warning("Failed to delete stale cert \(entry.fingerprint): \(deleteStatus)")
            }
        }

        if removedCount > 0 {
            logger.info("Cleaned up \(removedCount) stale Rockxy root certificate(s)")
        }
    }

    /// Removes ALL Rockxy root CA certificates from the login keychain.
    /// Called after helper successfully installs + trusts in System.keychain, to prevent
    /// duplicate copies from confusing SecTrust chain evaluation.
    static func removeAllRockxyCertsFromLoginKeychain(label: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return
        }

        var removedCount = 0
        for item in items {
            guard let certRef = item[kSecValueRef as String] else {
                continue
            }

            // Only delete from login keychain — system keychain certs return errSecWrPerm
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecValueRef as String: certRef,
            ]
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            if deleteStatus == errSecSuccess {
                removedCount += 1
            }
            // errSecWrPerm means system keychain — expected, skip silently
        }

        if removedCount > 0 {
            logger.info("Removed \(removedCount) stale Rockxy root cert(s) from login keychain")
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "KeychainHelper")

    /// Checks whether a SecCertificate has trustRoot settings in the specified domain.
    private static func hasTrustRootInDomain(
        _ secCert: SecCertificate,
        domain: SecTrustSettingsDomain
    )
        -> Bool
    {
        var trustSettings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(secCert, domain, &trustSettings)

        guard status == errSecSuccess, let settings = trustSettings as? [[String: Any]] else {
            return false
        }

        for entry in settings {
            if let resultValue = entry[kSecTrustSettingsResult as String] as? UInt32,
               resultValue == SecTrustSettingsResult.trustRoot.rawValue
            {
                return true
            }
        }
        return false
    }
}

// MARK: - KeychainError

nonisolated enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidCertificateData
    case trustSettingsFailed(OSStatus)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .saveFailed(status):
            "Keychain save failed with status: \(status)"
        case let .loadFailed(status):
            "Keychain load failed with status: \(status)"
        case let .deleteFailed(status):
            "Keychain delete failed with status: \(status)"
        case .invalidCertificateData:
            "Invalid certificate data — could not create SecCertificate"
        case let .trustSettingsFailed(status):
            "Failed to set certificate trust settings with status: \(status)"
        }
    }
}
