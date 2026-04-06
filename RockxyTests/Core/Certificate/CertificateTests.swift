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

// Note: CertificateManager.shared tests require Keychain entitlements
// that are not available in the xcodebuild test runner. The singleton's
// ensureRootCA() saves to Keychain, which fails with -25303 in test context.
// These tests are disabled until a testable initializer or Keychain mock is added.

// MARK: - Test Isolation Helpers

/// Uses installSharedTestOverrides() from CertificateTestHelpers.swift
/// for cross-suite lock coordination of CertificateStore overrides.
private func installTestOverrides() -> (label: String, storageDir: URL, cleanup: () -> Void) {
    installSharedTestOverrides()
}

// MARK: - CertificateStoreTests

@Suite(.serialized)
struct CertificateStoreTests {
    @Test("ensureDirectoryExists creates path without throwing")
    func ensureDirectoryCreatesPath() throws {
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        try CertificateStore.ensureDirectoryExists()
        #expect(FileManager.default.fileExists(atPath: overrides.storageDir.path))
    }

    @Test("save and load roundtrip preserves certificate DER bytes")
    func saveAndLoadRoundtrip() throws {
        let overrides = installTestOverrides()
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
    func saveAndLoadKeyRoundtrip() throws {
        let overrides = installTestOverrides()
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
}

// MARK: - KeychainPrimaryStorageTests

@Suite(.serialized)
struct KeychainPrimaryStorageTests {
    @Test("key round-trip through Keychain preserves key material")
    func keychainRoundTrip() throws {
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        // Probe keychain availability — skip in sandbox/CI where keychain is inaccessible
        do {
            try KeychainHelper.savePrivateKey(Data([0x01]), label: TestIdentity.keychainProbeLabel)
            try KeychainHelper.deletePrivateKey(label: TestIdentity.keychainProbeLabel)
        } catch {
            return
        }

        let ca = try RootCAGenerator.generate()
        let keyData = Data(ca.privateKey.x963Representation)

        try KeychainHelper.savePrivateKey(keyData, label: overrides.label)

        let loadedData = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))

        let loadedKey = try P256.Signing.PrivateKey(x963Representation: loadedData)
        #expect(loadedKey.rawRepresentation == ca.privateKey.rawRepresentation)
    }

    @Test("migration: disk-only key migrates to Keychain on load")
    func diskToKeychainMigration() throws {
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        // Probe keychain availability — skip in sandbox/CI where keychain is inaccessible
        do {
            try KeychainHelper.savePrivateKey(Data([0x01]), label: TestIdentity.keychainProbeLabel)
            try KeychainHelper.deletePrivateKey(label: TestIdentity.keychainProbeLabel)
        } catch {
            return
        }

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
    func keychainPrimaryNoDiskNeeded() throws {
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        // Probe keychain availability — skip in sandbox/CI where keychain is inaccessible
        do {
            try KeychainHelper.savePrivateKey(Data([0x01]), label: TestIdentity.keychainProbeLabel)
            try KeychainHelper.deletePrivateKey(label: TestIdentity.keychainProbeLabel)
        } catch {
            return
        }

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
    func bakRecoveryFallback() throws {
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        // Probe keychain availability — skip in sandbox/CI where keychain is inaccessible
        do {
            try KeychainHelper.savePrivateKey(Data([0x01]), label: TestIdentity.keychainProbeLabel)
            try KeychainHelper.deletePrivateKey(label: TestIdentity.keychainProbeLabel)
        } catch {
            return
        }

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
}
