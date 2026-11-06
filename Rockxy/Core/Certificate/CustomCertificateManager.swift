import Crypto
import Foundation
import NIOSSL
import Security
import SwiftASN1
import X509

// MARK: - CustomCertificateKind

enum CustomCertificateKind: String, Codable, CaseIterable, Equatable {
    case root
    case server
    case client
}

// MARK: - CustomCertificateMetadata

struct CustomCertificateMetadata: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: CustomCertificateKind
    var displayName: String
    var hostPattern: String?
    var certificatePEM: String
    var keychainAccount: String
    var createdAt: Date
    var notValidBefore: Date?
    var notValidAfter: Date?
    var fingerprintSHA256: String?
}

// MARK: - CustomTLSIdentity

struct CustomTLSIdentity: Sendable {
    let certificateChainPEM: [String]
    let privateKeyPEM: String

    var certificateSources: [NIOSSLCertificateSource] {
        get throws {
            try certificateChainPEM.map { pem in
                try .certificate(NIOSSLCertificate(bytes: Array(pem.utf8), format: .pem))
            }
        }
    }

    var privateKeySource: NIOSSLPrivateKeySource {
        get throws {
            try .privateKey(NIOSSLPrivateKey(bytes: Array(privateKeyPEM.utf8), format: .pem))
        }
    }
}

// MARK: - CustomCertificateImportIdentity

struct CustomCertificateImportIdentity: Equatable {
    // MARK: Internal

    let displayName: String
    let certificatePEM: String
    let privateKeyPEM: String

    static func fromCertificateAndPrivateKey(
        certificateData: Data,
        privateKeyData: Data,
        displayName: String
    )
        throws -> Self
    {
        let certificate = try certificatePEM(from: certificateData)
        let privateKeyPEM = try privateKeyPEM(from: privateKeyData)
        return Self(displayName: displayName, certificatePEM: certificate, privateKeyPEM: privateKeyPEM)
    }

    static func fromPKCS12(data: Data, displayName: String, passphrase: String) throws -> Self {
        do {
            return try fromNIOSSLPKCS12(data: data, displayName: displayName, passphrase: passphrase)
        } catch let error as CustomCertificateImportError {
            throw error
        } catch {
            return try fromSecurityPKCS12(data: data, displayName: displayName, passphrase: passphrase)
        }
    }

    // MARK: Private

    private static func fromNIOSSLPKCS12(data: Data, displayName: String, passphrase: String) throws -> Self {
        let bundle = try pkcs12Bundle(data: data, passphrase: passphrase)
        guard let leafCertificate = bundle.certificateChain.first else {
            throw CustomCertificateImportError.missingCertificate
        }

        let certificateDER = try leafCertificate.toDERBytes()
        let certificate = try Certificate(derEncoded: certificateDER)

        return try Self(
            displayName: displayName,
            certificatePEM: pem(certificate),
            privateKeyPEM: privateKeyPEM(from: Data(bundle.privateKey.derBytes))
        )
    }

    private static func fromSecurityPKCS12(data: Data, displayName: String, passphrase: String) throws -> Self {
        // Everything that needs the Security.framework key runs inside the closure: the identity
        // is only valid until the import scope ends (a temporary keychain is destroyed there).
        try withSecurityIdentity(data: data, passphrase: passphrase) { secCertificate, secKey in
            // Report a short RSA key plainly; the X509 parser below would reject it with a
            // low-level size error.
            if let key = SecCertificateCopyKey(secCertificate),
               let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
               (attributes[kSecAttrKeyType] as? String) == (kSecAttrKeyTypeRSA as String),
               let bits = attributes[kSecAttrKeySizeInBits] as? Int, bits < 2_048
            {
                throw CustomCertificateError.rootWeakKey(bits: bits)
            }
            let certificate = try certificate(from: secCertificate)
            let privateKey: Certificate.PrivateKey
            do {
                privateKey = try Certificate.PrivateKey(secKey)
            } catch {
                throw CustomCertificateImportError.invalidPrivateKey
            }

            return try Self(
                displayName: displayName,
                certificatePEM: pem(certificate),
                privateKeyPEM: privateKey.serializeAsPEM().pemString
            )
        }
    }

    private static func pkcs12Bundle(data: Data, passphrase: String) throws -> NIOSSLPKCS12Bundle {
        let bytes = Array(data)
        if passphrase.isEmpty {
            do {
                return try NIOSSLPKCS12Bundle(buffer: bytes)
            } catch {
                return try NIOSSLPKCS12Bundle(buffer: bytes, passphrase: [UInt8]())
            }
        }
        return try NIOSSLPKCS12Bundle(buffer: bytes, passphrase: Array(passphrase.utf8))
    }

    /// Unwraps a PKCS#12 identity for `body` without leaving anything behind in the user's keychains.
    ///
    /// `SecPKCS12Import` with no destination writes the unwrapped identity into the DEFAULT
    /// keychain (measured: two items in `login.keychain-db` per import), a copy the user never
    /// asked for and Rockxy's own delete path would never remove. Rockxy stores the key itself, so
    /// the Security import must stay private to this call.
    /// - macOS 15 and later: `kSecImportToMemoryOnly`, no keychain involved at all. Measured to
    ///   yield an exportable key for both legacy (3DES/RC2) and AES-encrypted files.
    /// - macOS 14: an owned temporary keychain, deleted unconditionally when `body` returns or
    ///   throws. `SecItemImport` is tried first because it marks the key extractable; a plain
    ///   `SecPKCS12Import` into a keychain yields a key that cannot be exported (measured), so
    ///   files only that path can read fail as `invalidPrivateKey` on macOS 14 instead of leaking.
    ///   Not measured on macOS 14 itself.
    private static func withSecurityIdentity<T>(
        data: Data,
        passphrase: String,
        _ body: (SecCertificate, SecKey) throws -> T
    )
        throws -> T
    {
        if #available(macOS 15.0, *) {
            let identity = try pkcs12Identity(
                data: data,
                passphrase: passphrase,
                options: [kSecImportToMemoryOnly as String: true]
            )
            return try body(identity.certificate, identity.privateKey)
        }
        return try withTemporaryKeychain { keychain in
            if let identity = try itemImportIdentity(data: data, passphrase: passphrase, keychain: keychain) {
                return try body(identity.certificate, identity.privateKey)
            }
            let identity = try pkcs12Identity(
                data: data,
                passphrase: passphrase,
                options: [kSecImportExportKeychain as String: keychain]
            )
            return try body(identity.certificate, identity.privateKey)
        }
    }

    /// Creates a private keychain, runs `body`, and always deletes the keychain and its folder.
    private static func withTemporaryKeychain<T>(_ body: (SecKeychain) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyP12Import-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw CustomCertificateImportError.keychainUnavailable
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        var password = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, password.count, &password) == errSecSuccess else {
            throw CustomCertificateImportError.keychainUnavailable
        }
        var created: SecKeychain?
        let path = directory.appendingPathComponent("import.keychain").path
        guard SecKeychainCreate(path, UInt32(password.count), password, false, nil, &created) == errSecSuccess,
              let keychain = created else
        {
            throw CustomCertificateImportError.keychainUnavailable
        }
        defer { SecKeychainDelete(keychain) }
        return try body(keychain)
    }

    /// `SecItemImport` into `keychain`, or `nil` when it could not produce an identity (it fails
    /// outright for some encryptions, which `SecPKCS12Import` can read).
    private static func itemImportIdentity(
        data: Data,
        passphrase: String,
        keychain: SecKeychain
    )
        throws -> (certificate: SecCertificate, privateKey: SecKey)?
    {
        var format = SecExternalFormat.formatPKCS12
        var itemType = SecExternalItemType.itemTypeAggregate
        let importPassphrase = passphrase as NSString
        let keyAttributes = [kSecAttrIsExtractable] as NSArray
        var keyParams = SecItemImportExportKeyParameters()
        keyParams.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        keyParams.passphrase = Unmanaged.passUnretained(importPassphrase)
        keyParams.keyAttributes = Unmanaged.passUnretained(keyAttributes)
        var importedItems: CFArray?
        let status = SecItemImport(
            data as CFData,
            "p12" as CFString,
            &format,
            &itemType,
            SecItemImportExportFlags(),
            &keyParams,
            keychain,
            &importedItems
        )
        guard status == errSecSuccess, let importedItems else {
            return nil
        }
        do {
            return try identity(from: importedItems)
        } catch CustomCertificateImportError.invalidPKCS12, CustomCertificateImportError.missingCertificate {
            return nil
        }
    }

    private static func pkcs12Identity(
        data: Data,
        passphrase: String,
        options extraOptions: [String: Any]
    )
        throws -> (certificate: SecCertificate, privateKey: SecKey)
    {
        var importedItems: CFArray?
        var options = extraOptions
        options[kSecImportExportPassphrase as String] = passphrase
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &importedItems)
        guard status == errSecSuccess, let importedItems else {
            throw importError(forSecurityStatus: status)
        }
        return try identity(from: importedItems)
    }

    /// Measured on macOS: a wrong password and a tampered file give the same statuses
    /// (`errSecAuthFailed` from `SecPKCS12Import`, `errSecPkcs12VerifyFailure` from `SecItemImport`),
    /// so they cannot be told apart and `incorrectPassword` words both. A
    /// truncated or non-PKCS#12 file is `errSecDecode` / `errSecUnknownFormat`.
    private static func importError(forSecurityStatus status: OSStatus) -> CustomCertificateImportError {
        switch status {
        case errSecAuthFailed,
             errSecPkcs12VerifyFailure:
            .incorrectPassword
        case errSecInteractionNotAllowed,
             errSecDuplicateItem,
             errSecNoDefaultKeychain:
            .keychainUnavailable
        default:
            .invalidPKCS12
        }
    }

    private static func identity(from importedItems: CFArray) throws
        -> (certificate: SecCertificate, privateKey: SecKey)
    {
        let items = importedItems as NSArray
        let rawIdentity = items.compactMap { item -> Any? in
            if CFGetTypeID(item as AnyObject) == SecIdentityGetTypeID() {
                return item
            }
            return (item as? [String: Any])?[kSecImportItemIdentity as String]
        }.first
        guard let rawIdentity else {
            throw CustomCertificateImportError.invalidPKCS12
        }

        let identityObject = rawIdentity as AnyObject
        guard CFGetTypeID(identityObject) == SecIdentityGetTypeID() else {
            throw CustomCertificateImportError.invalidPKCS12
        }
        let identity = unsafeBitCast(identityObject, to: SecIdentity.self)

        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
              let certificate else
        {
            throw CustomCertificateImportError.missingCertificate
        }

        var privateKey: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess,
              let privateKey else
        {
            throw CustomCertificateImportError.invalidPrivateKey
        }

        return (certificate, privateKey)
    }

    private static func certificate(from secCertificate: SecCertificate) throws -> Certificate {
        try Certificate(derEncoded: Array(SecCertificateCopyData(secCertificate) as Data))
    }

    private static func certificatePEM(from data: Data) throws -> String {
        if let pemString = String(data: data, encoding: .utf8),
           let certificate = try? Certificate(pemEncoded: pemString)
        {
            return try pem(certificate)
        }

        do {
            let certificate = try Certificate(derEncoded: Array(data))
            return try pem(certificate)
        } catch {
            throw CustomCertificateImportError.invalidCertificate
        }
    }

    private static func privateKeyPEM(from data: Data) throws -> String {
        if let pemString = String(data: data, encoding: .utf8),
           let privateKey = try? Certificate.PrivateKey(pemEncoded: pemString)
        {
            return try privateKey.serializeAsPEM().pemString
        }

        for discriminator in ["PRIVATE KEY", "EC PRIVATE KEY", "RSA PRIVATE KEY"] {
            let pemDocument = PEMDocument(type: discriminator, derBytes: Array(data))
            if let privateKey = try? Certificate.PrivateKey(pemDocument: pemDocument) {
                return try privateKey.serializeAsPEM().pemString
            }
        }
        throw CustomCertificateImportError.invalidPrivateKey
    }

    private static func pem(_ certificate: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
    }
}

// MARK: - SecureDataStore

protocol SecureDataStore: Sendable {
    func save(_ data: Data, account: String) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
}

// MARK: - KeychainSecureDataStore

struct KeychainSecureDataStore: SecureDataStore {
    // MARK: Internal

    func save(_ data: Data, account: String) throws {
        try KeychainHelper.saveSecureData(data, service: service, account: account)
    }

    func load(account: String) throws -> Data? {
        try KeychainHelper.loadSecureData(service: service, account: account)
    }

    func delete(account: String) throws {
        try KeychainHelper.deleteSecureData(service: service, account: account)
    }

    // MARK: Private

    private let service = RockxyIdentity.current.defaultsKey("CustomCertificates")
}

// MARK: - CustomCertificateMetadataWriter

protocol CustomCertificateMetadataWriter: Sendable {
    func write(_ data: Data, to url: URL) throws
}

// MARK: - FileCustomCertificateMetadataWriter

struct FileCustomCertificateMetadataWriter: CustomCertificateMetadataWriter {
    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - CustomCertificateManager

final class CustomCertificateManager: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        storageURL: URL = RockxyIdentity.current.sharedSupportDirectory()
            .appendingPathComponent("Certificates", isDirectory: true)
            .appendingPathComponent("custom-certificates.json"),
        secureStore: any SecureDataStore = KeychainSecureDataStore(),
        metadataWriter: any CustomCertificateMetadataWriter = FileCustomCertificateMetadataWriter()
    ) {
        self.storageURL = storageURL
        self.secureStore = secureStore
        self.metadataWriter = metadataWriter
        loadFromDisk()
    }

    // MARK: Internal

    static let shared = CustomCertificateManager()

    func metadata(kind: CustomCertificateKind? = nil) -> [CustomCertificateMetadata] {
        transactionLock.withLock {
            lock.withLock {
                entries
                    .filter { kind == nil || $0.kind == kind }
                    .sorted { $0.createdAt < $1.createdAt }
            }
        }
    }

    @discardableResult
    func importRoot(
        displayName: String,
        certificatePEM: String,
        privateKeyPEM: String
    )
        throws -> CustomCertificateMetadata
    {
        try importIdentity(
            kind: .root,
            hostPattern: nil,
            displayName: displayName,
            certificatePEM: certificatePEM,
            privateKeyPEM: privateKeyPEM
        )
    }

    @discardableResult
    func importServerIdentity(
        hostPattern: String,
        displayName: String,
        certificatePEM: String,
        privateKeyPEM: String
    )
        throws -> CustomCertificateMetadata
    {
        try importIdentity(
            kind: .server,
            hostPattern: hostPattern,
            displayName: displayName,
            certificatePEM: certificatePEM,
            privateKeyPEM: privateKeyPEM
        )
    }

    @discardableResult
    func importClientIdentity(
        hostPattern: String,
        displayName: String,
        certificatePEM: String,
        privateKeyPEM: String
    )
        throws -> CustomCertificateMetadata
    {
        try importIdentity(
            kind: .client,
            hostPattern: hostPattern,
            displayName: displayName,
            certificatePEM: certificatePEM,
            privateKeyPEM: privateKeyPEM
        )
    }

    func activeRootIssuer() throws -> (certificate: Certificate, privateKey: Certificate.PrivateKey)? {
        guard let snapshot = try activeRootIssuerSnapshot() else {
            return nil
        }
        return (certificate: snapshot.certificate, privateKey: snapshot.privateKey)
    }

    func activeRootIssuerSnapshot()
        throws -> (
            certificate: Certificate,
            privateKey: Certificate.PrivateKey,
            fingerprintSHA256: String
        )?
    {
        try transactionLock.withLock {
            guard let entry = metadata(kind: .root).last else {
                lock.withLock { cachedRootIssuer = nil }
                return nil
            }

            // `CertificateManager.certificateForHost` asks for this on every intercepted
            // connection, including the ones it then answers from its own host-certificate
            // cache. Resolving it costs a Keychain read plus a certificate and a private-key
            // PEM parse, which is why the result is kept. Every mutation of `entries` bumps
            // `entriesGeneration` and drops the cache, so a replaced or deleted root can never
            // be served from here -- the generation is also compared, not just the entry id,
            // because a re-import reuses neither but a restored backup could reuse the id.
            var generation: UInt64 = 0
            var memoized: (certificate: Certificate, privateKey: Certificate.PrivateKey, fingerprint: String)?
            lock.withLock {
                generation = entriesGeneration
                guard let cached = cachedRootIssuer,
                      cached.generation == generation,
                      cached.entryID == entry.id else
                {
                    return
                }
                memoized = (cached.certificate, cached.privateKey, cached.fingerprintSHA256)
            }
            if let memoized {
                return (
                    certificate: memoized.certificate,
                    privateKey: memoized.privateKey,
                    fingerprintSHA256: memoized.fingerprint
                )
            }

            guard let keyData = try secureStore.load(account: entry.keychainAccount),
                  let privateKeyPEM = String(data: keyData, encoding: .utf8) else
            {
                throw CustomCertificateError.missingPrivateKey
            }
            let certificate = try Certificate(pemEncoded: entry.certificatePEM)
            let privateKey = try Certificate.PrivateKey(pemEncoded: privateKeyPEM)
            let fingerprint = entry.fingerprintSHA256 ?? Self.fingerprint(certificate) ?? "custom"
            lock.withLock {
                cachedRootIssuer = CachedRootIssuer(
                    generation: generation,
                    entryID: entry.id,
                    certificate: certificate,
                    privateKey: privateKey,
                    fingerprintSHA256: fingerprint
                )
            }
            return (certificate: certificate, privateKey: privateKey, fingerprintSHA256: fingerprint)
        }
    }

    func serverIdentity(for host: String) -> CustomTLSIdentity? {
        identity(for: host, kind: .server)
    }

    func clientIdentity(for host: String) -> CustomTLSIdentity? {
        identity(for: host, kind: .client)
    }

    func delete(id: UUID) throws {
        try transactionLock.withLock {
            let currentEntries = lock.withLock { entries }
            guard let removed = currentEntries.first(where: { $0.id == id }) else {
                return
            }
            let proposedEntries = currentEntries.filter { $0.id != id }
            try commitDeletion(
                currentEntries: currentEntries,
                proposedEntries: proposedEntries,
                removedEntries: [removed]
            )
        }
    }

    func deleteAll(kind: CustomCertificateKind? = nil) throws {
        try transactionLock.withLock {
            let currentEntries = lock.withLock { entries }
            let removedEntries = currentEntries.filter { kind == nil || $0.kind == kind }
            guard !removedEntries.isEmpty else {
                return
            }
            let proposedEntries = currentEntries.filter { kind != nil && $0.kind != kind }
            try commitDeletion(
                currentEntries: currentEntries,
                proposedEntries: proposedEntries,
                removedEntries: removedEntries
            )
        }
    }

    // MARK: Private

    /// The parsed active root, memoized for `activeRootIssuerSnapshot`. Keyed by the generation of
    /// the entry list it was derived from so it cannot outlive the root it came from.
    ///
    /// Invalidation tracks this store, not the Keychain: an import, a delete, or a reload drops
    /// it, but a private key rewritten under the same account by something other than Rockxy is
    /// not noticed until one of those happens. Only this type writes those accounts, and an
    /// import always allocates a fresh one, so the window is a user editing Keychain Access by
    /// hand -- where keeping the key Rockxy already loaded is the better of the two outcomes.
    private struct CachedRootIssuer {
        let generation: UInt64
        let entryID: UUID
        let certificate: Certificate
        let privateKey: Certificate.PrivateKey
        let fingerprintSHA256: String
    }

    /// Private key PEMs loaded for `identity(for:kind:)`, keyed by Keychain account and tagged
    /// with the generation of the entry list they belong to.
    ///
    /// Same residual as `cachedRootIssuer`, and it is worth restating: invalidation tracks this
    /// store, not the Keychain. An import, a delete, or a reload drops this, but a key rewritten
    /// under the same account by something other than Rockxy is not noticed until one of those
    /// happens. Only this type writes those accounts and an import always allocates a fresh one,
    /// so the window is a user editing Keychain Access by hand. Clearing this also drops the
    /// loaded keys from memory as soon as the entries they belong to stop being current.
    private struct CachedIdentityKeys {
        let generation: UInt64
        var privateKeyPEMByAccount: [String: String]
    }

    private let storageURL: URL
    private let secureStore: any SecureDataStore
    private let metadataWriter: any CustomCertificateMetadataWriter
    // activeRootIssuer intentionally reuses metadata ordering while holding this lock.
    private let transactionLock = NSRecursiveLock()
    private let lock = NSLock()
    private var entries: [CustomCertificateMetadata] = []
    /// Bumped by every assignment to `entries`, so a cached derivation of them can tell that the
    /// store has moved on without comparing the entries themselves.
    private var entriesGeneration: UInt64 = 0
    private var cachedRootIssuer: CachedRootIssuer?
    private var cachedIdentityKeys: CachedIdentityKeys?

    /// A custom root signs a certificate for every host, so it must be a CA that is valid now.
    private static func validateRootAuthority(_ certificate: Certificate) throws {
        let now = Date()
        guard certificate.notValidBefore <= now, now <= certificate.notValidAfter else {
            throw CustomCertificateError.rootExpired
        }
        let basicConstraints = try? certificate.extensions.basicConstraints
        guard case .isCertificateAuthority = basicConstraints else {
            throw CustomCertificateError.rootNotCertificateAuthority
        }
        // Apple platforms reject chains signed with SHA-1 (short RSA keys are refused earlier).
        guard certificate.signatureAlgorithm != .sha1WithRSAEncryption else {
            throw CustomCertificateError.rootWeakSignature
        }
    }

    /// RSA modulus size of a PEM certificate's key, or nil for other key types. Read through
    /// Security so short keys that the X509 parser refuses outright are still measured.
    private static func rsaKeySize(certificatePEM: String) -> Int? {
        let base64 = certificatePEM
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: base64),
              let secCertificate = SecCertificateCreateWithData(nil, der as CFData),
              let key = SecCertificateCopyKey(secCertificate),
              let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              (attributes[kSecAttrKeyType] as? String) == (kSecAttrKeyTypeRSA as String) else
        {
            return nil
        }
        return attributes[kSecAttrKeySizeInBits] as? Int
    }

    private static func fingerprint(_ certificate: Certificate) -> String? {
        var serializer = DER.Serializer()
        guard (try? certificate.serialize(into: &serializer)) != nil else {
            return nil
        }
        return KeychainHelper.computeFingerprintSHA256(Data(serializer.serializedBytes))
    }

    private func importIdentity(
        kind: CustomCertificateKind,
        hostPattern: String?,
        displayName: String,
        certificatePEM: String,
        privateKeyPEM: String
    )
        throws -> CustomCertificateMetadata
    {
        // A root is checked before it and its key are parsed, so a weak root reports why
        // instead of failing inside the parsers.
        if kind == .root, let bits = Self.rsaKeySize(certificatePEM: certificatePEM), bits < 2_048 {
            throw CustomCertificateError.rootWeakKey(bits: bits)
        }
        let certificate = try Certificate(pemEncoded: certificatePEM)
        if kind == .root {
            try Self.validateRootAuthority(certificate)
        }
        let privateKey = try Certificate.PrivateKey(pemEncoded: privateKeyPEM)
        guard certificate.publicKey.subjectPublicKeyInfoBytes == privateKey.publicKey.subjectPublicKeyInfoBytes else {
            throw CustomCertificateError.invalidCertificateKeyPair
        }

        if kind != .root {
            try validateTLSIdentity(certificatePEM: certificatePEM, privateKeyPEM: privateKeyPEM)
        }

        let normalizedHostPattern = hostPattern?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let keychainAccount = "custom-certificate.\(kind.rawValue).\(UUID().uuidString)"

        let entry = CustomCertificateMetadata(
            id: UUID(),
            kind: kind,
            displayName: displayName,
            hostPattern: normalizedHostPattern,
            certificatePEM: certificatePEM,
            keychainAccount: keychainAccount,
            createdAt: Date(),
            notValidBefore: certificate.notValidBefore,
            notValidAfter: certificate.notValidAfter,
            fingerprintSHA256: Self.fingerprint(certificate)
        )

        return try transactionLock.withLock {
            let currentEntries = lock.withLock { entries }
            let supersededEntries = currentEntries.filter {
                $0.kind == kind && $0.hostPattern == normalizedHostPattern
            }
            var proposedEntries = currentEntries.filter {
                !($0.kind == kind && $0.hostPattern == normalizedHostPattern)
            }
            proposedEntries.append(entry)

            let accountsToDelete = unreferencedAccounts(
                removedEntries: supersededEntries,
                retainedEntries: proposedEntries
            )
            let supersededKeys = try loadAccountData(accounts: accountsToDelete)

            try secureStore.save(Data(privateKeyPEM.utf8), account: keychainAccount)
            do {
                try persist(entries: proposedEntries)
            } catch {
                let persistenceError = error
                do {
                    try secureStore.delete(account: keychainAccount)
                } catch {
                    throw CustomCertificateTransactionError.recoveryFailed
                }
                throw persistenceError
            }

            do {
                try deleteAccounts(accountsToDelete)
            } catch {
                let deletionError = error
                try performRecovery([
                    { try self.persist(entries: currentEntries) },
                    { try self.restoreAccountData(supersededKeys) },
                    { try self.secureStore.delete(account: keychainAccount) }
                ])
                throw deletionError
            }

            lock.withLock {
                entries = proposedEntries
                invalidateDerivedStateLocked()
            }
            return entry
        }
    }

    /// Resolves the custom identity Rockxy should present for `host`, if the user configured one.
    ///
    /// Called from the TLS interception path for every intercepted connection, so the two costs
    /// here are both per-connection. The Keychain read is memoized the same way
    /// `activeRootIssuerSnapshot` memoizes the active root -- same `entriesGeneration`, dropped by
    /// the same critical section that replaces `entries` -- and the host is only normalized once
    /// there is something to match it against, so a user with no custom certificates at all pays
    /// nothing beyond one `isEmpty` check.
    private func identity(for host: String, kind: CustomCertificateKind) -> CustomTLSIdentity? {
        transactionLock.withLock {
            let match = lock.withLock { () -> CustomCertificateMetadata? in
                guard !entries.isEmpty else {
                    return nil
                }
                let normalizedHost = host.lowercased()
                return entries.last { entry in
                    guard entry.kind == kind, let pattern = entry.hostPattern else {
                        return false
                    }
                    return HostPatternMatcher.matches(pattern: pattern, host: normalizedHost)
                }
            }

            guard let match else {
                return nil
            }

            if let memoized = memoizedPrivateKeyPEM(account: match.keychainAccount) {
                return CustomTLSIdentity(certificateChainPEM: [match.certificatePEM], privateKeyPEM: memoized)
            }

            guard let keyData = try? secureStore.load(account: match.keychainAccount),
                  let privateKeyPEM = String(data: keyData, encoding: .utf8) else
            {
                // Deliberately not memoized. An unreadable or undecodable key is the state a user
                // goes and fixes, and remembering it would keep answering with the failure until
                // the next store mutation -- long after the key worked again.
                return nil
            }
            memoizePrivateKeyPEM(privateKeyPEM, account: match.keychainAccount)
            return CustomTLSIdentity(certificateChainPEM: [match.certificatePEM], privateKeyPEM: privateKeyPEM)
        }
    }

    /// The memoized key for `account`, or `nil` when nothing was loaded for the current generation
    /// of `entries`.
    private func memoizedPrivateKeyPEM(account: String) -> String? {
        lock.withLock {
            guard let cached = cachedIdentityKeys, cached.generation == entriesGeneration else {
                return nil
            }
            return cached.privateKeyPEMByAccount[account]
        }
    }

    private func memoizePrivateKeyPEM(_ privateKeyPEM: String, account: String) {
        lock.withLock {
            // Keyed by account rather than by host: hosts arrive from the network and would grow
            // this without bound over a long capture, while the accounts are exactly the ones the
            // user imported.
            if cachedIdentityKeys?.generation != entriesGeneration {
                cachedIdentityKeys = CachedIdentityKeys(generation: entriesGeneration, privateKeyPEMByAccount: [:])
            }
            cachedIdentityKeys?.privateKeyPEMByAccount[account] = privateKeyPEM
        }
    }

    private func validateTLSIdentity(certificatePEM: String, privateKeyPEM: String) throws {
        let certificate = try NIOSSLCertificate(bytes: Array(certificatePEM.utf8), format: .pem)
        let privateKey = try NIOSSLPrivateKey(bytes: Array(privateKeyPEM.utf8), format: .pem)
        _ = try NIOSSLContext(configuration: TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(certificate)],
            privateKey: .privateKey(privateKey)
        ))
    }

    /// Marks everything derived from `entries` stale. Call with `lock` held, from the same
    /// critical section that replaces `entries`, so no reader can observe new entries beside a
    /// snapshot of the old ones. Clearing the issuer also drops the parsed private key from
    /// memory as soon as its root stops being the active one.
    private func invalidateDerivedStateLocked() {
        entriesGeneration &+= 1
        cachedRootIssuer = nil
        cachedIdentityKeys = nil
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([CustomCertificateMetadata].self, from: data) else
        {
            return
        }
        lock.withLock {
            entries = decoded
            invalidateDerivedStateLocked()
        }
    }

    private func commitDeletion(
        currentEntries: [CustomCertificateMetadata],
        proposedEntries: [CustomCertificateMetadata],
        removedEntries: [CustomCertificateMetadata]
    )
        throws
    {
        let accountsToDelete = unreferencedAccounts(
            removedEntries: removedEntries,
            retainedEntries: proposedEntries
        )
        let removedKeys = try loadAccountData(accounts: accountsToDelete)

        try persist(entries: proposedEntries)
        do {
            try deleteAccounts(accountsToDelete)
        } catch {
            let deletionError = error
            try performRecovery([
                { try self.persist(entries: currentEntries) },
                { try self.restoreAccountData(removedKeys) }
            ])
            throw deletionError
        }

        lock.withLock {
            entries = proposedEntries
            invalidateDerivedStateLocked()
        }
    }

    private func unreferencedAccounts(
        removedEntries: [CustomCertificateMetadata],
        retainedEntries: [CustomCertificateMetadata]
    )
        -> [String]
    {
        let retainedAccounts = Set(retainedEntries.map(\.keychainAccount))
        var seenAccounts = Set<String>()
        return removedEntries.compactMap { entry in
            guard !retainedAccounts.contains(entry.keychainAccount),
                  seenAccounts.insert(entry.keychainAccount).inserted else
            {
                return nil
            }
            return entry.keychainAccount
        }
    }

    private func loadAccountData(accounts: [String]) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for account in accounts {
            if let data = try secureStore.load(account: account) {
                result[account] = data
            }
        }
        return result
    }

    private func deleteAccounts(_ accounts: [String]) throws {
        for account in accounts {
            try secureStore.delete(account: account)
        }
    }

    private func restoreAccountData(_ accountData: [String: Data]) throws {
        var restorationFailed = false
        for (account, data) in accountData {
            do {
                try secureStore.save(data, account: account)
            } catch {
                restorationFailed = true
            }
        }
        if restorationFailed {
            throw CustomCertificateTransactionError.recoveryFailed
        }
    }

    private func performRecovery(_ actions: [() throws -> Void]) throws {
        var recoveryFailed = false
        for action in actions {
            do {
                try action()
            } catch {
                recoveryFailed = true
            }
        }
        if recoveryFailed {
            throw CustomCertificateTransactionError.recoveryFailed
        }
    }

    private func persist(entries snapshot: [CustomCertificateMetadata]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try metadataWriter.write(encoder.encode(snapshot), to: storageURL)
    }
}

// MARK: - CustomCertificateError

enum CustomCertificateError: LocalizedError, Equatable {
    case invalidCertificateKeyPair
    case missingPrivateKey
    case rootNotCertificateAuthority
    case rootExpired
    case rootWeakSignature
    case rootWeakKey(bits: Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .rootNotCertificateAuthority:
            String(
                localized: """
                This certificate is not a certificate authority, so it cannot sign the certificates \
                Rockxy generates for each host. Choose the root or intermediate CA certificate.
                """,
                bundle: RockxyLocalization.bundle
            )
        case .rootExpired:
            String(
                localized: "This certificate has expired or is not valid yet. Clients would reject every certificate signed by it.",
                bundle: RockxyLocalization.bundle
            )
        case .rootWeakSignature:
            String(
                localized: "This certificate is signed with SHA-1. Apple platforms reject it; create a root signed with SHA-256 or stronger.",
                bundle: RockxyLocalization.bundle
            )
        case let .rootWeakKey(bits):
            String(
                localized: "This certificate uses a \(String(bits))-bit RSA key. Apple platforms require at least 2048 bits.",
                bundle: RockxyLocalization.bundle
            )
        case .invalidCertificateKeyPair:
            String(
                localized: "The certificate and private key do not belong to the same identity.",
                bundle: RockxyLocalization.bundle
            )
        case .missingPrivateKey:
            String(
                localized: "The private key for this certificate could not be found in Keychain.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

// MARK: - CustomCertificateTransactionError

enum CustomCertificateTransactionError: LocalizedError, Equatable {
    case recoveryFailed

    // MARK: Internal

    var errorDescription: String? {
        String(
            localized: "Rockxy could not fully recover the custom certificate store. Restart Rockxy before making more certificate changes.",
            bundle: RockxyLocalization.bundle
        )
    }
}

// MARK: - CustomCertificateImportError

enum CustomCertificateImportError: LocalizedError, Equatable {
    case invalidCertificate
    case invalidPrivateKey
    case invalidPKCS12
    case incorrectPassword
    case missingCertificate
    case keychainUnavailable

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .incorrectPassword:
            String(
                localized: "The P12 file could not be opened. The password may be incorrect, or the file may be damaged.",
                bundle: RockxyLocalization.bundle
            )
        case .keychainUnavailable:
            String(
                localized: "macOS could not use the keychain to read this P12 file. Unlock the keychain and try again.",
                bundle: RockxyLocalization.bundle
            )
        case .invalidCertificate:
            String(
                localized: "The selected certificate must be a valid PEM or DER X.509 certificate.",
                bundle: RockxyLocalization.bundle
            )
        case .invalidPrivateKey:
            String(
                localized: "The selected private key must be a valid PEM or DER private key.",
                bundle: RockxyLocalization.bundle
            )
        case .invalidPKCS12:
            String(
                localized: "The selected P12 file could not be imported. Check that the file contains a certificate and private key, then try the correct password.",
                bundle: RockxyLocalization.bundle
            )
        case .missingCertificate:
            String(
                localized: "The selected P12 file does not contain a certificate.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}
