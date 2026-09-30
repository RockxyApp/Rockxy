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
        let identity = try secItemImportIdentity(data: data, passphrase: passphrase)
        let certificate = try certificate(from: identity.certificate)
        let privateKey: Certificate.PrivateKey
        do {
            privateKey = try Certificate.PrivateKey(identity.privateKey)
        } catch {
            throw CustomCertificateImportError.invalidPrivateKey
        }

        return try Self(
            displayName: displayName,
            certificatePEM: pem(certificate),
            privateKeyPEM: privateKey.serializeAsPEM().pemString
        )
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

    private static func secItemImportIdentity(
        data: Data,
        passphrase: String
    )
        throws -> (certificate: SecCertificate, privateKey: SecKey)
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
            nil,
            &importedItems
        )
        guard status == errSecSuccess, let importedItems else {
            return try secPKCS12Identity(data: data, passphrase: passphrase)
        }
        return try identity(from: importedItems)
    }

    private static func secPKCS12Identity(
        data: Data,
        passphrase: String
    )
        throws -> (certificate: SecCertificate, privateKey: SecKey)
    {
        var importedItems: CFArray?
        let options = [kSecImportExportPassphrase as String: passphrase] as CFDictionary
        let status = SecPKCS12Import(data as CFData, options, &importedItems)
        guard status == errSecSuccess, let importedItems else {
            throw status == errSecAuthFailed
                ? CustomCertificateImportError.incorrectPassword
                : CustomCertificateImportError.invalidPKCS12
        }
        return try identity(from: importedItems)
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
                return nil
            }
            guard let keyData = try secureStore.load(account: entry.keychainAccount),
                  let privateKeyPEM = String(data: keyData, encoding: .utf8) else
            {
                throw CustomCertificateError.missingPrivateKey
            }
            let certificate = try Certificate(pemEncoded: entry.certificatePEM)
            return try (
                certificate: certificate,
                privateKey: Certificate.PrivateKey(pemEncoded: privateKeyPEM),
                fingerprintSHA256: entry.fingerprintSHA256 ?? Self.fingerprint(certificate) ?? "custom"
            )
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

    private let storageURL: URL
    private let secureStore: any SecureDataStore
    private let metadataWriter: any CustomCertificateMetadataWriter
    // activeRootIssuer intentionally reuses metadata ordering while holding this lock.
    private let transactionLock = NSRecursiveLock()
    private let lock = NSLock()
    private var entries: [CustomCertificateMetadata] = []

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
        let certificate = try Certificate(pemEncoded: certificatePEM)
        let privateKey = try Certificate.PrivateKey(pemEncoded: privateKeyPEM)
        guard certificate.publicKey.subjectPublicKeyInfoBytes == privateKey.publicKey.subjectPublicKeyInfoBytes else {
            throw CustomCertificateError.invalidCertificateKeyPair
        }

        if kind != .root {
            try validateTLSIdentity(certificatePEM: certificatePEM, privateKeyPEM: privateKeyPEM)
        } else {
            try Self.validateRootAuthority(certificate)
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
            }
            return entry
        }
    }

    private func identity(for host: String, kind: CustomCertificateKind) -> CustomTLSIdentity? {
        let normalizedHost = host.lowercased()
        return transactionLock.withLock {
            let match = lock.withLock {
                entries.last { entry in
                    guard entry.kind == kind, let pattern = entry.hostPattern else {
                        return false
                    }
                    return HostPatternMatcher.matches(pattern: pattern, host: normalizedHost)
                }
            }

            guard let match,
                  let keyData = try? secureStore.load(account: match.keychainAccount),
                  let privateKeyPEM = String(data: keyData, encoding: .utf8) else
            {
                return nil
            }
            return CustomTLSIdentity(certificateChainPEM: [match.certificatePEM], privateKeyPEM: privateKeyPEM)
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

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([CustomCertificateMetadata].self, from: data) else
        {
            return
        }
        lock.withLock {
            entries = decoded
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

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .incorrectPassword:
            String(
                localized: "The password for this P12 file is incorrect.",
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
