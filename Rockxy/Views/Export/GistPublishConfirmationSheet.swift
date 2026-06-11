import SwiftUI

// MARK: - GistPublishConfirmationSheet

struct GistPublishConfirmationSheet: View {
    let context: GistPublishContext
    let onPublish: (GistPublishOptions) async throws -> GistPublishResult
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                Picker(String(localized: "Publish as"), selection: $visibility) {
                    Text(String(localized: "Private Gist")).tag(GitHubGistVisibility.secret)
                    Text(String(localized: "Public Gist")).tag(GitHubGistVisibility.public)
                }
                .pickerStyle(.radioGroup)

                if visibility == .public {
                    Label(String(localized: "Public Gists are discoverable. Review selected traffic before publishing."), systemImage: "exclamationmark.triangle.fill")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(String(localized: "Automatic redact sensitive headers"), isOn: $redactSensitiveData)
                    .toggleStyle(.checkbox)
                Toggle(String(localized: "Open Gist with default Web Browser"), isOn: $openInBrowser)
                    .toggleStyle(.checkbox)
                Toggle(String(localized: "Copy Gist URL to clipboard"), isOn: $copyURLToClipboard)
                    .toggleStyle(.checkbox)
            }

            Text(String(localized: "Rockxy will upload a README, HAR file, and readable request/response files for the selected traffic."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    onCancel()
                }
                .disabled(isPublishing)

                Button(String(localized: "Publish")) {
                    Task { await publish() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isPublishing)
            }
        }
        .font(toolMetrics.font())
        .padding(22)
        .frame(width: max(500, toolMetrics.fieldWidth(500)))
        .onAppear {
            let settings = AppSettingsManager.shared.settings
            visibility = settings.githubGistVisibility
            redactSensitiveData = settings.githubGistRedactSensitiveData
            openInBrowser = settings.githubGistOpenInBrowser
            copyURLToClipboard = settings.githubGistCopyURLToClipboard
        }
    }

    // MARK: Private

    @State private var visibility: GitHubGistVisibility = .secret
    @State private var redactSensitiveData = true
    @State private var openInBrowser = true
    @State private var copyURLToClipboard = false
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var title: String {
        context.transactions.count == 1
            ? String(localized: "Publish to Gist")
            : String(localized: "Publish Selected to Gist")
    }

    private func publish() async {
        isPublishing = true
        defer { isPublishing = false }
        do {
            _ = try await onPublish(GistPublishOptions(
                visibility: visibility,
                redactSensitiveData: redactSensitiveData,
                openInBrowser: openInBrowser,
                copyURLToClipboard: copyURLToClipboard,
                askBeforePublishing: true
            ))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
