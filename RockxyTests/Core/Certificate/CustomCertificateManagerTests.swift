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

    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var failingDeleteAccounts = Set<String>()
    private var saveCount = 0
    private var loadCount = 0
    private var deleteCount = 0
}

// MARK: - FaultingMetadataWriter

private final class FaultingMetadataWriter: CustomCertificateMetadataWriter, @unchecked Sendable {
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

    private let lock = NSLock()
    private let base = FileCustomCertificateMetadataWriter()
    private var shouldFail = false
    private var writeCount = 0
    private var failingWriteNumber: Int?
}

// MARK: - CustomCertificateManagerTests

struct CustomCertificateManagerTests {
    @Test("imports custom root certificate and exposes it as active issuer")
    func importsCustomRootIssuer() throws {
        let manager = makeManager()
        let root = try RootCAGenerator.generate()

        let metadata = try manager.importRoot(
            displayName: "Custom Root",
            certificatePEM: try pem(root.certificate),
            privateKeyPEM: root.privateKey.pemRepresentation
        )

        let issuer = try #require(try manager.activeRootIssuer())
        #expect(issuer.certificate.subject == root.certificate.subject)
        #expect(issuer.privateKey.publicKey.subjectPublicKeyInfoBytes == root.certificate.publicKey.subjectPublicKeyInfoBytes)

        let snapshot = try #require(try manager.activeRootIssuerSnapshot())
        #expect(snapshot.certificate.subject == root.certificate.subject)
        #expect(snapshot.privateKey.publicKey.subjectPublicKeyInfoBytes == root.certificate.publicKey.subjectPublicKeyInfoBytes)
        #expect(snapshot.fingerprintSHA256 == metadata.fingerprintSHA256)
    }

    @Test("rejects custom roots that Apple clients would refuse: SHA-1 signatures and short RSA keys")
    func rejectsWeakCustomRoots() throws {
        let manager = makeManager()

        #expect(throws: CustomCertificateError.rootWeakSignature) {
            try manager.importRoot(
                displayName: "SHA-1 Root",
                certificatePEM: Self.sha1RootPEM,
                privateKeyPEM: Self.sha1RootKeyPEM
            )
        }
        #expect(throws: CustomCertificateError.rootWeakKey(bits: 1_024)) {
            try manager.importRoot(
                displayName: "Short Key Root",
                certificatePEM: Self.rsa1024RootPEM,
                privateKeyPEM: Self.rsa1024RootKeyPEM
            )
        }
        #expect(manager.metadata(kind: .root).isEmpty)

        let shortKeyP12 = try #require(Data(base64Encoded: Self.rsa1024PKCS12Base64, options: .ignoreUnknownCharacters))
        #expect(throws: CustomCertificateError.rootWeakKey(bits: 1_024)) {
            try CustomCertificateImportIdentity.fromPKCS12(data: shortKeyP12, displayName: "Short Key", passphrase: "rockxy")
        }
    }

    @Test("a P12 opened with the wrong password reports the password, not a broken file")
    func wrongPKCS12PasswordIsReported() throws {
        let data = try #require(Data(base64Encoded: Self.pkcs12FixtureBase64, options: .ignoreUnknownCharacters))

        #expect(throws: CustomCertificateImportError.incorrectPassword) {
            try CustomCertificateImportIdentity.fromPKCS12(data: data, displayName: "P12 Root", passphrase: "wrong")
        }
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
        let data = try #require(Data(base64Encoded: Self.pkcs12FixtureBase64, options: .ignoreUnknownCharacters))

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

    private func makeManager() -> CustomCertificateManager {
        makeFixture().manager
    }

    private func makeFixture(
        metadataWriter: any CustomCertificateMetadataWriter = FileCustomCertificateMetadataWriter()
    ) -> (manager: CustomCertificateManager, store: MemorySecureDataStore, storageURL: URL) {
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
        return (try pem(leaf.certificate), leaf.privateKey.pemRepresentation)
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

    /// Throwaway CA certificates made with openssl for the weak-root checks.
    private static let sha1RootPEM = """
    -----BEGIN CERTIFICATE-----
    MIIDAjCCAeqgAwIBAgIUGE0sM7GdiFmdHaMNDpIsM6mahvEwDQYJKoZIhvcNAQEF
    BQAwGTEXMBUGA1UEAwwOV2VhayBUZXN0IFJvb3QwHhcNMjYxMDAyMDMwMTAxWhcN
    MjYxMTAxMDMwMTAxWjAZMRcwFQYDVQQDDA5XZWFrIFRlc3QgUm9vdDCCASIwDQYJ
    KoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ6vPe2zbKmHqNCi2rThctt8ItsbBBXY
    95tsHSJrlbXqcNw4gHjskVYCGFHfcXzXwdnPvdK1fj2PGteA62JvPQJ2koyGYAUP
    hcDCzCNN0q2AvZ9duEIIm3cg98pzrBSmTKJ9C7U48I4cTesXTcZ22ZNeP0qOyBZH
    pKkvob5ehX/JbiKHn07mNnqeBig69S5tdZYNPGT9F0AaIyMtLij/iYztwqA+na/2
    dcKtPxv9HInfBaRGdyA1UOnj/b9ojHidDEpwhEh3+Z7+Rhf5sqDQ8EAC+4SUFlyu
    cSGoCK/yjxMZ/YYK+WyUBzr7ZwmyVqeXOFml8lDzVvZGSdES5KZhBBUCAwEAAaNC
    MEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFBJ6
    CA6Q5Fori2V+F9dtKPB3VQg4MA0GCSqGSIb3DQEBBQUAA4IBAQA7/imucZ2cdm91
    vrLFznzffojEU/vN1OOeUu4LdknBP/EDIIMloyK8hAmByoR3dFf5rR/Cazgpo+2W
    2Meoc2T+9oA/PHUnJ1p44V63ypEeJLaZ8BGkE8eWD98nWBah+nT9bS9wcFKDNIxa
    GgMQke8LfnquYyJ77NhFuh8xgxiGoMPv4S7eAjFck237kgRNXSV+7YyYLAhzxQGu
    XoA6X8AJW85QB36tczR3Rym3+68inBgUBm44NRNPWLKD+ftxXb450J+faTJqn474
    lT3T3b/god9E9Tc3UltUKM5SFj1gAfJQyMis8rykXug+VNl0H5/sc8uZ6knOXu/B
    DwzIGZAB
    -----END CERTIFICATE-----
    """

    private static let sha1RootKeyPEM = """
    -----BEGIN PRIVATE KEY-----
    MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCerz3ts2yph6jQ
    otq04XLbfCLbGwQV2PebbB0ia5W16nDcOIB47JFWAhhR33F818HZz73StX49jxrX
    gOtibz0CdpKMhmAFD4XAwswjTdKtgL2fXbhCCJt3IPfKc6wUpkyifQu1OPCOHE3r
    F03GdtmTXj9KjsgWR6SpL6G+XoV/yW4ih59O5jZ6ngYoOvUubXWWDTxk/RdAGiMj
    LS4o/4mM7cKgPp2v9nXCrT8b/RyJ3wWkRncgNVDp4/2/aIx4nQxKcIRId/me/kYX
    +bKg0PBAAvuElBZcrnEhqAiv8o8TGf2GCvlslAc6+2cJslanlzhZpfJQ81b2RknR
    EuSmYQQVAgMBAAECggEAA5uUWt0jcU9GRUgOlOIzTE4sNLMOirieGIiCuQ+dHb+w
    xTD7qsQmIcB2cRYVbHMzUxJoDGxX7Gpef9vMfjZtOqsbddpwQG0z60gCgCL60TsG
    FKN61vV/I1w6hf3PQcDuKRuSspIS1ghKtTeYaxS0qacQ5U8NuYPzeG0+zicz/c27
    X1IzQVpD9Qroge+dabf5wBD8kAZ97MoQeoSg/rlsZArdt5bXcS0aYyh9Bo3wEh67
    f1+HE2eOvA0oyfh7GZQXDDAxgoCVe2OSzcB93DPDs3IQTT60WcFU1mbwKnALIC+H
    h/Rwddrtb2BI2kOl7VZp6fnuPW/lXOO+UjRkS3pWQQKBgQDex/yFVqiJPdtv8uVr
    NMj8PiuT9ZNQHrVcX7So0+1W4Arrlo7NCgANkiQmn/IDgyCh61wTSSaddbQ+1xfP
    7ecEUjCvTIv/1uMwaLgD7czIa4dhmo6qIy4T2A2r2xtE7RNoJeZM+i0CLHmQTnr7
    n0RFnnlb5U/jmukJ5wR4103CfQKBgQC2WI4YVBInr7m61ME0hvogrlkhj4hectWc
    ZdCSgEu8N36LBMexCCU3Aab1mW30P6W23HnyoKfu99AS5rkDqW7LGbYXLxsOD2X2
    L+SgfdGo0yYVDOXg+lRHV2LxCmkPsWywRFCWD4s45Eoh5AV/SY3WJLGIcMT9A+TF
    78aEkn0jeQKBgHPzZq0Ho4R624FyzJF10b3npcrGoDutH/vKHD9avkbfKQ/hNsXl
    FI37qDEqQk4tq4ha9XtcMWr23i9uyAgC7KBFHu2+S4eHEowZlN0GofUWckoMpYBL
    +yl84/C0g4bmVZl5UFp0Q4TEHSlMj5nzFRefGc8IlQIDmJL82EkE1oYJAoGAbHdw
    zvfzdLgK+x/jbaN81kPfsR74N3aHqmjGEN9QLb21AGzvfFckC/xnnGCQD2Js6MFt
    qO339yZiF1w3Yf4/cYDx2AilR0/RjwgeL3moZYx0csEhXRqLV4SbzlYq+LLJvHBm
    n1zPrB/gGRjSTE0smd1p3Yd3JipSw4tFw0aAOcECgYEAjbX+EJZQo3rAcIrrim8o
    N1mG/S46LBn7QpqTUaL5Xt9eHhuywCvR18dYTVmvCj20alJwrIZA6Y/B8J8eG362
    ELW3m3BK83jzhYOmFmMTMKEi93DGPtvrsGN7vgV/NMaFGzdW9GCdc2vts+Z0cfLs
    mPRBLGzrQQQY4/t3LXPYPBA=
    -----END PRIVATE KEY-----
    """

    private static let rsa1024RootPEM = """
    -----BEGIN CERTIFICATE-----
    MIIB/TCCAWagAwIBAgIUMjG3s2zMQhmhzKKSOC3gusm2fmYwDQYJKoZIhvcNAQEL
    BQAwGTEXMBUGA1UEAwwOV2VhayBUZXN0IFJvb3QwHhcNMjYxMDAyMDMwMTAxWhcN
    MjYxMTAxMDMwMTAxWjAZMRcwFQYDVQQDDA5XZWFrIFRlc3QgUm9vdDCBnzANBgkq
    hkiG9w0BAQEFAAOBjQAwgYkCgYEA3liY+CWKpwyL2RggdU6qCPvEJw4NM8KnxfFB
    e0oa0sAhsmp8Oq+DL0mEJyKIO194UmLq0pcvw2yZFms2RSi7avw3wScAerqyir8l
    msxCUkExLwTVaffGKU+AeIEwIW/Nx12t60uix/hUQHrqz1RFWZ+VMmXKPVFjr5+H
    /ifopLsCAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYw
    HQYDVR0OBBYEFBPgIVF5J+8ABZAr24b+xBMvPfVYMA0GCSqGSIb3DQEBCwUAA4GB
    ALjxDoarC4NaxuGON80RbPXRgv2DE165hcZVUCHzXP+gP3xXIdVC3grQCJ3FbXr0
    iVcYrvGqj8u03328z5Vp6cuNRRjEzM1TtUyHCDGDU1UvNjLwkADn9G+xumra+9xH
    AZTodgTa7qg3EUtKORIBii9mv+Jxdc3LBgcodF3xvpSk
    -----END CERTIFICATE-----
    """

    private static let rsa1024RootKeyPEM = """
    -----BEGIN PRIVATE KEY-----
    MIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGBAN5YmPgliqcMi9kY
    IHVOqgj7xCcODTPCp8XxQXtKGtLAIbJqfDqvgy9JhCciiDtfeFJi6tKXL8NsmRZr
    NkUou2r8N8EnAHq6soq/JZrMQlJBMS8E1Wn3xilPgHiBMCFvzcddretLosf4VEB6
    6s9URVmflTJlyj1RY6+fh/4n6KS7AgMBAAECgYEAo0zExHOmGrxfNcm/hQiKX2Cx
    ltF+JsbPO9TN+APcIW8VEJmetedT3PYMhkWZcqnSkAewWYzKeqgW411IlZCt3C39
    1wOwBP/mA2UFtYxeBzomRhbkJ5uO9mos6TNPnHCvueeypQAan83Ji5t1IeWRnIws
    Qs+w+5ZLd5WTMBr6cqECQQDwTFkMC+GYz/zOs8Aeg52L1PaxHU9Ssz1HFLjmSUOv
    OkIV1fZ2piMkiiRHLUYC8uqJ23kcEQF43tslktGXxtLLAkEA7N/zS6RHRNrMYnrv
    cokHB1q4Cqamr1tnaxRBa5KYKYLi4ALSD3IRfUZ9H3TmAEkA4R7Jr3rknS8vbfMU
    ixkH0QJAXU7IJQ1YBGZ+3CSgLTkeK/X99LhU3OAMo1VAlutMBPayQphao6fPbZjW
    jWzfCrYYrH80f9l6oNyoa+aezDjAEQJBAKQDRPDBJN/WJ+KggJ9rpcQ/2mL1lUCi
    J2+LLOkRLe7AQ9sb2Nr8/oMhhY18Ya0c31EBAmFQ1G7JtyuIPlc506ECPxWdHLHD
    14MtHbhbXJX7DDU25efaPsaSrJ8ztDsyS+iiMijqh3bectmxIPbJUKSygBIniqN8
    AyaFAw8Cz8La3A==
    -----END PRIVATE KEY-----
    """

    /// The 1024-bit root above with its key, as a P12 protected by "rockxy".
    private static let rsa1024PKCS12Base64 = """
    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
    """

    private static let pkcs12FixtureBase64 = """
    MIIEVAIBAzCCBAIGCSqGSIb3DQEHAaCCA/MEggPvMIID6zCCApoGCSqGSIb3DQEHBqCCAoswggKHAgEAMIICgAYJKoZIhvcNAQcB
    MF8GCSqGSIb3DQEFDTBSMDEGCSqGSIb3DQEFDDAkBBAxNpLso9in7R8sCZHKAQ/xAgIIADAMBggqhkiG9w0CCQUAMB0GCWCGSAFl
    AwQBKgQQtIhtwh53A4jQwcbZNZ/0OYCCAhC8RRu7BAQmpemAYSUHfARZl7twbOUeL6EPletqYeFjUeZWHl5QgNrL37lYG0PJMZ85
    nivPXKtk2vduLcZN3yogsy8U5o7qbXH3dEFbclPBWkf6xGiVhmGWw2M6auOWvMDeoqLZORQBTQpuniDpNqZw0G3Htr8rQwHeHvOH
    SFu/FqKi8VZMPaiRJ1KCrHSpQ4z/Qjver5Vs83lawuTZpXO3QYEJattVmvpy1ekEcGA/TH0+q6qnMWpdZXAAKFW6McmsBvMOiXZ3I
    gcNmnrhsqGBmYRa3tozFmZw4JLrq12KaQMQBL0mwMDaezbIbIRFmYuuCdxtEtPHi6tIZTuOtP3GB26L3693YE1uyOv1cmPEHNTD+
    3+TmgNDhpqf9+gGLLk5SD0D5lDGs9tYPonxGaKvWCL9vjr8ALfFYFN2bjXPmz87gKsxK8JVz1JxYRKqHfPyCn9rc71ClJbpyqfUa
    W7eWT67tkf3EIEl5aTAxm4UC8iNMhJbp2LboZ3zlzDNUEGTLmhMj/lOgSpePYBi2A28sZOzh1Uyu7PwPd51+2mnElQpRMgDmkr54
    rfvHWi/ZAA6/fiTaHl8ap4GFE0dXYoKFg75g54a7KhoENbCygMhBHGHC2SfdNeGyIqCvh//H7UrYN9uV+kDJkdYX6CAtvdmAAYDs
    fzhS6w+X2geQ0a7tCPp1Wey/X6iwTIa/Q2Gxv4wggFJBgkqhkiG9w0BBwGgggE6BIIBNjCCATIwggEuBgsqhkiG9w0BDAoBAqCB
    9zCB9DBfBgkqhkiG9w0BBQ0wUjAxBgkqhkiG9w0BBQwwJAQQBl3K6hD6S8KYv0PTRbAQSgICCAAwDAYIKoZIhvcNAgkFADAdBglg
    hkgBZQMEASoEEBP5A+ukk/fjo0zTeE+6KGQEgZDMc5QbtzBFYUW+GBr7rsmOnFFetxPwgHKrhF4sA1+2yTS5Et7geiUS0bRjmD0K
    918wZ2SnzLV+vvzv6HNJ0S4k8CW1C0lvdt8ZYcoqTkaqX8reOFS43JI/e1uDf+xe2ViAR88gj01iKaZ74pwhUufeYR9vo+SVCHP
    FhO1DNJ8eH+6lFnGEq+F37180LrCYDEoxJTAjBgkqhkiG9w0BCRUxFgQU9+YayiugoLHt103H3Ff2GbmU5/wwSTAxMA0GCWCGSAFl
    AwQCAQUABCCJFNm8nMsKzM5csV9O+pPY5WIF5jdz97gF+KzNWYDYPAQQqJeQHo2mDjCsjalH8p7WxwICCAA=
    """
}
