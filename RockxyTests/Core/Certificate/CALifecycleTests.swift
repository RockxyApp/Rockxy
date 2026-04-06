import Crypto
import Foundation
@testable import Rockxy
import SwiftASN1
import Testing
import X509

// MARK: - CALifecycleTests

/// Tests use shared CertificateStore overrides, so must run serially.
@Suite(.serialized)
struct CALifecycleTests {
    @Test("new root CA validity is 2 years")
    func rootCAValidityIsTwoYears() throws {
        let result = try RootCAGenerator.generate()
        let cert = result.certificate

        let now = Date()
        let expectedEnd = try #require(Calendar.current.date(byAdding: .year, value: 2, to: now))

        let tolerance: TimeInterval = 7 * 24 * 60 * 60
        let diff = abs(cert.notValidAfter.timeIntervalSince(expectedEnd))
        #expect(
            diff < tolerance,
            "Certificate validity should be ~2 years, got \(diff / (365.25 * 24 * 60 * 60)) years difference"
        )

        let twoDaysAgo = try #require(Calendar.current.date(byAdding: .day, value: -2, to: now))
        let startDiff = abs(cert.notValidBefore.timeIntervalSince(twoDaysAgo))
        #expect(startDiff < tolerance, "Certificate start should be ~2 days ago")
    }

    @Test("root CA validity is NOT 10 years")
    func rootCAValidityIsNotTenYears() throws {
        let result = try RootCAGenerator.generate()
        let cert = result.certificate

        let now = Date()
        let tenYears = try #require(Calendar.current.date(byAdding: .year, value: 10, to: now))

        let diff = tenYears.timeIntervalSince(cert.notValidAfter)
        #expect(diff > 7 * 365.25 * 24 * 60 * 60, "Validity should not be 10 years")
    }

    @Test("cleanupLegacyDiskKeys removes .bak when Keychain has key")
    func cleanupRemovesBakWithKeychainKey() throws {
        let overrides = installSharedTestOverrides()
        defer { overrides.cleanup() }

        // Probe Keychain — early return if inaccessible (sandbox/CI)
        let probeKey = P256.Signing.PrivateKey()
        do {
            try KeychainHelper.savePrivateKey(Data(probeKey.x963Representation), label: overrides.label)
        } catch {
            return
        }

        let bakPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        try FileManager.default.createDirectory(at: overrides.storageDir, withIntermediateDirectories: true)
        try "legacy key data".write(to: bakPath, atomically: true, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: bakPath.path))

        CertificateStore.cleanupLegacyDiskKeys()

        #expect(!FileManager.default.fileExists(atPath: bakPath.path))
    }

    @Test("cleanupLegacyDiskKeys preserves .bak when Keychain is empty")
    func cleanupPreservesBakWithoutKeychainKey() throws {
        let overrides = installSharedTestOverrides()
        defer { overrides.cleanup() }

        let bakPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        try FileManager.default.createDirectory(at: overrides.storageDir, withIntermediateDirectories: true)
        try "legacy key data".write(to: bakPath, atomically: true, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: bakPath.path))

        CertificateStore.cleanupLegacyDiskKeys()

        #expect(FileManager.default.fileExists(atPath: bakPath.path))
    }

    @Test("bak migration preserves recovery when no primary PEM exists")
    func bakMigrationPreservesRecoveryWhenNoPrimaryPEM() throws {
        let overrides = installSharedTestOverrides()
        defer { overrides.cleanup() }

        // Probe Keychain — early return if inaccessible (sandbox/CI)
        let probeKey = P256.Signing.PrivateKey()
        do {
            try KeychainHelper.savePrivateKey(Data(probeKey.x963Representation), label: overrides.label)
            try KeychainHelper.deletePrivateKey(label: overrides.label)
        } catch {
            return
        }

        try FileManager.default.createDirectory(at: overrides.storageDir, withIntermediateDirectories: true)

        let key = P256.Signing.PrivateKey()
        let derBytes = Array(key.x963Representation)
        let pemDocument = PEMDocument(type: "EC PRIVATE KEY", derBytes: derBytes)
        let bakPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCABackupFilename)
        try Data(pemDocument.pemString.utf8).write(to: bakPath)

        let primaryPath = overrides.storageDir.appendingPathComponent(TestIdentity.rootCAKeyFilename)
        #expect(!FileManager.default.fileExists(atPath: primaryPath.path))

        let loaded = try CertificateStore.loadRootCAPrivateKey()
        #expect(loaded != nil)

        #expect(FileManager.default.fileExists(atPath: bakPath.path))

        let keychainKey = try KeychainHelper.loadPrivateKey(label: overrides.label)
        #expect(keychainKey != nil)
    }

    @Test("CertificateManager clearFreshlyInstalledFlag resets flag")
    func clearFreshlyInstalledFlag() async {
        let manager = CertificateManager.shared
        await manager.clearFreshlyInstalledFlag()
        let flag = await manager.rootCAFreshlyInstalled
        #expect(flag == false)
    }
}
