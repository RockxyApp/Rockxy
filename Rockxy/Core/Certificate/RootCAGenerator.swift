import Crypto
import Foundation
import SwiftASN1
import X509

/// Generates a self-signed root Certificate Authority using P-256 ECDSA.
/// The root CA is valid for 2 years and is used to sign per-host leaf certificates
/// for HTTPS interception. Users must trust this CA in their system keychain for
/// TLS interception to work without browser warnings.
nonisolated enum RootCAGenerator {
    static func generate(
        serialNumber: Certificate.SerialNumber = CertificateSerialNumberGenerator.generate()
    ) throws -> (certificate: Certificate, privateKey: P256.Signing.PrivateKey) {
        let privateKey = P256.Signing.PrivateKey()

        let publicKey = Certificate.PublicKey(privateKey.publicKey)

        let subjectName = try DistinguishedName {
            CommonName(subjectCommonName(for: publicKey))
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
            SubjectKeyIdentifier(hash: publicKey)
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: serialNumber,
            publicKey: publicKey,
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

    /// Older Rockxy roots could encode a random 20-byte value with a leading sign octet,
    /// producing a 21-octet ASN.1 INTEGER. RFC 5280 limits certificate serial numbers to
    /// 20 octets and Chromium declines such a local root as a trust anchor.
    static func requiresClientCompatibilityRepair(_ certificate: Certificate) -> Bool {
        requiresClientCompatibilityRepair(serialNumber: certificate.serialNumber)
    }

    static func requiresClientCompatibilityRepair(serialNumber: Certificate.SerialNumber) -> Bool {
        let bytes = serialNumber.bytes
        return bytes.count > CertificateSerialNumberGenerator.maximumEncodedByteCount
            || (bytes.count == CertificateSerialNumberGenerator.maximumEncodedByteCount
                && bytes.first.map { $0 & 0x80 != 0 } == true)
    }

    private static func subjectCommonName(for publicKey: Certificate.PublicKey) -> String {
        let identity = SHA256.hash(data: publicKey.subjectPublicKeyInfoBytes)
            .prefix(6)
            .map { String(format: "%02X", $0) }
            .joined()
        // A key-specific subject prevents path builders from attempting to chain a newly
        // issued leaf through every historical Rockxy root left in a user's keychains.
        return "Rockxy Root CA \(identity)"
    }
}

/// Generates RFC 5280-compatible positive serial numbers. Nineteen random bytes retain
/// 152 bits of entropy while leaving room for the ASN.1 sign octet when the high bit is set.
nonisolated enum CertificateSerialNumberGenerator {
    static let maximumEncodedByteCount = 20

    static func generate() -> Certificate.SerialNumber {
        var generator = SystemRandomNumberGenerator()
        var bytes = (0 ..< 19).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        if bytes.allSatisfy({ $0 == 0 }) {
            bytes[bytes.index(before: bytes.endIndex)] = 1
        }
        return Certificate.SerialNumber(bytes: bytes)
    }
}
