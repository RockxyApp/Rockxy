import Foundation
@testable import Rockxy
import Testing

// Source-level contract that protects the original Welcome flow while allowing visual polish.

@MainActor
struct WelcomeViewReadabilityTests {
    // MARK: Internal

    @Test("Welcome preserves all four original steps and completion actions")
    func welcomePreservesOriginalFlow() throws {
        let view = try readProjectFile("Rockxy/Views/Welcome/WelcomeView.swift")

        #expect(view.contains("String(localized: \"Generate Root Certificate\", bundle: RockxyLocalization.bundle)"))
        #expect(view.contains("String(localized: \"Trust Root Certificate\", bundle: RockxyLocalization.bundle)"))
        #expect(view.contains("String(localized: \"Install Helper Tool\", bundle: RockxyLocalization.bundle)"))
        #expect(view.contains("String(localized: \"Enable System Proxy\", bundle: RockxyLocalization.bundle)"))
        #expect(view.contains("String(localized: \"Debug My App…\", bundle: RockxyLocalization.bundle)"))
        #expect(view.contains("String(localized: \"Get Started\", bundle: RockxyLocalization.bundle)"))
        #expect(view.contains(".disabled(!viewModel.canGetStarted || viewModel.isBusy)"))
        #expect(view.contains("WelcomeView(isFirstLaunch: true)"))
    }

    @Test("Welcome uses native metrics and a compact ordered setup surface")
    func welcomeUsesNativeOrderedLayout() throws {
        let view = try readProjectFile("Rockxy/Views/Welcome/WelcomeView.swift")

        #expect(view.contains("ToolWindowDisplayMetrics"))
        #expect(view.contains("@Environment(\\.appUIDisplayMetrics) private var appMetrics"))
        #expect(view.contains("GroupBox"))
        #expect(view.contains("ProgressView("))
        #expect(view.contains("String(localized: \"Checking system…\", bundle: RockxyLocalization.bundle)"))
        #expect(view.contains(".accessibilityLabel(String("))
        #expect(view.contains("localized: \"Checking system readiness\""))
        #expect(view.contains("ForEach(Array(steps.enumerated())"))
        #expect(view.contains("ViewThatFits(in: .horizontal)"))
        #expect(view.contains(".interactiveDismissDisabled(viewModel.isBusy)"))
    }

    @Test("helper failures have a confirmed recovery path without changing the other steps")
    func helperFailureRecoveryIsScoped() throws {
        let view = try readProjectFile("Rockxy/Views/Welcome/WelcomeView.swift")
        let model = try readProjectFile("Rockxy/ViewModels/WelcomeViewModel.swift")

        #expect(view.contains("String(localized: \"Repair & Reinstall…\", bundle: RockxyLocalization.bundle)"))
        #expect(view.contains("showingHelperRepairConfirmation"))
        #expect(view.contains("await viewModel.repairAndReinstallHelper()"))
        #expect(view.contains("SMAppService.openSystemSettingsLoginItems()"))
        #expect(model.contains("forceResetAndReinstall(resetBackgroundItems: false)"))
        #expect(model.contains("SystemProxyManager.shared.enableSystemProxy"))
        #expect(model.contains("certInstalled && certTrusted && isHelperReady && systemProxyEnabled"))
        #expect(model.contains("helperStatus == .installedCompatible && !helperAutomaticRefreshRecoveryPending"))
        #expect(view.contains("await viewModel.retryHelperConnection()"))
    }

    @Test("main app wiring and migration still require the original four readiness states")
    func welcomeAppWiringPreservesOriginalGate() throws {
        let app = try readProjectFile("Rockxy/RockxyApp.swift")

        #expect(app.contains("onEnableSystemProxy:"))
        #expect(app.contains("try await coordinator.enableSystemProxyFromWelcome()"))
        #expect(app.contains("let certInstalled = await CertificateManager.shared.isRootCAInstalled()"))
        #expect(app.contains("let helperOK = HelperManager.shared.status == .installedCompatible"))
        #expect(app.contains("&& !HelperManager.shared.automaticRefreshRecoveryPending"))
        #expect(app.contains("if certInstalled, certTrusted, helperOK, proxyOK {"))
    }

    @Test("incomplete Welcome has an explicit safe dismissal without completing onboarding")
    func incompleteSetupCanBeDismissed() throws {
        let view = try readProjectFile("Rockxy/Views/Welcome/WelcomeView.swift")
        let start = try #require(view.range(of: "Button(String(localized: \"Close\", bundle: RockxyLocalization.bundle), role: .cancel)"))
        let end = try #require(view.range(of: "if viewModel.canGetStarted", range: start.upperBound ..< view.endIndex))
        let closeAction = String(view[start.lowerBound ..< end.lowerBound])

        #expect(closeAction.contains("dismiss()"))
        #expect(closeAction.contains(".keyboardShortcut(.cancelAction)"))
        #expect(closeAction.contains(".disabled(viewModel.isBusy)"))
        #expect(!closeAction.contains("onboardingCompletedOnce ="))
        #expect(!closeAction.contains("finish("))
        #expect(!closeAction.contains("onComplete"))
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        let root = try resolveProjectRoot()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound
        }
        url.deleteLastPathComponent()
        return url
    }
}
