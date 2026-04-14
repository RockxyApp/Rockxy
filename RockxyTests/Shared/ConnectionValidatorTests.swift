import Foundation
@testable import Rockxy
import Security
import Testing

// MARK: - ConnectionValidatorTests

/// Direct tests for `ConnectionValidator` — the real helper XPC caller-validation entrypoint.
///
/// `isValidCaller(_:)` delegates to `validateCaller(pid:auditTokenData:)` after extracting
/// PID and audit token from the connection. These tests exercise both the testable seam
/// and the production entrypoint on real NSXPCConnection objects.
///
/// Anonymous XPC listeners do not fire shouldAcceptNewConnection in the unit-test host
/// (no run loop pump), so server-side accept-path coverage is through the testable seam
/// with the real test-host PID — exercising the exact same CallerValidation code path.
@Suite(.serialized)
struct ConnectionValidatorTests {
    // MARK: - Allowlist Contract

    @Test("ConnectionValidator reads the expected allowlist from RockxyIdentity")
    func allowlistMatchesIdentityConfig() {
        let ids = RockxyIdentity.current.allowedCallerIdentifiers
        #expect(ids.contains("com.amunx.rockxy.community"))
        #expect(ids.contains("com.amunx.rockxy"))
    }

    // MARK: - Accept Path via validateCaller(pid:auditTokenData:)

    @Test("validateCaller accepts test host PID with no audit token")
    func acceptsTestHostPIDNoAuditToken() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let accepted = ConnectionValidator.validateCaller(pid: pid, auditTokenData: nil)
        #expect(accepted)
    }

    @Test("validateCaller accepts test host PID with invalid audit token (graceful skip)")
    func acceptsTestHostPIDWithInvalidAuditToken() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let accepted = ConnectionValidator.validateCaller(pid: pid, auditTokenData: Data([1, 2, 3]))
        #expect(accepted)
    }

    @Test("validateCaller with zero-filled audit token data still accepts valid PID")
    func validPIDWithZeroAuditTokenAccepts() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let zeroToken = Data(repeating: 0, count: MemoryLayout<audit_token_t>.size)
        let accepted = ConnectionValidator.validateCaller(pid: pid, auditTokenData: zeroToken)
        #expect(accepted)
    }

    // MARK: - Reject Path via validateCaller(pid:auditTokenData:)

    @Test("validateCaller rejects invalid PID")
    func rejectsInvalidPID() {
        let rejected = ConnectionValidator.validateCaller(pid: 0, auditTokenData: nil)
        #expect(!rejected)
    }

    @Test("validateCaller rejects invalid PID even with valid-shaped audit token")
    func rejectsInvalidPIDWithAuditToken() {
        let fakeToken = Data(repeating: 0, count: MemoryLayout<audit_token_t>.size)
        let rejected = ConnectionValidator.validateCaller(pid: 0, auditTokenData: fakeToken)
        #expect(!rejected)
    }

    // MARK: - isValidCaller(_:) Production Entrypoint

    @Test("isValidCaller rejects client-side connection (processIdentifier == 0)")
    func rejectsClientSideConnection() {
        let connection = NSXPCConnection(serviceName: "com.amunx.rockxy.test.stub")
        defer { connection.invalidate() }
        #expect(connection.processIdentifier == 0)
        #expect(!ConnectionValidator.isValidCaller(connection))
    }

    @Test("extractAuditTokenData returns nil or valid-sized data for client-side connection")
    func extractHandlesClientConnection() {
        let connection = NSXPCConnection(serviceName: "com.amunx.rockxy.test.stub")
        defer { connection.invalidate() }
        let data = ConnectionValidator.extractAuditTokenData(from: connection)
        // Client-side connections may or may not have audit token data depending
        // on the macOS version. If present, it must be the correct size.
        #expect(data == nil || data?.count == MemoryLayout<audit_token_t>.size)
    }

    // MARK: - Audit Token Data Handling

    @Test("secCodeFromAuditToken rejects undersized data")
    func auditTokenRejectsUndersized() {
        #expect(CallerValidation.secCodeFromAuditToken(Data([1, 2, 3])) == nil)
    }

    @Test("secCodeFromAuditToken rejects empty data")
    func auditTokenRejectsEmpty() {
        #expect(CallerValidation.secCodeFromAuditToken(Data()) == nil)
    }

    @Test("secCodeFromAuditToken rejects oversized data")
    func auditTokenRejectsOversized() {
        let tooLarge = Data(repeating: 0, count: MemoryLayout<audit_token_t>.size + 1)
        #expect(CallerValidation.secCodeFromAuditToken(tooLarge) == nil)
    }

    @Test("secCodeFromAuditToken rejects zero-filled token-sized data")
    func zeroFilledTokenRejected() {
        let zeroToken = Data(repeating: 0, count: MemoryLayout<audit_token_t>.size)
        #expect(CallerValidation.secCodeFromAuditToken(zeroToken) == nil)
    }

    // MARK: - PID-Based Identity Equivalence

    @Test("PID-based SecCode satisfies the same identity check as audit-token path")
    func pidCodeSatisfiesSameIdentityCheck() {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let code = CallerValidation.secCodeForPID(pid) else {
            Issue.record("Cannot get SecCode for current PID")
            return
        }
        let satisfied = CallerValidation.callerSatisfiesAnyIdentifier(
            callerCode: code,
            allowedIdentifiers: RockxyIdentity.current.allowedCallerIdentifiers
        )
        #expect(satisfied)
    }
}
