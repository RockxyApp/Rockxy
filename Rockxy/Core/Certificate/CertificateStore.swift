import Crypto
import Foundation
import os
import SwiftASN1
import X509

// Root CA Private Key Storage Model:
// Primary: macOS Keychain (kSecAttrAccessibleWhenUnlocked) — OS-level encryption at rest,
//          protected by login session. Key material never written to disk in plaintext.
// Recovery: Disk PEM file (.bak suffix) — only exists after migration from older versions.
//          Read-only: it is still loaded once and migrated into the Keychain, but Rockxy
//          never writes a new plaintext key file.
// Rationale: Keychain provides OS-level encryption and login-session protection.
//          Plaintext PEM on disk (even with 0o600) is vulnerable to disk imaging and swap dumps.

// MARK: - CertificateStoreError

nonisolated enum CertificateStoreError: LocalizedError {
    /// The staging file for an atomic certificate write could not be created, so the
    /// previously persisted certificate was left in place.
    case certificateStagingFailed(String)
    /// The staged certificate could not be committed over the live path. The previously
    /// persisted certificate is still the one on disk.
    case certificateCommitFailed(Int32)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .certificateStagingFailed(name):
            "Failed to stage the root CA certificate file (\(name)) before persisting it"
        case let .certificateCommitFailed(code):
            "Failed to commit the root CA certificate file (errno \(code))"
        }
    }
}

// MARK: - CertificateStore

/// Handles persistence of the root CA certificate (disk PEM) and private key (Keychain-only,
/// with read-only disk recovery for older installs). Files are stored under the shared
/// Rockxy support directory.
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

    #if DEBUG
    /// Replaces the commit step of `saveRootCACertificate` so a test can fail the write
    /// deterministically at the one point that matters — before the live certificate is
    /// replaced — without corrupting the store or needing a filesystem abstraction.
    /// Production always takes the atomic replacement path below.
    static var certificateCommitOverride: ((_ staged: URL, _ destination: URL) throws -> Void)? {
        get { overrideLock.withLock { _certificateCommitOverride } }
        set { overrideLock.withLock { _certificateCommitOverride = newValue } }
    }
    #endif

    static var rootCACertificateURL: URL {
        storageDirectory.appendingPathComponent(rootCACertFilename)
    }

    /// The Keychain label this store reads and writes right now, honouring the test
    /// override. Deletion must target the same label the key was written under.
    static var activeKeychainKeyLabel: String {
        keychainKeyLabel
    }

    /// The Keychain label for the root CA *certificate* matching `activeKeychainKeyLabel`.
    ///
    /// The certificate and its key always move together: a test override that isolated only
    /// the key would still let `CertificateManager` install, trust-check, and delete the real
    /// root CA certificate the user has already approved.
    static var activeKeychainCertificateLabel: String {
        guard let override = keychainKeyLabelOverride else {
            return defaultKeychainCertificateLabel
        }
        return "\(override).cert"
    }

    static func ensureDirectoryExists() throws {
        let directory = storageDirectory
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logger.debug("Created certificate storage directory")
        }
    }

    /// Persists the root CA certificate PEM.
    ///
    /// The file is staged beside its destination with its final `0600` permissions and only
    /// then committed by an atomic replacement, so nothing that can throw runs after the live
    /// certificate has been replaced. Doing the `chmod` afterwards meant a failure there left
    /// the *new* certificate on disk while `generateRootCA` rolled the private key back — the
    /// mismatched pair that forces a regeneration and a fresh trust prompt on the next launch.
    static func saveRootCACertificate(_ certificate: Certificate) throws {
        try ensureDirectoryExists()

        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        let derBytes = Array(serializer.serializedBytes)

        let pemDocument = PEMDocument(type: "CERTIFICATE", derBytes: derBytes)
        let pemData = Data(pemDocument.pemString.utf8)

        let destination = rootCACertificateURL
        // Same directory, so the commit is a rename within one volume, and a unique name so a
        // failed attempt can only ever clean up the file it created itself.
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent("\(rootCACertFilename).staging-\(UUID().uuidString)")

        do {
            guard FileManager.default.createFile(
                atPath: staging.path,
                contents: pemData,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CertificateStoreError.certificateStagingFailed(staging.lastPathComponent)
            }
            try commitStagedCertificate(from: staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }

        logger.info("Saved root CA certificate to disk")
    }

    /// Persists the root CA private key to the Keychain. There is deliberately no disk
    /// fallback: writing a plaintext PEM would trade a visible failure for key material on
    /// disk, and a silently unpersisted key means the next launch regenerates the CA and
    /// invalidates the fingerprint the user already approved. A failure propagates so the
    /// caller never adopts a root CA that cannot survive relaunch. Legacy disk PEM / `.bak`
    /// files stay readable for one-time migration; new ones are never created.
    static func saveRootCAPrivateKey(_ key: P256.Signing.PrivateKey) throws {
        let keyData = Data(key.x963Representation)

        do {
            try KeychainHelper.savePrivateKey(keyData, label: keychainKeyLabel)
        } catch {
            logger.error("Failed to persist root CA private key to Keychain: \(error.localizedDescription)")
            throw error
        }

        logger.info("Saved root CA private key to Keychain (primary)")
    }

    static func loadRootCACertificate() throws -> Certificate? {
        let filePath = rootCACertificateURL

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        let pemData = try Data(contentsOf: filePath)
        guard let pemString = String(data: pemData, encoding: .utf8) else {
            logger.warning("Persisted root CA certificate is not valid UTF-8 — regeneration required")
            return nil
        }
        do {
            let pemDocument = try PEMDocument(pemString: pemString)
            let certificate = try Certificate(derEncoded: pemDocument.derBytes)
            logger.debug("Loaded root CA certificate from disk")
            return certificate
        } catch {
            // The file was readable, but its contents are not a usable certificate. Treat
            // that as an absent persisted CA so ensureRootCA can replace it once. Genuine
            // filesystem access failures still propagate from Data(contentsOf:) above.
            logger.warning(
                "Persisted root CA certificate is invalid — regeneration required: \(error.localizedDescription)"
            )
            return nil
        }
    }

    static func loadRootCAPrivateKey() throws -> P256.Signing.PrivateKey? {
        try loadRootCAPrivateKey(matching: nil)
    }

    /// Loads the root CA private key, preferring the Keychain and then falling through the
    /// read-only disk recovery files.
    ///
    /// - Parameter isExpectedKey: when supplied, every source is examined and only a candidate
    ///   this predicate accepts is adopted. Selecting the first *decodable* key instead lets a
    ///   valid-but-stale Keychain item or primary PEM shadow the one recovery file that
    ///   actually belongs to the persisted certificate, and migrates that stale copy over the
    ///   matching `.bak` before any cert/key comparison happens. A rejected candidate is left
    ///   exactly as it was found — nothing is migrated, renamed, or deleted unless the adopted
    ///   candidate satisfied the predicate — so the next attempt still sees every source.
    ///   Passing `nil` keeps the original first-decodable behaviour for callers that have no
    ///   certificate to match against.
    static func loadRootCAPrivateKey(
        matching isExpectedKey: ((P256.Signing.PrivateKey) -> Bool)?
    )
        throws -> P256.Signing.PrivateKey?
    {
        let accepts: (P256.Signing.PrivateKey) -> Bool = { isExpectedKey?($0) ?? true }

        // 1. Try Keychain first (primary storage)
        if let keyData = try KeychainHelper.loadPrivateKey(
            label: keychainKeyLabel,
            isUsable: { data in
                guard let candidate = try? P256.Signing.PrivateKey(x963Representation: data) else {
                    return false
                }
                return accepts(candidate)
            }
        ) {
            let key = try P256.Signing.PrivateKey(x963Representation: keyData)
            logger.info("Loaded root CA private key from Keychain (primary)")
            return key
        }

        // 2. Fall back to disk PEM for migration from older versions
        let filePath = storageDirectory.appendingPathComponent(rootCAKeyFilename)
        if let key = try loadPrivateKeyPEM(at: filePath, sourceDescription: "primary disk PEM"), accepts(key) {
            logger.info("Loaded root CA private key from disk (migration fallback)")

            // Migrate: store to Keychain, rename the valid primary disk copy to .bak.
            migrateKeyToKeychain(key: key, source: .primary)
            return key
        }

        // 3. Last resort: check for .bak file from previous migration
        let backupPath = storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")
        if let key = try loadPrivateKeyPEM(at: backupPath, sourceDescription: ".bak recovery file"), accepts(key) {
            logger.warning("Loaded root CA private key from .bak recovery file — re-migrating to Keychain")
            migrateKeyToKeychain(key: key, source: .backup)
            return key
        }

        return nil
    }

    /// Reads every persisted private-key source without migrating or rewriting any of them.
    ///
    /// Status and readiness checks use this to prove that the in-memory certificate/key pair is
    /// still the pair a relaunch would recover. Going through `loadRootCAPrivateKey(matching:)`
    /// here would turn a read-only status refresh into a Keychain migration and legacy-file
    /// cleanup opportunity. A rejected source remains untouched so an explicit recovery or trust
    /// action can still reconcile it later.
    static func loadRootCAPrivateKeyWithoutMigration(
        matching isExpectedKey: (P256.Signing.PrivateKey) -> Bool
    )
        throws -> P256.Signing.PrivateKey?
    {
        if let keyData = try KeychainHelper.loadPrivateKeyWithoutMigration(
            label: keychainKeyLabel,
            isUsable: { data in
                guard let candidate = try? P256.Signing.PrivateKey(x963Representation: data) else {
                    return false
                }
                return isExpectedKey(candidate)
            }
        ) {
            return try P256.Signing.PrivateKey(x963Representation: keyData)
        }

        let legacyPaths = [
            storageDirectory.appendingPathComponent(rootCAKeyFilename),
            storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")
        ]
        for path in legacyPaths {
            if let key = try loadPrivateKeyPEM(at: path, sourceDescription: "legacy disk recovery"),
               isExpectedKey(key)
            {
                return key
            }
        }
        return nil
    }

    /// Reads only the Keychain copy of the root CA private key.
    ///
    /// Used where a caller needs the currently persisted key as a value — capturing the
    /// rollback key before a regeneration, for example — without triggering the disk recovery
    /// migration side effects of `loadRootCAPrivateKey`.
    static func loadRootCAPrivateKeyFromKeychain() throws -> P256.Signing.PrivateKey? {
        guard let keyData = try KeychainHelper.loadPrivateKey(
            label: keychainKeyLabel,
            isUsable: { (try? P256.Signing.PrivateKey(x963Representation: $0)) != nil }
        ) else {
            return nil
        }
        return try P256.Signing.PrivateKey(x963Representation: keyData)
    }

    /// Loads the root CA private key from disk PEM only, skipping the Keychain lookup and any
    /// migration side effect. Reports what the recovery files currently hold; the matching
    /// candidate for a given certificate is selected by `loadRootCAPrivateKey(matching:)`.
    static func loadRootCAPrivateKeyFromDisk() throws -> P256.Signing.PrivateKey? {
        // Check primary disk PEM file
        let filePath = storageDirectory.appendingPathComponent(rootCAKeyFilename)
        if let key = try loadPrivateKeyPEM(at: filePath, sourceDescription: "primary disk PEM") {
            logger.info("Loaded root CA private key from disk PEM (direct, no Keychain)")
            return key
        }

        // Check .bak file from previous migration
        let backupPath = storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")
        if let key = try loadPrivateKeyPEM(at: backupPath, sourceDescription: ".bak recovery file") {
            logger.info("Loaded root CA private key from .bak recovery file (direct, no Keychain)")
            return key
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

    /// Removes plaintext migration sources only after `CertificateManager` has verified
    /// that the Keychain key matches the persisted certificate. Keeping this out of the
    /// raw Keychain load path preserves the disk recovery key when a stale or mismatched
    /// Keychain item is encountered.
    static func cleanupLegacyDiskKeys(matching expectedKey: P256.Signing.PrivateKey) {
        let expectedData = Data(expectedKey.x963Representation)
        let persistedData = try? KeychainHelper.loadPrivateKey(
            label: keychainKeyLabel,
            isUsable: { $0 == expectedData }
        )
        guard persistedData == expectedData else {
            logger.debug("Skipping legacy disk-key cleanup — Keychain does not hold the verified key")
            return
        }

        let legacyPaths = [
            storageDirectory.appendingPathComponent(rootCAKeyFilename),
            storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")
        ]
        var removedAny = false
        for path in legacyPaths where FileManager.default.fileExists(atPath: path.path) {
            do {
                try FileManager.default.removeItem(at: path)
                removedAny = true
            } catch {
                logger.warning("Failed to remove legacy private key file: \(error.localizedDescription)")
            }
        }
        if removedAny {
            logger.info("Cleaned up verified legacy private key files — Keychain is primary")
        }
    }

    #if DEBUG
    /// Removes the Keychain material this test process's *default* namespace may have created.
    ///
    /// Only the generated per-process fixture labels are addressed: the guard refuses to run
    /// unless the defaults actually differ from the production labels, so this can never delete
    /// the root CA the installed app uses. Explicit overrides own their own cleanup.
    static func removeDefaultTestNamespaceMaterial(
        deleteKey: (String) throws -> Void = { try KeychainHelper.deletePrivateKey(label: $0) },
        deleteCertificate: (String) throws -> Void = { try KeychainHelper.removeCertificate(label: $0) }
    ) {
        guard RockxyIdentity.isRunningTests,
              defaultKeychainKeyLabel != RockxyIdentity.current.rootCAKeyLabel,
              defaultKeychainCertificateLabel != RockxyIdentity.current.rootCACertificateLabel else
        {
            return
        }

        try? deleteKey(defaultKeychainKeyLabel)
        try? deleteCertificate(defaultKeychainCertificateLabel)
    }
    #endif

    // MARK: Private

    private enum DiskKeySource {
        case primary
        case backup
    }

    private static let overrideLock = NSLock()
    nonisolated(unsafe) private static var _keychainKeyLabelOverride: String?
    nonisolated(unsafe) private static var _storageDirectoryOverride: URL?
    #if DEBUG
    nonisolated(unsafe) private static var _certificateCommitOverride: ((URL, URL) throws -> Void)?
    #endif

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "CertificateStore")

    private static let rootCACertFilename = "rootCA.pem"
    private static let rootCAKeyFilename = "rootCA-key.pem"

    /// Per-process fallback labels. Production uses the shared identity labels unchanged.
    ///
    /// A test process gets its own namespace even when it installs no explicit override, so a
    /// test that reaches `CertificateManager` can never read, overwrite, trust-check, or
    /// delete the root CA material belonging to the installed app.
    private static let defaultKeychainKeyLabel: String = {
        let production = RockxyIdentity.current.rootCAKeyLabel
        guard RockxyIdentity.isRunningTests else {
            return production
        }
        return "\(production).\(testNamespaceSuffix)"
    }()

    private static let defaultKeychainCertificateLabel: String = {
        let production = RockxyIdentity.current.rootCACertificateLabel
        guard RockxyIdentity.isRunningTests else {
            return production
        }
        return "\(production).\(testNamespaceSuffix)"
    }()

    /// Namespace suffix for the default test labels.
    ///
    /// Each test *process* gets its own value. The certificate directory is already unique per
    /// process, so a constant suffix left two concurrently running XCTest processes writing and
    /// deleting one shared Keychain key while reading different certificates — exactly the
    /// mismatched pair this lifecycle work exists to prevent. The process identifier keeps the
    /// item recognisable in Keychain Access; the random component keeps two runs that reuse a
    /// process identifier apart.
    private static let testNamespaceSuffix: String = {
        #if DEBUG
        if RockxyIdentity.isRunningTests {
            // Wait until the process exits: another suite may still be using this namespace.
            atexit { CertificateStore.removeDefaultTestNamespaceMaterial() }
        }
        #endif
        let random = UUID().uuidString.prefix(8)
        return "test.\(ProcessInfo.processInfo.processIdentifier).\(random)"
    }()

    private static var keychainKeyLabel: String {
        keychainKeyLabelOverride ?? defaultKeychainKeyLabel
    }

    private static var storageDirectory: URL {
        if let override = storageDirectoryOverride {
            return override
        }
        return RockxyIdentity.current.sharedSupportDirectory()
            .appendingPathComponent("Certificates", isDirectory: true)
    }

    /// Commits an already-staged certificate file over the live path in one step.
    ///
    /// `rename(2)` is atomic within a filesystem — both paths are in the storage directory —
    /// and replaces any existing destination, so there is no window where the certificate is
    /// missing and no metadata to reapply afterwards: the committed file keeps the `0600` mode
    /// the staged file was created with.
    private static func commitStagedCertificate(from staged: URL, to destination: URL) throws {
        #if DEBUG
        if let override = certificateCommitOverride {
            try override(staged, destination)
            return
        }
        #endif

        guard rename(staged.path, destination.path) == 0 else {
            throw CertificateStoreError.certificateCommitFailed(errno)
        }
    }

    /// Migrates a private key from disk PEM to Keychain. On success, renames the disk
    /// file to `.bak` so it is no longer used as the primary source but remains available
    /// for manual recovery.
    private static func loadPrivateKeyPEM(
        at filePath: URL,
        sourceDescription: String
    )
        throws -> P256.Signing.PrivateKey?
    {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        // Read/access errors are operational failures and must propagate. Only readable but
        // malformed contents are skipped so another recovery source can be attempted.
        let pemData = try Data(contentsOf: filePath)
        guard let pemString = String(data: pemData, encoding: .utf8) else {
            logger.warning("Root CA private key \(sourceDescription) is not valid UTF-8 — skipping")
            return nil
        }

        do {
            let pemDocument = try PEMDocument(pemString: pemString)
            return try P256.Signing.PrivateKey(x963Representation: pemDocument.derBytes)
        } catch {
            logger.warning(
                "Root CA private key \(sourceDescription) is invalid — skipping: \(error.localizedDescription)"
            )
            return nil
        }
    }

    private static func migrateKeyToKeychain(key: P256.Signing.PrivateKey, source: DiskKeySource) {
        do {
            let keyData = Data(key.x963Representation)
            try KeychainHelper.savePrivateKey(keyData, label: keychainKeyLabel)
            logger.info("Migration: stored private key in Keychain")

            let filePath = storageDirectory.appendingPathComponent(rootCAKeyFilename)
            let backupPath = storageDirectory.appendingPathComponent(rootCAKeyFilename + ".bak")

            // Only a primary file that was successfully decoded may replace `.bak`. When
            // recovery came from `.bak`, keep it intact even if a corrupt primary file also
            // exists; CertificateManager removes both only after cert/key matching succeeds.
            if source == .primary, FileManager.default.fileExists(atPath: filePath.path) {
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
