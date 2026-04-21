import SwiftUI

// MARK: - DeveloperSetupAutomationSheet

struct DeveloperSetupAutomationSheet: View {
    // MARK: Internal

    let target: SetupTarget
    let preview: SetupAutomationPreview
    let onContinueManual: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    overviewCard
                    stepsCard
                    fallbackCard
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 700, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.title)
                        .font(.title3.weight(.semibold))
                    Text(target.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                automationBadge
            }

            Text(preview.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var automationBadge: some View {
        Text(target.automationSupport.badgeTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(nsColor: .systemBlue))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .systemBlue).opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color(nsColor: .systemBlue).opacity(0.22))
            )
    }

    private var overviewCard: some View {
        card(title: String(localized: "Primary action"), systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 8) {
                Text(preview.primaryActionTitle)
                    .font(.headline)

                Text(
                    String(
                        localized: """
                        This is the primary automation entrypoint for terminal-based runtimes.
                        Manual setup remains available in the main window when you want to follow the steps directly.
                        """
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var stepsCard: some View {
        card(title: String(localized: "Automation flow"), systemImage: "list.number") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(preview.steps) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))
                        Text(step.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var fallbackCard: some View {
        card(title: String(localized: "Manual fallback"), systemImage: "arrow.uturn.backward") {
            Text(preview.supplementaryNote)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button(String(localized: "Done")) {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button(String(localized: "Continue with Manual Setup")) {
                onContinueManual()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func card<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.3))
                )
        )
    }
}
