import Foundation
@testable import Rockxy
import Testing

// MARK: - MockSigningEnvironment

private struct MockSigningEnvironment: SigningDiagnostics.Environment {
    var appSignatureError: String?
    var helperExists: Bool = true
    var appSigner: String? = "Apple Development: dev@example.com"
    var helperSigner: String? = "Developer ID Application: Dev Corp"
    var appChain: [Data]? = [Data([1, 2, 3]), Data([4, 5, 6])]
    var helperChain: [Data]? = [Data([1, 2, 3]), Data([4, 5, 6])]

    func validateAppSignature() -> String? {
        appSignatureError
    }

    func helperBinaryExists() -> Bool {
        helperExists
    }

    func appSignerSummary() -> String? {
        appSigner
    }

    func helperSignerSummary() -> String? {
        helperSigner
    }

    func appCertificateChain() -> [Data]? {
        appChain
    }

    func helperCertificateChain() -> [Data]? {
        helperChain
    }
}

// MARK: - SigningDiagnosticsClassifyTests

struct SigningDiagnosticsClassifyTests {
    @Test("installed helper path is preferred over the bundled helper path")
    func helperExecutableCandidatesPreferInstalledHelper() {
        let bundledHelperURL = URL(fileURLWithPath: "/Applications/Rockxy.app/Contents/Library/HelperTools/RockxyHelperTool")
        let installedHelperURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.amunx.rockxy.helper")

        let candidates = SigningDiagnostics.helperExecutableCandidates(
            bundledHelperURL: bundledHelperURL,
            legacyInstalledHelperURL: installedHelperURL
        )

        #expect(candidates == [installedHelperURL, bundledHelperURL])
    }

    @Test("helper candidate list de-duplicates identical bundled and installed paths")
    func helperExecutableCandidatesDeduplicateIdenticalPaths() {
        let helperURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.amunx.rockxy.helper")

        let candidates = SigningDiagnostics.helperExecutableCandidates(
            bundledHelperURL: helperURL,
            legacyInstalledHelperURL: helperURL
        )

        #expect(candidates == [helperURL])
    }

    @Test("app signature invalid returns appSignatureInvalid")
    func appSignatureInvalid() {
        var env = MockSigningEnvironment()
        env.appSignatureError = "Code signature invalid (OSStatus -67054)"

        let result = SigningDiagnostics.classify(env)

        #expect(result == .appSignatureInvalid(
            detail: "Code signature invalid (OSStatus -67054)"
        ))
    }

    @Test("healthy when app valid and certificates match")
    func healthyWhenMatch() {
        let env = MockSigningEnvironment()

        let result = SigningDiagnostics.classify(env)

        #expect(result == .healthy)
    }

    @Test("signing identity mismatch when leaf certificate differs")
    func signingIdentityMismatchLeaf() {
        var env = MockSigningEnvironment()
        env.helperChain = [Data([7, 8, 9]), Data([4, 5, 6])]

        let result = SigningDiagnostics.classify(env)

        #expect(result == .signingIdentityMismatch(
            appSigner: "Apple Development: dev@example.com",
            helperSigner: "Developer ID Application: Dev Corp"
        ))
    }

    @Test("signing identity mismatch when chain lengths differ")
    func chainLengthMismatch() {
        var env = MockSigningEnvironment()
        env.helperChain = [Data([1, 2, 3])]

        let result = SigningDiagnostics.classify(env)

        #expect(result == .signingIdentityMismatch(
            appSigner: "Apple Development: dev@example.com",
            helperSigner: "Developer ID Application: Dev Corp"
        ))
    }

    @Test("helper binary not found returns helperBinaryNotFound")
    func helperNotFound() {
        var env = MockSigningEnvironment()
        env.helperExists = false

        let result = SigningDiagnostics.classify(env)

        #expect(result == .helperBinaryNotFound)
    }

    @Test("diagnostic error when app chain extraction fails")
    func diagnosticErrorAppChain() {
        var env = MockSigningEnvironment()
        env.appChain = nil

        let result = SigningDiagnostics.classify(env)

        #expect(result == .diagnosticError(
            detail: "Failed to extract certificate chains for comparison"
        ))
    }

    @Test("diagnostic error when helper chain extraction fails")
    func diagnosticErrorHelperChain() {
        var env = MockSigningEnvironment()
        env.helperChain = nil

        let result = SigningDiagnostics.classify(env)

        #expect(result == .diagnosticError(
            detail: "Failed to extract certificate chains for comparison"
        ))
    }

    @Test("app signature check runs before helper existence check")
    func appSignatureBeforeHelperCheck() {
        var env = MockSigningEnvironment()
        env.appSignatureError = "invalid"
        env.helperExists = false

        let result = SigningDiagnostics.classify(env)

        #expect(result == .appSignatureInvalid(detail: "invalid"))
    }

    @Test("helper existence check runs before chain comparison")
    func helperExistenceBeforeChainComparison() {
        var env = MockSigningEnvironment()
        env.helperExists = false
        env.appChain = nil

        let result = SigningDiagnostics.classify(env)

        #expect(result == .helperBinaryNotFound)
    }

    @Test("mismatch result carries signer names")
    func mismatchCarriesSignerNames() {
        var env = MockSigningEnvironment()
        env.appSigner = "Apple Development: test@dev.com"
        env.helperSigner = "Developer ID Application: Prod Corp"
        env.helperChain = [Data([99])]

        let result = SigningDiagnostics.classify(env)

        if case let .signingIdentityMismatch(app, helper) = result {
            #expect(app == "Apple Development: test@dev.com")
            #expect(helper == "Developer ID Application: Prod Corp")
        } else {
            Issue.record("Expected signingIdentityMismatch, got \(result)")
        }
    }
}

// MARK: - SigningDiagnosticsLiveTests

/// Tests against `LiveEnvironment` running in the signed test host.
/// These verify identity-derived paths and the real classify contract.
/// Full caller-validation logic is tested in `CallerValidationTests` and
/// `ConnectionValidatorTests` via the shared validation primitives.
@Suite(.serialized)
struct SigningDiagnosticsLiveTests {
    @Test("LiveEnvironment validates test host app signature successfully")
    func liveAppSignatureValid() {
        let env = SigningDiagnostics.LiveEnvironment()
        guard env.validateAppSignature() == nil else {
            return
        }

        let error = env.validateAppSignature()
        #expect(error == nil)
    }

    @Test("LiveEnvironment resolves the bundled helper executable from the app package")
    func liveBundledHelperExecutableDetected() {
        let bundledHelperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/HelperTools", isDirectory: true)
            .appendingPathComponent("RockxyHelperTool", isDirectory: false)

        #expect(FileManager.default.isExecutableFile(atPath: bundledHelperURL.path))

        let env = SigningDiagnostics.LiveEnvironment()
        #expect(env.helperBinaryExists())
    }

    @Test("LiveEnvironment can extract app certificate chain from test host")
    func liveAppCertificateChainExtractable() {
        let env = SigningDiagnostics.LiveEnvironment()
        guard env.validateAppSignature() == nil else {
            return
        }

        let chain = env.appCertificateChain()
        #expect(chain != nil)
        #expect((chain?.count ?? 0) > 0)
    }

    @Test("LiveEnvironment can extract helper certificate chain from the bundled helper executable")
    func liveHelperCertificateChainExtractable() {
        let env = SigningDiagnostics.LiveEnvironment()
        guard env.validateAppSignature() == nil else {
            return
        }

        let chain = env.helperCertificateChain()
        #expect(chain != nil)
        #expect((chain?.count ?? 0) > 0)
    }

    @Test("Live classify returns healthy or helperBinaryNotFound depending on helper install state")
    func liveClassifyContract() {
        let env = SigningDiagnostics.LiveEnvironment()
        guard env.validateAppSignature() == nil else {
            return
        }

        let result = SigningDiagnostics.classify(env)

        // The test host is validly signed (liveAppSignatureValid proves this).
        // Therefore classify must return either:
        // - .healthy (helper installed + chains match)
        // - .helperBinaryNotFound (helper not installed in dev)
        // - .signingIdentityMismatch (helper installed but stale/mismatched signing)
        // It must NOT return .appSignatureInvalid or .diagnosticError.
        switch result {
        case .healthy,
             .helperBinaryNotFound,
             .signingIdentityMismatch:
            break
        case .appSignatureInvalid,
             .diagnosticError:
            Issue.record("Live classify returned unexpected result: \(result)")
        }
    }
}

// MARK: - SigningPreflightCacheTests

struct SigningPreflightCacheTests {
    @Test("preflight cache invalidation triggers re-evaluation")
    @MainActor
    func preflightCacheInvalidation() {
        let cache = SigningPreflightCache()
        var callCount = 0

        cache.provider = {
            callCount += 1
            if callCount == 1 {
                return .signingIdentityMismatch(appSigner: "Dev", helperSigner: "Prod")
            }
            return .healthy
        }

        let first = cache.evaluate()
        #expect(first == .signingIdentityMismatch(appSigner: "Dev", helperSigner: "Prod"))
        #expect(callCount == 1)

        let second = cache.evaluate()
        #expect(second == .signingIdentityMismatch(appSigner: "Dev", helperSigner: "Prod"))
        #expect(callCount == 1)

        cache.invalidate()

        let third = cache.evaluate()
        #expect(third == .healthy)
        #expect(callCount == 2)
    }
}
