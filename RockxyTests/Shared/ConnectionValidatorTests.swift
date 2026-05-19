import Foundation
@testable import Rockxy
import Security
import Testing

// MARK: - ConnectionValidatorTests

/// Direct tests for `ConnectionValidator` — the real helper XPC caller-validation entrypoint.
///
/// Uses `TestXPCConnection` (an NSXPCConnection subclass) to override `processIdentifier`
/// and audit-token KVC, giving full control over the accept/reject paths and the
/// Data vs NSValue audit-token branch without requiring a real XPC daemon.
@Suite(.serialized)
struct ConnectionValidatorTests {
    // MARK: - Allowlist Contract

    @Test("ConnectionValidator reads the expected allowlist from RockxyIdentity")
    func allowlistMatchesIdentityConfig() {
        guard !TestIdentity.isRunningUnderRawXCTestTool else { return }
        let ids = RockxyIdentity.current.allowedCallerIdentifiers
        for expected in TestIdentity.expectedAllowedCallerIdentifiers {
            #expect(ids.contains(expected))
        }
    }

    // MARK: - isValidCaller(_:) Accept Path

    @Test("isValidCaller accepts connection with real test-host PID")
    func acceptsConnectionWithTestHostPID() {
        guard supportsLiveConnectionValidationHost() else {
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let connection = TestXPCConnection(fakePID: pid)
        defer { connection.invalidate() }

        #expect(ConnectionValidator.isValidCaller(connection))
    }

    @Test("isValidCaller accepts connection with test-host PID and Data audit token")
    func acceptsConnectionWithDataAuditToken() {
        guard supportsLiveConnectionValidationHost() else {
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        // Zero-filled token → secCodeFromAuditToken returns nil → audit recheck skipped.
        // PID validation passes → accept.
        let token = Data(repeating: 0, count: MemoryLayout<audit_token_t>.size)
        let connection = TestXPCConnection(fakePID: pid, auditTokenValue: token)
        defer { connection.invalidate() }

        #expect(ConnectionValidator.isValidCaller(connection))
    }

    @Test("isValidCaller accepts connection with test-host PID and NSValue audit token")
    func acceptsConnectionWithNSValueAuditToken() {
        guard supportsLiveConnectionValidationHost() else {
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let nsValue = makeAuditTokenNSValue()
        let connection = TestXPCConnection(fakePID: pid, auditTokenValue: nsValue)
        defer { connection.invalidate() }

        #expect(ConnectionValidator.isValidCaller(connection))
    }

    // MARK: - isValidCaller(_:) Accept Path with Real Audit Token Revalidation

    @Test("isValidCaller exercises audit-token revalidation branch with real Data token")
    func acceptsWithRealDataAuditToken() {
        guard supportsLiveConnectionValidationHost() else {
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        guard let realToken = CallerValidation.currentProcessAuditToken() else {
            Issue.record("Cannot obtain current process audit token")
            return
        }

        // This token produces a real SecCode, so the audit revalidation branch runs:
        //   if let auditCode = secCodeFromAuditToken(tokenData) → non-nil
        //     callerSatisfiesAnyIdentifier(auditCode, ...) → true
        let connection = TestXPCConnection(fakePID: pid, auditTokenValue: realToken)
        defer { connection.invalidate() }

        #expect(ConnectionValidator.isValidCaller(connection))
    }

    @Test("isValidCaller exercises audit-token revalidation branch with real NSValue token")
    func acceptsWithRealNSValueAuditToken() {
        guard supportsLiveConnectionValidationHost() else {
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        guard let realToken = CallerValidation.currentProcessAuditToken() else {
            Issue.record("Cannot obtain current process audit token")
            return
        }

        // Wrap the real token bytes in NSValue to exercise the NSValue → Data → SecCode path.
        let nsValue = makeAuditTokenNSValue(bytes: realToken)
        let connection = TestXPCConnection(fakePID: pid, auditTokenValue: nsValue)
        defer { connection.invalidate() }

        #expect(ConnectionValidator.isValidCaller(connection))
    }

    @Test("validateCaller exercises audit-token revalidation with real token data")
    func validateCallerWithRealAuditToken() {
        guard supportsLiveConnectionValidationHost() else {
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        guard let realToken = CallerValidation.currentProcessAuditToken() else {
            Issue.record("Cannot obtain current process audit token")
            return
        }

        // secCodeFromAuditToken(realToken) → real SecCode → callerSatisfiesAnyIdentifier → true
        #expect(ConnectionValidator.validateCaller(pid: pid, auditTokenData: realToken))
    }

    @Test("secCodeFromAuditToken returns non-nil for real current-process audit token")
    func secCodeFromRealAuditTokenSucceeds() {
        guard let realToken = CallerValidation.currentProcessAuditToken() else {
            Issue.record("Cannot obtain current process audit token")
            return
        }

        let code = CallerValidation.secCodeFromAuditToken(realToken)
        #expect(code != nil)
    }

    // MARK: - isValidCaller(_:) Reject Path

    @Test("isValidCaller rejects connection with PID 0")
    func rejectsConnectionWithZeroPID() {
        let connection = TestXPCConnection(fakePID: 0)
        defer { connection.invalidate() }

        #expect(!ConnectionValidator.isValidCaller(connection))
    }

    @Test("isValidCaller rejects real client-side connection (processIdentifier == 0)")
    func rejectsRealClientSideConnection() {
        let connection = NSXPCConnection(serviceName: "com.amunx.rockxy.test.stub")
        defer { connection.invalidate() }
        #expect(connection.processIdentifier == 0)
        #expect(!ConnectionValidator.isValidCaller(connection))
    }

    // MARK: - extractAuditTokenData Branch Coverage

    @Test("extractAuditTokenData returns Data when KVC returns Data")
    func extractReturnsDataFromDataKVC() {
        let expected = Data(repeating: 0xAB, count: MemoryLayout<audit_token_t>.size)
        let connection = TestXPCConnection(fakePID: 1, auditTokenValue: expected)
        defer { connection.invalidate() }

        let result = ConnectionValidator.extractAuditTokenData(from: connection)
        #expect(result == expected)
    }

    @Test("extractAuditTokenData converts NSValue to correctly-sized Data")
    func extractConvertsNSValueToData() {
        let nsValue = makeAuditTokenNSValue()
        let connection = TestXPCConnection(fakePID: 1, auditTokenValue: nsValue)
        defer { connection.invalidate() }

        let result = ConnectionValidator.extractAuditTokenData(from: connection)
        #expect(result != nil)
        #expect(result?.count == MemoryLayout<audit_token_t>.size)
    }

    @Test("extractAuditTokenData returns nil when KVC returns nil")
    func extractReturnsNilForNoToken() {
        let connection = TestXPCConnection(fakePID: 1, auditTokenValue: nil)
        defer { connection.invalidate() }

        #expect(ConnectionValidator.extractAuditTokenData(from: connection) == nil)
    }

    @Test("extractAuditTokenData returns nil for unexpected KVC type")
    func extractReturnsNilForUnexpectedType() {
        let connection = TestXPCConnection(fakePID: 1, auditTokenValue: "not a token")
        defer { connection.invalidate() }

        #expect(ConnectionValidator.extractAuditTokenData(from: connection) == nil)
    }

    // MARK: - validateCaller(pid:auditTokenData:) Seam

    @Test("validateCaller accepts test host PID with no audit token")
    func acceptsTestHostPIDNoAuditToken() {
        guard supportsLiveConnectionValidationHost() else {
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(ConnectionValidator.validateCaller(pid: pid, auditTokenData: nil))
    }

    @Test("validateCaller rejects invalid PID")
    func rejectsInvalidPID() {
        #expect(!ConnectionValidator.validateCaller(pid: 0, auditTokenData: nil))
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

    // MARK: - PID-Based Identity Equivalence

    @Test("PID-based SecCode satisfies the same identity check as audit-token path")
    func pidCodeSatisfiesSameIdentityCheck() {
        guard supportsLiveConnectionValidationHost() else {
            return
        }

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

// MARK: - Helpers

/// Creates an NSValue that round-trips through `NSValue.getValue(_:size:)` with
/// exactly `MemoryLayout<audit_token_t>.size` bytes. The ObjC type encoding is a
/// generic fixed-size byte array (`[<size>C]`) rather than the struct-specific
/// `"{audit_token_t=[8I]}"` layout so the test is not coupled to `audit_token_t`'s
/// internal composition.
///
/// Pass real audit-token bytes via `bytes:` when the test needs the token to
/// resolve through `secCodeFromAuditToken`; omit it for the zero-filled variant,
/// which still satisfies the size contract but returns nil from that resolver.
private func makeAuditTokenNSValue(bytes: Data? = nil) -> NSValue {
    let expectedSize = MemoryLayout<audit_token_t>.size
    let source = bytes ?? Data(repeating: 0, count: expectedSize)
    precondition(source.count == expectedSize, "audit token size mismatch")
    let objCType = "[\(expectedSize)C]"
    return source.withUnsafeBytes { buffer -> NSValue in
        guard let base = buffer.baseAddress else {
            preconditionFailure("Empty audit token buffer")
        }
        return NSValue(bytes: base, objCType: objCType)
    }
}

private func supportsLiveConnectionValidationHost() -> Bool {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let selfCode = code else {
        return false
    }
    guard CallerValidation.certificatesForSelf() != nil else {
        return false
    }
    return CallerValidation.callerSatisfiesAnyIdentifier(
        callerCode: selfCode,
        allowedIdentifiers: RockxyIdentity.current.allowedCallerIdentifiers
    )
}

// MARK: - TestXPCConnection

/// NSXPCConnection subclass that overrides `processIdentifier` and the
/// `auditToken` KVC path to provide controlled test values without
/// requiring a real XPC daemon or incoming server-side connection.
private final class TestXPCConnection: NSXPCConnection {
    // MARK: Lifecycle

    init(fakePID: pid_t, auditTokenValue: Any? = nil) {
        self.fakePID = fakePID
        self.fakeAuditToken = auditTokenValue
        super.init()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Not implemented")
    }

    // MARK: Internal

    override var processIdentifier: pid_t {
        fakePID
    }

    override func value(forKey key: String) -> Any? {
        if key == "auditToken" {
            return fakeAuditToken
        }
        return super.value(forKey: key)
    }

    // MARK: Private

    private let fakePID: pid_t
    private let fakeAuditToken: Any?
}
