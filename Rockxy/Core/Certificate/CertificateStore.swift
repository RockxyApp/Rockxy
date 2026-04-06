import Crypto
import Foundation
import os
import SwiftASN1
import X509

// Root CA Private Key Storage Model:
// Primary: macOS Keychain (kSecAttrAccessibleWhenUnlocked) — OS-level encryption at rest,
//          protected by login session. Key material never written to disk in plaintext.
// Recovery: Disk PEM file (.bak suffix) — only exists after migration from older versions.
//          Retained as a one-time recovery fallback in case Keychain is cleared/corrupted.
// Rationale: Keychain provides OS-level encryption and login-session protection.
//          Plaintext PEM on disk (even with 0o600) is vulnerable to disk imaging and swap dumps.

/// Handles persistence of the root CA certificate (disk PEM) and private key (Keychain-primary,
/// disk as recovery fallback). Files are stored under the shared Rockxy support directory.
nonisolated enum CertificateStore {
    // MARK: Internal

    // MARK: Internal — Test Overrides

    /// Override for test isolation. When set, used instead of the production Keychain label.
    /// Protected by lock for parallel test safety.
    static var keychainKeyLabelOverride: String? {
        get { overrideLock.withLock { _keychainKeyLabelOverride } }
        set { overrideLock.withLock { _keychainKeyLabelOverride = newValue } }
    }

    /// Override for test isolation. When set, used instead of the production storage directory.
    /// Protected by lock for parallel test safety.
    static var storageDirectoryOverride: URL? {
        get { overrideLock.withLock { _storageDirectoryOverride } }
        set { overrideLock.withLock { _storageDirectoryOverride = newValue } }
    }

    static func ensureDirectoryExists() throws {
        let directory = storageDirectory
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logger.debug("Created certificate storage directory")
        }
    }

    static func saveRootCACertificate(_ certificate: Certificate) throws {
        try ensureDirectoryExists()

        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        let derBytes = Array(serializer.serializedBytes)

        let pemDocument = PEMDocument(type: "CERTIFICATE", derBytes: derBytes)
        let pemString = pemDocument.pemString

        let filePath = storageDirectory.appendingPathComponent(rootCACertFilename)
        try Data(pemString.utf8).write(to: filePath)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath.path)
        logger.info("Saved root CA certificate to disk")
    }

    static func saveRootCAPrivateKey(_ key: P256.Signing.PrivateKey) throws {
        let keyData = Data(key.x963Representation)

        // Primary: store in Keychain (OS-level encryption)
        do {
            try KeychainHelper.savePrivateKey(keyData, label: keychainKeyLabel)
            logger.info("Saved root CA private key to Keychain (primary)")
            // Keychain succeeded — do NOT write plaintext PEM to disk
            // If a legacy disk file exists, leave it as recovery backup (do not write new ones)
            return
        } catch {
            logger.warning("Keychain save failed: \(error.localizedDescription). Falling back to disk PEM")
        }

        #if DEBUG
        // Fallback: write disk PEM only if Keychain fails
        try ensureDirectoryExists()
        let derBytes = Array(key.x963Representation)
        let pemDocument = PEMDocument(type: "EC PRIVATE KEY", derBytes: derBytes)
        let pemString = pemDocument.pemString

        let filePath = storageDirectory.appendingPathComponent(rootCAKeyFilename)
        try Data(pemString.utf8).write(to: filePath)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath.path)
        logger.warning("Saved root CA private key to disk (fallback — Keychain unavailable)")
        #endif
    }

    static func loadRootCACertificate() throws -> Certificate? {
        let filePath = storageDirectory.appendingPathComponent(rootCACertFilename)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        let pemData = try Data(contentsOf: filePath)
        guard let pemString = String(data: pemData, encoding: .utf8) else {
            return nil
        }
        let pemDocument = try PEMDocument(pemString: pemString)
        let certificate = try Certificate(derEncoded: pemDocument.derBytes)
        logger.debug("Loaded root CA certificate from disk")
        return certificate
    }

    static func loadRootCAPrivateKey() throws -> P256.Signing.PrivateKey? {
        // 1. Try Keychain first (primary storage)
        if let keyData = try KeychainHelper.loadPrivateKey(label: keychainKeyLabel) {
            let key = try P256.Signing.PrivateKey(x963Representation: keyData)
            logger.info("Loaded root CA private key from Keychain (primary)")
            cleanupLegacyDiskKeys()
            return key
        }

        // 2. Fall back to disk PEM for migration from older versions
        let filePath = storageDirectory.appendingPathComponent(rootCAKeyFilename)
        if FileManager.default.fileExists(atPath: filePath.path) {
            let pemData = try Data(contentsOf: filePath)
            if let pemString = String(data: pemData, encoding: .utf8) {
                let pemDocument = try PEMDocument(pemString: pemString)
                let key = try P256.Signing.PrivateKey(x963Representation: pemDocument.derBytes)
                logger.info("Loaded root CA private key from disk (migration fallback)")

                // Migrate: store to Keychain, rename disk copy to .bak
                migrateKeyToKeychain(key: key)

                return key
            }
        }

        // 3. Last resort: check for .bak file from previous migration
        let backupPath = storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")
        if FileManager.default.fileExists(atPath: backupPath.path) {
            let pemData = try Data(contentsOf: backupPath)
            guard let pemString = String(data: pemData, encoding: .utf8) else {
                return nil
            }
            let pemDocument = try PEMDocument(pemString: pemString)
            let key = try P256.Signing.PrivateKey(x963Representation: pemDocument.derBytes)
            logger.warning("Loaded root CA private key from .bak recovery file — re-migrating to Keychain")
            migrateKeyToKeychain(key: key)
            return key
        }

        return nil
    }

    /// Loads the root CA private key from disk PEM only, skipping Keychain lookup.
    /// Used as a fallback when the Keychain key does not match the certificate on disk
    /// (cert-key mismatch scenario), to check whether the disk copy is still consistent.
    static func loadRootCAPrivateKeyFromDisk() throws -> P256.Signing.PrivateKey? {
        // Check primary disk PEM file
        let filePath = storageDirectory.appendingPathComponent(rootCAKeyFilename)
        if FileManager.default.fileExists(atPath: filePath.path) {
            let pemData = try Data(contentsOf: filePath)
            if let pemString = String(data: pemData, encoding: .utf8) {
                let pemDocument = try PEMDocument(pemString: pemString)
                let key = try P256.Signing.PrivateKey(x963Representation: pemDocument.derBytes)
                logger.info("Loaded root CA private key from disk PEM (direct, no Keychain)")
                return key
            }
        }

        // Check .bak file from previous migration
        let backupPath = storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")
        if FileManager.default.fileExists(atPath: backupPath.path) {
            let pemData = try Data(contentsOf: backupPath)
            if let pemString = String(data: pemData, encoding: .utf8) {
                let pemDocument = try PEMDocument(pemString: pemString)
                let key = try P256.Signing.PrivateKey(x963Representation: pemDocument.derBytes)
                logger.info("Loaded root CA private key from .bak recovery file (direct, no Keychain)")
                return key
            }
        }

        return nil
    }

    static func deleteAll() throws {
        let directory = storageDirectory
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
            logger.info("Deleted all stored certificates")
        }
    }

    static func cleanupLegacyDiskKeys() {
        let backupPath = storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")
        guard FileManager.default.fileExists(atPath: backupPath.path) else {
            return
        }
        guard (try? KeychainHelper.loadPrivateKey(label: keychainKeyLabel)) != nil else {
            logger.debug("Skipping .bak cleanup — Keychain has no matching key")
            return
        }
        try? FileManager.default.removeItem(at: backupPath)
        logger.info("Cleaned up legacy .bak private key file — Keychain is primary")
    }

    // MARK: Private

    private static let overrideLock = NSLock()
    nonisolated(unsafe) private static var _keychainKeyLabelOverride: String?
    nonisolated(unsafe) private static var _storageDirectoryOverride: URL?

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "CertificateStore")

    private static let rootCACertFilename = "rootCA.pem"
    private static let rootCAKeyFilename = "rootCA-key.pem"

    private static var keychainKeyLabel: String {
        keychainKeyLabelOverride ?? RockxyIdentity.current.rootCAKeyLabel
    }

    private static var storageDirectory: URL {
        if let override = storageDirectoryOverride {
            return override
        }
        return RockxyIdentity.current.sharedSupportDirectory()
            .appendingPathComponent("Certificates", isDirectory: true)
    }

    /// Migrates a private key from disk PEM to Keychain. On success, renames the disk
    /// file to `.bak` so it is no longer used as the primary source but remains available
    /// for manual recovery.
    private static func migrateKeyToKeychain(key: P256.Signing.PrivateKey) {
        do {
            let keyData = Data(key.x963Representation)
            try KeychainHelper.savePrivateKey(keyData, label: keychainKeyLabel)
            logger.info("Migration: stored private key in Keychain")

            let filePath = storageDirectory.appendingPathComponent(rootCAKeyFilename)
            let backupPath = storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")

            // Only rename primary PEM → .bak when the primary PEM actually exists.
            // When migrating from .bak recovery, the primary PEM is absent — do not
            // delete the .bak that we just loaded from.
            if FileManager.default.fileExists(atPath: filePath.path) {
                if FileManager.default.fileExists(atPath: backupPath.path) {
                    try FileManager.default.removeItem(at: backupPath)
                }
                try FileManager.default.moveItem(at: filePath, to: backupPath)
                logger.info("Migration: renamed disk PEM to .bak (recovery-only)")
            } else {
                logger.info("Migration: primary PEM not present, keeping .bak as recovery")
            }
        } catch {
            logger
                .warning(
                    "Migration: failed to migrate key to Keychain — disk PEM retained: \(error.localizedDescription)"
                )
        }
    }
}
