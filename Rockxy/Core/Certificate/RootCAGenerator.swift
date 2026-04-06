import Crypto
import Foundation
import SwiftASN1
import X509

/// Generates a self-signed root Certificate Authority using P-256 ECDSA.
/// The root CA is valid for 2 years and is used to sign per-host leaf certificates
/// for HTTPS interception. Users must trust this CA in their system keychain for
/// TLS interception to work without browser warnings.
nonisolated enum RootCAGenerator {
    static func generate() throws -> (certificate: Certificate, privateKey: P256.Signing.PrivateKey) {
        let privateKey = P256.Signing.PrivateKey()

        let subjectName = try DistinguishedName {
            CommonName("Rockxy Root CA")
        }

        let now = Date()
        guard let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now),
              let twoYearsLater = Calendar.current.date(byAdding: .year, value: 2, to: now) else
        {
            throw CertificateGenerationError.invalidDateComputation
        }

        // BasicConstraints CA:TRUE and KeyUsage keyCertSign are required for the
        // system TLS stack to accept this as a valid issuer of leaf certificates.
        // SubjectKeyIdentifier (SHA-1 of public key per RFC 5280 §4.2.1.2) is needed
        // so leaf certs can reference this CA via AuthorityKeyIdentifier.
        let extensions = try Certificate.Extensions {
            Critical(
                BasicConstraints.isCertificateAuthority(maxPathLength: nil)
            )
            Critical(
                KeyUsage(keyCertSign: true, cRLSign: true)
            )
            SubjectKeyIdentifier(hash: Certificate.PublicKey(privateKey.publicKey))
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: .init(privateKey.publicKey),
            notValidBefore: twoDaysAgo,
            notValidAfter: twoYearsLater,
            issuer: subjectName,
            subject: subjectName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: .init(privateKey)
        )

        return (certificate, privateKey)
    }
}
