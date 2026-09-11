import Foundation
@testable import Rockxy
import Security
import Testing

// MARK: - CallerValidationTests

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

    @Test("DerivedData build product detection accepts only Xcode build outputs")
    func derivedDataBuildProductDetection() {
        let debugApp = "/Users/test/Library/Developer/Xcode/DerivedData/Rockxy-abc/Build/Products/Debug/Rockxy.app/Contents/MacOS/Rockxy"
        let releaseApp = "/Users/test/Library/Developer/Xcode/DerivedData/Rockxy-abc/Build/Products/Release/Rockxy.app/Contents/MacOS/Rockxy"
        let applicationsApp = "/Applications/Rockxy.app/Contents/MacOS/Rockxy"
        let siblingPath = "/Users/test/Library/Developer/Xcode/Archives/Rockxy.app/Contents/MacOS/Rockxy"

        #expect(CallerValidation.isXcodeDerivedDataBuildProduct(path: debugApp))
        #expect(CallerValidation.isXcodeDerivedDataBuildProduct(path: releaseApp))
        #expect(!CallerValidation.isXcodeDerivedDataBuildProduct(path: applicationsApp))
        #expect(!CallerValidation.isXcodeDerivedDataBuildProduct(path: siblingPath))
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
        guard !TestIdentity.isRunningUnderRawXCTestTool else {
            return
        }
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

    // MARK: - Launch Signing Snapshot (issue #319)

    // The self side of layer 1 is frozen at launch. A helper resolves its own signature from its
    // executable path, and an app update replaces the bytes at that path while the daemon started
    // from the old ones keeps running — so a later self-lookup describes a file this process never
    // ran, and the approved helper refuses the app that installed it.

    @Test("The launch signing profile is captured once and answers identically afterwards")
    func launchProfileIsCapturedOnceAndStable() {
        guard supportsLiveCallerValidationHost() else {
            return
        }

        #expect(CallerValidation.captureLaunchSigningProfile())
        let first = CallerValidation.launchSigningProfile
        let second = CallerValidation.launchSigningProfile
        #expect(first != nil)
        #expect(first == second)
    }

    @Test("A captured launch profile authorizes a caller with no live self-lookup available")
    func capturedProfileNeedsNoLiveSelfLookup() {
        // Only the snapshot is consulted for the helper side, so the decision is unchanged when
        // the executable at this process's path can no longer be resolved or validated.
        let captured = CallerValidation.CodeSigningProfile(
            identifier: "com.amunx.rockxy.helper",
            teamIdentifier: "9YNS969KZE",
            certificateDERs: [Data([1, 2, 3])],
            executablePath: "/Applications/Rockxy.app/Contents/Library/HelperTools/RockxyHelperTool"
        )
        let caller = CallerValidation.CodeSigningProfile(
            identifier: "com.amunx.rockxy",
            teamIdentifier: "9YNS969KZE",
            certificateDERs: [Data([4, 5, 6])],
            executablePath: "/Applications/Rockxy.app/Contents/MacOS/Rockxy"
        )

        #expect(CallerValidation.signingAuthoritiesMatch(helper: captured, caller: caller))
        // Fail closed: an absent snapshot is never read as "no objection".
        #expect(!CallerValidation.signingAuthoritiesMatch(helper: nil, caller: caller))
        #expect(!CallerValidation.signingAuthoritiesMatch(helper: captured, caller: nil))
    }

    @Test("A different team or certificate chain is still rejected against the snapshot")
    func snapshotStillRejectsForeignSigners() {
        let captured = CallerValidation.CodeSigningProfile(
            identifier: "com.amunx.rockxy.helper",
            teamIdentifier: "9YNS969KZE",
            certificateDERs: [Data([1, 2, 3])],
            executablePath: "/Applications/Rockxy.app/Contents/Library/HelperTools/RockxyHelperTool"
        )
        // A different team means a different leaf certificate, so neither layer-1 test can pass.
        let foreignTeam = CallerValidation.CodeSigningProfile(
            identifier: "com.amunx.rockxy",
            teamIdentifier: "ABCDE12345",
            certificateDERs: [Data([7, 8, 9])],
            executablePath: "/Applications/Rockxy.app/Contents/MacOS/Rockxy"
        )
        #expect(!CallerValidation.signingAuthoritiesMatch(helper: captured, caller: foreignTeam))

        // With no readable team on either side, the certificate chain has to match exactly.
        let teamlessHelper = CallerValidation.CodeSigningProfile(
            identifier: "com.amunx.rockxy.helper",
            teamIdentifier: nil,
            certificateDERs: [Data([1, 2, 3])],
            executablePath: "/Applications/Rockxy.app/Contents/Library/HelperTools/RockxyHelperTool"
        )
        let sameChain = CallerValidation.CodeSigningProfile(
            identifier: "com.amunx.rockxy",
            teamIdentifier: nil,
            certificateDERs: [Data([1, 2, 3])],
            executablePath: "/Applications/Rockxy.app/Contents/MacOS/Rockxy"
        )
        let otherChain = CallerValidation.CodeSigningProfile(
            identifier: "com.amunx.rockxy",
            teamIdentifier: nil,
            certificateDERs: [Data([9, 9, 9])],
            executablePath: "/Applications/Rockxy.app/Contents/MacOS/Rockxy"
        )
        #expect(CallerValidation.signingAuthoritiesMatch(helper: teamlessHelper, caller: sameChain))
        #expect(!CallerValidation.signingAuthoritiesMatch(helper: teamlessHelper, caller: otherChain))
    }

    @Test("Ad-hoc pairing through the snapshot stays confined to Xcode build products")
    func snapshotAdHocPairingStaysLocal() {
        let adHocHelper = CallerValidation.CodeSigningProfile(
            identifier: "com.amunx.rockxy.helper",
            teamIdentifier: nil,
            certificateDERs: [],
            executablePath: "/Users/test/Library/Developer/Xcode/DerivedData/Rockxy-abc/Build/Products/Debug/Rockxy.app/Contents/Library/HelperTools/RockxyHelperTool"
        )
        let derivedDataCaller = CallerValidation.CodeSigningProfile(
            identifier: "com.amunx.rockxy",
            teamIdentifier: nil,
            certificateDERs: [],
            executablePath: "/Users/test/Library/Developer/Xcode/DerivedData/Rockxy-abc/Build/Products/Debug/Rockxy.app/Contents/MacOS/Rockxy"
        )
        let installedCaller = CallerValidation.CodeSigningProfile(
            identifier: "com.amunx.rockxy",
            teamIdentifier: nil,
            certificateDERs: [],
            executablePath: "/Applications/Rockxy.app/Contents/MacOS/Rockxy"
        )

        #expect(CallerValidation.signingAuthoritiesMatch(helper: adHocHelper, caller: derivedDataCaller))
        #expect(!CallerValidation.signingAuthoritiesMatch(helper: adHocHelper, caller: installedCaller))
    }

    @Test("The live launch snapshot authorizes this process's own live profile")
    func liveSnapshotAuthorizesLiveProfile() {
        guard supportsLiveCallerValidationHost() else {
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        guard let snapshot = CallerValidation.launchSigningProfile,
              let live = CallerValidation.signingProfile(forPID: pid) else
        {
            Issue.record("Could not read the launch snapshot or the live caller profile")
            return
        }
        #expect(CallerValidation.signingAuthoritiesMatch(helper: snapshot, caller: live))
    }

    @Test("The snapshot never substitutes for the caller's identifier check")
    func snapshotDoesNotBypassIdentifierCheck() {
        guard supportsLiveCallerValidationHost() else {
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(CallerValidation.launchSigningProfile != nil)
        // Same signer, wrong bundle identifier: layer 2 still refuses it.
        #expect(!CallerValidation.validateCaller(pid: pid, allowedIdentifiers: ["com.evil.app"]))
        #expect(CallerValidation.validateCaller(
            pid: pid,
            allowedIdentifiers: RockxyIdentity.current.allowedCallerIdentifiers
        ))
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
