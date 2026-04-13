import Foundation
@testable import Rockxy
import Testing

// Regression tests for `WelcomeViewModel` in the view models layer.

// MARK: - WelcomeViewModelTests

@MainActor
struct WelcomeViewModelTests {
    // MARK: - completedSteps Tests

    @Test("completedSteps returns 0 when nothing is complete")
    func completedStepsAllFalse() {
        let viewModel = WelcomeViewModel()

        #expect(viewModel.completedSteps == 0)
    }

    @Test("completedSteps returns 1 when only certInstalled is true")
    func completedStepsCertInstalledOnly() {
        let viewModel = WelcomeViewModel()
        viewModel.certInstalled = true

        #expect(viewModel.completedSteps == 1)
    }

    @Test("completedSteps returns 2 when certInstalled and certTrusted are true")
    func completedStepsCertInstalledAndTrusted() {
        let viewModel = WelcomeViewModel()
        viewModel.certInstalled = true
        viewModel.certTrusted = true

        #expect(viewModel.completedSteps == 2)
    }

    @Test("completedSteps returns 3 when cert and helper are complete")
    func completedStepsThreeComplete() {
        let viewModel = WelcomeViewModel()
        viewModel.certInstalled = true
        viewModel.certTrusted = true
        viewModel.helperStatus = .installedCompatible

        #expect(viewModel.completedSteps == 3)
    }

    @Test("completedSteps returns 4 when all steps are complete")
    func completedStepsAllComplete() {
        let viewModel = WelcomeViewModel()
        viewModel.certInstalled = true
        viewModel.certTrusted = true
        viewModel.helperStatus = .installedCompatible
        viewModel.systemProxyEnabled = true

        #expect(viewModel.completedSteps == 4)
    }

    @Test("completedSteps counts only helper installed, not other statuses")
    func completedStepsHelperNotInstalled() {
        let viewModel = WelcomeViewModel()
        viewModel.helperStatus = .requiresApproval

        #expect(viewModel.completedSteps == 0)
    }

    @Test("completedSteps counts systemProxyEnabled independently")
    func completedStepsProxyOnly() {
        let viewModel = WelcomeViewModel()
        viewModel.systemProxyEnabled = true

        #expect(viewModel.completedSteps == 1)
    }

    // MARK: - totalSteps Tests

    @Test("totalSteps is always 4")
    func totalStepsIsFour() {
        let viewModel = WelcomeViewModel()

        #expect(viewModel.totalSteps == 4)
    }

    // MARK: - canGetStarted Tests

    @Test("canGetStarted is false when cert is not installed")
    func canGetStartedFalseNoCert() {
        let viewModel = WelcomeViewModel()

        #expect(viewModel.canGetStarted == false)
    }

    @Test("canGetStarted is false when cert installed but not trusted")
    func canGetStartedFalseNotTrusted() {
        let viewModel = WelcomeViewModel()
        viewModel.certInstalled = true

        #expect(viewModel.canGetStarted == false)
    }

    @Test("canGetStarted is false when cert trusted but not installed")
    func canGetStartedFalseTrustedNotInstalled() {
        let viewModel = WelcomeViewModel()
        viewModel.certTrusted = true

        #expect(viewModel.canGetStarted == false)
    }

    @Test("canGetStarted is true when all four steps are complete")
    func canGetStartedTrue() {
        let viewModel = WelcomeViewModel()
        viewModel.certInstalled = true
        viewModel.certTrusted = true
        viewModel.helperStatus = .installedCompatible
        viewModel.systemProxyEnabled = true

        #expect(viewModel.canGetStarted == true)
    }

    @Test("canGetStarted is false when only cert steps are done")
    func canGetStartedFalseWithoutHelperAndProxy() {
        let viewModel = WelcomeViewModel()
        viewModel.certInstalled = true
        viewModel.certTrusted = true
        viewModel.helperStatus = .notInstalled
        viewModel.systemProxyEnabled = false

        #expect(viewModel.canGetStarted == false)
    }

    // MARK: - installCert Guard Tests

    @Test("installCert skips when certTrusted is already true")
    func installCertSkipsWhenAlreadyTrusted() async {
        let viewModel = WelcomeViewModel()
        viewModel.certTrusted = true

        await viewModel.installCert()

        #expect(viewModel.isPerformingAction == false)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Initial State Tests

    @Test("initial state has all properties at defaults")
    func initialState() {
        let viewModel = WelcomeViewModel()

        #expect(viewModel.certInstalled == false)
        #expect(viewModel.certTrusted == false)
        #expect(viewModel.helperStatus == .notInstalled)
        #expect(viewModel.systemProxyEnabled == false)
        #expect(viewModel.isPerformingAction == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.completedSteps == 0)
        #expect(viewModel.totalSteps == 4)
        #expect(viewModel.canGetStarted == false)
    }

    // MARK: - Signing Mismatch Tests

    @Test("completedSteps does not count signingMismatch as complete")
    func completedStepsSigningMismatch() {
        let viewModel = WelcomeViewModel()
        viewModel.helperStatus = .signingMismatch

        #expect(viewModel.completedSteps == 0)
    }

    @Test("canGetStarted is false when helper has signing mismatch")
    func canGetStartedFalseSigningMismatch() {
        let viewModel = WelcomeViewModel()
        viewModel.certInstalled = true
        viewModel.certTrusted = true
        viewModel.helperStatus = .signingMismatch
        viewModel.systemProxyEnabled = true

        #expect(viewModel.canGetStarted == false)
    }

    @Test("subtype-only change through applyHelperState diverges action label")
    func subtypeChangeThroughApplyPath() {
        let viewModel = WelcomeViewModel()

        viewModel.applyHelperState(
            status: .signingMismatch,
            signingIssue: .appSignatureInvalid(detail: "stale")
        )
        #expect(viewModel.helperStatus == .signingMismatch)
        #expect(viewModel.helperSigningIssue == .appSignatureInvalid(detail: "stale"))
        let label1 = HelperManager.helperActionLabel(
            status: viewModel.helperStatus,
            signingIssue: viewModel.helperSigningIssue
        )
        #expect(label1 == nil)

        viewModel.applyHelperState(
            status: .signingMismatch,
            signingIssue: .identityMismatch(appSigner: "Dev", helperSigner: "Prod")
        )
        #expect(viewModel.helperStatus == .signingMismatch)
        #expect(
            viewModel.helperSigningIssue == .identityMismatch(
                appSigner: "Dev",
                helperSigner: "Prod"
            )
        )
        let label2 = HelperManager.helperActionLabel(
            status: viewModel.helperStatus,
            signingIssue: viewModel.helperSigningIssue
        )
        #expect(label2 == String(localized: "Reinstall"))
    }

    // MARK: - Helper Action Label Alignment

    @Test("unreachable label is Retry, not Install")
    func unreachableLabelIsRetry() {
        let label = HelperManager.helperActionLabel(
            status: .unreachable,
            signingIssue: nil
        )
        #expect(label == String(localized: "Retry"))
    }

    @Test("action labels cover all statuses consistently")
    func actionLabelsAllStatuses() {
        let cases: [(HelperManager.HelperStatus, HelperManager.SigningIssue?, String?)] = [
            (.notInstalled, nil, String(localized: "Install")),
            (.requiresApproval, nil, String(localized: "Open Settings")),
            (.installedCompatible, nil, nil),
            (.installedOutdated, nil, String(localized: "Update")),
            (.installedIncompatible, nil, String(localized: "Update")),
            (.unreachable, nil, String(localized: "Retry")),
            (.signingMismatch, .appSignatureInvalid(detail: "x"), nil),
            (.signingMismatch, .identityMismatch(appSigner: "a", helperSigner: "b"), String(localized: "Reinstall")),
            (.signingMismatch, nil, nil),
        ]

        for (status, issue, expected) in cases {
            let label = HelperManager.helperActionLabel(status: status, signingIssue: issue)
            #expect(label == expected, "status=\(status) issue=\(String(describing: issue))")
        }
    }
}
