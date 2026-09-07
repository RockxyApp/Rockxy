import Crypto
import Foundation
@testable import Rockxy
import Security
import SwiftASN1
import Testing
import X509

// Regression tests for the root CA lifecycle defects behind the repeated trust prompt after
// relaunch: status answered before the persisted root was loaded, trust metadata read more
// strictly than the SDK defines it, recovery picking the first decodable key instead of the
// matching one, reset leaving generation state behind, and mutations racing an in-flight
// trust installation.

// MARK: - TrustSettingsInterpreterTests

/// `Security/SecTrustSettings.h` lines 119–160 define the array semantics these cases pin.
struct TrustSettingsInterpreterTests {
    // MARK: Internal

    @Test("absent trust settings are never trust")
    func absentSettingsAreNotTrusted() {
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: nil) == false)
    }

    @Test("an empty settings array means unconditional trustRoot")
    func emptySettingsMeanTrustRoot() {
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: []))
    }

    @Test("an entry that omits the result key defaults to trustRoot")
    func omittedResultDefaultsToTrustRoot() {
        let constraintsOnly: [String: Any] = [kSecTrustSettingsPolicy as String: "ssl"]

        #expect(TrustSettingsInterpreter.verdict(for: constraintsOnly) == .trustsRoot)
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: [constraintsOnly]))
    }

    @Test("an explicit trustRoot result is trusted")
    func explicitTrustRootIsTrusted() {
        let entry = resultEntry(.trustRoot)

        #expect(TrustSettingsInterpreter.verdict(for: entry) == .trustsRoot)
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: [entry]))
    }

    @Test("an unconditional deny result is never trusted")
    func explicitDenyIsNotTrusted() {
        let entry = resultEntry(.deny)

        #expect(TrustSettingsInterpreter.verdict(for: entry) == .deniesUnconditionally)
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: [entry]) == false)
    }

    @Test("a deny constrained to another policy or application does not veto a trustRoot entry")
    func constrainedDenyDoesNotVetoTrustRoot() {
        var policyDeny = resultEntry(.deny)
        policyDeny[kSecTrustSettingsPolicy as String] = "smime"
        var applicationDeny = resultEntry(.deny)
        applicationDeny[kSecTrustSettingsApplication as String] = "/Applications/Other.app"
        var hostnameDeny = resultEntry(.deny)
        hostnameDeny[kSecTrustSettingsPolicyString as String] = "other.example.com"

        for deny in [policyDeny, applicationDeny, hostnameDeny] {
            #expect(TrustSettingsInterpreter.verdict(for: deny) == .deniesForConstrainedUse)
            // Whether the constraint applies to the evaluation at hand is SecTrust's call, so
            // the prefilter must not turn it into a permanent negative.
            #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: [resultEntry(.trustRoot), deny]))
        }
    }

    @Test("a constrained deny alone is still not a positive prefilter")
    func constrainedDenyAloneIsNotTrusted() {
        var deny = resultEntry(.deny)
        deny[kSecTrustSettingsPolicy as String] = "ssl"

        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: [deny]) == false)
    }

    @Test("an unconditional deny still vetoes a constrained trustRoot entry")
    func unconditionalDenyVetoesConstrainedTrustRoot() {
        var constrainedTrust = resultEntry(.trustRoot)
        constrainedTrust[kSecTrustSettingsPolicy as String] = "ssl"

        #expect(TrustSettingsInterpreter
            .indicatesTrustedRoot(settings: [constrainedTrust, resultEntry(.deny)]) == false)
    }

    @Test("unspecified and trustAsRoot results do not mark a root trusted")
    func inconclusiveResultsAreNotTrusted() {
        let unspecified = resultEntry(.unspecified)
        let trustAsRoot = resultEntry(.trustAsRoot)

        #expect(TrustSettingsInterpreter.verdict(for: unspecified) == .inconclusive)
        #expect(TrustSettingsInterpreter.verdict(for: trustAsRoot) == .inconclusive)
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: [unspecified]) == false)
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: [trustAsRoot]) == false)
    }

    @Test("a malformed result value is never trusted")
    func malformedResultIsNotTrusted() {
        let entry: [String: Any] = [kSecTrustSettingsResult as String: "trustRoot"]

        #expect(TrustSettingsInterpreter.verdict(for: entry) == .inconclusive)
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: [entry]) == false)
    }

    @Test("a boolean result value is malformed, not trustRoot")
    func booleanResultIsNotTrustRoot() {
        // A CFBoolean bridges to NSNumber and casts to UInt32, so `true` would otherwise read
        // as 1 — the raw value of kSecTrustSettingsResultTrustRoot.
        let entry: [String: Any] = [kSecTrustSettingsResult as String: true as NSNumber]

        #expect(SecTrustSettingsResult.trustRoot.rawValue == 1)
        #expect(TrustSettingsInterpreter.verdict(for: entry) == .inconclusive)
        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: [entry]) == false)
    }

    @Test("an unconditional deny alongside trustRoot keeps the prefilter negative")
    func denyVetoesTrustRoot() {
        let settings = [resultEntry(.trustRoot), resultEntry(.deny)]

        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: settings) == false)
    }

    @Test("a constraints-only entry alongside an inconclusive entry still reads as trustRoot")
    func defaultEntryAmongInconclusiveEntriesIsTrusted() {
        let settings: [[String: Any]] = [
            resultEntry(.unspecified),
            [kSecTrustSettingsPolicy as String: "ssl"]
        ]

        #expect(TrustSettingsInterpreter.indicatesTrustedRoot(settings: settings))
    }

    // MARK: Private

    private func resultEntry(_ result: SecTrustSettingsResult) -> [String: Any] {
        [kSecTrustSettingsResult as String: result.rawValue]
    }
}

// MARK: - TrustEvaluationDecisionTests

/// The snapshot trust rule: metadata is a prefilter, a cached positive result cannot outlive
/// the metadata behind it, and metadata alone never produces the first green state.
struct TrustEvaluationDecisionTests {
    @Test("missing metadata invalidates a cached positive result")
    func missingMetadataInvalidatesCachedTrue() {
        let decision = CertificateManager.trustEvaluationDecision(
            trustPresent: false,
            performValidation: false,
            cachedValidation: true
        )

        #expect(decision == .notTrusted(invalidatesCachedResult: true))
    }

    @Test("missing metadata leaves a cached negative result alone")
    func missingMetadataKeepsCachedFalse() {
        #expect(CertificateManager.trustEvaluationDecision(
            trustPresent: false,
            performValidation: false,
            cachedValidation: false
        ) == .notTrusted(invalidatesCachedResult: false))

        #expect(CertificateManager.trustEvaluationDecision(
            trustPresent: false,
            performValidation: false,
            cachedValidation: nil
        ) == .notTrusted(invalidatesCachedResult: false))
    }

    @Test("metadata alone never produces the first green result")
    func metadataAloneRequiresRealValidation() {
        #expect(CertificateManager.trustEvaluationDecision(
            trustPresent: true,
            performValidation: false,
            cachedValidation: nil
        ) == .runValidation)
    }

    @Test("an existing real result is reused on cheap refreshes")
    func cachedResultIsReusedWhenMetadataIsPresent() {
        #expect(CertificateManager.trustEvaluationDecision(
            trustPresent: true,
            performValidation: false,
            cachedValidation: true
        ) == .useCached(true))

        #expect(CertificateManager.trustEvaluationDecision(
            trustPresent: true,
            performValidation: false,
            cachedValidation: false
        ) == .useCached(false))
    }

    @Test("an explicit validation request always re-evaluates")
    func explicitValidationAlwaysReEvaluates() {
        #expect(CertificateManager.trustEvaluationDecision(
            trustPresent: true,
            performValidation: true,
            cachedValidation: true
        ) == .runValidation)

        #expect(CertificateManager.trustEvaluationDecision(
            trustPresent: true,
            performValidation: true,
            cachedValidation: false
        ) == .runValidation)
    }
}

// MARK: - RootCAKeyRecoverySelectionTests

/// Recovery must find the key that belongs to the persisted certificate, not the first key it
/// can decode, and must not consume or overwrite a recovery source it did not adopt.
@Suite(.serialized)
struct RootCAKeyRecoverySelectionTests {
    // MARK: Internal

    @Test("a valid but stale Keychain key and primary PEM never shadow the matching backup")
    func staleKeychainAndPrimaryDoNotShadowMatchingBackup() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCACertificate(persisted.certificate)
        try KeychainHelper.savePrivateKey(
            Data(P256.Signing.PrivateKey().x963Representation),
            label: overrides.label
        )
        try writeKeyPEM(P256.Signing.PrivateKey(), to: primaryKeyURL(in: overrides.storageDir))
        try writeKeyPEM(persisted.privateKey, to: backupKeyURL(in: overrides.storageDir))

        #expect(try await manager.loadExistingRootCA())

        #expect(await manager.getActiveRootFingerprint() == fingerprint(of: persisted.certificate))
        let persistedKey = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))
        #expect(persistedKey == Data(persisted.privateKey.x963Representation))
    }

    @Test("an absent Keychain key and stale primary PEM still recover the matching backup")
    func absentKeychainAndStalePrimaryRecoverMatchingBackup() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCACertificate(persisted.certificate)
        try KeychainHelper.deletePrivateKey(label: overrides.label)
        try writeKeyPEM(P256.Signing.PrivateKey(), to: primaryKeyURL(in: overrides.storageDir))
        try writeKeyPEM(persisted.privateKey, to: backupKeyURL(in: overrides.storageDir))

        #expect(try await manager.loadExistingRootCA())

        #expect(await manager.getActiveRootFingerprint() == fingerprint(of: persisted.certificate))
        let persistedKey = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))
        #expect(persistedKey == Data(persisted.privateKey.x963Representation))
    }

    @Test("a corrupt primary PEM falls through to the matching backup")
    func corruptPrimaryFallsThroughToMatchingBackup() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCACertificate(persisted.certificate)
        try KeychainHelper.deletePrivateKey(label: overrides.label)
        try Data("not a private key".utf8).write(to: primaryKeyURL(in: overrides.storageDir))
        try writeKeyPEM(persisted.privateKey, to: backupKeyURL(in: overrides.storageDir))

        #expect(try await manager.loadExistingRootCA())

        #expect(await manager.getActiveRootFingerprint() == fingerprint(of: persisted.certificate))
        let persistedKey = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))
        #expect(persistedKey == Data(persisted.privateKey.x963Representation))
    }

    @Test("no matching key regenerates once and leaves every recovery source untouched")
    func noMatchingKeyRegeneratesOnceWithoutConsumingSources() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCACertificate(persisted.certificate)

        let keychainKey = P256.Signing.PrivateKey()
        try KeychainHelper.savePrivateKey(Data(keychainKey.x963Representation), label: overrides.label)
        let primaryURL = primaryKeyURL(in: overrides.storageDir)
        let backupURL = backupKeyURL(in: overrides.storageDir)
        try writeKeyPEM(P256.Signing.PrivateKey(), to: primaryURL)
        try writeKeyPEM(P256.Signing.PrivateKey(), to: backupURL)
        let primaryBefore = try Data(contentsOf: primaryURL)
        let backupBefore = try Data(contentsOf: backupURL)

        #expect(try await manager.loadExistingRootCA() == false)

        // Nothing was migrated, renamed, or deleted while looking for a match.
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == Data(keychainKey.x963Representation))
        #expect(try Data(contentsOf: primaryURL) == primaryBefore)
        #expect(try Data(contentsOf: backupURL) == backupBefore)

        // Exactly one regeneration follows, and it is then stable across further loads.
        try await manager.ensureRootCA()
        let regenerated = try #require(await manager.getActiveRootFingerprint())
        #expect(regenerated != fingerprint(of: persisted.certificate))

        let relaunched = CertificateManager.makeForTesting()
        try await relaunched.ensureRootCA()
        #expect(await relaunched.getActiveRootFingerprint() == regenerated)
    }

    @Test("an unreadable recovery source fails instead of rotating the root CA")
    func unreadableRecoverySourceFailsClosed() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCACertificate(persisted.certificate)
        try KeychainHelper.deletePrivateKey(label: overrides.label)

        let primaryURL = primaryKeyURL(in: overrides.storageDir)
        try writeKeyPEM(persisted.privateKey, to: primaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: primaryURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: primaryURL.path)
        }

        await #expect(throws: (any Error).self) {
            try await manager.loadExistingRootCA()
        }

        #expect(await manager.getActiveRootFingerprint() == nil)
        #expect(try CertificateStore.loadRootCACertificate() != nil)
    }

    // MARK: Private

    private func primaryKeyURL(in directory: URL) -> URL {
        directory.appendingPathComponent(TestIdentity.rootCAKeyFilename)
    }

    private func backupKeyURL(in directory: URL) -> URL {
        directory.appendingPathComponent(TestIdentity.rootCABackupFilename)
    }

    private func writeKeyPEM(_ key: P256.Signing.PrivateKey, to url: URL) throws {
        try CertificateStore.ensureDirectoryExists()
        let document = PEMDocument(type: "EC PRIVATE KEY", derBytes: Array(key.x963Representation))
        try Data(document.pemString.utf8).write(to: url)
    }

    private func fingerprint(of certificate: Certificate) -> String? {
        certificateFingerprint(certificate)
    }
}

// MARK: - RootCAStartupReadinessTests

/// Status has to answer from the persisted root CA regardless of when the launch task runs.
@Suite(.serialized)
struct RootCAStartupReadinessTests {
    @Test("status snapshot loads the persisted root CA before evaluating trust")
    func snapshotLoadsPersistedRootBeforeEvaluatingTrust() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(persisted.privateKey)
        try CertificateStore.saveRootCACertificate(persisted.certificate)

        // A cold actor stands in for a launch where no `ensureRootCA()` task has run yet.
        let manager = CertificateManager.makeForTesting()
        let snapshot = await manager.rootCAStatusSnapshot()

        #expect(snapshot.hasGeneratedCertificate)
        #expect(snapshot.fingerprintSHA256 == certificateFingerprint(persisted.certificate))
        #expect(snapshot.isSystemTrustValidated == false)
        #expect(await manager.getActiveRootFingerprint() == certificateFingerprint(persisted.certificate))
    }

    @Test("an unreadable persisted certificate fails closed with a diagnostic and no rotation")
    func storageFailureFailsClosedWithoutRotating() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(persisted.privateKey)
        try CertificateStore.saveRootCACertificate(persisted.certificate)

        let certificateURL = CertificateStore.rootCACertificateURL
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: certificateURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: certificateURL.path)
        }

        let manager = CertificateManager.makeForTesting()
        let snapshot = await manager.rootCAStatusSnapshot()

        #expect(snapshot.hasGeneratedCertificate == false)
        #expect(snapshot.isSystemTrustValidated == false)
        #expect(snapshot.lastValidationErrorMessage != nil)

        // The persisted material was neither adopted nor replaced.
        #expect(await manager.getActiveRootFingerprint() == nil)
        #expect(try KeychainHelper
            .loadPrivateKey(label: overrides.label) == Data(persisted.privateKey.x963Representation))
    }

    @Test("adopting a different CA drops the previous generation's validation, flag, and host cache")
    func identityChangeClearsDerivedState() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        _ = try await manager.certificateForHost("example.com")
        _ = await manager.validateSystemTrust()

        #expect(await manager.cachedHostCount == 1)
        #expect(await manager.lastTrustValidationResult != nil)
        #expect(await manager.rootCAFreshlyInstalled)

        let replacement = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(replacement.privateKey)
        try CertificateStore.saveRootCACertificate(replacement.certificate)

        #expect(try await manager.loadExistingRootCA())

        #expect(await manager.getActiveRootFingerprint() == certificateFingerprint(replacement.certificate))
        #expect(await manager.lastTrustValidationResult == nil)
        #expect(await manager.lastValidationErrorMessage == nil)
        #expect(await manager.rootCAFreshlyInstalled == false)
        #expect(await manager.cachedHostCount == 0)
    }

    @Test("reset clears fingerprint, freshly-installed flag, and both caches")
    func resetClearsGenerationState() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        _ = try await manager.certificateForHost("example.com")
        _ = await manager.validateSystemTrust()

        try await manager.reset()

        #expect(await manager.getActiveRootFingerprint() == nil)
        #expect(await manager.rootCAFreshlyInstalled == false)
        #expect(await manager.lastTrustValidationResult == nil)
        #expect(await manager.lastValidationErrorMessage == nil)
        #expect(await manager.cachedHostCount == 0)

        let snapshot = await manager.rootCAStatusSnapshot()
        #expect(snapshot.hasGeneratedCertificate == false)
        #expect(snapshot.fingerprintSHA256 == nil)
        #expect(snapshot.isSystemTrustValidated == false)
    }

    @Test("a relaunched manager reloads the persisted root CA without rotating it")
    func relaunchReloadsPersistedRootCA() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let first = CertificateManager.makeForTesting()
        try await first.ensureRootCA()
        let originalFingerprint = try #require(await first.getActiveRootFingerprint())

        let relaunched = CertificateManager.makeForTesting()
        try await relaunched.ensureRootCA()

        #expect(await relaunched.getActiveRootFingerprint() == originalFingerprint)
        // Nothing was installed during this launch, so the UI must not claim a fresh install.
        #expect(await relaunched.rootCAFreshlyInstalled == false)

        let snapshot = await relaunched.rootCAStatusSnapshot()
        #expect(snapshot.fingerprintSHA256 == originalFingerprint)
    }

    @Test("status fails closed when another process replaces the persisted root identity")
    func statusRejectsPersistedIdentityDrift() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let activeFingerprint = try #require(await manager.getActiveRootFingerprint())

        // Model an older sibling process replacing both persisted halves while this actor still
        // holds the previously trusted CA and its derived state in memory.
        let replacement = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(replacement.privateKey)
        try CertificateStore.saveRootCACertificate(replacement.certificate)

        let snapshot = await manager.rootCAStatusSnapshot(performValidation: true)

        #expect(snapshot.isStatusUnavailable)
        #expect(snapshot.statusReadFailure?.scope == .persistedMaterial)
        #expect(snapshot.statusReadErrorMessage == CertificateManagerError.persistedRootIdentityDrift.localizedDescription)
        #expect(snapshot.isSystemTrustValidated == false)
        #expect(await manager.lastTrustValidationResult == nil)
        // A status read is fail-closed and non-mutating. The explicit trust action owns adoption.
        #expect(await manager.getActiveRootFingerprint() == activeFingerprint)
        #expect(
            certificateFingerprint(try #require(try CertificateStore.loadRootCACertificate()))
                == certificateFingerprint(replacement.certificate)
        )
    }
}

// MARK: - RootCATestIsolationTests

/// Nothing reachable from a test may address the production root CA material.
@Suite(.serialized)
struct RootCATestIsolationTests {
    @Test("test labels never match the production root CA labels")
    func labelsDifferFromProduction() async throws {
        #expect(RockxyIdentity.isRunningTests)
        #expect(CertificateStore.activeKeychainKeyLabel != RockxyIdentity.current.rootCAKeyLabel)
        #expect(
            CertificateStore.activeKeychainCertificateLabel != RockxyIdentity.current.rootCACertificateLabel
        )

        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        #expect(CertificateStore.activeKeychainKeyLabel == overrides.label)
        #expect(CertificateStore.activeKeychainCertificateLabel == overrides.certificateLabel)
        #expect(overrides.certificateLabel != RockxyIdentity.current.rootCACertificateLabel)
        #expect(overrides.certificateLabel.hasPrefix(overrides.label))
    }

    @Test("manager cleanup removes only its own certificate")
    func cleanupPreservesUnrelatedCertificate() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let sentinelLabel = "\(TestIdentity.keychainProbeLabel).sentinel.\(UUID().uuidString)"
        let sentinel = try RootCAGenerator.generate()
        try KeychainHelper.installCertificate(certificateDER(sentinel.certificate), label: sentinelLabel)
        defer { try? KeychainHelper.removeCertificate(label: sentinelLabel) }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        try await manager.installRootCAInKeychain()
        #expect(KeychainHelper.isCertificateInstalled(label: overrides.certificateLabel))

        try await manager.reset()

        #expect(KeychainHelper.isCertificateInstalled(label: overrides.certificateLabel) == false)
        #expect(KeychainHelper.isCertificateInstalled(label: sentinelLabel))
    }
}

// MARK: - RootCAMutationGuardTests

/// `installAndTrust()` suspends into the helper and the authorization dialog, and this actor is
/// reentrant across those awaits.
@Suite(.serialized)
struct RootCAMutationGuardTests {
    @Test("material-replacing operations are rejected while a trust installation is in flight")
    func mutationsRejectedDuringTrustInstallation() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())

        await manager.setTrustInstallationInFlightForTests(true)

        await #expect(throws: CertificateManagerError.trustInstallationInProgress) {
            try await manager.reset()
        }
        await #expect(throws: CertificateManagerError.trustInstallationInProgress) {
            try await manager.removeRootCATrust()
        }
        await #expect(throws: CertificateManagerError.trustInstallationInProgress) {
            try await manager.generateRootCA()
        }
        // A second install would raise a second authorization dialog for the same material.
        await #expect(throws: CertificateManagerError.trustInstallationInProgress) {
            try await manager.installAndTrust()
        }
        // Adopting persisted material would replace what the installation is trusting.
        await #expect(throws: CertificateManagerError.trustInstallationInProgress) {
            try await manager.loadExistingRootCA()
        }

        #expect(await manager.getActiveRootFingerprint() == originalFingerprint)

        await manager.setTrustInstallationInFlightForTests(false)

        try await manager.reset()
        #expect(await manager.getActiveRootFingerprint() == nil)
    }

    @Test("a status refresh during an installation is not recorded as a storage failure")
    func statusRefreshDuringInstallationKeepsDiagnostic() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(persisted.privateKey)
        try CertificateStore.saveRootCACertificate(persisted.certificate)

        // A cold actor whose installation is already in flight: the status refresh wants to
        // load the persisted material and is refused by the guard.
        let manager = CertificateManager.makeForTesting()
        await manager.setTrustInstallationInFlightForTests(true)

        let snapshot = await manager.rootCAStatusSnapshot()

        // A guard rejection is not a storage failure and must not poison the diagnostic or the
        // validation cache the installation is about to update.
        #expect(snapshot.lastValidationErrorMessage == nil)
        #expect(snapshot.isSystemTrustValidated == false)
        #expect(await manager.lastTrustValidationResult == nil)
        #expect(await manager.getActiveRootFingerprint() == nil)
    }
}

// MARK: - RootCATrustInstallCancellationTests

/// `installAndTrust()` raises a macOS authorization dialog in this process, and has no helper
/// attempt to fall back from. A cancelled request must stop before the dialog and must always
/// release the guard. Cancellation that arrives once the native call is already running is covered
/// in `AuthorizationCancellationTests`.
@Suite(.serialized)
struct RootCATrustInstallCancellationTests {
    @Test("a cancelled request performs no privileged work and leaves the guard released")
    func cancelledInstallDoesNoPrivilegedWork() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())

        let task = Task {
            // Start suspended so `installAndTrust()` is always entered by an already-cancelled
            // task: nothing privileged can run before the first cancellation check.
            while !Task.isCancelled {
                await Task.yield()
            }
            try await manager.installAndTrust()
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(await manager.getActiveRootFingerprint() == originalFingerprint)

        // The guard is released on every exit path, so the next mutation is not rejected.
        try await manager.generateRootCA()
        #expect(await manager.getActiveRootFingerprint() != nil)
    }

    @Test("the legacy helper-dispatch classifier still refuses to fall back after a cancellation")
    func cancelledHelperAttemptDoesNotFallBack() {
        struct HelperFailure: Error {}

        // Scoped to the legacy `HelperConnection.installRootCertificate` RPC, which the GUI
        // installation never sends. On that path a cancelled request reaches the caller either as
        // `CancellationError` or as a transport failure raised because the task was cancelled, and
        // neither may turn into an authorization dialog.
        #expect(CertificateManager.shouldFallBackToAppSideTrust(
            afterHelperError: HelperFailure(),
            isCancelled: false
        ))
        #expect(CertificateManager.shouldFallBackToAppSideTrust(
            afterHelperError: CancellationError(),
            isCancelled: false
        ) == false)
        #expect(CertificateManager.shouldFallBackToAppSideTrust(
            afterHelperError: HelperFailure(),
            isCancelled: true
        ) == false)
    }
}

// MARK: - RootCAStatusNotificationTests

/// Adopting a different root CA is a status change wherever it happens, and re-adopting the same
/// one is not — otherwise every observer that refreshes on the notification re-triggers it.
@Suite(.serialized)
struct RootCAStatusNotificationTests {
    @Test("a changed identity notifies once, and repeated loads and snapshots do not")
    func identityAdoptionNotifiesExactlyOnce() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(persisted.privateKey)
        try CertificateStore.saveRootCACertificate(persisted.certificate)

        let counter = NotificationCounter()

        // A cold actor stands in for a launch where no `ensureRootCA()` task has run yet.
        // Adopting the persisted identity is a status change even though no snapshot asked
        // for it, so readiness surfaces refresh instead of waiting for the next poll.
        let manager = CertificateManager.makeForTesting()
        // Observe this actor's production notification path, not unrelated global posts
        // from other suites. Delivery to readiness observers is covered separately.
        await manager.observeStatusNotificationsForTests { counter.increment() }
        #expect(try await manager.loadExistingRootCA())
        #expect(counter.posts == 1)

        // The same identity is already adopted, so nothing below is a status change.
        #expect(try await manager.loadExistingRootCA())
        _ = await manager.rootCAStatusSnapshot()
        _ = await manager.rootCAStatusSnapshot()
        #expect(counter.posts == 1)
    }
}

// MARK: - NotificationCounter

/// Counts notifications requested by one isolated certificate manager.
private final class NotificationCounter: @unchecked Sendable {
    // MARK: Internal

    var posts: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }

    // MARK: Private

    private let lock = NSLock()
    private var value = 0
}

// MARK: - RootCATrustResolutionTests

/// The legacy `isRootCATrusted()` getter feeds the app menu's onboarding backfill and the
/// certificate wizard, so it has to answer with the same rule as the status snapshot.
@Suite(.serialized)
struct RootCATrustResolutionTests {
    @Test("the installed getter adopts the persisted identity before answering")
    func installedGetterLoadsPersistedIdentity() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }
        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(persisted.privateKey)
        try CertificateStore.saveRootCACertificate(persisted.certificate)
        try KeychainHelper.installCertificate(
            certificateDER(persisted.certificate), label: overrides.certificateLabel
        )

        let manager = CertificateManager.makeForTesting()
        #expect(await manager.isRootCAInstalled())
        #expect(await manager.getActiveRootFingerprint() == certificateFingerprint(persisted.certificate))
        #expect(await manager.isRootCATrustValidated() == false)
    }

    @Test("the legacy getter loads the persisted root and matches the snapshot")
    func legacyGetterMatchesSnapshot() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(persisted.privateKey)
        try CertificateStore.saveRootCACertificate(persisted.certificate)

        let manager = CertificateManager.makeForTesting()
        let trusted = await manager.isRootCATrusted()

        // No admin trust settings exist for a freshly generated test CA, so the only honest
        // answer is false — and the persisted root was adopted while answering.
        #expect(trusted == false)
        #expect(await manager.getActiveRootFingerprint() == certificateFingerprint(persisted.certificate))

        let snapshot = await manager.rootCAStatusSnapshot()
        #expect(snapshot.isSystemTrustValidated == trusted)
        #expect(snapshot.hasTrustSettings == false)
    }

    @Test("metadata alone never produces a green result without a real evaluation")
    func metadataAloneIsNotTrust() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()

        // hasTrustSettingsPresent() is the prefilter; the reported answer must come from the
        // real SecTrust evaluation cached in lastTrustValidationResult.
        let trusted = await manager.isRootCATrusted()
        let metadataPresent = await manager.hasTrustSettingsPresent()
        let cachedValidation = await manager.lastTrustValidationResult

        if metadataPresent {
            #expect(cachedValidation != nil)
            #expect(trusted == cachedValidation)
        } else {
            #expect(trusted == false)
        }
    }

    @Test("a storage failure keeps its own diagnostic instead of the generic no-root message")
    func storageFailureKeepsItsDiagnostic() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(persisted.privateKey)
        try CertificateStore.saveRootCACertificate(persisted.certificate)

        let certificateURL = CertificateStore.rootCACertificateURL
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: certificateURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: certificateURL.path)
        }

        let manager = CertificateManager.makeForTesting()
        // A deep refresh must not run validation on the empty actor and overwrite the read
        // failure with "No root CA certificate or private key available".
        let snapshot = await manager.rootCAStatusSnapshot(performValidation: true)

        let message = try #require(snapshot.lastValidationErrorMessage)
        #expect(message.contains("No root CA certificate or private key available") == false)
        #expect(snapshot.isSystemTrustValidated == false)
        #expect(await manager.isRootCATrusted() == false)
    }
}

// MARK: - RootCACertificatePersistenceTests

/// The certificate PEM is replaced atomically with its final permissions already applied, so a
/// failed write can never leave a new certificate paired with the rolled-back previous key.
@Suite(.serialized)
struct RootCACertificatePersistenceTests {
    // MARK: Internal

    @Test("a persisted certificate lands with 0600 permissions and leaves no staging file")
    func persistedCertificateIsPrivateAndLeavesNoStagingFile() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let original = try RootCAGenerator.generate()
        try CertificateStore.saveRootCACertificate(original.certificate)
        #expect(try permissions(ofFileAt: CertificateStore.rootCACertificateURL) == 0o600)

        // Replacing an existing certificate keeps the mode instead of inheriting the replaced
        // file's metadata, so no follow-up chmod is needed after the commit.
        let replacement = try RootCAGenerator.generate()
        try CertificateStore.saveRootCACertificate(replacement.certificate)
        #expect(try permissions(ofFileAt: CertificateStore.rootCACertificateURL) == 0o600)
        #expect(try stagingFiles(in: overrides.storageDir).isEmpty)

        let loaded = try #require(try CertificateStore.loadRootCACertificate())
        #expect(certificateFingerprint(loaded) == certificateFingerprint(replacement.certificate))
    }

    @Test("a failure before the commit leaves the previously persisted certificate untouched")
    func preCommitFailurePreservesPreviousCertificate() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let original = try RootCAGenerator.generate()
        try CertificateStore.saveRootCACertificate(original.certificate)
        let originalBytes = try Data(contentsOf: CertificateStore.rootCACertificateURL)

        CertificateStore.certificateCommitOverride = { _, _ in throw CommitFailure() }
        defer { CertificateStore.certificateCommitOverride = nil }

        let replacement = try RootCAGenerator.generate()
        #expect(throws: CommitFailure.self) {
            try CertificateStore.saveRootCACertificate(replacement.certificate)
        }

        #expect(try Data(contentsOf: CertificateStore.rootCACertificateURL) == originalBytes)
        #expect(try stagingFiles(in: overrides.storageDir).isEmpty)
    }

    @Test("a certificate persistence failure rolls the key back and keeps the persisted pair")
    func certificatePersistenceFailureRollsKeyBack() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())
        let originalKey = try #require(try CertificateStore.loadRootCAPrivateKeyFromKeychain())
        let originalCertificateBytes = try Data(contentsOf: CertificateStore.rootCACertificateURL)

        CertificateStore.certificateCommitOverride = { _, _ in throw CommitFailure() }
        await #expect(throws: CommitFailure.self) {
            try await manager.generateRootCA()
        }
        CertificateStore.certificateCommitOverride = nil

        // The certificate on disk and the key in the Keychain still describe one CA — the one
        // the user already approved.
        #expect(try Data(contentsOf: CertificateStore.rootCACertificateURL) == originalCertificateBytes)
        let rolledBackKey = try #require(try CertificateStore.loadRootCAPrivateKeyFromKeychain())
        #expect(rolledBackKey.rawRepresentation == originalKey.rawRepresentation)

        let relaunched = CertificateManager.makeForTesting()
        #expect(try await relaunched.loadExistingRootCA())
        #expect(await relaunched.getActiveRootFingerprint() == originalFingerprint)
    }

    // MARK: Private

    private struct CommitFailure: Error {}

    private func permissions(ofFileAt url: URL) throws -> Int? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue
    }

    private func stagingFiles(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains(".staging-") }
    }
}

// MARK: - RootCADefaultTestNamespaceTests

/// The default (override-free) test namespace has to be unique per test process: the certificate
/// directory already is, so a constant Keychain suffix let two XCTest processes overwrite each
/// other's root CA key while reading different certificates.
@Suite(.serialized)
struct RootCADefaultTestNamespaceTests {
    @Test("default test labels are per process and never the production labels")
    func defaultLabelsAreProcessSpecific() async throws {
        try await withDefaultCertificateNamespace {
            let keyLabel = CertificateStore.activeKeychainKeyLabel
            let certificateLabel = CertificateStore.activeKeychainCertificateLabel
            let processMarker = ".test.\(ProcessInfo.processInfo.processIdentifier)."

            #expect(keyLabel != RockxyIdentity.current.rootCAKeyLabel)
            #expect(certificateLabel != RockxyIdentity.current.rootCACertificateLabel)
            #expect(keyLabel.hasSuffix("test-default") == false)
            #expect(keyLabel.contains(processMarker))
            #expect(certificateLabel.contains(processMarker))
        }
    }

    @Test("default-namespace cleanup removes only its own fixture material")
    func defaultNamespaceCleanupIsScoped() async throws {
        try await withDefaultCertificateNamespace {
            // Do not mutate the process-wide fixture while other suites may be reading it.
            var deletedKeys: [String] = []
            var deletedCertificates: [String] = []
            CertificateStore.removeDefaultTestNamespaceMaterial(
                deleteKey: { deletedKeys.append($0) },
                deleteCertificate: { deletedCertificates.append($0) }
            )
            #expect(deletedKeys == [CertificateStore.activeKeychainKeyLabel])
            #expect(deletedCertificates == [CertificateStore.activeKeychainCertificateLabel])
            #expect(deletedKeys.contains(RockxyIdentity.current.rootCAKeyLabel) == false)
            #expect(deletedCertificates.contains(RockxyIdentity.current.rootCACertificateLabel) == false)
        }
    }
}

// MARK: - RockxyCertificateCleanupScopeTests

/// Login-keychain cleanup must be bounded by an explicit keychain search list. Relying on
/// `errSecWrPerm` to protect `System.keychain` is a permission accident, not a scope boundary —
/// the certificate the helper just installed and trusted lives there.
@Suite(.serialized)
struct RockxyCertificateCleanupScopeTests {
    @Test("certificate import accepts only one unambiguous persistent reference")
    func certificateImportReferenceShapes() {
        let reference = Data([1, 2, 3])
        #expect(KeychainHelper.certificatePersistentReference(from: reference) == reference)
        #expect(KeychainHelper.certificatePersistentReference(from: [reference]) == reference)
        #expect(KeychainHelper.certificatePersistentReference(from: nil) == nil)
        #expect(KeychainHelper.certificatePersistentReference(from: Data()) == nil)
        #expect(KeychainHelper.certificatePersistentReference(from: [Data]()) == nil)
        #expect(KeychainHelper.certificatePersistentReference(from: [reference, reference]) == nil)
    }

    @Test("certificate lookup requires the requested DER, not another installed root")
    func installedLookupDoesNotMatchAnotherCertificate() throws {
        let firstLabel = "\(TestIdentity.keychainProbeLabel).first.\(UUID().uuidString)"
        let secondLabel = "\(TestIdentity.keychainProbeLabel).second.\(UUID().uuidString)"
        let firstDER = try certificateDER(RootCAGenerator.generate().certificate)
        let secondDER = try certificateDER(RootCAGenerator.generate().certificate)
        try KeychainHelper.installCertificate(firstDER, label: firstLabel)
        defer { try? KeychainHelper.removeCertificate(label: firstLabel) }

        #expect(KeychainHelper.isCertificateInstalled(certData: firstDER))
        #expect(KeychainHelper.isCertificateInstalled(certData: secondDER) == false)
        // The same serial number must not be enough: a different DER/signature is not
        // the installed certificate. The altered bytes are never installed or trusted.
        var differentDERWithSameSerial = firstDER
        differentDERWithSameSerial[differentDERWithSameSerial.endIndex - 1] ^= 1
        #expect(KeychainHelper.isCertificateInstalled(certData: differentDERWithSameSerial) == false)

        try KeychainHelper.installCertificate(secondDER, label: secondLabel)
        defer { try? KeychainHelper.removeCertificate(label: secondLabel) }
        #expect(KeychainHelper.isCertificateInstalled(certData: secondDER))
        #expect(KeychainHelper.isCertificateInstalled(certData: firstDER))
    }

    @Test("discovery is scoped by label and by an explicit keychain search list")
    func discoveryQueryIsScoped() {
        let unscoped = KeychainHelper.rockxyCertificateQuery(label: "probe", searchList: nil)
        #expect(unscoped.keys.contains(kSecMatchSearchList as String) == false)

        guard let loginKeychain = KeychainHelper.openLoginKeychain() else {
            // Without a login keychain the production path skips the cleanup entirely.
            return
        }

        let scoped = KeychainHelper.rockxyCertificateQuery(label: "probe", searchList: [loginKeychain])
        #expect((scoped[kSecClass as String] as? String) == (kSecClassCertificate as String))
        #expect(scoped[kSecAttrLabel as String] as? String == "probe")
        #expect((scoped[kSecMatchSearchList as String] as? [SecKeychain])?.count == 1)
    }

    @Test("deletion addresses exactly the items already returned")
    func deleteQueryUsesExactItemList() throws {
        let sample = try RootCAGenerator.generate()
        let secCert = try #require(SecCertificateCreateWithData(nil, certificateDER(sample.certificate) as CFData))

        let query = KeychainHelper.exactItemDeleteQuery(certificateReferences: [secCert])

        // `kSecValueRef` is the iOS deletion shape; macOS references specific items with
        // `kSecMatchItemList`. A class-and-label query would delete every match instead.
        #expect(query.keys.contains(kSecValueRef as String) == false)
        #expect(query.keys.contains(kSecAttrLabel as String) == false)
        #expect((query[kSecMatchItemList as String] as? [AnyObject])?.count == 1)
        if let loginKeychain = KeychainHelper.openLoginKeychain() {
            let scoped = KeychainHelper.exactItemDeleteQuery(
                certificateReferences: [secCert], searchList: [loginKeychain]
            )
            #expect((scoped[kSecMatchSearchList as String] as? [SecKeychain])?.count == 1)
            #expect((scoped[kSecMatchItemList as String] as? [AnyObject])?.count == 1)
        }
    }

    @Test("login-keychain cleanup removes only the requested label")
    func loginCleanupPreservesOtherLabels() throws {
        guard let loginKeychain = KeychainHelper.openLoginKeychain() else {
            return
        }

        let targetLabel = "\(TestIdentity.keychainProbeLabel).cleanup.\(UUID().uuidString)"
        let sentinelLabel = "\(TestIdentity.keychainProbeLabel).sentinel.\(UUID().uuidString)"
        try KeychainHelper.installCertificate(
            certificateDER(RootCAGenerator.generate().certificate),
            label: targetLabel
        )
        defer { try? KeychainHelper.removeCertificate(label: targetLabel) }
        try KeychainHelper.installCertificate(
            certificateDER(RootCAGenerator.generate().certificate),
            label: sentinelLabel
        )
        defer { try? KeychainHelper.removeCertificate(label: sentinelLabel) }

        // Only assert removal for a fixture the login-scoped query can actually see; the point
        // of the scope is that anything outside the login keychain is never touched.
        let wasInLoginKeychain = !KeychainHelper
            .enumerateRockxyCertificates(label: targetLabel, searchList: [loginKeychain])
            .isEmpty

        KeychainHelper.removeAllRockxyCertsFromLoginKeychain(label: targetLabel)

        if wasInLoginKeychain {
            #expect(KeychainHelper.isCertificateInstalled(label: targetLabel) == false)
        }
        #expect(KeychainHelper.isCertificateInstalled(label: sentinelLabel))
    }
}

// MARK: - RootCARemovalSafetyTests

/// `reset()` destroys the only material that can identify — and remove — the installed root CA,
/// so removal has to come first and has to be verified. A helper reply is not verification: the
/// daemon's sweep is label-based, its trust removal swallows CLI failures, and a legacy import
/// can carry a common name instead of the configured label.
@Suite(.serialized)
struct RootCARemovalSafetyTests {
    // MARK: Internal

    @Test("cold reset still identifies a legacy installed certificate when its key is missing")
    func coldResetWithMissingKeyRemovesLegacyCertificate() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }
        let root = try RootCAGenerator.generate()
        try CertificateStore.saveRootCACertificate(root.certificate)
        let der = try certificateDER(root.certificate)
        let legacyLabel = "\(overrides.label).legacy"
        try KeychainHelper.installCertificate(der, label: legacyLabel)
        defer { try? KeychainHelper.removeCertificate(label: legacyLabel) }

        let manager = CertificateManager.makeForTesting()
        try await manager.reset()

        #expect(try CertificateStore.loadRootCACertificate() == nil)
        #expect(try !KeychainHelper.isCertificateInstalledStrict(certData: der))
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == nil)
    }

    @Test("cold reset refuses unreadable certificate data before helper or local deletion")
    func unreadableRemovalTargetPreservesKey() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }
        let root = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(root.privateKey)
        try CertificateStore.saveRootCACertificate(root.certificate)
        let certificateURL = CertificateStore.rootCACertificateURL
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: certificateURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: certificateURL.path) }
        let gate = RemovalGate()
        let manager = CertificateManager.makeForTesting()
        await manager.setHelperRemovalOverrideForTests { _ in gate.markStarted() }

        await #expect(throws: (any Error).self) { try await manager.reset() }

        #expect(!gate.hasStarted)
        #expect(FileManager.default.fileExists(atPath: certificateURL.path))
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == Data(root.privateKey.x963Representation))
    }

    @Test("removal presence checks reject unknown errors and recognize both no-settings statuses")
    func strictTrustAbsenceClassification() throws {
        #expect(try KeychainHelper.trustSettingsExist(status: errSecSuccess))
        #expect(try !KeychainHelper.trustSettingsExist(status: errSecItemNotFound))
        #expect(try !KeychainHelper.trustSettingsExist(status: errSecNoTrustSettings))
        #expect(throws: KeychainError.self) {
            try KeychainHelper.trustSettingsExist(status: errSecAuthFailed)
        }
        #expect(throws: KeychainError.self) {
            try KeychainHelper.isCertificateInstalledStrict(certData: Data())
        }
        #expect(throws: KeychainError.self) {
            try KeychainHelper.hasAnyTrustSettings(certData: Data())
        }
    }

    @Test("a removal that leaves the certificate installed preserves the key, the PEM, and the fingerprint")
    func removalFailurePreservesLocalIdentity() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())
        let originalKey = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))
        let originalCertificateBytes = try Data(contentsOf: CertificateStore.rootCACertificateURL)
        _ = await manager.validateSystemTrust()

        // Simulate an app-side operation that falsely reports completion without deleting.
        await manager.setAppRemovalOverrideForTests { _ in }
        let persistedDER = try await manager.getRootCADER()
        let der = try #require(persistedDER)
        let legacyLabel = "\(TestIdentity.keychainProbeLabel).legacy.\(UUID().uuidString)"
        try KeychainHelper.installCertificate(der, label: legacyLabel)
        defer { try? KeychainHelper.removeCertificate(label: legacyLabel) }

        let counter = NotificationCounter()
        await manager.observeStatusNotificationsForTests { counter.increment() }

        await #expect(throws: CertificateManagerError.self) {
            try await manager.reset()
        }

        // Nothing local was destroyed, so the CA the user approved is still usable and still
        // identifies the copy that is still installed.
        #expect(await manager.getActiveRootFingerprint() == originalFingerprint)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == originalKey)
        #expect(try Data(contentsOf: CertificateStore.rootCACertificateURL) == originalCertificateBytes)
        #expect(KeychainHelper.isCertificateInstalled(certData: der))

        // Derived trust state is invalidated and observers are told once to re-read reality.
        #expect(await manager.lastTrustValidationResult == nil)
        let message = try #require(await manager.lastValidationErrorMessage)
        #expect(message.contains("still installed"))
        #expect(counter.posts == 1)
    }

    @Test("a helper success reply does not authorize destroying the local key and certificate")
    func helperFalseSuccessRefusesLocalCleanup() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())
        let originalKey = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))

        let persistedDER = try await manager.getRootCADER()
        let der = try #require(persistedDER)
        let legacyLabel = "\(TestIdentity.keychainProbeLabel).legacy.\(UUID().uuidString)"
        try KeychainHelper.installCertificate(der, label: legacyLabel)
        defer { try? KeychainHelper.removeCertificate(label: legacyLabel) }

        // Stands in for the real daemon replying "removed" after a label-based sweep that found
        // nothing and a trust removal that swallowed its own failure.
        let gate = RemovalGate()
        await manager.setHelperRemovalOverrideForTests { _ in gate.markStarted() }
        await manager.setAppRemovalOverrideForTests { _ in }

        await #expect(throws: CertificateManagerError.self) {
            try await manager.reset()
        }

        #expect(gate.hasStarted)
        #expect(await manager.getActiveRootFingerprint() == originalFingerprint)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == originalKey)
        #expect(try CertificateStore.loadRootCACertificate() != nil)
        #expect(KeychainHelper.isCertificateInstalled(certData: der))
    }

    @Test("a reset suspended in the privileged removal rejects every competing mutation")
    func removalInFlightRejectsCompetingMutations() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()

        let gate = RemovalGate()
        await manager.setHelperRemovalOverrideForTests { _ in
            gate.markStarted()
            while !gate.isReleased {
                try? await Task.sleep(nanoseconds: 500_000)
            }
        }

        let resetTask = Task { try await manager.reset() }
        let removalStarted = await waitUntil { gate.hasStarted }
        #expect(removalStarted)

        // The guard is held across the helper await, so nothing may replace, adopt, or
        // re-delete the material this removal is working on.
        await #expect(throws: CertificateManagerError.rootRemovalInProgress) {
            try await manager.generateRootCA()
        }
        await #expect(throws: CertificateManagerError.rootRemovalInProgress) {
            try await manager.reset()
        }
        await #expect(throws: CertificateManagerError.rootRemovalInProgress) {
            try await manager.removeRootCATrust()
        }
        await #expect(throws: CertificateManagerError.rootRemovalInProgress) {
            try await manager.installAndTrust()
        }
        await #expect(throws: CertificateManagerError.rootRemovalInProgress) {
            try await manager.loadExistingRootCA()
        }

        gate.release()
        try await resetTask.value

        // The guard is released, so the removal completed normally.
        #expect(await manager.getActiveRootFingerprint() == nil)
    }

    @Test("a cancelled reset deletes nothing and leaves the guard released")
    func cancelledResetDeletesNothing() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())

        let task = Task {
            // Enter `reset()` already cancelled, so nothing can be removed or deleted before
            // the first cancellation check.
            while !Task.isCancelled {
                await Task.yield()
            }
            try await manager.reset()
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(await manager.getActiveRootFingerprint() == originalFingerprint)
        #expect(try CertificateStore.loadRootCACertificate() != nil)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) != nil)

        // The guard is released on every exit path, so the next reset is not rejected.
        try await manager.reset()
        #expect(await manager.getActiveRootFingerprint() == nil)
    }

    @Test("cancellation during helper removal preserves local material and notifies once")
    func cancellationDuringHelperRemovalPreservesIdentity() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }
        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let fingerprint = await manager.getActiveRootFingerprint()
        let key = try KeychainHelper.loadPrivateKey(label: overrides.label)
        let gate = RemovalGate()
        let counter = NotificationCounter()
        await manager.observeStatusNotificationsForTests { counter.increment() }
        await manager.setHelperRemovalOverrideForTests { _ in
            gate.markStarted()
            while !gate.isReleased {
                try? await Task.sleep(nanoseconds: 500_000)
            }
        }
        let task = Task { try await manager.reset() }
        #expect(await waitUntil { gate.hasStarted })
        task.cancel()
        gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(await manager.getActiveRootFingerprint() == fingerprint)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == key)
        #expect(try CertificateStore.loadRootCACertificate() != nil)
        #expect(counter.posts == 1)
        await manager.setHelperRemovalOverrideForTests(nil)
        try await manager.reset()
    }

    @Test("a verified removal deletes the certificate, the PEM, and the key exactly once")
    func successfulResetRemovesEverything() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        try await manager.installRootCAInKeychain()
        let persistedDER = try await manager.getRootCADER()
        let der = try #require(persistedDER)
        #expect(KeychainHelper.isCertificateInstalled(certData: der))

        let counter = NotificationCounter()
        await manager.observeStatusNotificationsForTests { counter.increment() }

        try await manager.reset()

        #expect(KeychainHelper.isCertificateInstalled(certData: der) == false)
        #expect(KeychainHelper.isCertificateInstalled(label: overrides.certificateLabel) == false)
        #expect(try CertificateStore.loadRootCACertificate() == nil)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == nil)
        #expect(await manager.getActiveRootFingerprint() == nil)
        #expect(counter.posts == 1)
    }

    @Test("the helper is given exactly the deduplicated certificates the verification will check")
    func helperReceivesDeduplicatedTargets() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        try await manager.installRootCAInKeychain()
        let der = try #require(await manager.getRootCADER())

        let recorder = RemovalTargetRecorder()
        await manager.setHelperRemovalOverrideForTests { targets in recorder.record(targets) }

        try await manager.reset()

        // The adopted certificate and the label-discovered copy are the same certificate, so
        // the privileged call names it once — never twice, and never a bare label.
        #expect(recorder.calls == 1)
        #expect(recorder.targets == [der])
    }

    @Test("nothing installed and nothing persisted never reaches the privileged helper")
    func emptyTargetsSkipTheHelper() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        let recorder = RemovalTargetRecorder()
        await manager.setHelperRemovalOverrideForTests { targets in recorder.record(targets) }

        try await manager.reset()

        // With no certificate to name, a privileged removal could only be a label sweep.
        #expect(recorder.calls == 0)
    }

    @Test("a helper too old for exact removal still completes through verified app-side removal")
    func unsupportedHelperFallsBackToVerifiedAppSideRemoval() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        try await manager.installRootCAInKeychain()
        let der = try #require(await manager.getRootCADER())
        await manager.setHelperRemovalOverrideForTests { _ in
            throw HelperConnectionError.certRemovalUnsupported
        }

        try await manager.reset()

        // The app-side removal cleared everything the verification checks, so the outdated
        // helper does not turn into a failed reset — but the verification still had to pass.
        #expect(KeychainHelper.isCertificateInstalled(certData: der) == false)
        #expect(try CertificateStore.loadRootCACertificate() == nil)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == nil)
    }

    @Test("a helper failure that leaves a copy installed keeps local material and reports the reason")
    func helperFailurePreservesLocalMaterial() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())
        let originalKey = try #require(try KeychainHelper.loadPrivateKey(label: overrides.label))
        let der = try #require(await manager.getRootCADER())

        // Simulate failed removal in both paths, without requiring a real trusted fixture.
        await manager.setAppRemovalOverrideForTests { _ in }
        let legacyLabel = "\(TestIdentity.keychainProbeLabel).legacy.\(UUID().uuidString)"
        try KeychainHelper.installCertificate(der, label: legacyLabel)
        defer { try? KeychainHelper.removeCertificate(label: legacyLabel) }

        await manager.setHelperRemovalOverrideForTests { _ in
            throw HelperConnectionError.certRemoveFailed("daemon refused")
        }

        await #expect(throws: CertificateManagerError.self) {
            try await manager.reset()
        }

        #expect(await manager.getActiveRootFingerprint() == originalFingerprint)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == originalKey)
        #expect(try CertificateStore.loadRootCACertificate() != nil)
        let message = try #require(await manager.lastValidationErrorMessage)
        #expect(message.contains("still installed"))
        #expect(message.contains("daemon refused"))
    }

    @Test("legacy login certificate removal preserves a different root with the same common name")
    func legacyLoginRemovalPreservesOtherRoot() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }
        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let target = try #require(await manager.getRootCADER())
        let other = try certificateDER(RootCAGenerator.generate().certificate)
        let targetLabel = overrides.label + ".legacy"
        let otherLabel = overrides.label + ".other"
        try KeychainHelper.installCertificate(target, label: targetLabel)
        defer { try? KeychainHelper.removeCertificate(label: targetLabel) }
        try KeychainHelper.installCertificate(other, label: otherLabel)
        defer { try? KeychainHelper.removeCertificate(label: otherLabel) }
        await manager.setHelperRemovalOverrideForTests { _ in
            throw HelperConnectionError.certRemovalUnsupported
        }

        try await manager.reset()

        #expect(try !KeychainHelper.isCertificateInstalledStrict(certData: target))
        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: other))
        #expect(try CertificateStore.loadRootCACertificate() == nil)
    }

    @Test("app-side permission failure retains the pair and the helper update recovery reason")
    func appRemovalFailurePreservesMaterialAndRecovery() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }
        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let fingerprint = await manager.getActiveRootFingerprint()
        let key = try KeychainHelper.loadPrivateKey(label: overrides.label)
        await manager.setHelperRemovalOverrideForTests { _ in
            throw HelperConnectionError.certRemovalUnsupported
        }
        await manager.setAppRemovalOverrideForTests { _ in throw KeychainError.deleteFailed(errSecAuthFailed) }

        await #expect(throws: CertificateManagerError.self) { try await manager.reset() }

        #expect(await manager.getActiveRootFingerprint() == fingerprint)
        #expect(try KeychainHelper.loadPrivateKey(label: overrides.label) == key)
        #expect(try CertificateStore.loadRootCACertificate() != nil)
        let message = try #require(await manager.lastValidationErrorMessage)
        #expect(message.contains("Advanced"))
        #expect(message.contains(String(errSecAuthFailed)))
    }

    // MARK: Private

    private func waitUntil(_ condition: @Sendable @escaping () -> Bool) async -> Bool {
        for _ in 0 ..< 4_000 {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return condition()
    }
}

// MARK: - RemovalTargetRecorder

/// Captures the exact removal targets a manager hands to the privileged helper.
private final class RemovalTargetRecorder: @unchecked Sendable {
    // MARK: Internal

    var calls: Int {
        lock.withLock { recorded.count }
    }

    var targets: [Data] {
        lock.withLock { recorded.flatMap { $0 } }
    }

    func record(_ targets: [Data]) {
        lock.withLock { recorded.append(targets) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var recorded: [[Data]] = []
}

// MARK: - RemovalGate

/// Lets a test hold a manager's injected helper removal suspended, so the actor's removal guard
/// can be observed while a removal is genuinely in flight.
private final class RemovalGate: @unchecked Sendable {
    // MARK: Internal

    var hasStarted: Bool {
        lock.withLock { started }
    }

    var isReleased: Bool {
        lock.withLock { released }
    }

    func markStarted() {
        lock.withLock { started = true }
    }

    func release() {
        lock.withLock { released = true }
    }

    // MARK: Private

    private let lock = NSLock()
    private var started = false
    private var released = false
}

// MARK: - RootCAStatusLoadAttemptTests

/// One status answer must attempt the persisted load at most once. Retrying it repeats the same
/// failing Keychain and filesystem work and lets the second failure overwrite the first
/// diagnostic, which is the only explanation the UI has for the red state.
@Suite(.serialized)
struct RootCAStatusLoadAttemptTests {
    @Test("a snapshot whose persisted load fails attempts that load exactly once")
    func failedSnapshotLoadsOnce() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let persisted = try RootCAGenerator.generate()
        try CertificateStore.saveRootCAPrivateKey(persisted.privateKey)
        try CertificateStore.saveRootCACertificate(persisted.certificate)

        let certificateURL = CertificateStore.rootCACertificateURL
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: certificateURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: certificateURL.path)
        }

        let manager = CertificateManager.makeForTesting()
        let snapshot = await manager.rootCAStatusSnapshot()

        #expect(await manager.persistedRootLoadAttemptsForTests == 1)
        #expect(snapshot.hasGeneratedCertificate == false)
        #expect(snapshot.isSystemTrustValidated == false)
        // The read failure stays the reported cause instead of being replaced by a second one.
        let message = try #require(snapshot.lastValidationErrorMessage)
        #expect(message.contains("No root CA certificate or private key available") == false)

        // A later refresh is a new answer, so it retries once — never twice within one answer.
        let refreshed = await manager.rootCAStatusSnapshot()
        #expect(await manager.persistedRootLoadAttemptsForTests == 2)
        #expect(refreshed.lastValidationErrorMessage == message)

        // The standalone getter is still the only load opportunity its own callers have.
        #expect(await manager.isRootCAInstalled() == false)
        #expect(await manager.persistedRootLoadAttemptsForTests == 3)
    }
}

// MARK: - Shared Helpers

private func certificateDER(_ certificate: Certificate) throws -> Data {
    var serializer = DER.Serializer()
    try certificate.serialize(into: &serializer)
    return Data(serializer.serializedBytes)
}

private func certificateFingerprint(_ certificate: Certificate) -> String? {
    guard let der = try? certificateDER(certificate) else {
        return nil
    }
    return KeychainHelper.computeFingerprintSHA256(der)
}
