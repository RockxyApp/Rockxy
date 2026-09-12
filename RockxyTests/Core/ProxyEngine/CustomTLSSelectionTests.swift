import Crypto
import Foundation
import NIOSSL
@testable import Rockxy
import SwiftASN1
import Testing
import X509

// MARK: - CustomTLSSelectionTests

struct CustomTLSSelectionTests {
    @Test("server TLS configuration accepts custom server identity")
    func serverTLSConfigurationUsesCustomIdentity() throws {
        let identity = try makeIdentity(host: "pinned.example.com")
        let config = try TLSInterceptHandler.makeServerTLSConfiguration(identity: identity)

        #expect(config.certificateChain.count == 1)
        #expect(config.privateKey != nil)
        #expect(config.applicationProtocols == ["http/1.1"])
    }

    @Test("generated server identity includes the exact root issuer")
    func generatedServerIdentityIncludesIssuer() throws {
        let root = try RootCAGenerator.generate()
        let leaf = try HostCertGenerator.generate(
            host: "duplicate-root.example.com",
            issuer: root.certificate,
            issuerKey: root.privateKey
        )
        let generated = GeneratedHostCertificate(
            certificate: leaf.certificate,
            privateKey: leaf.privateKey,
            issuerCertificate: root.certificate
        )

        let identity = try generated.serverIdentity()
        let config = try TLSInterceptHandler.makeServerTLSConfiguration(identity: identity)
        let expectedLeafPEM = try certificatePEM(leaf.certificate)
        let expectedIssuerPEM = try certificatePEM(root.certificate)

        #expect(identity.certificateChainPEM.count == 2)
        #expect(identity.certificateChainPEM[0] == expectedLeafPEM)
        #expect(identity.certificateChainPEM[1] == expectedIssuerPEM)
        #expect(config.certificateChain.count == 2)
        #expect(generated.provesRootCATrust)
    }

    @Test("custom root generated identity does not claim Rockxy Root CA trust")
    func customRootGeneratedIdentityKeepsTrustProvenance() throws {
        let root = try RootCAGenerator.generate()
        let leaf = try HostCertGenerator.generate(
            host: "custom-root.example.com",
            issuer: root.certificate,
            issuerKey: root.privateKey
        )
        let generated = GeneratedHostCertificate(
            certificate: leaf.certificate,
            privateKey: leaf.privateKey,
            issuerCertificate: root.certificate,
            provesRootCATrust: false
        )

        #expect(!generated.provesRootCATrust)
        #expect(try generated.serverIdentity().certificateChainPEM.count == 2)
    }

    @Test("client TLS configuration includes matching identity and keeps full verification")
    func clientTLSConfigurationIncludesIdentity() throws {
        let identity = try makeIdentity(host: "mtls.example.com")
        let config = try HTTPSProxyRelayHandler.makeClientTLSConfiguration(clientIdentity: identity)

        #expect(config.certificateVerification == .fullVerification)
        #expect(config.certificateChain.count == 1)
        #expect(config.privateKey != nil)
    }

    @Test("client TLS configuration omits identity when there is no match and keeps full verification")
    func clientTLSConfigurationWithoutIdentity() throws {
        let config = try HTTPSProxyRelayHandler.makeClientTLSConfiguration(clientIdentity: nil)

        #expect(config.certificateVerification == .fullVerification)
        #expect(config.certificateChain.isEmpty)
        #expect(config.privateKey == nil)
    }

    @Test("default generated certificate remains available when no custom server match exists")
    func defaultGeneratedCertificateFallback() throws {
        let manager = CustomCertificateManager(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("RockxyTLSSelection-\(UUID().uuidString)")
                .appendingPathComponent("custom.json"),
            secureStore: MemorySecureDataStoreForTLS()
        )

        #expect(manager.serverIdentity(for: "fallback.example.com") == nil)
    }

    private func makeIdentity(host: String) throws -> CustomTLSIdentity {
        let root = try RootCAGenerator.generate()
        let leaf = try HostCertGenerator.generate(host: host, issuer: root.certificate, issuerKey: root.privateKey)
        let certificatePEM = try certificatePEM(leaf.certificate)
        return CustomTLSIdentity(certificateChainPEM: [certificatePEM], privateKeyPEM: leaf.privateKey.pemRepresentation)
    }

    private func certificatePEM(_ certificate: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
    }
}

private final class MemorySecureDataStoreForTLS: SecureDataStore, @unchecked Sendable {
    func save(_ data: Data, account: String) throws {
        lock.withLock {
            values[account] = data
        }
    }

    func load(account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    func delete(account: String) throws {
        _ = lock.withLock {
            values.removeValue(forKey: account)
        }
    }

    private let lock = NSLock()
    private var values: [String: Data] = [:]
}
