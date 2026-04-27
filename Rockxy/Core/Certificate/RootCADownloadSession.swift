import Foundation
import Security

// MARK: - RootCADownloadSession

struct RootCADownloadSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let token: String
    let publicURL: URL
    let host: String
    let port: Int
    let createdAt: Date
    let expiresAt: Date

    var isExpired: Bool {
        isExpired(at: Date())
    }

    func isExpired(at date: Date) -> Bool {
        date >= expiresAt
    }

    func validates(token candidate: String, at date: Date = Date()) -> Bool {
        guard !isExpired(at: date) else {
            return false
        }
        return Self.constantTimeEquals(candidate, token)
    }

    static func make(host: String, port: Int, now: Date = Date(), ttl: TimeInterval = 600) throws -> Self {
        let token = try makeToken()
        return try make(id: UUID(), token: token, host: host, port: port, now: now, ttl: ttl)
    }

    func withPort(_ port: Int) throws -> Self {
        try Self.make(id: id, token: token, host: host, port: port, now: createdAt, ttl: expiresAt.timeIntervalSince(createdAt))
    }

    private static func make(id: UUID, token: String, host: String, port: Int, now: Date, ttl: TimeInterval) throws -> Self {
        guard let url = URL(string: "http://\(host):\(port)/root-ca.pem?token=\(token)") else {
            throw RootCADownloadError.invalidSessionURL
        }

        return RootCADownloadSession(
            id: id,
            token: token,
            publicURL: url,
            host: host,
            port: port,
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttl)
        )
    }

    private static func makeToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw RootCADownloadError.tokenGenerationFailed
        }

        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else {
            return false
        }

        var difference: UInt8 = 0
        for index in lhsBytes.indices {
            difference |= lhsBytes[index] ^ rhsBytes[index]
        }
        return difference == 0
    }
}

// MARK: - RootCADownloadError

enum RootCADownloadError: LocalizedError {
    case tokenGenerationFailed
    case invalidSessionURL
    case noReachableLANAddress
    case noRootCA
    case portUnavailable

    var errorDescription: String? {
        switch self {
        case .tokenGenerationFailed:
            String(localized: "Failed to generate a secure sharing token.")
        case .invalidSessionURL:
            String(localized: "Failed to build the certificate sharing URL.")
        case .noReachableLANAddress:
            String(localized: "No reachable LAN IPv4 address was found. Connect this Mac to Wi-Fi or Ethernet, then try again.")
        case .noRootCA:
            String(localized: "No Root CA certificate is available to share.")
        case .portUnavailable:
            String(localized: "Rockxy could not start the temporary certificate sharing server.")
        }
    }
}

// MARK: - RootCAShareValidationError

enum RootCAShareValidationError: LocalizedError {
    case missingFingerprint
    case certificateFingerprintUnavailable
    case fingerprintMismatch

    var errorDescription: String? {
        switch self {
        case .missingFingerprint:
            String(localized: "The Root CA fingerprint is unavailable. Stop sharing and regenerate the Root CA before installing it on another device.")
        case .certificateFingerprintUnavailable:
            String(localized: "Rockxy could not compute the Root CA fingerprint. Stop sharing and regenerate the Root CA before installing it on another device.")
        case .fingerprintMismatch:
            String(localized: "The Root CA fingerprint changed before sharing. Stop sharing and try again.")
        }
    }
}

// MARK: - RootCAFingerprintVerifier

enum RootCAFingerprintVerifier {
    static func verifiedFingerprint(certificatePEM: String, expectedFingerprint: String?) throws -> String {
        guard let expectedFingerprint, !expectedFingerprint.isEmpty else {
            throw RootCAShareValidationError.missingFingerprint
        }

        guard let computedFingerprint = fingerprint(certificatePEM: certificatePEM) else {
            throw RootCAShareValidationError.certificateFingerprintUnavailable
        }

        guard normalized(computedFingerprint) == normalized(expectedFingerprint) else {
            throw RootCAShareValidationError.fingerprintMismatch
        }

        return expectedFingerprint
    }

    static func fingerprint(certificatePEM: String) -> String? {
        let base64 = certificatePEM
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") }
            .joined()

        guard let derData = Data(base64Encoded: base64) else {
            return nil
        }

        return KeychainHelper.computeFingerprintSHA256(derData)
    }

    private static func normalized(_ fingerprint: String) -> String {
        fingerprint
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}
