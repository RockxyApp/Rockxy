import Crypto
import Foundation
@testable import Rockxy
import SwiftASN1
import Testing
import X509

// MARK: - CountingSecureDataStore

/// Counts loads so a memoized snapshot can be told apart from a re-resolved one, and can forget
/// an account to simulate a private key that is no longer readable.
private final class CountingSecureDataStore: SecureDataStore, @unchecked Sendable {
    // MARK: Internal

    func save(_ data: Data, account: String) throws {
        lock.withLock { values[account] = data }
    }

    func load(account: String) throws -> Data? {
        lock.withLock {
            loadCount += 1
            return values[account]
        }
    }

    func delete(account: String) throws {
        lock.withLock { values.removeValue(forKey: account) }
    }

    func forget(account: String) {
        lock.withLock { values.removeValue(forKey: account) }
    }

    func loads() -> Int {
        lock.withLock { loadCount }
    }

    // MARK: Private

    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var loadCount = 0
}

// MARK: - CustomRootIssuerMemoizationTests

/// `CertificateManager.certificateForHost` asks for the active custom root on every intercepted
/// connection, so resolving it is memoized. These cover the part that matters: a stale snapshot
/// must never survive the user replacing or removing their root.
struct CustomRootIssuerMemoizationTests {
    // MARK: Internal

    @Test("repeated snapshots of an unchanged root resolve the private key once")
    func memoizesUnchangedRoot() throws {
        let fixture = makeFixture()
        let root = try RootCAGenerator.generate()
        try fixture.manager.importRoot(
            displayName: "Custom Root",
            certificatePEM: pem(root.certificate),
            privateKeyPEM: root.privateKey.pemRepresentation
        )

        let first = try #require(try fixture.manager.activeRootIssuerSnapshot())
        let loadsAfterFirst = fixture.store.loads()
        let second = try #require(try fixture.manager.activeRootIssuerSnapshot())
        let third = try #require(try fixture.manager.activeRootIssuerSnapshot())

        #expect(fixture.store.loads() == loadsAfterFirst)
        #expect(second.fingerprintSHA256 == first.fingerprintSHA256)
        #expect(third.certificate.subject == root.certificate.subject)
    }

    @Test("replacing the root invalidates the memoized snapshot")
    func replacingRootInvalidatesSnapshot() throws {
        let fixture = makeFixture()
        let first = try RootCAGenerator.generate()
        try fixture.manager.importRoot(
            displayName: "First Root",
            certificatePEM: pem(first.certificate),
            privateKeyPEM: first.privateKey.pemRepresentation
        )
        let firstSnapshot = try #require(try fixture.manager.activeRootIssuerSnapshot())

        let second = try RootCAGenerator.generate()
        let replacement = try fixture.manager.importRoot(
            displayName: "Second Root",
            certificatePEM: pem(second.certificate),
            privateKeyPEM: second.privateKey.pemRepresentation
        )
        let secondSnapshot = try #require(try fixture.manager.activeRootIssuerSnapshot())

        #expect(secondSnapshot.fingerprintSHA256 != firstSnapshot.fingerprintSHA256)
        #expect(secondSnapshot.fingerprintSHA256 == replacement.fingerprintSHA256)
        #expect(
            secondSnapshot.privateKey.publicKey.subjectPublicKeyInfoBytes
                == second.certificate.publicKey.subjectPublicKeyInfoBytes
        )
    }

    @Test("deleting the root stops the memoized snapshot being served")
    func deletingRootInvalidatesSnapshot() throws {
        let fixture = makeFixture()
        let root = try RootCAGenerator.generate()
        try fixture.manager.importRoot(
            displayName: "Deleted Root",
            certificatePEM: pem(root.certificate),
            privateKeyPEM: root.privateKey.pemRepresentation
        )
        #expect(try fixture.manager.activeRootIssuerSnapshot() != nil)

        try fixture.manager.deleteAll(kind: .root)

        #expect(try fixture.manager.activeRootIssuerSnapshot() == nil)
    }

    /// The certificate UI distinguishes "no custom root" from "a custom root Rockxy cannot use",
    /// so an unreadable private key must still be reported here. Falling back to Rockxy's own
    /// generated root is `CertificateManager`'s job, not this API's.
    @Test("an unreadable private key is still reported instead of resolving to nil")
    func unreadablePrivateKeyStillThrows() throws {
        let fixture = makeFixture()
        let root = try RootCAGenerator.generate()
        let metadata = try fixture.manager.importRoot(
            displayName: "Broken Root",
            certificatePEM: pem(root.certificate),
            privateKeyPEM: root.privateKey.pemRepresentation
        )

        fixture.store.forget(account: metadata.keychainAccount)

        #expect(throws: CustomCertificateError.missingPrivateKey) {
            try fixture.manager.activeRootIssuerSnapshot()
        }
    }

    // MARK: Private

    private func makeFixture() -> (manager: CustomCertificateManager, store: CountingSecureDataStore) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyCustomRootMemoization-\(UUID().uuidString)")
            .appendingPathComponent("custom.json")
        let store = CountingSecureDataStore()
        return (
            CustomCertificateManager(
                storageURL: url,
                secureStore: store,
                metadataWriter: FileCustomCertificateMetadataWriter()
            ),
            store
        )
    }

    private func pem(_ certificate: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
    }
}
