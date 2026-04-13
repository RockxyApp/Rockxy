import Foundation
@testable import Rockxy
import ServiceManagement
import Testing

// MARK: - HelperManagerTests

struct HelperManagerTests {
    @Test("install disposition preserves approval-required state")
    @MainActor
    func installDispositionRequiresApproval() {
        #expect(HelperManager.installDisposition(for: .requiresApproval) == .requiresApproval)
    }

    @Test("install disposition does not re-register already enabled helpers")
    @MainActor
    func installDispositionAlreadyEnabled() {
        #expect(HelperManager.installDisposition(for: .enabled) == .alreadyEnabled)
    }

    @Test("install disposition registers when helper is absent")
    @MainActor
    func installDispositionRegistersMissingHelper() {
        #expect(HelperManager.installDisposition(for: .notRegistered) == .register)
        #expect(HelperManager.installDisposition(for: .notFound) == .register)
    }

    @Test("approval-required detection accepts SMAppService approval errors")
    @MainActor
    func approvalRequiredErrorsAreRecognized() {
        let operationNotPermitted = NSError(domain: NSOSStatusErrorDomain, code: 1)
        let userDenied = NSError(domain: NSOSStatusErrorDomain, code: kSMErrorLaunchDeniedByUser)

        #expect(HelperManager.requiresApproval(error: operationNotPermitted, serviceStatus: .notRegistered))
        #expect(HelperManager.requiresApproval(error: userDenied, serviceStatus: .notRegistered))
    }

    @Test("approval-required detection accepts requiresApproval service state")
    @MainActor
    func approvalRequiredStatusIsRecognized() {
        let unrelatedError = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)

        #expect(HelperManager.requiresApproval(error: unrelatedError, serviceStatus: .requiresApproval))
    }

    @Test("approval message stays user-facing for direct approval flows")
    @MainActor
    func approvalMessageUsesStandardPromptForApprovalState() {
        let unrelatedError = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        let message = HelperManager.approvalMessage(error: unrelatedError, serviceStatus: .requiresApproval)

        #expect(message.contains("System Settings"))
        #expect(!message.contains("stale"))
    }

    @Test("approval message explains stale helper state when registration is blocked early")
    @MainActor
    func approvalMessageExplainsEarlyRegistrationBlock() {
        let operationNotPermitted = NSError(domain: NSOSStatusErrorDomain, code: 1)
        let message = HelperManager.approvalMessage(error: operationNotPermitted, serviceStatus: .notRegistered)

        #expect(message.contains("blocked helper registration"))
        #expect(message.contains("stale Rockxy helper registrations"))
    }

    @Test("approval-required detection ignores unrelated failures")
    @MainActor
    func unrelatedErrorsDoNotLookLikeApproval() {
        let unrelatedError = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)

        #expect(!HelperManager.requiresApproval(error: unrelatedError, serviceStatus: .notRegistered))
    }

    // MARK: - Probe Error Classification

    @Test("classifyProbeError maps appSignatureInvalid")
    @MainActor
    func classifyProbeErrorAppSignature() {
        let probe = HelperManager.classifyProbeError(.appSignatureInvalid("stale build"))
        #expect(probe == .appSignatureInvalid(detail: "stale build"))
    }

    @Test("classifyProbeError maps signingIdentityMismatch")
    @MainActor
    func classifyProbeErrorSigningMismatch() {
        let probe = HelperManager.classifyProbeError(
            .signingIdentityMismatch(app: "Dev", helper: "Prod")
        )
        #expect(probe == .signingIdentityMismatch(appSigner: "Dev", helperSigner: "Prod"))
    }

    @Test("classifyProbeError maps xpcTimeout to xpcFailure")
    @MainActor
    func classifyProbeErrorTimeout() {
        let probe = HelperManager.classifyProbeError(.xpcTimeout)
        #expect(probe == .xpcFailure)
    }

    @Test("classifyProbeError maps connectionFailed to xpcFailure")
    @MainActor
    func classifyProbeErrorConnectionFailed() {
        let probe = HelperManager.classifyProbeError(.connectionFailed)
        #expect(probe == .xpcFailure)
    }

    @Test("decideRecovery returns attemptReRegistration for xpcFailure")
    @MainActor
    func decideRecoveryXpcFailure() {
        let action = HelperManager.decideRecovery(probe: .xpcFailure)
        #expect(action == .attemptReRegistration)
    }

    // MARK: - Subtype-Only Change Detection

    @Test("signing issue change without status change is detected")
    @MainActor
    func signingIssueOnlyChangeDetected() {
        let changed = HelperManager.helperStateDidChange(
            previousStatus: .signingMismatch, currentStatus: .signingMismatch,
            previousReachable: false, currentReachable: false,
            previousInfo: nil, currentInfo: nil,
            previousSigningIssue: .appSignatureInvalid(detail: "stale"),
            currentSigningIssue: .identityMismatch(appSigner: "Dev", helperSigner: "Prod")
        )
        #expect(changed == true)
    }

    @Test("identical signing issue is not a change")
    @MainActor
    func identicalSigningIssueNotChanged() {
        let changed = HelperManager.helperStateDidChange(
            previousStatus: .signingMismatch, currentStatus: .signingMismatch,
            previousReachable: false, currentReachable: false,
            previousInfo: nil, currentInfo: nil,
            previousSigningIssue: .appSignatureInvalid(detail: "stale"),
            currentSigningIssue: .appSignatureInvalid(detail: "stale")
        )
        #expect(changed == false)
    }

    // MARK: - Action Label and Warning Reason

    @Test("appSignatureInvalid produces no action label")
    @MainActor
    func appSignatureInvalidNoActionLabel() {
        let label = HelperManager.helperActionLabel(
            status: .signingMismatch,
            signingIssue: .appSignatureInvalid(detail: "stale")
        )
        #expect(label == nil)
    }

    @Test("identityMismatch produces reinstall action label")
    @MainActor
    func identityMismatchReinstallLabel() {
        let label = HelperManager.helperActionLabel(
            status: .signingMismatch,
            signingIssue: .identityMismatch(appSigner: "Dev", helperSigner: "Prod")
        )
        #expect(label == String(localized: "Reinstall"))
    }

    @Test("installedCompatible produces no action label")
    @MainActor
    func installedCompatibleNoLabel() {
        let label = HelperManager.helperActionLabel(
            status: .installedCompatible,
            signingIssue: nil
        )
        #expect(label == nil)
    }

    @Test("appSignatureInvalid warning mentions clean build")
    func appSignatureInvalidWarning() {
        let reason = HelperManager.signingMismatchWarningReason(
            issue: .appSignatureInvalid(detail: "stale")
        )
        #expect(reason.localizedLowercase.contains("clean"))
    }

    @Test("identityMismatch warning mentions reinstall")
    func identityMismatchWarning() {
        let reason = HelperManager.signingMismatchWarningReason(
            issue: .identityMismatch(appSigner: "Dev", helperSigner: "Prod")
        )
        #expect(reason.localizedLowercase.contains("reinstall"))
    }

    // MARK: - Re-registration Approval Detection

    @Test("requiresApproval recognizes kSMErrorLaunchDeniedByUser during re-registration")
    func reRegistrationApprovalDetected() {
        let deniedError = NSError(domain: NSOSStatusErrorDomain, code: kSMErrorLaunchDeniedByUser)
        #expect(HelperManager.requiresApproval(error: deniedError, serviceStatus: .requiresApproval))
    }

    @Test("approval message is user-facing for requiresApproval service state")
    func reRegistrationApprovalMessage() {
        let deniedError = NSError(domain: NSOSStatusErrorDomain, code: kSMErrorLaunchDeniedByUser)
        let message = HelperManager.approvalMessage(error: deniedError, serviceStatus: .requiresApproval)
        #expect(message.contains("System Settings"))
        #expect(message.contains("Login Items"))
    }

    // MARK: - Uninstall Registration Status Reset

    @Test("injecting notInstalled state resets registrationStatus via injectHelperStateForTests")
    @MainActor
    func uninstallResetsRegistrationStatus() {
        let manager = HelperManager.shared

        manager.injectHelperStateForTests(
            status: .installedCompatible,
            signingIssue: nil,
            isReachable: true
        )
        #expect(manager.status == .installedCompatible)

        manager.injectHelperStateForTests(
            status: .notInstalled,
            signingIssue: nil,
            isReachable: false
        )
        #expect(manager.status == .notInstalled)
        #expect(manager.isReachable == false)
        #expect(manager.installedInfo == nil)
    }
}
