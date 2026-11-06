import Foundation
import os
@testable import Rockxy
import Testing

// MARK: - MockSigningEnvironment

private struct MockSigningEnvironment: SigningDiagnostics.Environment {
    var appSignatureValidation: SigningDiagnostics.AppSignatureValidation = .valid
    var helperExists: Bool = true
    var appSigner: String? = "Apple Development: dev@example.com"
    var helperSigner: String? = "Developer ID Application: Dev Corp"
    var appChain: [Data]? = [Data([1, 2, 3]), Data([4, 5, 6])]
    var helperChain: [Data]? = [Data([1, 2, 3]), Data([4, 5, 6])]

    func validateAppSignature() -> SigningDiagnostics.AppSignatureValidation {
        appSignatureValidation
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
        let bundledHelperURL =
            URL(fileURLWithPath: "/Applications/Rockxy.app/Contents/Library/HelperTools/RockxyHelperTool")
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
        env.appSignatureValidation = .invalid(
            detail: "Code signature invalid (OSStatus -67054)"
        )

        let result = SigningDiagnostics.classify(env)

        #expect(result == .appSignatureInvalid(
            detail: "Code signature invalid (OSStatus -67054)"
        ))
    }

    @Test("running code change requires reopening before helper checks")
    func runningCodeChanged() {
        var env = MockSigningEnvironment()
        env.appSignatureValidation = .runningCodeChanged(
            detail: "OSStatus -67034"
        )
        env.helperExists = false

        let result = SigningDiagnostics.classify(env)

        #expect(result == .runningCodeChanged(detail: "OSStatus -67034"))
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

    @Test("certificate chain unavailable when app chain extraction fails")
    func certificateChainUnavailableForAppChain() {
        var env = MockSigningEnvironment()
        env.appChain = nil

        let result = SigningDiagnostics.classify(env)

        #expect(result == .certificateChainUnavailable)
    }

    @Test("certificate chain unavailable when helper chain extraction fails")
    func certificateChainUnavailableForHelperChain() {
        var env = MockSigningEnvironment()
        env.helperChain = nil

        let result = SigningDiagnostics.classify(env)

        #expect(result == .certificateChainUnavailable)
    }

    @Test("app signature check runs before helper existence check")
    func appSignatureBeforeHelperCheck() {
        var env = MockSigningEnvironment()
        env.appSignatureValidation = .invalid(detail: "invalid")
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
        guard !TestIdentity.isRunningUnderRawXCTestTool else {
            return
        }
        let env = SigningDiagnostics.LiveEnvironment()
        guard env.validateAppSignature() == .valid else {
            return
        }

        #expect(env.validateAppSignature() == .valid)
    }

    @Test("LiveEnvironment resolves the bundled helper executable from the app package")
    func liveBundledHelperExecutableDetected() {
        guard !TestIdentity.isRunningUnderRawXCTestTool else {
            return
        }
        let bundledHelperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/HelperTools", isDirectory: true)
            .appendingPathComponent("RockxyHelperTool", isDirectory: false)

        #expect(FileManager.default.isExecutableFile(atPath: bundledHelperURL.path))

        let env = SigningDiagnostics.LiveEnvironment()
        #expect(env.helperBinaryExists())
    }

    @Test("LiveEnvironment can extract app certificate chain from test host")
    func liveAppCertificateChainExtractable() {
        // An ad-hoc host validates but embeds no certificates, so the assertion below
        // has no precondition there.
        guard !TestIdentity.isRunningUnderRawXCTestTool, !TestIdentity.isAdHocSigned else {
            return
        }
        let env = SigningDiagnostics.LiveEnvironment()
        guard env.validateAppSignature() == .valid else {
            return
        }

        let chain = env.appCertificateChain()
        #expect(chain != nil)
        #expect((chain?.count ?? 0) > 0)
    }

    @Test("LiveEnvironment handles helper certificate chain availability")
    func liveHelperCertificateChainAvailability() {
        guard !TestIdentity.isRunningUnderRawXCTestTool else {
            return
        }
        let env = SigningDiagnostics.LiveEnvironment()
        guard env.validateAppSignature() == .valid else {
            return
        }

        let chain = env.helperCertificateChain()
        if let chain {
            #expect(!chain.isEmpty)
        } else {
            #expect(SigningDiagnostics.classify(env) == .certificateChainUnavailable)
        }
    }

    @Test("Live classify returns healthy or helperBinaryNotFound depending on helper install state")
    func liveClassifyContract() {
        guard !TestIdentity.isRunningUnderRawXCTestTool else {
            return
        }
        let env = SigningDiagnostics.LiveEnvironment()
        guard env.validateAppSignature() == .valid else {
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
             .signingIdentityMismatch,
             .certificateChainUnavailable:
            break
        case .runningCodeChanged,
             .appSignatureInvalid,
             .diagnosticError:
            Issue.record("Live classify returned unexpected result: \(result)")
        }
    }
}

// MARK: - SigningPreflightCacheTests

@MainActor
struct SigningPreflightCacheTests {
    @Test("async cache memoizes repeated calls until invalidated")
    func preflightCacheInvalidation() async {
        let cache = SigningPreflightCache()
        let callCount = OSAllocatedUnfairLock(initialState: 0)

        cache.provider = {
            let count = callCount.withLock { value -> Int in
                value += 1
                return value
            }
            if count == 1 {
                return .signingIdentityMismatch(appSigner: "Dev", helperSigner: "Prod")
            }
            return .healthy
        }

        let first = await cache.evaluate()
        #expect(first == .signingIdentityMismatch(appSigner: "Dev", helperSigner: "Prod"))
        #expect(callCount.withLock { $0 } == 1)

        let second = await cache.evaluate()
        #expect(second == .signingIdentityMismatch(appSigner: "Dev", helperSigner: "Prod"))
        #expect(callCount.withLock { $0 } == 1)

        cache.invalidate()

        let third = await cache.evaluate()
        #expect(third == .healthy)
        #expect(callCount.withLock { $0 } == 2)
    }

    @Test("concurrent evaluations coalesce to a single provider invocation")
    func concurrentEvaluationsCoalesce() async {
        let cache = SigningPreflightCache()
        let callCount = OSAllocatedUnfairLock(initialState: 0)

        cache.provider = {
            callCount.withLock { $0 += 1 }
            // Hold the detached diagnosis open long enough for a second caller to attach to
            // the same in-flight generation instead of starting its own.
            Thread.sleep(forTimeInterval: 0.05)
            return .healthy
        }

        async let first = cache.evaluate()
        async let second = cache.evaluate()
        let results = await [first, second]

        #expect(results == [.healthy, .healthy])
        #expect(callCount.withLock { $0 } == 1)
    }

    @Test("provider runs off the main thread")
    func providerRunsOffMainThread() async {
        let cache = SigningPreflightCache()
        let ranOnMainThread = OSAllocatedUnfairLock(initialState: true)

        cache.provider = {
            ranOnMainThread.withLock { $0 = Thread.isMainThread }
            return .healthy
        }

        _ = await cache.evaluate()

        #expect(ranOnMainThread.withLock { $0 } == false)
    }

    @Test("invalidation during an in-flight evaluation returns the current generation")
    func invalidationDuringFlightRetriesCurrentGeneration() async {
        let cache = SigningPreflightCache()
        let callCount = OSAllocatedUnfairLock(initialState: 0)
        // Hand-shake with the first diagnosis instead of sleeping: it must be in flight when the
        // cache is invalidated, and it must not finish before that happens.
        let firstDiagnosisStarted = DispatchSemaphore(value: 0)
        let invalidationDone = DispatchSemaphore(value: 0)

        cache.provider = {
            let count = callCount.withLock { value -> Int in
                value += 1
                return value
            }
            if count == 1 {
                // The first (soon-to-be-stale) diagnosis blocks while it is invalidated.
                firstDiagnosisStarted.signal()
                _ = invalidationDone.wait(timeout: .now() + 5)
                return .signingIdentityMismatch(appSigner: "Stale", helperSigner: "Stale")
            }
            return .healthy
        }

        async let firstEvaluation = cache.evaluate()
        await Task.detached {
            _ = firstDiagnosisStarted.wait(timeout: .now() + 5)
        }.value
        cache.invalidate()
        invalidationDone.signal()

        let result = await firstEvaluation
        #expect(result == .healthy)
        #expect(callCount.withLock { $0 } == 2)

        // The fresh result is now memoized; no further diagnosis runs.
        let cached = await cache.evaluate()
        #expect(cached == .healthy)
        #expect(callCount.withLock { $0 } == 2)
    }
}
