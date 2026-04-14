import Foundation
import Security

/// Testable caller-validation primitives shared between the helper and app test targets.
/// `ConnectionValidator` delegates to these for its two-layer validation:
/// 1. Certificate chain comparison (same-developer check)
/// 2. Bundle identity requirement (allowlist check)
enum CallerValidation {
    /// Compares two DER-encoded certificate chains byte-by-byte.
    /// Returns `true` if both chains have the same length and every certificate matches.
    static func certificateDataChainsMatch(_ lhs: [Data], _ rhs: [Data]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { $0 == $1 }
    }

    /// Checks whether a caller process satisfies any of the allowed bundle identifiers
    /// by constructing a `SecRequirement` for each identifier and validating the caller's `SecCode`.
    static func callerSatisfiesAnyIdentifier(
        callerCode: SecCode,
        allowedIdentifiers: [String]
    )
        -> Bool
    {
        for identifier in allowedIdentifiers {
            var requirement: SecRequirement?
            let status = SecRequirementCreateWithString(
                "identifier \"\(identifier)\" and anchor apple generic" as CFString,
                [],
                &requirement
            )
            guard status == errSecSuccess, let requirement else {
                continue
            }
            if SecCodeCheckValidity(callerCode, [], requirement) == errSecSuccess {
                return true
            }
        }
        return false
    }

    /// Extracts DER certificate data from `SecCertificate` objects for comparison.
    static func certificateDERData(from certificates: [SecCertificate]) -> [Data] {
        certificates.map { SecCertificateCopyData($0) as Data }
    }
}
