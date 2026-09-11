import Foundation
import os
import SwiftUI

// Owns the original four-step onboarding flow and helper recovery state.

// MARK: - WelcomeViewModel

@MainActor @Observable
final class WelcomeViewModel {
    // MARK: Internal

    enum ActiveAction: Equatable {
        case certificate
        case helper
        case systemProxy
    }

    enum ErrorArea: Equatable {
        case certificate
        case helper
        case systemProxy
    }

    /// An incomplete app bundle cannot be repaired by deleting the currently installed helper.
    /// Other helper failures can offer the confirmed hard-remove-and-reinstall path.
    enum HelperFailureRecovery: Equatable {
        case repairAndReinstall
        case rebuildApp
        case reopenApp
        /// The helper is still installed and still approved; the operation simply did not
        /// converge. Offering a reinstall here is what turns a recoverable app update into a
        /// second Login Items approval prompt.
        case retryLater
    }

    /// What the two certificate steps should show for one readiness answer.
    ///
    /// Pure so the unavailable case can be exercised without a coordinator, a Keychain, or an
    /// authorization dialog: an unreadable status is neither "generated" nor "trusted", and the
    /// only action it may offer is a recheck.
    nonisolated struct CertificateStepState: Equatable {
        let isGenerated: Bool
        let isTrusted: Bool
        /// Set only when the status could not be read. Kept out of `errorMessage` so it can
        /// never overwrite an unrelated helper or system-proxy failure.
        let unavailableMessage: String?

        var isUnavailable: Bool {
            unavailableMessage != nil
        }
    }

    var certInstalled = false
    var certTrusted = false
    private(set) var certStatusUnavailableMessage: String?
    var helperStatus: HelperManager.HelperStatus = .notInstalled
    var helperSigningIssue: HelperManager.SigningIssue?
    var helperAutomaticRefreshRecoveryPending = false
    var systemProxyEnabled = false

    private(set) var activeAction: ActiveAction?
    private(set) var errorArea: ErrorArea?
    private(set) var helperFailureRecovery: HelperFailureRecovery?
    private(set) var isCheckingSystem = false
    var errorMessage: String?

    var isPerformingAction: Bool {
        activeAction != nil
    }

    var isBusy: Bool {
        isCheckingSystem || isPerformingAction
    }

    var completedSteps: Int {
        var count = 0
        if certInstalled {
            count += 1
        }
        if certTrusted {
            count += 1
        }
        if helperStatus == .installedCompatible {
            count += 1
        }
        if systemProxyEnabled {
            count += 1
        }
        return count
    }

    var totalSteps: Int {
        4
    }

    var canGetStarted: Bool {
        certInstalled && certTrusted && helperStatus == .installedCompatible && systemProxyEnabled
    }

    var helperActionLabel: String? {
        HelperManager.helperActionLabel(
            status: helperStatus,
            signingIssue: helperSigningIssue
        )
    }

    var shouldOfferHelperRepair: Bool {
        !helperAutomaticRefreshRecoveryPending && (helperStatus == .unreachable
            || helperStatus == .requiresApproval
            || helperFailureRecovery == .repairAndReinstall)
    }

    var shouldShowHelperDiagnostics: Bool {
        if errorArea == .helper || helperFailureRecovery == .rebuildApp {
            return true
        }
        if case .appSignatureInvalid = helperSigningIssue {
            return helperStatus == .signingMismatch
        }
        return false
    }

    var helperStatusDetail: String? {
        switch helperStatus {
        case .notInstalled:
            nil
        case .requiresApproval:
            String(
                localized: "Approve Rockxy in System Settings → General → Login Items, then return here.",
                bundle: RockxyLocalization.bundle
            )
        case .installedCompatible:
            String(localized: "Installed, compatible, and reachable.", bundle: RockxyLocalization.bundle)
        case .installedOutdated:
            String(
                localized: "An older helper is installed. Update it from this version of Rockxy.",
                bundle: RockxyLocalization.bundle
            )
        case .installedIncompatible:
            String(
                localized: "The installed helper is incompatible with this version of Rockxy.",
                bundle: RockxyLocalization.bundle
            )
        case .unreachable:
            String(
                localized: "The helper is registered, but Rockxy cannot reach it.",
                bundle: RockxyLocalization.bundle
            )
        case .signingMismatch:
            switch helperSigningIssue {
            case .applicationMustReopen:
                String(
                    localized: "Quit and reopen Rockxy, then check the helper again.",
                    bundle: RockxyLocalization.bundle
                )
            case .identityMismatch:
                String(
                    localized: "The installed helper does not match this copy of Rockxy.",
                    bundle: RockxyLocalization.bundle
                )
            case .appSignatureInvalid,
                 nil:
                String(
                    localized: "Rockxy could not verify this app copy. Open diagnostics before continuing.",
                    bundle: RockxyLocalization.bundle
                )
            }
        }
    }

    var isCertStatusUnavailable: Bool {
        certStatusUnavailableMessage != nil
    }

    static func canBeginAction(current: ActiveAction?, isCheckingSystem: Bool = false) -> Bool {
        current == nil && !isCheckingSystem
    }

    /// Maps one readiness answer onto the certificate steps.
    ///
    /// `.unknown` is deliberately not folded into "generated": marking step 1 complete because
    /// the readiness is merely not `.notGenerated` claims a certificate nobody could read.
    nonisolated static func certificateStepState(
        certReadiness: CertReadiness,
        snapshot: RootCAStatusSnapshot?
    )
        -> CertificateStepState
    {
        guard certReadiness != .unknown else {
            return CertificateStepState(
                isGenerated: snapshot?.isGeneratedStateKnown == true && snapshot?.hasGeneratedCertificate == true,
                isTrusted: false,
                unavailableMessage: snapshot?.statusReadErrorMessage ?? String(
                    localized: "Rockxy cannot read the certificate and trust status right now.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
        return CertificateStepState(
            isGenerated: certReadiness != .notGenerated,
            isTrusted: certReadiness == .trusted,
            unavailableMessage: nil
        )
    }

    static func resolveHelperFailureRecovery(for error: Error) -> HelperFailureRecovery {
        if let operationError = error as? HelperManager.HelperOperationError {
            switch operationError {
            case .applicationMustReopen:
                return .reopenApp
            case .helperPackageIncomplete:
                return .rebuildApp
            case .automaticHelperRefreshFailed,
                 .helperApprovalRequired,
                 .helperUpdateUnavailable:
                // The approved registration was never touched, so the recovery is to try again —
                // not to delete a working helper and ask the user to approve a new one.
                return .retryLater
            case .appSignatureInvalid:
                return .repairAndReinstall
            }
        }
        if error is HelperManager.HelperInstallPreflightError {
            return .rebuildApp
        }
        return .repairAndReinstall
    }

    func loadInitialStatus() async {
        guard !isCheckingSystem, activeAction == nil else {
            return
        }
        isCheckingSystem = true
        defer { isCheckingSystem = false }

        let readiness = ReadinessCoordinator.shared
        await readiness.deepRefresh()
        apply(readiness: readiness)
    }

    func refreshStatus() async {
        await ReadinessCoordinator.shared.refresh()
        apply(readiness: ReadinessCoordinator.shared)
    }

    func syncFromCoordinator() {
        apply(readiness: ReadinessCoordinator.shared)
    }

    func installCert() async {
        guard !certTrusted, !isCertStatusUnavailable else {
            return
        }
        await perform(.certificate, errorArea: .certificate) {
            try await CertificateManager.shared.installAndTrust()
        }
    }

    /// Re-reads the real certificate state and nothing else.
    ///
    /// The recovery for an unreadable status is a read, never an install or a trust write: those
    /// would raise an administrator prompt for material this app cannot describe. Unrelated
    /// helper and system-proxy failures are left exactly as they are.
    func recheckCertificateStatus() async {
        guard Self.canBeginAction(current: activeAction, isCheckingSystem: isCheckingSystem) else {
            return
        }
        activeAction = .certificate
        defer { activeAction = nil }

        await ReadinessCoordinator.shared.deepRefresh()
        apply(readiness: ReadinessCoordinator.shared)
    }

    func installHelper() async {
        await perform(.helper, errorArea: .helper) {
            try await HelperManager.shared.install()
        }
    }

    func applyHelperState(
        status: HelperManager.HelperStatus,
        signingIssue: HelperManager.SigningIssue?,
        automaticRefreshRecoveryPending: Bool = false
    ) {
        helperStatus = status
        helperSigningIssue = signingIssue
        helperAutomaticRefreshRecoveryPending = automaticRefreshRecoveryPending
    }

    /// Applies one resolved certificate step state. Kept separate from `apply(readiness:)` so a
    /// test can drive the four-step UI from a snapshot without the shared coordinator.
    func applyCertificateState(_ state: CertificateStepState) {
        certInstalled = state.isGenerated
        certTrusted = state.isTrusted
        certStatusUnavailableMessage = state.unavailableMessage
        if !state.isUnavailable, certificateErrorWasUnavailable, errorArea == .certificate {
            errorMessage = nil
            errorArea = nil
            certificateErrorWasUnavailable = false
        }
    }

    func retryHelperConnection() async {
        guard begin(.helper, errorArea: .helper) else {
            return
        }
        defer { activeAction = nil }

        if helperAutomaticRefreshRecoveryPending {
            await HelperManager.shared.reconcileEmbeddedHelperOnLaunch()
        } else {
            await HelperManager.shared.retryConnection()
        }
        await refreshStatus()

        guard helperStatus == .unreachable else {
            errorArea = nil
            return
        }
        errorMessage = HelperManager.shared.lastErrorMessage
            ?? String(localized: "Rockxy still cannot reach the installed helper.", bundle: RockxyLocalization.bundle)
        helperFailureRecovery = helperAutomaticRefreshRecoveryPending ? .retryLater : .repairAndReinstall
    }

    func repairAndReinstallHelper() async {
        guard begin(.helper, errorArea: .helper) else {
            return
        }
        defer { activeAction = nil }

        let captureWasActive = ReadinessCoordinator.shared.isCaptureActive
        if captureWasActive {
            NotificationCenter.default.post(name: .stopProxyRequested, object: nil)
            try? await Task.sleep(for: .milliseconds(750))
        }

        do {
            _ = try await HelperManager.shared.forceResetAndReinstall(resetBackgroundItems: false)
            await refreshStatus()
            if helperStatus == .unreachable {
                errorMessage = HelperManager.shared.lastErrorMessage
                    ?? String(
                        localized: "Rockxy reinstalled the helper but still cannot reach it.",
                        bundle: RockxyLocalization.bundle
                    )
                helperFailureRecovery = .repairAndReinstall
            } else {
                errorArea = nil
            }
        } catch {
            Self.logger.error("Failed to repair helper: \(error.localizedDescription)")
            await refreshStatus()
            recordFailure(error, area: .helper)
        }
    }

    func reinstallHelper() async {
        await perform(.helper, errorArea: .helper) {
            try await HelperManager.shared.reinstall()
        }
    }

    func updateHelper() async {
        await perform(.helper, errorArea: .helper) {
            try await HelperManager.shared.update()
        }
    }

    func enableProxy() async {
        await perform(.systemProxy, errorArea: .systemProxy) {
            let settings = AppSettingsStorage.load()
            try await SystemProxyManager.shared.enableSystemProxy(port: settings.proxyPort)
        }
    }

    func recordFailure(_ error: Error, area: ErrorArea) {
        errorMessage = error.localizedDescription
        errorArea = area
        if area == .certificate, case CertificateManagerError.trustStateUnavailable = error {
            certificateErrorWasUnavailable = true
        } else {
            certificateErrorWasUnavailable = false
        }
        if area == .helper {
            helperFailureRecovery = Self.resolveHelperFailureRecovery(for: error)
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "WelcomeViewModel")

    private var certificateErrorWasUnavailable = false

    private func begin(_ action: ActiveAction, errorArea: ErrorArea) -> Bool {
        guard Self.canBeginAction(current: activeAction, isCheckingSystem: isCheckingSystem) else {
            return false
        }
        activeAction = action
        self.errorArea = errorArea
        errorMessage = nil
        if action == .helper {
            helperFailureRecovery = nil
        }
        return true
    }

    private func perform(
        _ action: ActiveAction,
        errorArea: ErrorArea,
        operation: () async throws -> Void
    )
        async
    {
        guard begin(action, errorArea: errorArea) else {
            return
        }
        defer { activeAction = nil }

        do {
            try await operation()
            await refreshStatus()
            if action == .helper, helperStatus == .unreachable {
                errorMessage = HelperManager.shared.lastErrorMessage
                    ?? String(
                        localized: "Rockxy still cannot reach the installed helper.",
                        bundle: RockxyLocalization.bundle
                    )
                helperFailureRecovery = helperAutomaticRefreshRecoveryPending ? .retryLater : .repairAndReinstall
            } else {
                self.errorArea = nil
            }
        } catch {
            Self.logger.error("Welcome \(String(describing: action)) action failed: \(error.localizedDescription)")
            await refreshStatus()
            recordFailure(error, area: errorArea)
        }
    }

    private func apply(readiness: ReadinessCoordinator) {
        applyCertificateState(Self.certificateStepState(
            certReadiness: readiness.certReadiness,
            snapshot: readiness.lastCertSnapshot
        ))
        applyHelperState(
            status: readiness.helperReadiness,
            signingIssue: readiness.helperSigningIssue,
            automaticRefreshRecoveryPending: HelperManager.shared.automaticRefreshRecoveryPending
        )
        systemProxyEnabled = readiness.proxyMode != .unavailable
    }
}
