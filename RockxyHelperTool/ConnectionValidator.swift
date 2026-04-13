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

        // Layer 1: Certificate chain comparison (same-developer check)
        guard let selfCertificates = certificatesForSelf() else {
            logger.error("SECURITY: Unable to extract helper's own signing certificates")
            return false
        }

        guard let callerCertificates = certificatesForProcess(pid: pid) else {
            logger.error("SECURITY: Unable to extract caller signing certificates for pid \(pid)")
            return false
        }

        guard certificateChainsMatch(selfCertificates, callerCertificates) else {
            logger.error("SECURITY: Certificate chain mismatch for pid \(pid) — rejecting connection")
            return false
        }

        // Layer 2: Bundle identity requirement (narrower identity check)
        guard validateCallerIdentity(connection: connection) else {
            logger.error("SECURITY: Bundle identity validation failed for pid \(pid) — rejecting connection")
            return false
        }

        logger.info("SECURITY: Two-layer validation passed for pid \(pid)")
        return true
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ConnectionValidator"
    )

    private static let allowedCallerIdentifiers = RockxyIdentity.current.allowedCallerIdentifiers

    // MARK: - Bundle Identity Validation

    /// Validates that the caller satisfies the configured bundle identity requirement.
    ///
    /// Uses the connection's audit token (via PID fallback, since `NSXPCConnection.auditToken`
    /// is not public API) to obtain a `SecCode` reference, then checks it against a
    /// `SecRequirement` that pins both the bundle identifier and Apple certificate anchor.
    ///
    /// This is narrower than certificate-chain comparison: even if another app is signed
    /// with the same developer certificate, it will be rejected unless its bundle identifier
    /// matches one of the configured allowlist entries.
    private static func validateCallerIdentity(connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier

        // Obtain SecCode for the caller process.
        // Prefer audit token (race-resistant) over PID when available.
        guard let callerCode = codeForConnection(connection) else {
            logger.error("SECURITY: Failed to obtain SecCode for pid \(pid)")
            return false
        }

        guard !allowedCallerIdentifiers.isEmpty else {
            logger.error("SECURITY: No allowed caller identifiers configured")
            return false
        }

        for identifier in allowedCallerIdentifiers {
            var requirement: SecRequirement?
            let reqStatus = SecRequirementCreateWithString(
                "identifier \"\(identifier)\" and anchor apple generic" as CFString,
                [],
                &requirement
            )

            guard reqStatus == errSecSuccess, let requirement else {
                logger.error(
                    "SECURITY: Failed to create SecRequirement for \(identifier) (status: \(reqStatus))"
                )
                continue
            }

            let validityStatus = SecCodeCheckValidity(callerCode, [], requirement)
            if validityStatus == errSecSuccess {
                logger.debug("SECURITY: Bundle identity requirement satisfied for pid \(pid)")
                return true
            }
        }

        logger.error("SECURITY: Caller pid \(pid) does not satisfy any allowed bundle identifier")
        return false
    }

    /// Obtains a `SecCode` reference for the XPC connection's caller.
    ///
    /// Attempts audit-token-based lookup first (immune to PID recycling attacks),
    /// falling back to PID-based lookup if the audit token is unavailable.
    private static func codeForConnection(_ connection: NSXPCConnection) -> SecCode? {
        // Try audit token first — more secure than PID because it is unique per process
        // lifetime and cannot be recycled. Accessed via KVC since the public property
        // is only available in macOS 15+ SDK. Falls back to PID if KVC fails.
        if let code = codeFromAuditToken(connection: connection) {
            return code
        }

        // Fallback: PID-based lookup. Less secure (PID recycling possible in theory)
        // but still validated by the certificate chain check in layer 1.
        logger.debug("SECURITY: Audit token unavailable, falling back to PID-based code lookup")
        return codeFromPID(connection.processIdentifier)
    }

    /// Attempts to obtain a `SecCode` using the connection's audit token.
    ///
    /// `NSXPCConnection` stores the audit token internally but the property was not
    /// publicly exposed until macOS 15 / Xcode 16 SDK. We access it via KVC as a
    /// `Data`-valued property, which has been stable since macOS 10.7. If KVC access
    /// fails (e.g., Apple removes or renames the property), we return nil and the
    /// caller falls back to PID-based lookup.
    private static func codeFromAuditToken(connection: NSXPCConnection) -> SecCode? {
        // KVC access to the audit token. The underlying Obj-C property wraps
        // audit_token_t in an NSData when accessed via valueForKey:.
        guard let tokenValue = connection.value(forKey: "auditToken") else {
            logger.debug("SECURITY: auditToken KVC returned nil")
            return nil
        }

        // The KVC result may come back as Data (NSData) containing the raw audit_token_t bytes.
        let tokenData: Data
        if let data = tokenValue as? Data {
            tokenData = data
        } else {
            // If the runtime returns audit_token_t as a struct wrapped in NSValue,
            // extract its bytes. This branch handles future SDK changes gracefully.
            var token = audit_token_t()
            let expectedSize = MemoryLayout<audit_token_t>.size
            guard let nsValue = tokenValue as? NSValue else {
                logger.debug("SECURITY: auditToken KVC returned unexpected type: \(type(of: tokenValue))")
                return nil
            }
            nsValue.getValue(&token, size: expectedSize)
            tokenData = Data(bytes: &token, count: expectedSize)
        }

        guard tokenData.count == MemoryLayout<audit_token_t>.size else {
            logger.debug("SECURITY: auditToken data size mismatch: \(tokenData.count)")
            return nil
        }

        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary

        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)

        guard status == errSecSuccess, let code else {
            logger.debug("SecCodeCopyGuestWithAttributes (audit token) failed: \(status)")
            return nil
        }

        return code
    }

    /// Obtains a `SecCode` using the caller's PID.
    private static func codeFromPID(_ pid: pid_t) -> SecCode? {
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)

        guard status == errSecSuccess, let code else {
            logger.debug("SecCodeCopyGuestWithAttributes (PID) failed for pid \(pid): \(status)")
            return nil
        }

        return code
    }

    // MARK: - Certificate Extraction

    private static func certificatesForSelf() -> [SecCertificate]? {
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)

        guard status == errSecSuccess, let selfCode = code else {
            logger.error("SecCodeCopySelf failed: \(status)")
            return nil
        }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(selfCode, [], &staticCode)

        guard staticStatus == errSecSuccess, let selfStaticCode = staticCode else {
            logger.error("SecCodeCopyStaticCode failed for self: \(staticStatus)")
            return nil
        }

        return extractCertificates(from: selfStaticCode, label: "self")
    }

    private static func certificatesForProcess(pid: pid_t) -> [SecCertificate]? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)

        guard status == errSecSuccess, let guestCode = code else {
            logger.error("SecCodeCopyGuestWithAttributes failed for pid \(pid): \(status)")
            return nil
        }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(guestCode, [], &staticCode)

        guard staticStatus == errSecSuccess, let guestStaticCode = staticCode else {
            logger.error("SecCodeCopyStaticCode failed for pid \(pid): \(staticStatus)")
            return nil
        }

        return extractCertificates(from: guestStaticCode, label: "pid \(pid)")
    }

    private static func extractCertificates(
        from staticCode: SecStaticCode,
        label: String
    )
        -> [SecCertificate]?
    {
        let validityStatus = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags([]),
            nil
        )

        guard validityStatus == errSecSuccess else {
            let statusDesc = SecCopyErrorMessageString(validityStatus, nil) as String? ?? "unknown"
            logger.error(
                "SecStaticCodeCheckValidity failed for \(label): OSStatus \(validityStatus) (\(statusDesc))"
            )
            return nil
        }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )

        guard infoStatus == errSecSuccess, let info = information as? [String: Any] else {
            logger.error("SecCodeCopySigningInformation failed for \(label): \(infoStatus)")
            return nil
        }

        guard let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              !certificates.isEmpty else
        {
            logger.error("No certificates found in signing information for \(label)")
            return nil
        }

        return certificates
    }

    // MARK: - Certificate Comparison

    private static func certificateChainsMatch(
        _ lhs: [SecCertificate],
        _ rhs: [SecCertificate]
    )
        -> Bool
    {
        guard lhs.count == rhs.count else {
            logger.debug("Certificate chain length mismatch: \(lhs.count) vs \(rhs.count)")
            return false
        }

        for index in lhs.indices {
            let lhsData = SecCertificateCopyData(lhs[index]) as Data
            let rhsData = SecCertificateCopyData(rhs[index]) as Data

            if lhsData != rhsData {
                let lhsSummary = SecCertificateCopySubjectSummary(lhs[index]) as String? ?? "unknown"
                let rhsSummary = SecCertificateCopySubjectSummary(rhs[index]) as String? ?? "unknown"
                logger.debug(
                    "Certificate mismatch at index \(index): self=\"\(lhsSummary)\" caller=\"\(rhsSummary)\""
                )
                return false
            }
        }

        return true
    }
}
