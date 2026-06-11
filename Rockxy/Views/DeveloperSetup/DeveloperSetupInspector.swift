import SwiftUI

// MARK: - DeveloperSetupInspector

struct DeveloperSetupInspector: View {
    // MARK: Internal

    let snapshot: SetupSnapshot
    let activeIssue: SetupIssue?
    let setupModeActions: SetupModeActionState
    let supportsValidation: Bool
    let showsCertificateShareAction: Bool
    let validationInstruction: String
    let onOpenManualSetup: () -> Void
    let onOpenAutomaticSetup: () -> Void
    let onRunTest: () -> Void
    let onShareCertificate: () -> Void
    let onOpenCertificate: () -> Void
    let onOpenTools: () -> Void
    let onRevealRequest: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                setupModesCard
                readinessCard
                validationCard
                troubleshootingCard
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectedSetupMode = setupModeActions.preferredMode
        }
        .onChange(of: setupModeActions) { _, newActions in
            selectedSetupMode = newActions.preferredMode
        }
    }

    // MARK: Private

    @State private var selectedSetupMode: SetupModeSelection = .manual

    private var setupModesCard: some View {
        inspectorSection(
            title: String(localized: "Setup Modes"),
            systemImage: "slider.horizontal.2.square"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(String(localized: "Use"))
                        .font(.system(size: setupMetrics.secondaryFontSize))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedSetupMode) {
                        Label(setupModeActions.manualTitle, systemImage: SetupModeSelection.manual.systemImage)
                            .tag(SetupModeSelection.manual)
                        Label(setupModeActions.automaticTitle, systemImage: SetupModeSelection.automatic.systemImage)
                            .tag(SetupModeSelection.automatic)
                            .disabled(!setupModeActions.isAutomaticEnabled)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)

                    Button(openSelectedSetupModeTitle) {
                        openSelectedSetupMode()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSetupMode == .automatic && !setupModeActions.isAutomaticEnabled)
                }

                Text(selectedSetupModeCaption)
                    .font(.system(size: setupMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(setupReadinessHint)
                    .font(.system(size: setupMetrics.metadataFontSize))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var readinessCard: some View {
        inspectorSection(
            title: String(localized: "Readiness"),
            systemImage: "gauge.with.dots.needle.50percent"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                readinessRow(
                    title: String(localized: "Proxy"),
                    value: snapshot.proxyRunning ? String(localized: "Running") : String(localized: "Stopped")
                )
                readinessRow(
                    title: String(localized: "Recording"),
                    value: snapshot.recordingEnabled ? String(localized: "On") : String(localized: "Paused")
                )
                readinessRow(
                    title: String(localized: "Certificate"),
                    value: snapshot.certificateTrusted ? String(localized: "Trusted") : String(localized: "Needs attention")
                )
                readinessRow(
                    title: String(localized: "Port"),
                    value: "\(snapshot.activePort)"
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35))
                    )
            )
        }
    }

    private var validationCard: some View {
        inspectorSection(
            title: String(localized: "Validation"),
            systemImage: "bolt.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(snapshot.verificationState.title)
                    .font(.system(size: setupMetrics.bodyFontSize, weight: .semibold))

                if let host = snapshot.matchedHost, let method = snapshot.matchedMethod {
                    Text("\(method) \(host)")
                        .font(.system(size: setupMetrics.secondaryFontSize))
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        supportsValidation
                            ? validationInstruction
                            : String(localized: "Interactive validation is not available for this target.")
                    )
                    .font(.system(size: setupMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                }

                if supportsValidation {
                    HStack(spacing: 8) {
                        Button(String(localized: "Run Local Probe")) {
                            onRunTest()
                        }
                        .buttonStyle(.borderedProminent)

                        if snapshot.verificationState == .success, snapshot.matchedTransactionID != nil {
                            Button(String(localized: "Reveal")) {
                                onRevealRequest()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var troubleshootingCard: some View {
        inspectorSection(
            title: String(localized: "Troubleshooting"),
            systemImage: "wrench.and.screwdriver"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let activeIssue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeIssue.title)
                            .font(.system(size: setupMetrics.bodyFontSize, weight: .semibold))
                        Text(activeIssue.message)
                            .font(.system(size: setupMetrics.secondaryFontSize))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(localized: "No active issue"))
                        .font(.system(size: setupMetrics.bodyFontSize, weight: .semibold))
                    Text(String(localized: "Rockxy is ready for the selected flow."))
                        .font(.system(size: setupMetrics.secondaryFontSize))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if showsCertificateShareAction {
                            Button(String(localized: "Share Certificate")) {
                                onShareCertificate()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button(String(localized: "Open Certificate")) {
                            onOpenCertificate()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(String(localized: "Open in Tools")) {
                        onOpenTools()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func readinessRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: setupMetrics.secondaryFontSize))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: setupMetrics.secondaryFontSize, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private var selectedSetupModeCaption: String {
        switch selectedSetupMode {
        case .manual:
            setupModeActions.manualCaption
        case .automatic:
            setupModeActions.automaticCaption
        }
    }

    private var openSelectedSetupModeTitle: String {
        switch selectedSetupMode {
        case .manual:
            String(localized: "Open...")
        case .automatic:
            String(localized: "Open...")
        }
    }

    private var setupReadinessHint: String {
        if snapshot.proxyRunning && snapshot.certificateTrusted {
            return String(localized: "Proxy and certificate are ready. Setup can still be rerun for a fresh session.")
        }

        return String(localized: "Readiness below shows current proxy and certificate state; setup can be rerun anytime.")
    }

    private func openSelectedSetupMode() {
        switch selectedSetupMode {
        case .manual:
            onOpenManualSetup()
        case .automatic:
            guard setupModeActions.isAutomaticEnabled else {
                return
            }
            onOpenAutomaticSetup()
        }
    }

    private func inspectorSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(size: setupMetrics.sectionTitleFontSize, weight: .semibold))
                .foregroundStyle(.primary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.28))
                )
        )
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var setupMetrics: DeveloperSetupDisplayMetrics {
        DeveloperSetupDisplayMetrics(appMetrics: appMetrics)
    }
}
