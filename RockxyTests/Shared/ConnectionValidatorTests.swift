import Foundation
@testable import Rockxy
import Security
import Testing

/// Direct tests for `ConnectionValidator` — the real helper XPC caller-validation entrypoint.
/// `ConnectionValidator` lives in `Shared/` so both the helper and tests can access it.
///
/// `isValidCaller(_:)` requires a real incoming XPC connection with a valid PID and
/// audit token, which cannot be synthesized in unit tests (client-side NSXPCConnection
/// reports processIdentifier == 0). These tests verify the entrypoint's structural
/// contracts and exercise the underlying validation primitives with real signed code.
struct ConnectionValidatorTests {
    // MARK: - Allowlist Contract

    @Test("ConnectionValidator reads the expected allowlist from RockxyIdentity")
    func allowlistMatchesIdentityConfig() {
        let ids = RockxyIdentity.current.allowedCallerIdentifiers
        #expect(ids.contains("com.amunx.rockxy.community"))
        #expect(ids.contains("com.amunx.rockxy"))
    }

    // MARK: - Client-Side Connection (PID = 0)

    @Test("isValidCaller rejects client-side connection (processIdentifier == 0)")
    func rejectsClientSideConnection() {
        let connection = NSXPCConnection(serviceName: "com.amunx.rockxy.test.stub")
        defer { connection.invalidate() }

        // Client-side connections have processIdentifier == 0, which fails
        // certificate extraction in CallerValidation.validateCaller(pid:).
        #expect(connection.processIdentifier == 0)
        #expect(!ConnectionValidator.isValidCaller(connection))
    }

    // MARK: - Full Validation via PID (Same Code Path as isValidCaller)

    @Test("validateCaller accepts the test host process by PID")
    func fullValidationAcceptsTestHostPID() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let allowed = RockxyIdentity.current.allowedCallerIdentifiers

        // This is the exact code path isValidCaller delegates to.
        let accepted = CallerValidation.validateCaller(pid: pid, allowedIdentifiers: allowed)
        #expect(accepted)
    }

    @Test("validateCaller rejects the test host with wrong allowlist")
    func fullValidationRejectsWrongAllowlist() {
        let pid = ProcessInfo.processInfo.processIdentifier

        let rejected = CallerValidation.validateCaller(
            pid: pid,
            allowedIdentifiers: ["com.evil.impersonator"]
        )
        #expect(!rejected)
    }

    // MARK: - Audit Token Seam Coverage

    @Test("secCodeFromAuditToken rejects invalid token data")
    func auditTokenSeamRejectsInvalid() {
        // The audit-token recheck in isValidCaller uses this exact primitive.
        #expect(CallerValidation.secCodeFromAuditToken(Data()) == nil)
        #expect(CallerValidation.secCodeFromAuditToken(Data([1, 2, 3])) == nil)
        #expect(CallerValidation.secCodeFromAuditToken(
            Data(repeating: 0, count: MemoryLayout<audit_token_t>.size + 1)
        ) == nil)
    }

    @Test("PID-based SecCode satisfies the same identity check as audit-token path")
    func pidCodeSatisfiesSameCheck() {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let code = CallerValidation.secCodeForPID(pid) else {
            Issue.record("Cannot get SecCode for current PID")
            return
        }

        // This is the same callerSatisfiesAnyIdentifier call that the audit-token
        // recheck in isValidCaller uses. If PID-based and audit-token-based SecCode
        // are for the same process, they must produce the same result.
        let satisfied = CallerValidation.callerSatisfiesAnyIdentifier(
            callerCode: code,
            allowedIdentifiers: RockxyIdentity.current.allowedCallerIdentifiers
        )
        #expect(satisfied)
    }
}
