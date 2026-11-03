import Crypto
import Foundation
@testable import Rockxy
import SwiftASN1
import Testing
import X509

// MARK: - IdentityLoadCountingStore

/// Counts loads so a memoized identity can be told apart from a re-resolved one, and can forget
/// and restore an account to simulate a private key that stops and starts being readable.
private final class IdentityLoadCountingStore: SecureDataStore, @unchecked Sendable {
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

    func forget(account: String) -> Data? {
        lock.withLock { values.removeValue(forKey: account) }
    }

    func restore(_ data: Data, account: String) {
        lock.withLock { values[account] = data }
    }

    func loads() -> Int {
        lock.withLock { loadCount }
    }

    // MARK: Private

    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var loadCount = 0
}

// MARK: - CustomIdentityKeyMemoizationTests

/// `TLSInterceptHandler` asks for a per-host custom identity on every intercepted connection, and
/// resolving one used to mean an XPC round trip to securityd each time. The memoization follows
/// `activeRootIssuerSnapshot`: same generation counter, dropped in the same critical section that
/// replaces the entry list. These cover the parts that matter -- a replaced or removed identity
/// must never be served, and a key that cannot be read must be retried rather than remembered.
struct CustomIdentityKeyMemoizationTests {
    // MARK: Internal

    @Test("repeated connections to one host load the private key once")
    func memoizesMatchedServerIdentity() throws {
        let fixture = makeFixture()
        let identity = try makeLeafIdentity(host: "api.example.com")
        try fixture.manager.importServerIdentity(
            hostPattern: "api.example.com",
            displayName: "Pinned Server",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )

        let first = try #require(fixture.manager.serverIdentity(for: "api.example.com"))
        let loadsAfterFirst = fixture.store.loads()
        let second = try #require(fixture.manager.serverIdentity(for: "API.Example.com"))
        let third = try #require(fixture.manager.serverIdentity(for: "api.example.com"))

        #expect(fixture.store.loads() == loadsAfterFirst)
        #expect(second.privateKeyPEM == first.privateKeyPEM)
        #expect(third.certificateChainPEM == first.certificateChainPEM)
    }

    /// The no-custom-certificates case is the common one, and it used to pay a `lowercased()` per
    /// intercepted connection before discovering there was nothing to match.
    @Test("no imported certificates means no keychain read at all")
    func emptyStoreReadsNothing() {
        let fixture = makeFixture()

        #expect(fixture.manager.serverIdentity(for: "api.example.com") == nil)
        #expect(fixture.manager.clientIdentity(for: "api.example.com") == nil)
        #expect(fixture.store.loads() == 0)
    }

    @Test("replacing the identity for a host stops the memoized key being served")
    func replacingIdentityInvalidatesMemoizedKey() throws {
        let fixture = makeFixture()
        let original = try makeLeafIdentity(host: "api.example.com")
        try fixture.manager.importServerIdentity(
            hostPattern: "api.example.com",
            displayName: "First",
            certificatePEM: original.certificatePEM,
            privateKeyPEM: original.privateKeyPEM
        )
        let before = try #require(fixture.manager.serverIdentity(for: "api.example.com"))
        let loadsAfterFirst = fixture.store.loads()

        let replacement = try makeLeafIdentity(host: "api.example.com")
        try fixture.manager.importServerIdentity(
            hostPattern: "api.example.com",
            displayName: "Second",
            certificatePEM: replacement.certificatePEM,
            privateKeyPEM: replacement.privateKeyPEM
        )

        let after = try #require(fixture.manager.serverIdentity(for: "api.example.com"))
        #expect(fixture.store.loads() > loadsAfterFirst)
        #expect(after.privateKeyPEM != before.privateKeyPEM)
        #expect(after.privateKeyPEM == replacement.privateKeyPEM)
    }

    @Test("deleting the identity stops it being served from memory")
    func deletingIdentityInvalidatesMemoizedKey() throws {
        let fixture = makeFixture()
        let identity = try makeLeafIdentity(host: "api.example.com")
        try fixture.manager.importServerIdentity(
            hostPattern: "api.example.com",
            displayName: "Deleted",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )
        #expect(fixture.manager.serverIdentity(for: "api.example.com") != nil)

        try fixture.manager.deleteAll(kind: .server)

        #expect(fixture.manager.serverIdentity(for: "api.example.com") == nil)
    }

    /// A key that cannot be read right now is the state a user goes and fixes. Remembering the
    /// failure would keep answering with it until the next store mutation, long after the key
    /// worked again.
    @Test("an unreadable private key is retried rather than memoized")
    func doesNotMemoizeAnUnreadableKey() throws {
        let fixture = makeFixture()
        let identity = try makeLeafIdentity(host: "api.example.com")
        let metadata = try fixture.manager.importServerIdentity(
            hostPattern: "api.example.com",
            displayName: "Broken Then Fixed",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )

        let keyData = try #require(fixture.store.forget(account: metadata.keychainAccount))
        #expect(fixture.manager.serverIdentity(for: "api.example.com") == nil)
        let loadsAfterFailure = fixture.store.loads()
        #expect(fixture.manager.serverIdentity(for: "api.example.com") == nil)
        #expect(fixture.store.loads() > loadsAfterFailure)

        // No store mutation in between: the fix has to be visible on the next connection.
        fixture.store.restore(keyData, account: metadata.keychainAccount)
        let resolved = try #require(fixture.manager.serverIdentity(for: "api.example.com"))
        #expect(resolved.privateKeyPEM == identity.privateKeyPEM)
    }

    // MARK: Private

    private func makeFixture() -> (manager: CustomCertificateManager, store: IdentityLoadCountingStore) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyCustomIdentityMemoization-\(UUID().uuidString)")
            .appendingPathComponent("custom.json")
        let store = IdentityLoadCountingStore()
        return (
            CustomCertificateManager(
                storageURL: url,
                secureStore: store,
                metadataWriter: FileCustomCertificateMetadataWriter()
            ),
            store
        )
    }

    private func makeLeafIdentity(host: String) throws -> (certificatePEM: String, privateKeyPEM: String) {
        let root = try RootCAGenerator.generate()
        let leaf = try HostCertGenerator.generate(host: host, issuer: root.certificate, issuerKey: root.privateKey)
        return try (pem(leaf.certificate), leaf.privateKey.pemRepresentation)
    }

    private func pem(_ certificate: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
    }
}
