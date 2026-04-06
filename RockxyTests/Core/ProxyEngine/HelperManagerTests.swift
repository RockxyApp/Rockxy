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
}
