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
/// Both checks must pass, and layer 2 is mandatory UNLESS the XPC runtime is already enforcing
/// a code-signing requirement on this very connection (`IdentityEnforcement`).
///
/// - `.validatorOnly`: the audit token is the only identity check. A token that cannot be read
///   or resolved REFUSES the connection with a distinct logged `Refusal`.
/// - `.runtimeRequirementApplied`: `NSXPCConnection.setCodeSigningRequirement(_:)` (macOS 13+)
///   was applied before `resume()`, so the runtime already enforces the caller's signature
///   independent of the undocumented KVC key. An unreadable token is then logged at fault and
///   accepted, so a future macOS renaming that key degrades to "runtime enforces" instead of a
///   total helper outage. A token that IS readable and mismatches still refuses in both modes.
///
/// launchd has no authorized-clients key for `MachServices`, so there is no job-level option.
///
/// References:
/// - Pearcleaner `CodesignCheck.swift` for certificate chain comparison
/// - smjobbless `XPCServer.swift` for `SecRequirement`-based audit token validation
/// - Apple `SecCodeCheckValidity` / `SecRequirementCreateWithString` documentation
///
enum ConnectionValidator {
    // MARK: Internal

    // MARK: - Public API

    /// Why a connection was refused. Each case is logged distinctly so a refusal is diagnosable.
    enum Refusal: String, Equatable {
        /// PID-based signing/identity validation failed.
        case pidValidationFailed
        /// No audit token could be read from the connection (for example the KVC key is gone).
        case auditTokenUnavailable
        /// A token was read but did not resolve to a code object.
        case auditTokenUnresolvable
        /// The token resolved but its code does not satisfy an allowed identity.
        case auditIdentityMismatch
    }

    /// Whether the XPC runtime is already enforcing a signing requirement on the connection
    /// being validated. Deliberately has no default: callers must state it.
    enum IdentityEnforcement: Equatable {
        /// `setCodeSigningRequirement` was applied to this connection before validation.
        case runtimeRequirementApplied
        /// No runtime requirement; the audit-token check is the only identity enforcement.
        case validatorOnly
    }

    /// Production entrypoint: validates a real incoming XPC connection.
    static func isValidCaller(_ connection: NSXPCConnection, enforcement: IdentityEnforcement) -> Bool {
        let auditTokenData = extractAuditTokenData(from: connection)
        return validateCaller(
            pid: connection.processIdentifier,
            auditTokenData: auditTokenData,
            enforcement: enforcement
        )
    }

    /// Testable entrypoint: validates a caller by PID and audit token data.
    static func validateCaller(pid: pid_t, auditTokenData: Data?, enforcement: IdentityEnforcement) -> Bool {
        refusal(pid: pid, auditTokenData: auditTokenData, enforcement: enforcement) == nil
    }

    /// Returns `nil` when the caller is accepted, otherwise the specific reason it was refused.
    static func refusal(pid: pid_t, auditTokenData: Data?, enforcement: IdentityEnforcement) -> Refusal? {
        let pidValid = CallerValidation.validateCaller(
            pid: pid,
            allowedIdentifiers: allowedCallerIdentifiers
        )

        guard pidValid else {
            logger.error("SECURITY: Caller validation failed for pid \(pid)")
            return .pidValidationFailed
        }

        guard let tokenData = auditTokenData else {
            return tokenFailure(.auditTokenUnavailable, pid: pid, enforcement: enforcement)
        }

        guard let auditCode = CallerValidation.secCodeFromAuditToken(tokenData) else {
            return tokenFailure(.auditTokenUnresolvable, pid: pid, enforcement: enforcement)
        }

        let auditSatisfied = CallerValidation.callerSatisfiesAnyIdentifier(
            callerCode: auditCode,
            allowedIdentifiers: allowedCallerIdentifiers
        )
        guard auditSatisfied else {
            logger.error("SECURITY: PID validation passed but audit token check failed for pid \(pid)")
            return .auditIdentityMismatch
        }

        logger.info("SECURITY: Two-layer validation passed for pid \(pid)")
        return nil
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

    /// Handles a token that could not be read or resolved. Refuses unless the runtime is
    /// already enforcing identity, in which case it accepts (returns `nil`) and says so.
    private static func tokenFailure(
        _ reason: Refusal,
        pid: pid_t,
        enforcement: IdentityEnforcement
    )
        -> Refusal?
    {
        switch enforcement {
        case .validatorOnly:
            logger.fault(
                "SECURITY: refused pid \(pid): \(reason.rawValue), and no runtime signing requirement is applied (the undocumented token key may have changed)"
            )
            return reason
        case .runtimeRequirementApplied:
            logger.fault(
                "SECURITY: pid \(pid): \(reason.rawValue); accepted because identity rests on the XPC signing requirement applied to this connection (the undocumented token key may have changed)"
            )
            return nil
        }
    }
}
