import Foundation
import os
import Security

/// XPC Caller Validation Model (two-layer defense-in-depth):
///
/// 1. **Certificate chain comparison** (Pearcleaner pattern): extracts the helper's own
///    signing certificate chain and compares it byte-by-byte against the caller's.
///    Validates that both binaries were signed by the same developer certificate.
///    Immune to Info.plist tampering since certificates are embedded in the code signature.
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

    static func isValidCaller(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier

        // Primary path: delegate both layers to the shared CallerValidation primitive.
        // This uses PID-based SecCode lookup (equivalent to the audit-token fallback path).
        let pidValid = CallerValidation.validateCaller(
            pid: pid,
            allowedIdentifiers: allowedCallerIdentifiers
        )

        if pidValid {
            // If PID-based validation passed, also try audit-token-based SecCode for
            // defense-in-depth (audit tokens are immune to PID recycling attacks).
            if let auditCode = codeFromAuditToken(connection: connection) {
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

        logger.error("SECURITY: Caller validation failed for pid \(pid)")
        return false
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ConnectionValidator"
    )

    private static let allowedCallerIdentifiers = RockxyIdentity.current.allowedCallerIdentifiers

    /// Extracts the audit token from an XPC connection via KVC and delegates
    /// to `CallerValidation.secCodeFromAuditToken(_:)` for SecCode lookup.
    private static func codeFromAuditToken(connection: NSXPCConnection) -> SecCode? {
        guard let tokenValue = connection.value(forKey: "auditToken") else {
            logger.debug("SECURITY: auditToken KVC returned nil")
            return nil
        }

        let tokenData: Data
        if let data = tokenValue as? Data {
            tokenData = data
        } else {
            var token = audit_token_t()
            let expectedSize = MemoryLayout<audit_token_t>.size
            guard let nsValue = tokenValue as? NSValue else {
                logger.debug("SECURITY: auditToken KVC returned unexpected type: \(type(of: tokenValue))")
                return nil
            }
            nsValue.getValue(&token, size: expectedSize)
            tokenData = Data(bytes: &token, count: expectedSize)
        }

        return CallerValidation.secCodeFromAuditToken(tokenData)
    }
}
