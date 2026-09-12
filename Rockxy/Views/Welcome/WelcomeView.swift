import ServiceManagement
import SwiftUI

// Renders the original four-step onboarding flow with native macOS hierarchy and helper recovery.

// MARK: - WelcomeStepItem

private struct WelcomeStepItem: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let symbol: String
    let actionLabel: String?
    let isCompleted: Bool
    let isDisabled: Bool
    let activeAction: WelcomeViewModel.ActiveAction
    let errorArea: WelcomeViewModel.ErrorArea
    let action: (() async -> Void)?
}

// MARK: - WelcomeView

struct WelcomeView: View {
    // MARK: Internal

    var isFirstLaunch = false
    var onComplete: (() -> Void)?
    var onEnableSystemProxy: (@MainActor () async throws -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            stepsSection
            Divider()
            footerSection
        }
        .frame(width: windowWidth, height: windowHeight)
        .interactiveDismissDisabled(viewModel.isBusy)
        .task {
            await viewModel.loadInitialStatus()
        }
        .onChange(of: ReadinessCoordinator.shared.certReadiness) {
            viewModel.syncFromCoordinator()
        }
        .onChange(of: ReadinessCoordinator.shared.helperReadiness) {
            viewModel.syncFromCoordinator()
        }
        .onChange(of: ReadinessCoordinator.shared.helperSigningIssue) {
            viewModel.syncFromCoordinator()
        }
        .onChange(of: ReadinessCoordinator.shared.proxyMode) {
            viewModel.syncFromCoordinator()
        }
        .alert(
            String(localized: "Repair Helper Tool?", bundle: RockxyLocalization.bundle),
            isPresented: $showingHelperRepairConfirmation
        ) {
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {}
            Button(String(localized: "Repair & Reinstall", bundle: RockxyLocalization.bundle), role: .destructive) {
                Task {
                    await viewModel.repairAndReinstallHelper()
                }
            }
        } message: {
            Text(
                String(
                    localized: """
                    Rockxy will stop capture, request administrator approval, remove stale helper files and registration state, then reinstall the helper from this app.

                    Use this when Install, Retry, Update, or Reinstall cannot recover the helper.
                    """, bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    // MARK: Private

    @State private var viewModel = WelcomeViewModel()
    @State private var showingHelperRepairConfirmation = false
    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch = true
    @AppStorage(RockxyIdentity.current.defaultsKey("onboardingCompletedOnce")) private var onboardingCompletedOnce =
        false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var windowWidth: CGFloat {
        max(540, min(620, toolMetrics.bodyFontSize * 5 + 495))
    }

    private var windowHeight: CGFloat {
        max(540, min(660, toolMetrics.bodyFontSize * 8 + 456))
    }

    private var steps: [WelcomeStepItem] {
        [
            WelcomeStepItem(
                id: 1,
                title: String(localized: "Generate Root Certificate", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Create Rockxy's local certificate authority for HTTPS inspection.",
                    bundle: RockxyLocalization.bundle
                ),
                symbol: "lock.badge.plus",
                actionLabel: certificateStepActionLabel,
                isCompleted: viewModel.certInstalled,
                isDisabled: false,
                activeAction: .certificate,
                errorArea: .certificate,
                action: certificateStepAction
            ),
            WelcomeStepItem(
                id: 2,
                title: String(localized: "Trust Root Certificate", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Trust the certificate so intercepted HTTPS connections are accepted.",
                    bundle: RockxyLocalization.bundle
                ),
                symbol: "checkmark.shield",
                actionLabel: trustStepActionLabel,
                isCompleted: viewModel.certTrusted,
                isDisabled: !viewModel.certInstalled,
                activeAction: .certificate,
                errorArea: .certificate,
                action: certificateStepAction
            ),
            WelcomeStepItem(
                id: 3,
                title: String(localized: "Install Helper Tool", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Install the privileged service used for reliable proxy changes and recovery.",
                    bundle: RockxyLocalization.bundle
                ),
                symbol: "wrench.and.screwdriver",
                actionLabel: viewModel.helperActionLabel,
                isCompleted: viewModel.isHelperReady,
                isDisabled: false,
                activeAction: .helper,
                errorArea: .helper,
                action: performHelperAction
            ),
            WelcomeStepItem(
                id: 4,
                title: String(localized: "Enable System Proxy", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Route macOS network traffic through Rockxy for capture.",
                    bundle: RockxyLocalization.bundle
                ),
                symbol: "network",
                actionLabel: viewModel.systemProxyEnabled ? nil : String(
                    localized: "Enable",
                    bundle: RockxyLocalization.bundle
                ),
                isCompleted: viewModel.systemProxyEnabled,
                isDisabled: false,
                activeAction: .systemProxy,
                errorArea: .systemProxy,
                action: { await viewModel.enableProxy(using: onEnableSystemProxy) }
            ),
        ]
    }

    /// An unreadable status offers a status check, never an install: the install would raise an
    /// administrator prompt for a certificate Rockxy could not describe.
    private var certificateStepActionLabel: String? {
        if viewModel.isCertStatusUnavailable {
            return viewModel.certInstalled ? nil : String(localized: "Recheck Status", bundle: RockxyLocalization.bundle)
        }
        return viewModel.certInstalled
            ? nil
            : String(localized: "Install", bundle: RockxyLocalization.bundle)
    }

    private var certificateStepAction: () async -> Void {
        if viewModel.isCertStatusUnavailable {
            return { await viewModel.recheckCertificateStatus() }
        }
        return { await viewModel.installCert() }
    }

    private var trustStepActionLabel: String? {
        if viewModel.isCertStatusUnavailable {
            return viewModel.certInstalled ? String(localized: "Recheck Status", bundle: RockxyLocalization.bundle) : nil
        }
        return viewModel.certTrusted ? nil : String(localized: "Trust", bundle: RockxyLocalization.bundle)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: toolMetrics.headerSpacing) {
                Image(nsImage: AppIconProvider.appIcon)
                    .resizable()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Welcome to Rockxy", bundle: RockxyLocalization.bundle))
                        .font(
                            toolMetrics.appMetrics.swiftUIFont(
                                size: max(20, toolMetrics.bodyFontSize + 7),
                                weight: .semibold
                            )
                        )
                    Text(
                        isFirstLaunch
                            ? String(
                                localized: "Complete these four steps to prepare network debugging.",
                                bundle: RockxyLocalization.bundle
                            )
                            : String(
                                localized: "Review the four setup steps before continuing.",
                                bundle: RockxyLocalization.bundle
                            )
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                ProgressView(
                    value: Double(viewModel.completedSteps),
                    total: Double(viewModel.totalSteps)
                )
                .tint(.accentColor)

                if viewModel.isCheckingSystem {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Checking system…", bundle: RockxyLocalization.bundle))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(
                        localized: "Checking system readiness",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.metadataFont(weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                } else {
                    Text(String(
                        localized: "\(viewModel.completedSteps) of \(viewModel.totalSteps) complete",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.metadataFont(weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
    }

    // MARK: - Steps

    private var stepsSection: some View {
        ScrollView {
            GroupBox {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(step)
                        if index < steps.count - 1 {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
            }
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
    }

    /// Shown under the first certificate step when the status could not be read. It states what
    /// is unknown; the step's own action re-reads it. Nothing here offers an install or a trust
    /// write, and it never touches `errorMessage`, so an unrelated helper or proxy failure keeps
    /// its own inline error.
    @ViewBuilder private var certificateSupplement: some View {
        if let message = viewModel.certStatusUnavailableMessage {
            Label {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "questionmark.circle.fill")
            }
            .font(toolMetrics.metadataFont())
            .foregroundStyle(.orange)
            .padding(.top, 2)
        }
    }

    @ViewBuilder private var helperSupplement: some View {
        if let detail = viewModel.helperStatusDetail {
            Text(detail)
                .font(toolMetrics.metadataFont())
                .foregroundStyle(viewModel.isHelperReady ? Color.green : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if viewModel.shouldOfferHelperRepair {
            Button(role: .destructive) {
                showingHelperRepairConfirmation = true
            } label: {
                Label(
                    String(localized: "Repair & Reinstall…", bundle: RockxyLocalization.bundle),
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                )
                .font(toolMetrics.metadataFont(weight: .medium))
            }
            .buttonStyle(.link)
            .disabled(viewModel.isBusy)
        }

        if viewModel.shouldShowHelperDiagnostics {
            Button {
                openWindow(id: "advancedProxySettings")
            } label: {
                Label(
                    String(localized: "View Advanced Diagnostics", bundle: RockxyLocalization.bundle),
                    systemImage: "wrench.and.screwdriver"
                )
                .font(toolMetrics.metadataFont(weight: .medium))
            }
            .buttonStyle(.link)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: toolMetrics.controlSpacing) {
                    startupToggle
                    Spacer(minLength: toolMetrics.controlSpacing)
                    footerButtons
                }

                VStack(alignment: .trailing, spacing: toolMetrics.controlSpacing) {
                    footerButtons
                    startupToggle
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text(appVersion)
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.footerTopPadding)
        .padding(.bottom, toolMetrics.footerBottomPadding)
    }

    private var startupToggle: some View {
        Toggle(isOn: $showWelcomeOnLaunch) {
            Text(String(localized: "Show on startup", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.secondaryFont())
        }
        .toggleStyle(.checkbox)
    }

    private var footerButtons: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Button(String(localized: "Close", bundle: RockxyLocalization.bundle), role: .cancel) {
                // Dismissing setup is not completing it. Keep the readiness milestones and
                // onboarding preference intact so incomplete setup remains discoverable.
                dismiss()
            }
            .rockxyGlassButtonStyle()
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            .disabled(viewModel.isBusy)

            if viewModel.canGetStarted {
                Button(String(localized: "Debug My App…", bundle: RockxyLocalization.bundle)) {
                    finish(openDeveloperSetup: true)
                }
                .rockxyGlassButtonStyle()
                .controlSize(.large)
            }

            Button(String(localized: "Get Started", bundle: RockxyLocalization.bundle)) {
                finish(openDeveloperSetup: false)
            }
            .rockxyGlassButtonStyle(prominent: true)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canGetStarted || viewModel.isBusy)
        }
    }

    private func stepRow(_ step: WelcomeStepItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            stepStatus(step)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(toolMetrics.font(weight: .semibold))
                    .foregroundStyle(step.isDisabled ? .tertiary : .primary)

                Text(step.detail)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(step.isDisabled ? .tertiary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if step.id == 1 {
                    certificateSupplement
                }

                if step.id == 3 {
                    helperSupplement
                }

                if viewModel.errorArea == step.errorArea, let errorMessage = viewModel.errorMessage {
                    inlineError(errorMessage)
                }
            }

            Spacer(minLength: 8)

            stepAction(step)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(step.isCompleted ? Color.green.opacity(0.055) : Color.clear)
    }

    private func stepStatus(_ step: WelcomeStepItem) -> some View {
        ZStack {
            Circle()
                .fill(step.isCompleted
                    ? Color.green
                    : (step.isDisabled ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.12)))
            if step.isCompleted {
                Image(systemName: "checkmark")
                    .font(toolMetrics.metadataFont(weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: step.symbol)
                    .font(toolMetrics.metadataFont(weight: .semibold))
                    .foregroundStyle(step.isDisabled ? Color.secondary.opacity(0.55) : Color.accentColor)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityLabel(
            step.isCompleted
                ? String(localized: "Completed", bundle: RockxyLocalization.bundle)
                : String(localized: "Step \(step.id)", bundle: RockxyLocalization.bundle)
        )
    }

    @ViewBuilder
    private func stepAction(_ step: WelcomeStepItem) -> some View {
        if viewModel.activeAction == step.activeAction {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 88)
                .padding(.top, 3)
        } else if let actionLabel = step.actionLabel, !step.isDisabled {
            Button(actionLabel) {
                Task {
                    await step.action?()
                }
            }
            .controlSize(.small)
            .frame(minWidth: 88)
            .disabled(viewModel.isBusy)
        }
    }

    private func inlineError(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(toolMetrics.metadataFont())
        .foregroundStyle(.red)
        .padding(.top, 2)
    }

    private func performHelperAction() async {
        switch viewModel.helperStatus {
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        case .installedOutdated,
             .installedIncompatible:
            await viewModel.updateHelper()
        case .signingMismatch:
            if case .applicationMustReopen = viewModel.helperSigningIssue {
                HelperRecoveryPresenter.requestRequiredReopen()
            } else if case .identityMismatch = viewModel.helperSigningIssue {
                await viewModel.reinstallHelper()
            }
        case .unreachable:
            await viewModel.retryHelperConnection()
        case .notInstalled:
            await viewModel.installHelper()
        case .installedCompatible:
            if viewModel.helperAutomaticRefreshRecoveryPending {
                await viewModel.retryHelperConnection()
            }
        }
    }

    private func finish(openDeveloperSetup: Bool) {
        guard viewModel.canGetStarted else {
            return
        }
        onboardingCompletedOnce = true
        if openDeveloperSetup {
            openWindow(id: "developerSetupHub")
        }
        if let onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    WelcomeView(isFirstLaunch: true)
}
