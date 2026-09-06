import Crypto
import Foundation
@testable import Rockxy
import Security
import SwiftASN1
import Testing
import X509

// Regression tests for two lifecycle defects found while investigating #319.
//
// The first: installing a certificate destroyed other certificates. `installAndTrust()` swept
// stale certificates through the helper before the install, swept the login keychain after it, and
// swept again on the fallback path — so a routine reinstall, and even a *failed* one, removed roots
// the user was still relying on.
//
// The second: the install was routed to the privileged helper whenever one was reachable. Adding
// the certificate worked there; the trust write did not. Marking a root trusted in the `.admin`
// domain needs interactive Authorization Services, which a launchd daemon has no session for, so it
// was denied even as root — leaving an installed, untrusted certificate and nobody to ask for the
// approval. The trust write now always happens in this GUI process.
//
// The rules pinned here are that the installation only ever adds, that it always runs app-side and
// sends no helper installation RPC, and that a real `SecTrust` evaluation is the only thing that
// counts as success.

// MARK: - RootCAInstallDispatchRuleTests

/// Classification for the legacy `HelperConnection.installRootCertificate` dispatch path, which
/// survives for compatibility. `installAndTrust()` no longer consults it — it never asks the helper
/// at all — but the rules still govern anything that does send that RPC.
struct RootCAInstallDispatchRuleTests {
    @Test("only a proven not-dispatched failure licenses an app-side install")
    func onlyNotDispatchedFailuresAllowFallback() {
        struct HelperFailure: Error {}

        #expect(CertificateManager.helperInstallSentNothing(HelperInstallNotDispatched(HelperFailure())))
        // Everything else may have been applied by the daemon, so a second attempt would mean a
        // second admin dialog for material that is possibly already installed.
        #expect(CertificateManager.helperInstallSentNothing(HelperFailure()) == false)
        #expect(CertificateManager.helperInstallSentNothing(HelperConnectionError.xpcTimeout) == false)
        #expect(CertificateManager
            .helperInstallSentNothing(HelperConnectionError.certInstallFailed("refused")) == false)
        #expect(CertificateManager.helperInstallSentNothing(CancellationError()) == false)
    }

    @Test("only known non-destructive helper protocols may be asked to install")
    func onlyKnownNonDestructiveProtocolsInstallSafely() {
        #expect(HelperCompatibilityPolicy.safeCertificateInstallProtocolVersion == 2)
        #expect(HelperCompatibilityPolicy.supportsSafeCertificateInstall(protocolVersion: 2))
        #expect(HelperCompatibilityPolicy.supportsSafeCertificateInstall(protocolVersion: 3))

        // The selector is as old as protocol 1, so its presence proves nothing, and a build number
        // proves less: shipped copies embed a protocol 1 helper at or above this build.
        for protocolVersion in [-1, 0, 1, 4, 99] {
            #expect(HelperCompatibilityPolicy
                .supportsSafeCertificateInstall(protocolVersion: protocolVersion) == false)
        }
    }
}

// MARK: - RootCANonDestructiveInstallTests

@Suite(.serialized)
struct RootCANonDestructiveInstallTests {
    // MARK: Internal

    @Test("the install runs app-side, sends no helper RPC, and deletes no other certificate")
    func installAlwaysRunsAppSide() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()

        // An older Rockxy root, installed under the very label a sweep used to address.
        let older = try nonDestructiveInstallDER(RootCAGenerator.generate().certificate)
        try KeychainHelper.installCertificate(older, label: overrides.certificateLabel)

        let recorder = InstallCallRecorder()
        await manager.setHelperInstallOverrideForTests { der in
            recorder.recordHelper(der)
            Issue.record("The trust installation must not dispatch a helper installation RPC")
        }
        await manager.setAppInstallOverrideForTests { der in recorder.recordApp(der) }

        // A test CA is never actually system-trusted, so the final real evaluation fails — which
        // is the point: an install that macOS does not honour must not report success.
        await #expect(throws: CertificateManagerError.trustValidationFailed) {
            try await manager.installAndTrust()
        }

        let target = try #require(await manager.getRootCADER())
        // Exactly one privileged path ran, and it was the one that can raise the dialog macOS is
        // waiting for. The daemon can add the certificate but not trust it, so it is never asked.
        #expect(recorder.appPayloads == [target])
        #expect(recorder.helperPayloads.isEmpty)
        // Nothing was swept: not before the install, not after it.
        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: older))
        #expect(KeychainHelper.isCertificateInstalled(label: overrides.certificateLabel))
    }

    @Test("a helper that is present, outdated, or absent makes no difference to the route")
    func helperStateNeverChangesTheRoute() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()

        // Each injected helper installer models one of the states the route used to branch on: a
        // helper that would have accepted the install, one that refuses before dispatching, and one
        // that fails after dispatching. None of them is consulted any more.
        let helperBehaviours: [@Sendable (Data) async throws -> Void] = [
            { _ in },
            { _ in throw HelperInstallNotDispatched(HelperConnectionError.certInstallUnsupported) },
            { _ in throw HelperConnectionError.certInstallFailed("daemon refused") }
        ]

        for behaviour in helperBehaviours {
            try await manager.generateRootCA()
            let recorder = InstallCallRecorder()
            await manager.setHelperInstallOverrideForTests { der in
                recorder.recordHelper(der)
                try await behaviour(der)
            }
            await manager.setAppInstallOverrideForTests { der in recorder.recordApp(der) }

            await #expect(throws: CertificateManagerError.trustValidationFailed) {
                try await manager.installAndTrust()
            }

            let target = try #require(await manager.getRootCADER())
            #expect(recorder.appPayloads == [target])
            #expect(recorder.helperPayloads.isEmpty)
        }
    }

    @Test("a refused authorization dialog is reported as itself, with no second attempt")
    func refusedAuthorizationIsReportedOnce() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()

        let older = try nonDestructiveInstallDER(RootCAGenerator.generate().certificate)
        try KeychainHelper.installCertificate(older, label: overrides.certificateLabel)

        let recorder = InstallCallRecorder()
        await manager.setHelperInstallOverrideForTests { der in
            recorder.recordHelper(der)
            Issue.record("A refused dialog must not be answered by asking the daemon instead")
        }
        await manager.setAppInstallOverrideForTests { der in
            recorder.recordApp(der)
            throw KeychainError.trustNotApplied
        }

        let failure = await #expect(throws: KeychainError.self) {
            try await manager.installAndTrust()
        }

        #expect(failure?.errorDescription?.contains("Trust settings were not applied") == true)
        // One attempt, one dialog. The reason is kept for the UI, and nothing claims a rollback.
        #expect(recorder.appPayloads.count == 1)
        #expect(recorder.helperPayloads.isEmpty)
        let message = try #require(await manager.lastValidationErrorMessage)
        #expect(message.contains("authorization prompt"))
        #expect(try KeychainHelper.isCertificateInstalledStrict(certData: older))
    }

    @Test("competing mutations are rejected while the authorization dialog is open")
    func mutationsRejectedWhileDialogIsOpen() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let originalFingerprint = try #require(await manager.getActiveRootFingerprint())

        // The injected installer stands in for the macOS dialog: the actor stays suspended inside
        // it, exactly as it does while a real approval is on screen.
        let gate = InstallGate()
        await manager.setAppInstallOverrideForTests { _ in
            gate.markStarted()
            while !gate.isReleased {
                try? await Task.sleep(nanoseconds: 500_000)
            }
        }

        let task = Task { try await manager.installAndTrust() }
        #expect(await waitUntil { gate.hasStarted })

        // A second install would raise a second dialog for the same material; the others would
        // replace what this one is trusting.
        await #expect(throws: CertificateManagerError.trustInstallationInProgress) {
            try await manager.installAndTrust()
        }
        await #expect(throws: CertificateManagerError.trustInstallationInProgress) {
            try await manager.generateRootCA()
        }
        await #expect(throws: CertificateManagerError.trustInstallationInProgress) {
            try await manager.reset()
        }
        await #expect(throws: CertificateManagerError.trustInstallationInProgress) {
            try await manager.removeRootCATrust()
        }

        gate.release()
        await #expect(throws: CertificateManagerError.trustValidationFailed) { try await task.value }
        #expect(await manager.getActiveRootFingerprint() == originalFingerprint)
    }

    @Test("cancellation while the dialog is open does not validate or install again")
    func cancelledDialogStopsBeforeValidation() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }
        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        await manager.clearFreshlyInstalledFlag()
        let gate = InstallGate()
        let recorder = InstallCallRecorder()
        await manager.setHelperInstallOverrideForTests { der in recorder.recordHelper(der) }
        await manager.setAppInstallOverrideForTests { der in
            recorder.recordApp(der)
            gate.markStarted()
            while !gate.isReleased {
                try? await Task.sleep(nanoseconds: 500_000)
            }
        }
        let task = Task { try await manager.installAndTrust() }
        let started = await waitUntil { gate.hasStarted }
        #expect(started)
        task.cancel()
        gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }

        // The dialog was answered once at most; a cancelled request neither repeats it nor reports
        // a validation result for work whose outcome it stopped waiting for.
        #expect(recorder.appPayloads.count == 1)
        #expect(recorder.helperPayloads.isEmpty)
        #expect(await manager.lastTrustValidationResult == nil)
        #expect(await manager.rootCAFreshlyInstalled == false)
    }

    @Test("tests without an app installer override cannot request actual administrator approval")
    func missingTestInstallerFailsClosed() async throws {
        try #require(RockxyIdentity.isRunningTests)
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }
        let manager = CertificateManager.makeForTesting()
        try await manager.generateRootCA()
        let error = await #expect(throws: CertificateManagerError.self) {
            try await manager.installAndTrust()
        }
        #expect(error?.errorDescription?.contains("tests require an injected app-side installer") == true)
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

// MARK: - InstallCallRecorder

/// Records which installation path a manager actually took, and with which bytes.
private final class InstallCallRecorder: @unchecked Sendable {
    // MARK: Internal

    var helperPayloads: [Data] {
        lock.withLock { helper }
    }

    var appPayloads: [Data] {
        lock.withLock { app }
    }

    func recordHelper(_ derData: Data) {
        lock.withLock { helper.append(derData) }
    }

    func recordApp(_ derData: Data) {
        lock.withLock { app.append(derData) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var helper: [Data] = []
    private var app: [Data] = []
}

// MARK: - InstallGate

/// Holds an injected helper install suspended, so the actor can be observed mid-install.
private final class InstallGate: @unchecked Sendable {
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

// MARK: - Shared Helpers

private func nonDestructiveInstallDER(_ certificate: Certificate) throws -> Data {
    var serializer = DER.Serializer()
    try certificate.serialize(into: &serializer)
    return Data(serializer.serializedBytes)
}
