import Crypto
import Foundation
import SwiftASN1
import X509

/// Generates short-lived (1-year) leaf certificates for individual hostnames,
/// signed by Rockxy's root CA. Each certificate includes a Subject Alternative
/// Name (SAN) matching the target host, which modern TLS clients require —
/// CommonName alone is no longer sufficient for hostname verification.
nonisolated enum HostCertGenerator {
    static func generate(
        host: String,
        issuer: Certificate,
        issuerKey: P256.Signing.PrivateKey
    )
        throws -> (certificate: Certificate, privateKey: P256.Signing.PrivateKey)
    {
        try generate(host: host, issuer: issuer, issuerPrivateKey: .init(issuerKey))
    }

    static func generate(
        host: String,
        issuer: Certificate,
        issuerPrivateKey: Certificate.PrivateKey
    )
        throws -> (certificate: Certificate, privateKey: P256.Signing.PrivateKey)
    {
        let hostKey = P256.Signing.PrivateKey()

        let subjectName = try DistinguishedName {
            CommonName(host)
        }

        let now = Date()
        guard let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now),
              let oneYearLater = Calendar.current.date(byAdding: .year, value: 1, to: now) else
        {
            throw CertificateGenerationError.invalidDateComputation
        }

        // serverAuth EKU + SAN dnsName are the minimum set of extensions for
        // browsers and system TLS to accept this as a valid server certificate.
        // AuthorityKeyIdentifier links this leaf cert to the root CA via SHA-1
        // hash of the issuer's public key — required for macOS SecTrust chain building.
        let extensions = try Certificate.Extensions {
            Critical(
                BasicConstraints.notCertificateAuthority
            )
            Critical(
                KeyUsage(digitalSignature: true)
            )
            SubjectAlternativeNames([
                .dnsName(host)
            ])
            try ExtendedKeyUsage([.serverAuth])
            SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(
                    Insecure.SHA1.hash(data: Certificate.PublicKey(hostKey.publicKey).subjectPublicKeyInfoBytes)
                )
            )
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(Insecure.SHA1.hash(data: issuer.publicKey.subjectPublicKeyInfoBytes))
            )
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: CertificateSerialNumberGenerator.generate(),
            publicKey: .init(hostKey.publicKey),
            notValidBefore: twoDaysAgo,
            notValidAfter: oneYearLater,
            issuer: issuer.subject,
            subject: subjectName,
            signatureAlgorithm: signatureAlgorithm(for: issuerPrivateKey),
            extensions: extensions,
            issuerPrivateKey: issuerPrivateKey
        )

        return (certificate, hostKey)
    }

    private static func signatureAlgorithm(for privateKey: Certificate.PrivateKey) -> Certificate.SignatureAlgorithm {
        let description = privateKey.description
        if description.hasPrefix("P384") {
            return .ecdsaWithSHA384
        }
        if description.hasPrefix("P521") {
            return .ecdsaWithSHA512
        }
        if description.hasPrefix("RSA") {
            return .sha256WithRSAEncryption
        }
        return .ecdsaWithSHA256
    }
}
