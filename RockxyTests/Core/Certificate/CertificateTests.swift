import Crypto
import Foundation
@testable import Rockxy
import Security
import SwiftASN1
import Testing
import X509

// Regression tests for `Certificate` in the core certificate layer.

// MARK: - RootCAGeneratorTests

struct RootCAGeneratorTests {
    @Test("generate creates valid certificate and key")
    func generateCreatesValidCertificate() throws {
        let result = try RootCAGenerator.generate()
        #expect(result.certificate.subject.description.contains("Rockxy"))
    }

    @Test("generated certificate subject contains Rockxy")
    func generatedCertificateHasCorrectSubject() throws {
        let result = try RootCAGenerator.generate()
        var serializer = DER.Serializer()
        try result.certificate.serialize(into: &serializer)
        let derBytes = serializer.serializedBytes
        #expect(!derBytes.isEmpty)
        #expect(result.certificate.subject.description.contains("Rockxy"))
    }

    @Test("generated key is P256 (32-byte raw representation)")
    func generatedKeyIsP256() throws {
        let result = try RootCAGenerator.generate()
        #expect(result.privateKey.rawRepresentation.count == 32)
    }

    @Test("multiple generations produce different keys")
    func multipleGenerationsProduceDifferentKeys() throws {
        let first = try RootCAGenerator.generate()
        let second = try RootCAGenerator.generate()
        #expect(first.privateKey.rawRepresentation != second.privateKey.rawRepresentation)
    }

    @Test("generated roots use RFC 5280 serial lengths and key-specific subjects")
    func generatedRootsAvoidChromiumTrustAmbiguity() throws {
        let first = try RootCAGenerator.generate().certificate
        let second = try RootCAGenerator.generate().certificate

        #expect(first.serialNumber.bytes.count <= CertificateSerialNumberGenerator.maximumEncodedByteCount)
        #expect(second.serialNumber.bytes.count <= CertificateSerialNumberGenerator.maximumEncodedByteCount)
        #expect(!RootCAGenerator.requiresClientCompatibilityRepair(first))
        #expect(first.subject != second.subject)
        #expect(first.subject.description.contains("Rockxy Root CA "))
    }

    @Test("legacy sign-prefixed 20-byte serial requires compatibility repair")
    func legacySerialRequiresCompatibilityRepair() {
        let legacySerial = Certificate.SerialNumber(bytes: [0x80] + Array(repeating: 0, count: 19))

        #expect(legacySerial.bytes.count == 20)
        #expect(RootCAGenerator.requiresClientCompatibilityRepair(serialNumber: legacySerial))
    }

    @Test("serial generator always leaves room for a positive sign octet")
    func serialGeneratorIsAlwaysRFC5280Bounded() {
        for _ in 0 ..< 512 {
            let serial = CertificateSerialNumberGenerator.generate()
            #expect(serial.bytes.count <= CertificateSerialNumberGenerator.maximumEncodedByteCount)
        }
    }
}

// MARK: - HostCertGeneratorTests

struct HostCertGeneratorTests {
    @Test("generate host cert for domain without throwing")
    func generateHostCertForDomain() throws {
        let ca = try RootCAGenerator.generate()
        let hostResult = try HostCertGenerator.generate(
            host: "example.com",
            issuer: ca.certificate,
            issuerKey: ca.privateKey
        )
        #expect(hostResult.certificate.subject.description.contains("example.com"))
    }

    @Test("host cert has different key from CA")
    func hostCertHasDifferentKeyFromCA() throws {
        let ca = try RootCAGenerator.generate()
        let hostResult = try HostCertGenerator.generate(
            host: "example.com",
            issuer: ca.certificate,
            issuerKey: ca.privateKey
        )
        #expect(hostResult.privateKey.rawRepresentation != ca.privateKey.rawRepresentation)
    }

    @Test("host certificate serial stays within the RFC 5280 limit")
    func hostCertificateSerialIsRFC5280Bounded() throws {
        let ca = try RootCAGenerator.generate()
        let hostResult = try HostCertGenerator.generate(
            host: "serial.example.com",
            issuer: ca.certificate,
            issuerKey: ca.privateKey
        )

        #expect(hostResult.certificate.serialNumber.bytes.count <= CertificateSerialNumberGenerator.maximumEncodedByteCount)
    }

    @Test("host cert includes SubjectKeyIdentifier extension")
    func hostCertIncludesSKI() throws {
        let ca = try RootCAGenerator.generate()
        let hostResult = try HostCertGenerator.generate(
            host: "ski-test.example.com",
            issuer: ca.certificate,
            issuerKey: ca.privateKey
        )
        let ski = try? hostResult.certificate.extensions.subjectKeyIdentifier
        #expect(ski != nil)
    }

    @Test("host cert includes AuthorityKeyIdentifier extension")
    func hostCertIncludesAKI() throws {
        let ca = try RootCAGenerator.generate()
        let hostResult = try HostCertGenerator.generate(
            host: "aki-test.example.com",
            issuer: ca.certificate,
            issuerKey: ca.privateKey
        )
        let aki = try? hostResult.certificate.extensions.authorityKeyIdentifier
        #expect(aki != nil)
    }

    @Test("multiple host certs have different keys")
    func multipleHostCertsHaveDifferentKeys() throws {
        let ca = try RootCAGenerator.generate()
        let host1 = try HostCertGenerator.generate(
            host: "one.example.com",
            issuer: ca.certificate,
            issuerKey: ca.privateKey
        )
        let host2 = try HostCertGenerator.generate(
            host: "two.example.com",
            issuer: ca.certificate,
            issuerKey: ca.privateKey
        )
        #expect(host1.privateKey.rawRepresentation != host2.privateKey.rawRepresentation)
    }
}

// MARK: - CertificateManagerTests

// Note: root CA private keys are stored as secure generic-password data. The previous
// kSecClassKey item shape failed with errSecNoSuchAttr (-25303), which is why these tests
// used to skip silently instead of exercising the real round-trip. Keychain-backed
// assertions below run for real and fail loudly if storage breaks again.

// MARK: - Test Isolation Helpers

/// Uses installSharedTestOverrides() from CertificateTestHelpers.swift
/// for cross-suite gate coordination of CertificateStore overrides.
private func installTestOverrides() async throws
    -> (label: String, certificateLabel: String, storageDir: URL, cleanup: @Sendable () -> Void)
{
    try await installSharedTestOverrides()
}

// MARK: - CertificateStoreTests

@Suite(.serialized)
struct CertificateStoreTests {
    // MARK: Internal

    @Test("ensureDirectoryExists creates path without throwing")
    func ensureDirectoryCreatesPath() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        try CertificateStore.ensureDirectoryExists()
        #expect(FileManager.default.fileExists(atPath: overrides.storageDir.path))
    }

    @Test("save and load roundtrip preserves certificate DER bytes")
    func saveAndLoadRoundtrip() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        let ca = try RootCAGenerator.generate()

        try CertificateStore.saveRootCACertificate(ca.certificate)
        try CertificateStore.saveRootCAPrivateKey(ca.privateKey)

        let loadedCert = try CertificateStore.loadRootCACertificate()
        #expect(loadedCert != nil)

        var originalSerializer = DER.Serializer()
        try ca.certificate.serialize(into: &originalSerializer)

        var loadedSerializer = DER.Serializer()
        try loadedCert?.serialize(into: &loadedSerializer)

        #expect(
            Array(originalSerializer.serializedBytes) == Array(loadedSerializer.serializedBytes)
        )

        try CertificateStore.deleteAll()
    }

    @Test("save and load roundtrip preserves private key")
    func saveAndLoadKeyRoundtrip() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        let ca = try RootCAGenerator.generate()

        try CertificateStore.saveRootCACertificate(ca.certificate)
        try CertificateStore.saveRootCAPrivateKey(ca.privateKey)

        let loadedCert = try CertificateStore.loadRootCACertificate()
        let loadedKey = try CertificateStore.loadRootCAPrivateKey()

        #expect(loadedCert != nil)
        #expect(loadedKey != nil)
        #expect(loadedKey?.rawRepresentation == ca.privateKey.rawRepresentation)

        try CertificateStore.deleteAll()
    }

    @Test("reload after persistence keeps the exact key and certificate fingerprint")
    func reloadPreservesKeyAndFingerprint() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        let ca = try RootCAGenerator.generate()

        try CertificateStore.saveRootCAPrivateKey(ca.privateKey)
        try CertificateStore.saveRootCACertificate(ca.certificate)

        // Simulate a relaunch: nothing is cached in memory, everything comes back from
        // the Keychain and the certificate PEM on disk.
        let reloadedKey = try #require(try CertificateStore.loadRootCAPrivateKey())
        let reloadedCert = try #require(try CertificateStore.loadRootCACertificate())

        let expectedFingerprint = try fingerprint(of: ca.certificate)
        let reloadedFingerprint = try fingerprint(of: reloadedCert)

        #expect(reloadedKey.rawRepresentation == ca.privateKey.rawRepresentation)
        #expect(reloadedFingerprint == expectedFingerprint)

        try CertificateStore.deleteAll()
    }

    @Test("persisting the private key never writes a plaintext key file")
    func persistingKeyWritesNoPlaintextFile() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        let ca = try RootCAGenerator.generate()

        try CertificateStore.saveRootCAPrivateKey(ca.privateKey)
        try CertificateStore.saveRootCACertificate(ca.certificate)

        let keyPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        let backupPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)

        #expect(!FileManager.default.fileExists(atPath: keyPath.path))
        #expect(!FileManager.default.fileExists(atPath: backupPath.path))

        try CertificateStore.deleteAll()
    }

    @Test("corrupt persisted certificate is treated as recoverable absence")
    func corruptCertificateReturnsNil() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        try CertificateStore.ensureDirectoryExists()
        try Data("not a certificate".utf8).write(to: CertificateStore.rootCACertificateURL)

        let loadedCertificate = try CertificateStore.loadRootCACertificate()
        #expect(loadedCertificate == nil)
    }

    // MARK: Private

    private func fingerprint(of certificate: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return KeychainHelper.computeFingerprintSHA256(Data(serializer.serializedBytes))
    }
}

// MARK: - KeychainPrimaryStorageTests

@Suite(.serialized)
struct KeychainPrimaryStorageTests {
    // MARK: Internal

    @Test("key round-trip through Keychain preserves key material")
    func keychainRoundTrip() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        let ca = try RootCAGenerator.generate()
        let keyData = Data(ca.privateKey.x963Representation)

        try KeychainHelper.savePrivateKey(keyData, label: overrides.label)

        let loadedData = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))

        let loadedKey = try P256.Signing.PrivateKey(x963Representation: loadedData)
        #expect(loadedKey.rawRepresentation == ca.privateKey.rawRepresentation)
    }

    @Test("manually seeded generic-password key is loaded")
    func seededGenericPasswordKeyLoads() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        let key = P256.Signing.PrivateKey()
        let keyData = Data(key.x963Representation)
        try addPrivateKeyFixture(keyData, label: overrides.label)

        let loadedData = try #require(try KeychainHelper.loadPrivateKey(
            label: overrides.label,
            isUsable: { (try? P256.Signing.PrivateKey(x963Representation: $0)) != nil }
        ))

        #expect(loadedData == keyData)
        #expect(try privateKeyFixture(label: overrides.label) == keyData)
    }

    @Test("invalid Keychain key recovers from valid disk backup")
    func corruptKeychainKeyRecoversFromBackup() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        let validKey = P256.Signing.PrivateKey()
        let validData = Data(validKey.x963Representation)
        try addPrivateKeyFixture(Data([0x01, 0x02, 0x03]), label: overrides.label)
        try CertificateStore.ensureDirectoryExists()
        let backupDocument = PEMDocument(type: "EC PRIVATE KEY", derBytes: Array(validData))
        let backupPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        try Data(backupDocument.pemString.utf8).write(to: backupPath)

        let loadedKey = try #require(try CertificateStore.loadRootCAPrivateKey())

        #expect(loadedKey.rawRepresentation == validKey.rawRepresentation)
        #expect(try privateKeyFixture(label: overrides.label) == validData)
        #expect(FileManager.default.fileExists(atPath: backupPath.path))
    }

    @Test("migration: disk-only key migrates to Keychain on load")
    func diskToKeychainMigration() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        let ca = try RootCAGenerator.generate()

        // Clear Keychain to simulate pre-migration state
        try KeychainHelper.deletePrivateKey(label: overrides.label)

        // Write key to disk only (bypassing the new Keychain-primary save)
        try CertificateStore.ensureDirectoryExists()
        let derBytes = Array(ca.privateKey.x963Representation)
        let pemDocument = PEMDocument(type: "EC PRIVATE KEY", derBytes: derBytes)
        let pemString = pemDocument.pemString
        let filePath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        try Data(pemString.utf8).write(to: filePath)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath.path)

        // Load should find disk file, migrate to Keychain, rename to .bak
        let loadedKey = try CertificateStore.loadRootCAPrivateKey()
        #expect(loadedKey != nil)
        #expect(loadedKey?.rawRepresentation == ca.privateKey.rawRepresentation)

        // Verify key is now in Keychain
        let keychainData = try KeychainHelper.loadPrivateKey(label: overrides.label)
        #expect(keychainData != nil)

        // Verify disk file was renamed to .bak
        let backupPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        #expect(FileManager.default.fileExists(atPath: backupPath.path))
        #expect(!FileManager.default.fileExists(atPath: filePath.path))
    }

    @Test("Keychain-primary: loads from Keychain even without disk file")
    func keychainPrimaryNoDiskNeeded() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        let ca = try RootCAGenerator.generate()

        // Store key in Keychain directly
        let keyData = Data(ca.privateKey.x963Representation)
        try KeychainHelper.savePrivateKey(keyData, label: overrides.label)

        // Ensure no disk PEM exists
        try CertificateStore.ensureDirectoryExists()
        let filePath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        if FileManager.default.fileExists(atPath: filePath.path) {
            try FileManager.default.removeItem(at: filePath)
        }

        // Load should succeed from Keychain alone
        let loadedKey = try CertificateStore.loadRootCAPrivateKey()
        #expect(loadedKey != nil)
        #expect(loadedKey?.rawRepresentation == ca.privateKey.rawRepresentation)
    }

    @Test(".bak recovery: loads from .bak when Keychain and disk PEM are both missing")
    func bakRecoveryFallback() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        let ca = try RootCAGenerator.generate()

        // Clear Keychain — simulate lost Keychain state
        try KeychainHelper.deletePrivateKey(label: overrides.label)

        // Write key as .bak only (simulate post-migration state where Keychain was later lost)
        try CertificateStore.ensureDirectoryExists()
        let derBytes = Array(ca.privateKey.x963Representation)
        let pemDocument = PEMDocument(type: "EC PRIVATE KEY", derBytes: derBytes)
        let pemString = pemDocument.pemString
        let backupPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        try Data(pemString.utf8).write(to: backupPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupPath.path)

        // Ensure no active disk PEM exists
        let filePath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        if FileManager.default.fileExists(atPath: filePath.path) {
            try FileManager.default.removeItem(at: filePath)
        }

        // Load should recover from .bak and re-migrate to Keychain
        let loadedKey = try CertificateStore.loadRootCAPrivateKey()
        #expect(loadedKey != nil)
        #expect(loadedKey?.rawRepresentation == ca.privateKey.rawRepresentation)

        // Verify key was re-migrated to Keychain
        let keychainData = try KeychainHelper.loadPrivateKey(label: overrides.label)
        #expect(keychainData != nil)
    }

    @Test("corrupt primary disk key falls through to valid backup")
    func corruptPrimaryDiskKeyFallsThroughToBackup() async throws {
        let overrides = try await installTestOverrides()
        defer { overrides.cleanup() }

        try KeychainHelper.deletePrivateKey(label: overrides.label)
        try CertificateStore.ensureDirectoryExists()

        let validKey = P256.Signing.PrivateKey()
        let primaryPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        let backupPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        try Data("not a private key".utf8).write(to: primaryPath)
        let backupDocument = PEMDocument(
            type: "EC PRIVATE KEY",
            derBytes: Array(validKey.x963Representation)
        )
        try Data(backupDocument.pemString.utf8).write(to: backupPath)

        let loadedKey = try #require(try CertificateStore.loadRootCAPrivateKey())
        let directDiskKey = try #require(try CertificateStore.loadRootCAPrivateKeyFromDisk())

        #expect(loadedKey.rawRepresentation == validKey.rawRepresentation)
        #expect(directDiskKey.rawRepresentation == validKey.rawRepresentation)
        #expect(FileManager.default.fileExists(atPath: primaryPath.path))
        #expect(FileManager.default.fileExists(atPath: backupPath.path))
    }

    @Test("transient Keychain read statuses are never classified as absence")
    func transientKeychainStatusesRemainFailures() {
        #expect(KeychainHelper.classifyReadStatus(errSecItemNotFound) == .absent)
        #expect(KeychainHelper.classifyReadStatus(errSecInteractionNotAllowed) == .failure)
        #expect(KeychainHelper.classifyReadStatus(errSecAuthFailed) == .failure)
        #expect(KeychainHelper.classifyReadStatus(errSecNoSuchAttr) == .failure)
        #expect(
            KeychainHelper.classifyReadStatus(errSecNoSuchAttr, toleratesMalformedShape: true) == .absent
        )
    }

    // MARK: Private

    private var privateKeyAccount: String {
        "root-ca-private-key"
    }

    private func addPrivateKeyFixture(
        _ data: Data,
        label: String
    )
        throws
    {
        var query = privateKeyFixtureQuery(label: label)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func privateKeyFixture(label: String) throws -> Data? {
        var query = privateKeyFixtureQuery(label: label)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        return result as? Data
    }

    private func privateKeyFixtureQuery(label: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: label,
            kSecAttrAccount as String: privateKeyAccount
        ]
    }
}
