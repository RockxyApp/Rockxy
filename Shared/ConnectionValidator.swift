import Foundation
import os
import Security

/// XPC Caller Validation Model (two-layer defense-in-depth):
///
/// 1. **Team identifier comparison**: extracts the helper's and caller's signing
///    TeamIdentifier and requires the same Apple team. This keeps one canonical helper
///    usable across Apple Development Xcode builds and Developer ID release builds.
///    When a TeamIdentifier is unavailable, validation falls back to exact certificate
///    chain comparison.
///
/// 2. **Bundle identity requirement** (Apple SecRequirement pattern): validates the caller
///    matches one of the configured Rockxy app bundle identifiers, not just any app sharing
///    the same developer certificate. Uses the connection's audit token for
///    PID-race-resistant caller identification, then checks against a `SecRequirement`
///    string for each allowed bundle identifier.
///
/// Both checks must pass for a connection to be accepted.
///
/// References:
/// - Pearcleaner `CodesignCheck.swift` for certificate chain comparison
/// - smjobbless `XPCServer.swift` for `SecRequirement`-based audit token validation
/// - Apple `SecCodeCheckValidity` / `SecRequirementCreateWithString` documentation
///
enum ConnectionValidator {
    // MARK: Internal

    // MARK: - Public API

    /// Production entrypoint: validates a real incoming XPC connection.
    static func isValidCaller(_ connection: NSXPCConnection) -> Bool {
        let auditTokenData = extractAuditTokenData(from: connection)
        return validateCaller(
            pid: connection.processIdentifier,
            auditTokenData: auditTokenData
        )
    }

    /// Testable entrypoint: validates a caller by PID and optional audit token data.
    /// The production `isValidCaller(_:)` delegates here after extracting the
    /// PID and audit token from the connection object.
    static func validateCaller(pid: pid_t, auditTokenData: Data?) -> Bool {
        let pidValid = CallerValidation.validateCaller(
            pid: pid,
            allowedIdentifiers: allowedCallerIdentifiers
        )

        guard pidValid else {
            logger.error("SECURITY: Caller validation failed for pid \(pid)")
            return false
        }

        // Defense-in-depth: if audit token data is available, recheck identity
        // via the audit-token-derived SecCode (immune to PID recycling).
        if let tokenData = auditTokenData,
           let auditCode = CallerValidation.secCodeFromAuditToken(tokenData)
        {
            let auditSatisfied = CallerValidation.callerSatisfiesAnyIdentifier(
                callerCode: auditCode,
                allowedIdentifiers: allowedCallerIdentifiers
            )
            if !auditSatisfied {
                logger.error("SECURITY: PID validation passed but audit token check failed for pid \(pid)")
                return false
            }
        }

        logger.info("SECURITY: Two-layer validation passed for pid \(pid)")
        return true
    }

    /// Extracts raw audit token data from an NSXPCConnection via KVC.
    /// Returns `nil` if the token is unavailable (client-side connections,
    /// KVC failure, or unexpected runtime type).
    static func extractAuditTokenData(from connection: NSXPCConnection) -> Data? {
        guard let tokenValue = connection.value(forKey: "auditToken") else {
            logger.debug("SECURITY: auditToken KVC returned nil")
            return nil
        }

        if let data = tokenValue as? Data {
            return data
        }

        var token = audit_token_t()
        let expectedSize = MemoryLayout<audit_token_t>.size
        guard let nsValue = tokenValue as? NSValue else {
            logger.debug("SECURITY: auditToken KVC returned unexpected type: \(type(of: tokenValue))")
            return nil
        }
        nsValue.getValue(&token, size: expectedSize)
        return Data(bytes: &token, count: expectedSize)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ConnectionValidator"
    )

    private static let allowedCallerIdentifiers = RockxyIdentity.current.allowedCallerIdentifiers
}
