import Crypto
import Foundation
@testable import Rockxy
import SwiftASN1
import Testing
import X509

// MARK: - TestStoreError

private enum TestStoreError: Error {
    case injectedDelete
    case injectedPersistence
}

// MARK: - MemorySecureDataStore

private final class MemorySecureDataStore: SecureDataStore, @unchecked Sendable {
    // MARK: Internal

    func save(_ data: Data, account: String) throws {
        lock.withLock {
            saveCount += 1
            values[account] = data
        }
    }

    func load(account: String) throws -> Data? {
        lock.withLock {
            loadCount += 1
            return values[account]
        }
    }

    func delete(account: String) throws {
        try lock.withLock {
            deleteCount += 1
            if failingDeleteAccounts.contains(account) {
                throw TestStoreError.injectedDelete
            }
            values.removeValue(forKey: account)
        }
    }

    func failDelete(account: String) {
        lock.withLock {
            _ = failingDeleteAccounts.insert(account)
        }
    }

    func data(account: String) -> Data? {
        lock.withLock { values[account] }
    }

    func accounts() -> Set<String> {
        lock.withLock { Set(values.keys) }
    }

    func operationCounts() -> (save: Int, load: Int, delete: Int) {
        lock.withLock { (saveCount, loadCount, deleteCount) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var failingDeleteAccounts = Set<String>()
    private var saveCount = 0
    private var loadCount = 0
    private var deleteCount = 0
}

// MARK: - FaultingMetadataWriter

private final class FaultingMetadataWriter: CustomCertificateMetadataWriter, @unchecked Sendable {
    // MARK: Internal

    func write(_ data: Data, to url: URL) throws {
        try lock.withLock {
            writeCount += 1
            if shouldFail {
                throw TestStoreError.injectedPersistence
            }
            if let failingWriteNumber, writeCount == failingWriteNumber {
                throw TestStoreError.injectedPersistence
            }
            try base.write(data, to: url)
        }
    }

    func failWrites() {
        lock.withLock {
            shouldFail = true
        }
    }

    func failAfterSuccessfulWrites(_ count: Int) {
        lock.withLock {
            failingWriteNumber = writeCount + count + 1
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private let base = FileCustomCertificateMetadataWriter()
    private var shouldFail = false
    private var writeCount = 0
    private var failingWriteNumber: Int?
}

// MARK: - CustomCertificateManagerTests

struct CustomCertificateManagerTests {
    // MARK: Internal

    @Test("imports custom root certificate and exposes it as active issuer")
    func importsCustomRootIssuer() throws {
        let manager = makeManager()
        let root = try RootCAGenerator.generate()

        let metadata = try manager.importRoot(
            displayName: "Custom Root",
            certificatePEM: pem(root.certificate),
            privateKeyPEM: root.privateKey.pemRepresentation
        )

        let issuer = try #require(try manager.activeRootIssuer())
        #expect(issuer.certificate.subject == root.certificate.subject)
        #expect(issuer.privateKey.publicKey.subjectPublicKeyInfoBytes == root.certificate.publicKey
            .subjectPublicKeyInfoBytes)

        let snapshot = try #require(try manager.activeRootIssuerSnapshot())
        #expect(snapshot.certificate.subject == root.certificate.subject)
        #expect(snapshot.privateKey.publicKey.subjectPublicKeyInfoBytes == root.certificate.publicKey
            .subjectPublicKeyInfoBytes)
        #expect(snapshot.fingerprintSHA256 == metadata.fingerprintSHA256)
    }

    @Test("rejects custom roots that Apple clients would refuse: SHA-1 signatures and short RSA keys")
    func rejectsWeakCustomRoots() throws {
        let manager = makeManager()
        // Minted now, so both are inside their validity window: the import checks expiry before
        // signature strength, and an expired fixture would reach `.rootExpired` instead.
        let sha1Root = try TestCertificateFactory.rsaRoot(bits: 2_048, signatureDigest: "sha1")
        let shortKeyRoot = try TestCertificateFactory.rsaRoot(bits: 1_024, signatureDigest: "sha256")
        let sha1Certificate = try Certificate(pemEncoded: sha1Root.certificatePEM)
        #expect(sha1Certificate.signatureAlgorithm == .sha1WithRSAEncryption)
        #expect(sha1Certificate.notValidAfter > Date())

        #expect(throws: CustomCertificateError.rootWeakSignature) {
            try manager.importRoot(
                displayName: "SHA-1 Root",
                certificatePEM: sha1Root.certificatePEM,
                privateKeyPEM: sha1Root.privateKeyPEM
            )
        }
        #expect(throws: CustomCertificateError.rootWeakKey(bits: 1_024)) {
            try manager.importRoot(
                displayName: "Short Key Root",
                certificatePEM: shortKeyRoot.certificatePEM,
                privateKeyPEM: shortKeyRoot.privateKeyPEM
            )
        }
        #expect(manager.metadata(kind: .root).isEmpty)

        let shortKeyP12 = try TestCertificateFactory.pkcs12(shortKeyRoot, password: "rockxy")
        #expect(throws: CustomCertificateError.rootWeakKey(bits: 1_024)) {
            try CustomCertificateImportIdentity.fromPKCS12(
                data: shortKeyP12,
                displayName: "Short Key",
                passphrase: "rockxy"
            )
        }
    }

    @Test("a P12 opened with the wrong password reports the password, not a broken file")
    func wrongPKCS12PasswordIsReported() throws {
        let data = try TestCertificateFactory.pkcs12(
            TestCertificateFactory.rsaRoot(bits: 2_048, signatureDigest: "sha256", commonName: "Rockxy Test P12"),
            password: "rockxy"
        )

        #expect(throws: CustomCertificateImportError.incorrectPassword) {
            try CustomCertificateImportIdentity.fromPKCS12(data: data, displayName: "P12 Root", passphrase: "wrong")
        }
    }

    @Test("an unreadable custom root key is reported, not silently replaced, and the report clears")
    func unreadableCustomRootKeyIsSurfacedAndClears() async throws {
        let fixture = makeFixture()
        let root = try RootCAGenerator.generate()
        let entry = try fixture.manager.importRoot(
            displayName: "Custom Root",
            certificatePEM: pem(root.certificate),
            privateKeyPEM: root.privateKey.pemRepresentation
        )
        let keyData = try #require(fixture.store.data(account: entry.keychainAccount))

        // A fresh manager over the same storage has no memoized root, like a relaunch.
        try fixture.store.delete(account: entry.keychainAccount)
        let broken = CustomCertificateManager(storageURL: fixture.storageURL, secureStore: fixture.store)
        let certificates = CertificateManager(customCertificates: broken)
        let changes = NotificationCounter(name: .customRootFallbackDidChange, object: certificates.customRootFallback)
        defer { changes.stop() }

        #expect(await certificates.customRootFallbackReason == nil)
        let reason = try #require(await certificates.refreshCustomRootFallbackReason())
        #expect(reason.contains(CustomCertificateError.missingPrivateKey.localizedDescription))
        #expect(await certificates.customRootFallbackReason == reason)
        // Re-evaluating an unchanged failure is not a new event.
        #expect(await certificates.refreshCustomRootFallbackReason() == reason)
        #expect(changes.count == 1)

        // The key comes back: the report clears.
        try fixture.store.save(keyData, account: entry.keychainAccount)
        #expect(await certificates.refreshCustomRootFallbackReason() == nil)
        #expect(changes.count == 2)

        // Break it again, then remove the root: nothing is configured, so nothing to warn about.
        try fixture.store.delete(account: entry.keychainAccount)
        let brokenAgain = CustomCertificateManager(storageURL: fixture.storageURL, secureStore: fixture.store)
        let second = CertificateManager(customCertificates: brokenAgain)
        #expect(await second.refreshCustomRootFallbackReason() != nil)
        try brokenAgain.deleteAll(kind: .root)
        #expect(await second.refreshCustomRootFallbackReason() == nil)
    }

    @Test("a healthy or absent custom root reports no fallback")
    func healthyOrAbsentCustomRootReportsNoFallback() async throws {
        let absent = CertificateManager(customCertificates: makeManager())
        #expect(await absent.refreshCustomRootFallbackReason() == nil)

        let fixture = makeFixture()
        let root = try RootCAGenerator.generate()
        try fixture.manager.importRoot(
            displayName: "Custom Root",
            certificatePEM: pem(root.certificate),
            privateKeyPEM: root.privateKey.pemRepresentation
        )
        let healthy = CertificateManager(customCertificates: fixture.manager)
        #expect(await healthy.refreshCustomRootFallbackReason() == nil)
    }

    @Test("normalizes DER certificate imports into PEM identity material")
    func normalizesDERCertificateImports() throws {
        let root = try RootCAGenerator.generate()
        let certificateDER = try der(root.certificate)

        let identity = try CustomCertificateImportIdentity.fromCertificateAndPrivateKey(
            certificateData: certificateDER,
            privateKeyData: Data(root.privateKey.pemRepresentation.utf8),
            displayName: "DER Root"
        )

        let certificate = try Certificate(pemEncoded: identity.certificatePEM)
        let privateKey = try Certificate.PrivateKey(pemEncoded: identity.privateKeyPEM)
        #expect(identity.displayName == "DER Root")
        #expect(certificate.subject == root.certificate.subject)
        #expect(privateKey.publicKey.subjectPublicKeyInfoBytes == root.certificate.publicKey.subjectPublicKeyInfoBytes)
    }

    @Test("normalizes P12 imports into PEM identity material")
    func normalizesPKCS12Imports() throws {
        let data = try TestCertificateFactory.pkcs12(
            TestCertificateFactory.rsaRoot(bits: 2_048, signatureDigest: "sha256", commonName: "Rockxy Test P12"),
            password: "rockxy"
        )

        let identity = try CustomCertificateImportIdentity.fromPKCS12(
            data: data,
            displayName: "P12 Root",
            passphrase: "rockxy"
        )

        let certificate = try Certificate(pemEncoded: identity.certificatePEM)
        let privateKey = try Certificate.PrivateKey(pemEncoded: identity.privateKeyPEM)
        #expect(identity.displayName == "P12 Root")
        #expect(String(describing: certificate.subject).contains("Rockxy Test P12"))
        #expect(privateKey.publicKey.subjectPublicKeyInfoBytes == certificate.publicKey.subjectPublicKeyInfoBytes)
    }

    @Test("matches exact and wildcard server certificate hosts")
    func matchesServerHostPatterns() throws {
        let manager = makeManager()
        let identity = try makeLeafIdentity(host: "api.example.com")

        try manager.importServerIdentity(
            hostPattern: "*.example.com",
            displayName: "Pinned Server",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )

        #expect(manager.serverIdentity(for: "api.example.com") != nil)
        #expect(manager.serverIdentity(for: "example.com") == nil)
        #expect(manager.serverIdentity(for: "api.example.net") == nil)
    }

    @Test("matches client certificates only for configured hosts")
    func matchesClientHostPatterns() throws {
        let manager = makeManager()
        let identity = try makeLeafIdentity(host: "mtls.example.com")

        try manager.importClientIdentity(
            hostPattern: "mtls.example.com",
            displayName: "mTLS Client",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )

        #expect(manager.clientIdentity(for: "mtls.example.com") != nil)
        #expect(manager.clientIdentity(for: "www.example.com") == nil)
    }

    @Test("rejects invalid certificate key pairs")
    func rejectsInvalidCertificateKeyPairs() throws {
        let manager = makeManager()
        let first = try makeLeafIdentity(host: "one.example.com")
        let second = try makeLeafIdentity(host: "two.example.com")

        #expect(throws: CustomCertificateError.invalidCertificateKeyPair) {
            try manager.importServerIdentity(
                hostPattern: "one.example.com",
                displayName: "Invalid",
                certificatePEM: first.certificatePEM,
                privateKeyPEM: second.privateKeyPEM
            )
        }
    }

    @Test("delete and revert remove custom certificate behavior")
    func deleteAndRevert() throws {
        let manager = makeManager()
        let identity = try makeLeafIdentity(host: "delete.example.com")
        let entry = try manager.importServerIdentity(
            hostPattern: "delete.example.com",
            displayName: "Delete Me",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )

        #expect(manager.serverIdentity(for: "delete.example.com") != nil)
        try manager.delete(id: entry.id)
        #expect(manager.serverIdentity(for: "delete.example.com") == nil)
    }

    @Test("replacing an exact normalized host removes the superseded private key")
    func replacementRemovesSupersededPrivateKey() throws {
        let fixture = makeFixture()
        let firstIdentity = try makeLeafIdentity(host: "api.example.com")
        let secondIdentity = try makeLeafIdentity(host: "api.example.com")
        let firstEntry = try fixture.manager.importServerIdentity(
            hostPattern: " API.Example.com ",
            displayName: "First",
            certificatePEM: firstIdentity.certificatePEM,
            privateKeyPEM: firstIdentity.privateKeyPEM
        )

        let secondEntry = try fixture.manager.importServerIdentity(
            hostPattern: "api.example.com",
            displayName: "Second",
            certificatePEM: secondIdentity.certificatePEM,
            privateKeyPEM: secondIdentity.privateKeyPEM
        )

        #expect(fixture.manager.metadata(kind: .server) == [secondEntry])
        #expect(fixture.store.data(account: firstEntry.keychainAccount) == nil)
        #expect(fixture.store.data(account: secondEntry.keychainAccount) != nil)
    }

    @Test("replacement persistence failure preserves old metadata and removes the new private key")
    func replacementPersistenceFailureRollsBack() throws {
        let writer = FaultingMetadataWriter()
        let fixture = makeFixture(metadataWriter: writer)
        let firstIdentity = try makeLeafIdentity(host: "api.example.com")
        let secondIdentity = try makeLeafIdentity(host: "api.example.com")
        let firstEntry = try fixture.manager.importServerIdentity(
            hostPattern: "api.example.com",
            displayName: "First",
            certificatePEM: firstIdentity.certificatePEM,
            privateKeyPEM: firstIdentity.privateKeyPEM
        )
        let accountsBeforeReplacement = fixture.store.accounts()
        writer.failWrites()

        #expect(throws: TestStoreError.self) {
            try fixture.manager.importServerIdentity(
                hostPattern: "API.EXAMPLE.COM",
                displayName: "Second",
                certificatePEM: secondIdentity.certificatePEM,
                privateKeyPEM: secondIdentity.privateKeyPEM
            )
        }

        #expect(fixture.manager.metadata(kind: .server) == [firstEntry])
        #expect(fixture.store.accounts() == accountsBeforeReplacement)
        #expect(fixture.store.data(account: firstEntry.keychainAccount) != nil)
    }

    @Test("delete-all key failure restores prior keys, metadata, and persisted snapshot")
    func deleteAllFailureDoesNotPartiallyPublish() throws {
        let fixture = makeFixture()
        let firstIdentity = try makeLeafIdentity(host: "one.example.com")
        let secondIdentity = try makeLeafIdentity(host: "two.example.com")
        let firstEntry = try fixture.manager.importServerIdentity(
            hostPattern: "one.example.com",
            displayName: "One",
            certificatePEM: firstIdentity.certificatePEM,
            privateKeyPEM: firstIdentity.privateKeyPEM
        )
        let secondEntry = try fixture.manager.importServerIdentity(
            hostPattern: "two.example.com",
            displayName: "Two",
            certificatePEM: secondIdentity.certificatePEM,
            privateKeyPEM: secondIdentity.privateKeyPEM
        )
        fixture.store.failDelete(account: secondEntry.keychainAccount)

        #expect(throws: TestStoreError.self) {
            try fixture.manager.deleteAll(kind: .server)
        }

        #expect(fixture.manager.metadata(kind: .server) == [firstEntry, secondEntry])
        #expect(fixture.store.data(account: firstEntry.keychainAccount) != nil)
        #expect(fixture.store.data(account: secondEntry.keychainAccount) != nil)

        let reloaded = CustomCertificateManager(
            storageURL: fixture.storageURL,
            secureStore: fixture.store
        )
        #expect(reloaded.metadata(kind: .server) == [firstEntry, secondEntry])
    }

    @Test("rollback failure surfaces a non-sensitive recovery error")
    func rollbackFailureIsExplicit() throws {
        let writer = FaultingMetadataWriter()
        let fixture = makeFixture(metadataWriter: writer)
        let firstIdentity = try makeLeafIdentity(host: "one.example.com")
        let secondIdentity = try makeLeafIdentity(host: "two.example.com")
        let firstEntry = try fixture.manager.importServerIdentity(
            hostPattern: "one.example.com",
            displayName: "One",
            certificatePEM: firstIdentity.certificatePEM,
            privateKeyPEM: firstIdentity.privateKeyPEM
        )
        let secondEntry = try fixture.manager.importServerIdentity(
            hostPattern: "two.example.com",
            displayName: "Two",
            certificatePEM: secondIdentity.certificatePEM,
            privateKeyPEM: secondIdentity.privateKeyPEM
        )
        fixture.store.failDelete(account: secondEntry.keychainAccount)
        writer.failAfterSuccessfulWrites(1)

        #expect(throws: CustomCertificateTransactionError.self) {
            try fixture.manager.deleteAll(kind: .server)
        }

        #expect(fixture.manager.metadata(kind: .server) == [firstEntry, secondEntry])
        #expect(fixture.store.data(account: firstEntry.keychainAccount) != nil)
        #expect(fixture.store.data(account: secondEntry.keychainAccount) != nil)
    }

    @Test("deleting an unknown identifier performs no persistence or secure-store work")
    func deletingUnknownIdentifierIsNoOp() throws {
        let fixture = makeFixture()
        let identity = try makeLeafIdentity(host: "known.example.com")
        let entry = try fixture.manager.importServerIdentity(
            hostPattern: "known.example.com",
            displayName: "Known",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )
        let operationCounts = fixture.store.operationCounts()

        try fixture.manager.delete(id: UUID())

        #expect(fixture.manager.metadata(kind: .server) == [entry])
        let finalCounts = fixture.store.operationCounts()
        #expect(finalCounts.save == operationCounts.save)
        #expect(finalCounts.load == operationCounts.load)
        #expect(finalCounts.delete == operationCounts.delete)
    }

    @Test("deleting metadata retains a private key account still referenced by another entry")
    func deletionRetainsSharedAccount() throws {
        let fixture = makeFixture()
        let identity = try makeLeafIdentity(host: "shared.example.com")
        let imported = try fixture.manager.importServerIdentity(
            hostPattern: "shared.example.com",
            displayName: "Imported",
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )
        let retained = CustomCertificateMetadata(
            id: UUID(),
            kind: .client,
            displayName: "Shared Account",
            hostPattern: "shared.example.com",
            certificatePEM: imported.certificatePEM,
            keychainAccount: imported.keychainAccount,
            createdAt: imported.createdAt.addingTimeInterval(1),
            notValidBefore: imported.notValidBefore,
            notValidAfter: imported.notValidAfter,
            fingerprintSHA256: imported.fingerprintSHA256
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileCustomCertificateMetadataWriter().write(
            encoder.encode([imported, retained]),
            to: fixture.storageURL
        )
        let manager = CustomCertificateManager(
            storageURL: fixture.storageURL,
            secureStore: fixture.store
        )
        let deleteCount = fixture.store.operationCounts().delete

        try manager.delete(id: imported.id)

        #expect(manager.metadata() == [retained])
        #expect(fixture.store.data(account: retained.keychainAccount) != nil)
        #expect(fixture.store.operationCounts().delete == deleteCount)
    }

    // MARK: Private

    private func makeManager() -> CustomCertificateManager {
        makeFixture().manager
    }

    private func makeFixture(
        metadataWriter: any CustomCertificateMetadataWriter = FileCustomCertificateMetadataWriter()
    )
        -> (manager: CustomCertificateManager, store: MemorySecureDataStore, storageURL: URL)
    {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyCustomCertificateTests-\(UUID().uuidString)")
            .appendingPathComponent("custom.json")
        let store = MemorySecureDataStore()
        return (
            CustomCertificateManager(
                storageURL: url,
                secureStore: store,
                metadataWriter: metadataWriter
            ),
            store,
            url
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

    private func der(_ certificate: Certificate) throws -> Data {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }
}

// MARK: - NotificationCounter

/// Counts posts of one notification, so a test can tell "changed" from "re-checked".
private final class NotificationCounter: @unchecked Sendable {
    // MARK: Lifecycle

    init(name: Notification.Name, object: AnyObject) {
        token = NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
            guard let self else {
                return
            }
            lock.withLock { self.posts += 1 }
        }
    }

    // MARK: Internal

    var count: Int {
        lock.withLock { posts }
    }

    func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var token: NSObjectProtocol?
    private var posts = 0
}

// MARK: - TestCertificateFactory

/// Mints the certificates these suites need at the moment a test runs, so no fixture can expire
/// under the suite. A baked PEM carries a fixed notAfter; every one that was checked in eventually
/// turned into a failure with no code change behind it.
///
/// The product has no way to produce the identities the weak-root checks need (a SHA-1 signature,
/// a 1024-bit RSA key, an RSA PKCS#12), and `RootCAGenerator` only makes P-256 roots with a
/// key-derived subject. Rather than keep a second generator in product code for tests, this drives
/// the `openssl` tool that macOS ships. Each certificate is valid for ten years from now.
enum TestCertificateFactory {
    // MARK: Internal

    struct Identity {
        let certificatePEM: String
        let privateKeyPEM: String
    }

    /// A self-signed RSA CA. `signatureDigest` is an openssl digest name such as "sha1" or "sha256".
    static func rsaRoot(
        bits: Int,
        signatureDigest: String,
        commonName: String = "Weak Test Root"
    )
        throws -> Identity
    {
        try selfSignedRoot(
            keyArguments: ["-newkey", "rsa:\(bits)"],
            signatureDigest: signatureDigest,
            subject: "/CN=\(commonName)"
        )
    }

    /// A self-signed RSA-2048 CA with an exact subject, for fixtures whose subject hash is asserted.
    /// RSA rather than EC on purpose: LibreSSL writes EC keys with explicit curve parameters, which
    /// swift-certificates cannot parse (it accepts named curves only).
    static func root(subject: String) throws -> Identity {
        try selfSignedRoot(keyArguments: ["-newkey", "rsa:2048"], signatureDigest: "sha256", subject: subject)
    }

    /// The identity as a PKCS#12 file protected by `password`.
    static func pkcs12(_ identity: Identity, password: String) throws -> Data {
        try withScratchDirectory { directory in
            let certificate = directory.appendingPathComponent("cert.pem")
            let key = directory.appendingPathComponent("key.pem")
            let output = directory.appendingPathComponent("identity.p12")
            try identity.certificatePEM.write(to: certificate, atomically: true, encoding: .utf8)
            try identity.privateKeyPEM.write(to: key, atomically: true, encoding: .utf8)
            try runOpenSSL([
                "pkcs12", "-export", "-inkey", key.path, "-in", certificate.path,
                "-passout", "env:ROCKXY_TEST_P12_PASSWORD", "-out", output.path,
            ], environment: ["ROCKXY_TEST_P12_PASSWORD": password])
            return try Data(contentsOf: output)
        }
    }

    // MARK: Private

    private struct OpenSSLError: Error, CustomStringConvertible {
        let description: String
    }

    private static func selfSignedRoot(
        keyArguments: [String],
        signatureDigest: String,
        subject: String
    )
        throws -> Identity
    {
        try withScratchDirectory { directory in
            let certificate = directory.appendingPathComponent("cert.pem")
            let key = directory.appendingPathComponent("key.pem")
            try runOpenSSL(
                ["req", "-x509", "-nodes", "-\(signatureDigest)"] + keyArguments + [
                    "-keyout", key.path, "-out", certificate.path, "-days", "3650", "-subj", subject,
                    "-addext", "basicConstraints=critical,CA:TRUE",
                    "-addext", "keyUsage=critical,keyCertSign,cRLSign",
                    "-addext", "subjectKeyIdentifier=hash",
                ]
            )
            return try Identity(
                certificatePEM: String(contentsOf: certificate, encoding: .utf8),
                privateKeyPEM: String(contentsOf: key, encoding: .utf8)
            )
        }
    }

    private static func withScratchDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTestCertificates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }

    private static func runOpenSSL(_ arguments: [String], environment: [String: String] = [:]) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        // Secrets go in the environment of this one process, never in argv where `ps` shows them.
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OpenSSLError(description: "openssl \(arguments.first ?? "") failed: "
                + (String(data: stderr, encoding: .utf8) ?? ""))
        }
    }
}
