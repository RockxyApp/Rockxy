import AppKit
import SwiftUI

// MARK: - DeveloperSetupManualWindowView

struct DeveloperSetupManualWindowView: View {
    // MARK: Lifecycle

    init(coordinator: MainContentCoordinator) {
        _viewModel = State(initialValue: DeveloperSetupSessionSetupViewModel(coordinator: coordinator))
    }

    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            terminalCard
            footerButtons
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: 780, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .centerOverRockxyMainWindowOnAppear()
        .task {
            viewModel.refresh()
            viewModel.prepareScriptForDisplay()
        }
    }

    // MARK: Private

    @State private var viewModel: DeveloperSetupSessionSetupViewModel
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var setupMetrics: DeveloperSetupDisplayMetrics {
        DeveloperSetupDisplayMetrics(appMetrics: appMetrics)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: setupMetrics.prominentIconFontSize, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)

                Text(String(localized: "Manual Setup"))
                    .font(.system(size: setupMetrics.titleFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                benefitRow(
                    systemImage: "checkmark.circle.fill",
                    text: String(localized: "Capture traffic from Node.js, Python, Ruby, Go, cURL, and terminal-based tools.")
                )
                benefitRow(
                    systemImage: "lock.shield.fill",
                    text: String(localized: "Safe by default: source the command in your current shell session only.")
                )
            }
        }
    }

    private var terminalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Terminal app"))
                .font(.system(size: setupMetrics.sectionTitleFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 16) {
                instructionStep(
                    title: String(localized: "1. Open your favorite Terminal app"),
                    caption: String(localized: "Supports Terminal, iTerm2, Ghostty, Hyper, and Bash/Zsh/Fish shells.")
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "2. Copy and paste this command into that terminal"))
                        .font(.system(size: setupMetrics.bodyFontSize, weight: .semibold))
                        .foregroundStyle(.primary)

                    commandBox

                    Button {
                        viewModel.copyManualCommand()
                    } label: {
                        Text(String(localized: "Copy to Clipboard"))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                instructionStep(
                    title: String(localized: "3. Done"),
                    caption: String(localized: "Start your server or run scripts in that terminal session."),
                    trailingSystemImage: "checkmark"
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private var commandBox: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                Text(viewModel.manualSourceCommand)
                    .font(.system(size: setupMetrics.snippetFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 64)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {
            Button(String(localized: "How does it work?")) {
                revealSetupScript()
            }
            .buttonStyle(.bordered)

            Button(String(localized: "Troubleshooting")) {
                revealSetupScript()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefitRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: setupMetrics.iconFontSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(nsColor: .systemGreen))
                .frame(width: 18)

            Text(text)
                .font(.system(size: setupMetrics.bodyFontSize))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func instructionStep(
        title: String,
        caption: String,
        trailingSystemImage: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: setupMetrics.bodyFontSize, weight: .semibold))
                    .foregroundStyle(.primary)

                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: setupMetrics.iconFontSize, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                }
            }

            Text(caption)
                .font(.system(size: setupMetrics.bodyFontSize))
                .foregroundStyle(.secondary)
                .padding(.leading, 24)
        }
    }

    private func revealSetupScript() {
        do {
            try viewModel.prepareScript()
            NSWorkspace.shared.activateFileViewerSelecting([viewModel.scriptURL])
        } catch {
            viewModel.statusMessage = String(localized: "Could not prepare the setup script: \(error.localizedDescription)")
        }
    }
}
