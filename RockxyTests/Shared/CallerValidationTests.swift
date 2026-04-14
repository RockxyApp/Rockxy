import Foundation
@testable import Rockxy
import Security
import Testing

/// Tests for the shared caller-validation primitives used by `ConnectionValidator`.
/// These exercise the real validation logic (certificate chain comparison, bundle
/// identity requirement checking) that the helper's `isValidCaller` delegates to.
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

    // MARK: - Live Caller Identity (TEST_HOST = signed Rockxy app)

    @Test("Live test host satisfies its own configured bundle identifiers")
    func liveTestHostSatisfiesOwnIdentity() {
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
        #expect(ids.contains("com.amunx.rockxy.community"))
        #expect(ids.contains("com.amunx.rockxy"))
    }

    @Test("Live certificate chain extraction produces non-empty data")
    func liveCertificateChainExtraction() {
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
}
