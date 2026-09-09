import Foundation
import os
import Security

/// App-side signing diagnostics that detect certificate mismatches between the
/// running app and the installed helper binary BEFORE attempting XPC communication.
///
/// Two layers for testability:
/// 1. `Environment` protocol abstracts Security framework calls.
/// 2. `classify(_:)` is a pure function that maps environment observations to a result.
enum SigningDiagnostics {
    // MARK: Internal

    enum AppSignatureValidation: Equatable {
        case valid
        /// The executable on disk no longer matches the code already running in this process.
        case runningCodeChanged(detail: String)
        case invalid(detail: String)
    }

    // MARK: - Result

    enum Result: Equatable, Sendable {
        /// App signature is valid, helper exists, certificate chains match.
        case healthy
        /// Rockxy was replaced or updated in place while this process was still running.
        case runningCodeChanged(detail: String)
        /// App bundle code signature is invalid (e.g., missing dylib after stale Xcode build).
        case appSignatureInvalid(detail: String)
        /// App is valid, helper binary exists, but signing identities differ.
        case signingIdentityMismatch(appSigner: String, helperSigner: String)
        /// App is valid, but no helper binary exists at the expected path.
        case helperBinaryNotFound
        /// App and helper exist, but at least one binary is signed without an extractable
        /// certificate chain. This is common for Xcode/local ad-hoc helper repair paths.
        case certificateChainUnavailable
        /// An unexpected error occurred during diagnosis.
        case diagnosticError(detail: String)
    }

    // MARK: - Environment

    protocol Environment {
        /// Validate the current app bundle's code signature.
        func validateAppSignature() -> AppSignatureValidation
        /// Check whether the helper binary exists at the expected path.
        func helperBinaryExists() -> Bool
        /// Extract leaf certificate subject summary from the running app.
        func appSignerSummary() -> String?
        /// Extract leaf certificate subject summary from the installed helper binary.
        func helperSignerSummary() -> String?
        /// Extract full DER certificate chain from the running app.
        func appCertificateChain() -> [Data]?
        /// Extract full DER certificate chain from the installed helper binary.
        func helperCertificateChain() -> [Data]?
    }

    // MARK: - Live Environment

    struct LiveEnvironment: Environment {
        // MARK: Lifecycle

        init(helperExecutableURL: URL? = nil) {
            explicitHelperExecutableURL = helperExecutableURL
        }

        // MARK: Internal

        func validateAppSignature() -> AppSignatureValidation {
            var code: SecCode?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let selfCode = code else {
                return .invalid(detail: "SecCodeCopySelf failed")
            }

            let runningStatus = SecCodeCheckValidity(selfCode, [], nil)
            if runningStatus == errSecCSStaticCodeChanged {
                let description = SecCopyErrorMessageString(runningStatus, nil) as String? ?? "unknown"
                return .runningCodeChanged(
                    detail: "OSStatus \(runningStatus) (\(description))"
                )
            }
            if runningStatus != errSecSuccess {
                let description = SecCopyErrorMessageString(runningStatus, nil) as String? ?? "unknown"
                return .invalid(
                    detail: "Code signature invalid: OSStatus \(runningStatus) (\(description))"
                )
            }

            var staticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
                  let selfStatic = staticCode else
            {
                return .invalid(detail: "SecCodeCopyStaticCode failed")
            }
            let status = SecStaticCodeCheckValidity(selfStatic, SecCSFlags([]), nil)
            if status != errSecSuccess {
                let desc = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
                return .invalid(
                    detail: "Code signature invalid: OSStatus \(status) (\(desc))"
                )
            }
            return .valid
        }

        func helperBinaryExists() -> Bool {
            resolvedHelperExecutableURL != nil
        }

        func appSignerSummary() -> String? {
            guard let chain = appCertificateChain(), let leafDER = chain.first else {
                return nil
            }
            return summaryFromDER(leafDER)
        }

        func helperSignerSummary() -> String? {
            guard let chain = helperCertificateChain(), let leafDER = chain.first else {
                return nil
            }
            return summaryFromDER(leafDER)
        }

        func appCertificateChain() -> [Data]? {
            certificateChainForSelf()
        }

        func helperCertificateChain() -> [Data]? {
            guard let helperURL = resolvedHelperExecutableURL else {
                return nil
            }

            return certificateChainForURL(helperURL)
        }

        // MARK: Private

        private let explicitHelperExecutableURL: URL?

        private var resolvedHelperExecutableURL: URL? {
            if let explicitHelperExecutableURL {
                return FileManager.default.isExecutableFile(atPath: explicitHelperExecutableURL.path)
                    ? explicitHelperExecutableURL
                    : nil
            }
            return helperExecutableCandidates.first { candidateURL in
                FileManager.default.isExecutableFile(atPath: candidateURL.path)
            }
        }

        private var helperExecutableCandidates: [URL] {
            SigningDiagnostics.helperExecutableCandidates()
        }

        private func certificateChainForSelf() -> [Data]? {
            var code: SecCode?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let selfCode = code else {
                return nil
            }
            var staticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
                  let sc = staticCode else
            {
                return nil
            }
            return extractCertificateDERs(from: sc)
        }

        private func certificateChainForURL(_ url: URL) -> [Data]? {
            var staticCode: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
                  let sc = staticCode else
            {
                return nil
            }
            guard SecStaticCodeCheckValidity(sc, SecCSFlags([]), nil) == errSecSuccess else {
                return nil
            }
            return extractCertificateDERs(from: sc)
        }

        private func extractCertificateDERs(from staticCode: SecStaticCode) -> [Data]? {
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &info
            ) == errSecSuccess,
                let dict = info as? [String: Any],
                let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
                !certs.isEmpty else
            {
                return nil
            }
            return certs.map { SecCertificateCopyData($0) as Data }
        }

        private func summaryFromDER(_ der: Data) -> String? {
            guard let cert = SecCertificateCreateWithData(nil, der as CFData) else {
                return nil
            }
            return SecCertificateCopySubjectSummary(cert) as String?
        }
    }

    nonisolated static func helperExecutableCandidates(
        bundledHelperURL: URL = Bundle.main.bundleURL
            .appendingPathComponent(HelperManager.bundledHelperBinaryRelativePath, isDirectory: false),
        legacyInstalledHelperURL: URL = URL(
            fileURLWithPath: "/Library/PrivilegedHelperTools/\(RockxyIdentity.current.helperBundleIdentifier)"
        )
    )
        -> [URL]
    {
        if bundledHelperURL == legacyInstalledHelperURL {
            return [legacyInstalledHelperURL]
        }

        return [legacyInstalledHelperURL, bundledHelperURL]
    }

    // MARK: - Classification

    /// Pure decision function. Maps environment observations to a diagnostic result.
    static func classify(_ env: some Environment) -> Result {
        switch env.validateAppSignature() {
        case .valid:
            break
        case let .runningCodeChanged(detail):
            return .runningCodeChanged(detail: detail)
        case let .invalid(detail):
            return .appSignatureInvalid(detail: detail)
        }

        guard env.helperBinaryExists() else {
            return .helperBinaryNotFound
        }

        guard let appChain = env.appCertificateChain(),
              let helperChain = env.helperCertificateChain() else
        {
            return .certificateChainUnavailable
        }

        let appSigner = env.appSignerSummary() ?? "unknown"
        let helperSigner = env.helperSignerSummary() ?? "unknown"

        guard appChain.count == helperChain.count else {
            return .signingIdentityMismatch(
                appSigner: appSigner,
                helperSigner: helperSigner
            )
        }

        for index in appChain.indices {
            if appChain[index] != helperChain[index] {
                return .signingIdentityMismatch(
                    appSigner: appSigner,
                    helperSigner: helperSigner
                )
            }
        }

        return .healthy
    }

    // MARK: - Convenience

    /// Run diagnostics using the live Security framework environment.
    static func diagnose(helperExecutableURL: URL? = nil) -> Result {
        let result = classify(LiveEnvironment(helperExecutableURL: helperExecutableURL))
        switch result {
        case .healthy:
            logger.debug("Signing diagnostics: healthy")
        case let .runningCodeChanged(detail):
            logger.warning("Signing diagnostics: running code changed — \(detail)")
        case let .appSignatureInvalid(detail):
            logger.warning("Signing diagnostics: app signature invalid — \(detail)")
        case let .signingIdentityMismatch(app, helper):
            logger.warning(
                "Signing diagnostics: identity mismatch — app=\(app) helper=\(helper)"
            )
        case .helperBinaryNotFound:
            logger.debug("Signing diagnostics: helper binary not found")
        case .certificateChainUnavailable:
            logger.debug("Signing diagnostics: certificate chain unavailable for comparison")
        case let .diagnosticError(detail):
            logger.error("Signing diagnostics: error — \(detail)")
        }
        return result
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "SigningDiagnostics"
    )
}
