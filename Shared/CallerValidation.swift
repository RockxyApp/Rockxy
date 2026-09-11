import Foundation
import Security

/// Testable caller-validation primitives shared between the helper and app test targets.
/// `ConnectionValidator` delegates to these for its two-layer validation:
/// 1. Team identifier comparison (same-developer check), with exact certificate
///    chain comparison as a fallback when the signing team cannot be read.
/// 2. Bundle identity requirement (allowlist check)
///
/// Layer 1 compares every caller against a *snapshot* of this process's own signing profile,
/// taken once at launch. `SecCodeCopySelf` ultimately resolves to a path on disk, and an app
/// update replaces the bytes at that path while the daemon launchd started from the old ones
/// keeps running. A self-lookup performed after that describes the new file — or fails validity
/// outright — so an already-approved helper ends up rejecting the very app that installed it.
/// Only the self side is frozen: each caller is still resolved and validated live, against the
/// current team identifier or certificate chain, the exact allowed bundle identifiers, and its
/// own audit token.
enum CallerValidation {
    // MARK: Internal

    /// The signing facts read out of one process's code signature.
    struct CodeSigningProfile: Equatable {
        let identifier: String?
        let teamIdentifier: String?
        let certificateDERs: [Data]
        let executablePath: String?

        var isAdHoc: Bool {
            teamIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                && certificateDERs.isEmpty
        }
    }

    /// This process's own signing profile as it was when the snapshot was first taken, or `nil`
    /// if it could not be read at all.
    ///
    /// Resolved exactly once, on first access. The helper primes it from `main.swift` before its
    /// XPC listener is resumed, which is what keeps the snapshot ahead of any bundle replacement.
    static var launchSigningProfile: CodeSigningProfile? {
        capturedLaunchSigningProfile
    }

    /// Captures this process's own signing profile before anything can replace the executable at
    /// its path. Returns `false` when the snapshot could not be taken — in which case validation
    /// fails closed, because a process that cannot identify itself has nothing to compare a
    /// caller against.
    @discardableResult
    static func captureLaunchSigningProfile() -> Bool {
        capturedLaunchSigningProfile != nil
    }

    /// Compares two DER-encoded certificate chains byte-by-byte.
    /// Returns `true` if both chains have the same length and every certificate matches.
    static func certificateDataChainsMatch(_ lhs: [Data], _ rhs: [Data]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { $0 == $1 }
    }

    static func teamIdentifiersMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = lhs?.trimmingCharacters(in: .whitespacesAndNewlines),
              let rhs = rhs?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lhs.isEmpty,
              !rhs.isEmpty else
        {
            return false
        }
        return lhs == rhs
    }

    /// Checks whether a caller process satisfies any of the allowed bundle identifiers
    /// by constructing a `SecRequirement` for each identifier and validating the caller's `SecCode`.
    static func callerSatisfiesAnyIdentifier(
        callerCode: SecCode,
        allowedIdentifiers: [String]
    )
        -> Bool
    {
        for identifier in allowedIdentifiers {
            if callerSatisfiesAppleGenericIdentifier(callerCode: callerCode, identifier: identifier) {
                return true
            }
            if callerSatisfiesLocalXcodeAdHocIdentifier(callerCode: callerCode, identifier: identifier) {
                return true
            }
        }
        return false
    }

    /// Extracts DER certificate data from `SecCertificate` objects for comparison.
    static func certificateDERData(from certificates: [SecCertificate]) -> [Data] {
        certificates.map { SecCertificateCopyData($0) as Data }
    }

    // MARK: - Full Caller Validation by PID

    /// Performs the same two-layer validation as `ConnectionValidator.isValidCaller(_:)`
    /// but accepts a `pid_t` directly, making it testable without a real `NSXPCConnection`.
    ///
    /// Layer 1: Compares the launch snapshot of this process's signing TeamIdentifier against the
    ///          caller's, read live (same-developer check). If either team is unavailable,
    ///          falls back to exact certificate-chain comparison.
    /// Layer 2: Constructs `SecRequirement` for each allowed identifier and validates
    ///          the caller's `SecCode` against them (bundle identity check).
    static func validateCaller(pid: pid_t, allowedIdentifiers: [String]) -> Bool {
        guard let selfProfile = launchSigningProfile else {
            // Fail closed: without a usable self-identity there is nothing to compare against.
            return false
        }

        guard let callerCode = secCodeForPID(pid),
              let callerProfile = signingProfile(from: callerCode) else
        {
            return false
        }

        guard signingAuthoritiesMatch(helper: selfProfile, caller: callerProfile) else {
            return false
        }

        return callerSatisfiesAnyIdentifier(callerCode: callerCode, allowedIdentifiers: allowedIdentifiers)
    }

    /// Whether a caller signed like `caller` may talk to a process signed like `helper`.
    ///
    /// Both profiles must be present: a missing one is an absence of evidence, never a pass.
    static func signingAuthoritiesMatch(
        helper: CodeSigningProfile?,
        caller: CodeSigningProfile?
    )
        -> Bool
    {
        guard let helper, let caller else {
            return false
        }

        if teamIdentifiersMatch(helper.teamIdentifier, caller.teamIdentifier) {
            return true
        }

        if !helper.certificateDERs.isEmpty,
           !caller.certificateDERs.isEmpty
        {
            return certificateDataChainsMatch(helper.certificateDERs, caller.certificateDERs)
        }

        return localXcodeAdHocPair(helper: helper, caller: caller)
    }

    /// Reads a process's signing profile from its `SecCode`, validating the signature first.
    static func signingProfile(from code: SecCode) -> CodeSigningProfile? {
        guard let dict = signingInformation(from: code) else {
            return nil
        }

        let certs = certificates(from: dict) ?? []
        let executableURL = dict[kSecCodeInfoMainExecutable as String] as? URL
        return CodeSigningProfile(
            identifier: dict[kSecCodeInfoIdentifier as String] as? String,
            teamIdentifier: dict[kSecCodeInfoTeamIdentifier as String] as? String,
            certificateDERs: certificateDERData(from: certs),
            executablePath: executableURL?.path
        )
    }

    static func signingProfile(forPID pid: pid_t) -> CodeSigningProfile? {
        guard let code = secCodeForPID(pid) else {
            return nil
        }
        return signingProfile(from: code)
    }

    // MARK: - Security Framework Helpers

    static func secCodeForPID(_ pid: pid_t) -> SecCode? {
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess else {
            return nil
        }
        return code
    }

    static func secCodeForSelf() -> SecCode? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess else {
            return nil
        }
        return code
    }

    static func isXcodeDerivedDataBuildProduct(path: String) -> Bool {
        path.contains("/Library/Developer/Xcode/DerivedData/")
            && path.contains("/Build/Products/")
    }

    /// Obtains a `SecCode` from raw audit token data (32-byte `audit_token_t`).
    /// Returns nil if the data size is wrong or the Security framework rejects it.
    static func secCodeFromAuditToken(_ tokenData: Data) -> SecCode? {
        guard tokenData.count == MemoryLayout<audit_token_t>.size else {
            return nil
        }
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess else {
            return nil
        }
        return code
    }

    /// Returns the raw audit token bytes for the current process via `task_info`.
    /// Used by tests to obtain a real token that `secCodeFromAuditToken` can resolve.
    static func currentProcessAuditToken() -> Data? {
        var token = audit_token_t()
        var size = mach_msg_type_number_t(
            MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &token) { tokenPtr in
            tokenPtr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), intPtr, &size)
            }
        }
        guard kr == KERN_SUCCESS else {
            return nil
        }
        return withUnsafeBytes(of: token) { Data($0) }
    }

    static func certificatesForSelf() -> [SecCertificate]? {
        guard let selfCode = secCodeForSelf() else {
            return nil
        }
        return certificatesFromCode(selfCode)
    }

    static func certificatesForProcess(pid: pid_t) -> [SecCertificate]? {
        guard let code = secCodeForPID(pid) else {
            return nil
        }
        return certificatesFromCode(code)
    }

    // MARK: Private

    /// Taken once, on first access, and never recomputed. See the type documentation for why a
    /// later self-lookup is not equivalent.
    private static let capturedLaunchSigningProfile: CodeSigningProfile? = {
        guard let selfCode = secCodeForSelf() else {
            return nil
        }
        return signingProfile(from: selfCode)
    }()

    private static func certificatesFromCode(_ code: SecCode) -> [SecCertificate]? {
        guard let dict = signingInformation(from: code),
              let certs = certificates(from: dict),
              !certs.isEmpty else
        {
            return nil
        }
        return certs
    }

    private static func certificates(from signingInfo: [String: Any]) -> [SecCertificate]? {
        signingInfo[kSecCodeInfoCertificates as String] as? [SecCertificate]
    }

    private static func callerSatisfiesAppleGenericIdentifier(
        callerCode: SecCode,
        identifier: String
    )
        -> Bool
    {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            "identifier \"\(identifier)\" and anchor apple generic" as CFString,
            [],
            &requirement
        )
        guard status == errSecSuccess, let requirement else {
            return false
        }
        return SecCodeCheckValidity(callerCode, [], requirement) == errSecSuccess
    }

    private static func callerSatisfiesLocalXcodeAdHocIdentifier(
        callerCode: SecCode,
        identifier: String
    )
        -> Bool
    {
        guard let profile = signingProfile(from: callerCode),
              profile.isAdHoc,
              profile.identifier == identifier,
              let executablePath = profile.executablePath,
              isXcodeDerivedDataBuildProduct(path: executablePath) else
        {
            return false
        }
        return true
    }

    private static func localXcodeAdHocPair(
        helper: CodeSigningProfile,
        caller: CodeSigningProfile
    )
        -> Bool
    {
        guard helper.isAdHoc,
              caller.isAdHoc,
              let callerPath = caller.executablePath else
        {
            return false
        }
        return isXcodeDerivedDataBuildProduct(path: callerPath)
    }

    private static func signingInformation(from code: SecCode) -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let sc = staticCode else
        {
            return nil
        }
        guard SecStaticCodeCheckValidity(sc, SecCSFlags([]), nil) == errSecSuccess else {
            return nil
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            sc, SecCSFlags(rawValue: kSecCSSigningInformation), &info
        ) == errSecSuccess,
            let dict = info as? [String: Any] else
        {
            return nil
        }
        return dict
    }
}
