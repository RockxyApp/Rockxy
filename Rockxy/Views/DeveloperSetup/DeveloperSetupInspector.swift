import SwiftUI

// MARK: - DeveloperSetupInspector

struct DeveloperSetupInspector: View {
    // MARK: Internal

    let target: SetupTarget
    let snapshot: SetupSnapshot
    let activeIssue: SetupIssue?
    let automationPreview: SetupAutomationPreview?
    let supportsValidation: Bool
    let showsCertificateShareAction: Bool
    let validationInstruction: String
    let onRunTest: () -> Void
    let onOpenAutomation: () -> Void
    let onShareCertificate: () -> Void
    let onOpenCertificate: () -> Void
    let onOpenTools: () -> Void
    let onRevealRequest: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                readinessCard
                validationCard
                troubleshootingCard
                if let automationPreview {
                    automationCard(preview: automationPreview)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Private

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
                    .font(.subheadline.weight(.semibold))

                if let host = snapshot.matchedHost, let method = snapshot.matchedMethod {
                    Text("\(method) \(host)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        supportsValidation
                            ? validationInstruction
                            : String(localized: "Interactive validation is not available for this target.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if supportsValidation {
                    HStack(spacing: 8) {
                        Button(String(localized: "Run Test")) {
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
                            .font(.subheadline.weight(.semibold))
                        Text(activeIssue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(localized: "No active issue"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Rockxy is ready for the selected flow."))
                        .font(.caption)
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

    private func automationCard(preview: SetupAutomationPreview) -> some View {
        inspectorSection(
            title: preview.title,
            systemImage: "terminal"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(target.automationSupport.badgeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .systemBlue).opacity(0.12))
                    )

                Text(preview.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(target.automationSupport.entryActionTitle) {
                    onOpenAutomation()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func readinessRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private func inspectorSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
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
}
