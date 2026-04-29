import Foundation
@testable import Rockxy
import Security
import Testing

/// Tests for the shared caller-validation primitives used by `ConnectionValidator`.
/// These exercise the real validation logic (team/certificate comparison, bundle
/// identity requirement checking) that the helper's `isValidCaller` delegates to.
@Suite(.serialized)
struct CallerValidationTests {
    // MARK: - Certificate Chain Comparison

    @Test("Matching DER chains return true")
    func matchingChainsPass() {
        let cert1 = Data([1, 2, 3, 4])
        let cert2 = Data([5, 6, 7, 8])
        #expect(CallerValidation.certificateDataChainsMatch([cert1, cert2], [cert1, cert2]))
    }

    @Test("Mismatched leaf certificate returns false")
    func mismatchedLeafFails() {
        let cert1 = Data([1, 2, 3])
        let cert2 = Data([4, 5, 6])
        let wrong = Data([9, 9, 9])
        #expect(!CallerValidation.certificateDataChainsMatch([cert1, cert2], [wrong, cert2]))
    }

    @Test("Different chain lengths return false")
    func differentLengthsFails() {
        let cert = Data([1, 2, 3])
        #expect(!CallerValidation.certificateDataChainsMatch([cert], [cert, cert]))
    }

    @Test("Empty chains match")
    func emptyChainsMatch() {
        #expect(CallerValidation.certificateDataChainsMatch([], []))
    }

    @Test("Single certificate match")
    func singleCertMatch() {
        let cert = Data([10, 20, 30])
        #expect(CallerValidation.certificateDataChainsMatch([cert], [cert]))
    }

    @Test("Single certificate mismatch")
    func singleCertMismatch() {
        #expect(!CallerValidation.certificateDataChainsMatch([Data([1])], [Data([2])]))
    }

    // MARK: - Team Identifier Comparison

    @Test("Matching TeamIdentifiers pass with whitespace normalized")
    func matchingTeamIdentifiersPass() {
        #expect(CallerValidation.teamIdentifiersMatch(" 9YNS969KZE ", "9YNS969KZE\n"))
    }

    @Test("Different TeamIdentifiers fail")
    func differentTeamIdentifiersFail() {
        #expect(!CallerValidation.teamIdentifiersMatch("9YNS969KZE", "ABCDE12345"))
    }

    @Test("Missing TeamIdentifier fails")
    func missingTeamIdentifierFails() {
        #expect(!CallerValidation.teamIdentifiersMatch(nil, "9YNS969KZE"))
        #expect(!CallerValidation.teamIdentifiersMatch("", "9YNS969KZE"))
        #expect(!CallerValidation.teamIdentifiersMatch("9YNS969KZE", " "))
    }

    // MARK: - Live Caller Identity (TEST_HOST = signed Rockxy app)

    @Test("Live test host satisfies its own configured bundle identifiers")
    func liveTestHostSatisfiesOwnIdentity() {
        guard supportsLiveCallerValidationHost() else {
            return
        }

        // Obtain SecCode for the current process (the test host = signed Rockxy app).
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)
        guard status == errSecSuccess, let selfCode = code else {
            Issue.record("SecCodeCopySelf failed: \(status)")
            return
        }

        let allowedIDs = RockxyIdentity.current.allowedCallerIdentifiers
        #expect(!allowedIDs.isEmpty)

        let satisfied = CallerValidation.callerSatisfiesAnyIdentifier(
            callerCode: selfCode,
            allowedIdentifiers: allowedIDs
        )
        #expect(satisfied)
    }

    @Test("Unknown bundle identifier is rejected by the validation primitive")
    func unknownIdentifierRejected() {
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)
        guard status == errSecSuccess, let selfCode = code else {
            Issue.record("SecCodeCopySelf failed: \(status)")
            return
        }

        let rejected = CallerValidation.callerSatisfiesAnyIdentifier(
            callerCode: selfCode,
            allowedIdentifiers: ["com.evil.app"]
        )
        #expect(!rejected)
    }

    @Test("Empty allowlist rejects all callers")
    func emptyAllowlistRejectsAll() {
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)
        guard status == errSecSuccess, let selfCode = code else {
            Issue.record("SecCodeCopySelf failed: \(status)")
            return
        }

        let rejected = CallerValidation.callerSatisfiesAnyIdentifier(
            callerCode: selfCode,
            allowedIdentifiers: []
        )
        #expect(!rejected)
    }

    // MARK: - Config Drift Detection

    @Test("Configured allowlist contains expected Rockxy identifiers")
    func allowlistContainsExpectedIdentifiers() {
        let ids = RockxyIdentity.current.allowedCallerIdentifiers
        for expected in TestIdentity.expectedAllowedCallerIdentifiers {
            #expect(ids.contains(expected))
        }
    }

    @Test("Live certificate chain extraction produces non-empty data")
    func liveCertificateChainExtraction() {
        guard supportsLiveCallerValidationHost() else {
            return
        }

        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let selfCode = code else {
            Issue.record("SecCodeCopySelf failed")
            return
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
              let selfStatic = staticCode else
        {
            Issue.record("SecCodeCopyStaticCode failed")
            return
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            selfStatic,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        ) == errSecSuccess,
            let dict = info as? [String: Any],
            let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate] else
        {
            Issue.record("Failed to extract certificates")
            return
        }

        let derData = CallerValidation.certificateDERData(from: certs)
        #expect(!derData.isEmpty)
        #expect(derData.allSatisfy { !$0.isEmpty })

        // Self-comparison must match
        #expect(CallerValidation.certificateDataChainsMatch(derData, derData))
    }

    // MARK: - Full Two-Layer Validation (Same Path as ConnectionValidator)

    @Test("Full validateCaller accepts the test host by its own PID")
    func fullValidationAcceptsTestHost() {
        guard supportsLiveCallerValidationHost() else {
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let allowed = RockxyIdentity.current.allowedCallerIdentifiers

        let accepted = CallerValidation.validateCaller(pid: pid, allowedIdentifiers: allowed)
        #expect(accepted)
    }

    @Test("Full validateCaller rejects the test host with unknown allowlist")
    func fullValidationRejectsUnknownAllowlist() {
        let pid = ProcessInfo.processInfo.processIdentifier

        let rejected = CallerValidation.validateCaller(pid: pid, allowedIdentifiers: ["com.evil.app"])
        #expect(!rejected)
    }

    @Test("Full validateCaller rejects empty allowlist")
    func fullValidationRejectsEmptyAllowlist() {
        let pid = ProcessInfo.processInfo.processIdentifier

        let rejected = CallerValidation.validateCaller(pid: pid, allowedIdentifiers: [])
        #expect(!rejected)
    }

    // MARK: - Audit Token SecCode Path

    @Test("secCodeFromAuditToken rejects undersized data")
    func auditTokenRejectsUndersizedData() {
        let tooSmall = Data([1, 2, 3, 4])
        let code = CallerValidation.secCodeFromAuditToken(tooSmall)
        #expect(code == nil)
    }

    @Test("secCodeFromAuditToken rejects empty data")
    func auditTokenRejectsEmptyData() {
        let code = CallerValidation.secCodeFromAuditToken(Data())
        #expect(code == nil)
    }

    @Test("secCodeForPID-based code satisfies the allowlist (audit-token equivalent path)")
    func pidBasedCodeSatisfiesAllowlist() {
        guard supportsLiveCallerValidationHost() else {
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

    @Test("secCodeFromAuditToken rejects oversized data")
    func auditTokenRejectsOversizedData() {
        let tooLarge = Data(repeating: 0, count: MemoryLayout<audit_token_t>.size + 1)
        let code = CallerValidation.secCodeFromAuditToken(tooLarge)
        #expect(code == nil)
    }

    @Test("Full validateCaller rejects invalid PID")
    func fullValidationRejectsInvalidPID() {
        let allowed = RockxyIdentity.current.allowedCallerIdentifiers

        // PID 0 is the kernel — will fail certificate extraction
        let rejected = CallerValidation.validateCaller(pid: 0, allowedIdentifiers: allowed)
        #expect(!rejected)
    }
}

private func supportsLiveCallerValidationHost() -> Bool {
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
