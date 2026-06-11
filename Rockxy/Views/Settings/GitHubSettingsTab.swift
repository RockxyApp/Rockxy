import AppKit
import SwiftUI

// MARK: - GitHubSettingsTab

struct GitHubSettingsTab: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                permissionSection
                    .padding(.top, 26)
                    .padding(.bottom, 34)

                Divider()

                defaultsSection
                    .padding(.top, 36)
                    .padding(.bottom, 28)

                advancedSection
                    .padding(.top, 8)

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $showPersonalAccessTokenSheet) {
            PersonalAccessTokenFallbackSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showDeviceCodeSheet) {
            GitHubDeviceCodeAuthorizationSheet(viewModel: viewModel)
        }
    }

    // MARK: Private

    @State private var viewModel = GitHubSettingsViewModel()
    @State private var showPersonalAccessTokenSheet = false
    @State private var showDeviceCodeSheet = false

    @AppStorage(RockxyIdentity.current.defaultsKey("github.gist.visibility"))
    private var gistVisibility = GitHubGistVisibility.secret.rawValue

    @AppStorage(RockxyIdentity.current.defaultsKey("github.gist.redactSensitiveData"))
    private var redactSensitiveData = true

    @AppStorage(RockxyIdentity.current.defaultsKey("github.gist.openInBrowser"))
    private var openInBrowser = true

    @AppStorage(RockxyIdentity.current.defaultsKey("github.gist.copyURLToClipboard"))
    private var copyURLToClipboard = false

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            alignedRow(label: String(localized: "Gist Permission:")) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.isConnected ? .green : .orange)
                    Text(viewModel.connectionTitle)
                        .font(settingsMetrics.font())
                }
            }

            alignedRow(label: "") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Button(String(localized: viewModel.isConnected ? "Reconnect..." : "Authorize...")) {
                            if viewModel.canUseOAuth {
                                showDeviceCodeSheet = true
                            } else {
                                showPersonalAccessTokenSheet = true
                            }
                        }
                        .controlSize(.regular)
                        .frame(width: settingsMetrics.menuWidth(124))

                        Button(String(localized: "Use Token...")) {
                            showPersonalAccessTokenSheet = true
                        }
                        .controlSize(.regular)

                        if viewModel.isConnected {
                            Button(String(localized: "Disconnect")) {
                                viewModel.disconnect()
                            }
                            .controlSize(.regular)
                        }
                    }

                    Text(
                        String(
                            localized: """
                            To read or write Gists on a user's behalf, Rockxy requires Gist Permission from your \
                            GitHub account. After the authorization, your GitHub Access Token will securely store \
                            in System Keychain.
                            """
                        )
                    )
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: settingsMetrics.fieldWidth(640), alignment: .leading)

                    if !viewModel.canUseOAuth {
                        Text(String(localized: "OAuth is not configured for this build. Personal access token fallback is available."))
                            .font(settingsMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, settingsMetrics.contentPadding + 12)
    }

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            alignedRow(label: String(localized: "Publish as:")) {
                VStack(alignment: .leading, spacing: 14) {
                    radioRow(
                        title: String(localized: "Private Gist"),
                        subtitle: String(localized: "Only the owner or colleagues who have a link can access the Gist."),
                        value: .secret
                    )
                    radioRow(
                        title: String(localized: "Public Gist"),
                        subtitle: String(localized: "Anyone can access the Gist."),
                        value: .public
                    )

                    if GitHubGistVisibility(rawValue: gistVisibility) == .public {
                        Text(String(localized: "Public Gists are discoverable. Review captured traffic before publishing."))
                            .font(settingsMetrics.secondaryFont(weight: .medium))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    checkboxWithHelp(
                        title: String(localized: "Automatic redact sensitive headers"),
                        subtitle: String(localized: "Authorization, Cookies, Set-Cookies, ... are censored before publishing to Gist."),
                        isOn: $redactSensitiveData,
                        onChange: AppSettingsManager.shared.updateGitHubGistRedactSensitiveData
                    )
                }
            }

            alignedRow(label: String(localized: "After Publish:")) {
                VStack(alignment: .leading, spacing: 12) {
                    checkboxWithHelp(
                        title: String(localized: "Open Gist with default Web Browser"),
                        subtitle: nil,
                        isOn: $openInBrowser,
                        onChange: AppSettingsManager.shared.updateGitHubGistOpenInBrowser
                    )
                    checkboxWithHelp(
                        title: String(localized: "Copy Gist URL to clipboard"),
                        subtitle: nil,
                        isOn: $copyURLToClipboard,
                        onChange: AppSettingsManager.shared.updateGitHubGistCopyURLToClipboard
                    )
                }
            }
        }
        .padding(.horizontal, settingsMetrics.contentPadding + 12)
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            alignedRow(label: String(localized: "Advanced:")) {
                VStack(alignment: .leading, spacing: 12) {
                    Button(String(localized: "Manage Access")) {
                        viewModel.openManageAccess()
                    }
                    .controlSize(.large)

                    Text(String(localized: "Review or Revoke Application Authorization."))
                        .font(settingsMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        viewModel.openHelp()
                    } label: {
                        Image(systemName: "questionmark")
                            .font(.system(size: max(18, settingsMetrics.bodyFontSize + 5), weight: .bold))
                            .frame(width: settingsMetrics.controlHeight + 14, height: settingsMetrics.controlHeight + 14)
                    }
                    .buttonStyle(.borderless)
                    .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                    .help(String(localized: "Open Publish to Gist documentation"))
                }
            }
        }
        .padding(.horizontal, settingsMetrics.contentPadding + 12)
    }

    private func alignedRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 18) {
            Text(label)
                .font(settingsMetrics.font(weight: .medium))
                .frame(width: settingsMetrics.wideLabelWidth, alignment: .trailing)
                .padding(.top, 2)
            content()
        }
    }

    private func radioRow(title: String, subtitle: String, value: GitHubGistVisibility) -> some View {
        Button {
            gistVisibility = value.rawValue
            AppSettingsManager.shared.updateGitHubGistVisibility(value)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: GitHubGistVisibility(rawValue: gistVisibility) == value ? "largecircle.fill.circle" : "circle.fill")
                        .font(.system(size: max(14, settingsMetrics.bodyFontSize + 1)))
                        .foregroundStyle(GitHubGistVisibility(rawValue: gistVisibility) == value ? .blue : Color(nsColor: .controlColor))
                    Text(title)
                        .font(settingsMetrics.font())
                        .foregroundStyle(.primary)
                }
                Text(subtitle)
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 33)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func checkboxWithHelp(
        title: String,
        subtitle: String?,
        isOn: Binding<Bool>,
        onChange: @escaping (Bool) -> Void
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
                .onChange(of: isOn.wrappedValue) { _, newValue in
                    onChange(newValue)
                }
            if let subtitle {
                Text(subtitle)
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 27)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - GitHubSettingsViewModel

@MainActor @Observable
final class GitHubSettingsViewModel {
    // MARK: Lifecycle

    init(
        credentialStorage: any GitHubCredentialStorage = KeychainGitHubCredentialStorage(),
        authService: GitHubAuthService = GitHubAuthService()
    ) {
        self.credentialStorage = credentialStorage
        self.authService = authService
        self.metadata = GitHubSettingsStore.loadMetadata()
    }

    // MARK: Internal

    private(set) var metadata: GitHubAuthMetadata?
    var personalAccessToken = ""
    var errorMessage: String?

    var isConnected: Bool {
        metadata != nil
    }

    var canUseOAuth: Bool {
        authService.configuredOAuthClientID != nil
    }

    var connectionTitle: String {
        guard let metadata else {
            return String(localized: "Not Authorized Yet!")
        }
        if let login = metadata.login, !login.isEmpty {
            return String(localized: "Authorized as \(login)")
        }
        return String(localized: "Authorized ••••\(metadata.tokenSuffix)")
    }

    var oauthClientID: String? {
        authService.configuredOAuthClientID
    }

    func savePersonalAccessToken() {
        do {
            let credential = try authService.credentialForPersonalAccessToken(personalAccessToken)
            try credentialStorage.save(credential)
            let metadata = credential.metadata
            GitHubSettingsStore.saveMetadata(metadata)
            self.metadata = metadata
            personalAccessToken = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveOAuthCredential(_ credential: GitHubCredential) {
        do {
            try credentialStorage.save(credential)
            let metadata = credential.metadata
            GitHubSettingsStore.saveMetadata(metadata)
            self.metadata = metadata
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestDeviceCode() async throws -> GitHubAuthService.DeviceCode {
        guard let oauthClientID else {
            throw GitHubAuthService.AuthError.clientIDMissing
        }
        return try await authService.requestDeviceCode(clientID: oauthClientID)
    }

    func pollDeviceToken(deviceCode: String) async throws -> GitHubCredential {
        guard let oauthClientID else {
            throw GitHubAuthService.AuthError.clientIDMissing
        }
        return try await authService.pollDeviceToken(clientID: oauthClientID, deviceCode: deviceCode)
    }

    func disconnect() {
        do {
            try credentialStorage.delete()
            GitHubSettingsStore.deleteMetadata()
            metadata = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openManageAccess() {
        let urlString = switch metadata?.method {
        case .deviceCode:
            "https://github.com/settings/applications"
        case .personalAccessToken, nil:
            "https://github.com/settings/tokens"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openHelp() {
        if let url = URL(string: "https://docs.proxyman.com/advanced-features/publish-to-gist") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Private

    private let credentialStorage: any GitHubCredentialStorage
    private let authService: GitHubAuthService
}

// MARK: - PersonalAccessTokenFallbackSheet

private struct PersonalAccessTokenFallbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Bindable var viewModel: GitHubSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Personal Access Token"))
                .font(.system(size: max(16, settingsMetrics.bodyFontSize + 3), weight: .semibold))

            Text(String(localized: "Paste a GitHub token with Gist access. Rockxy stores the token in Keychain."))
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField(String(localized: "GitHub token"), text: $viewModel.personalAccessToken)
                .textFieldStyle(.roundedBorder)
                .font(settingsMetrics.font(monospaced: true))
                .frame(minHeight: settingsMetrics.controlHeight)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(String(localized: "Create Token")) {
                    if let url = URL(string: "https://github.com/settings/tokens/new?scopes=gist&description=Rockxy") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                Button(String(localized: "Save")) {
                    viewModel.savePersonalAccessToken()
                    if viewModel.errorMessage == nil {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(settingsMetrics.font())
        .padding(settingsMetrics.contentPadding)
        .frame(width: settingsMetrics.fieldWidth(430))
    }

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - GitHubDeviceCodeAuthorizationSheet

private struct GitHubDeviceCodeAuthorizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Bindable var viewModel: GitHubSettingsViewModel
    @State private var deviceCode: GitHubAuthService.DeviceCode?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Authorize GitHub"))
                .font(.system(size: max(16, settingsMetrics.bodyFontSize + 3), weight: .semibold))

            if let deviceCode {
                Text(String(localized: "Enter this code on GitHub:"))
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Text(deviceCode.userCode)
                    .font(.system(size: max(28, settingsMetrics.bodyFontSize + 15), weight: .bold, design: .monospaced))
                    .textSelection(.enabled)

                HStack {
                    Button(String(localized: "Open GitHub")) {
                        if let url = URL(string: deviceCode.verificationURI) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button(String(localized: "I Authorized")) {
                        Task { await poll() }
                    }
                    .disabled(isLoading)
                }
            } else {
                Text(String(localized: "Rockxy will request GitHub Gist permission using OAuth device authorization."))
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Start Authorization")) {
                    Task { await start() }
                }
                .disabled(isLoading)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(String(localized: "Done")) {
                    dismiss()
                }
            }
        }
        .font(settingsMetrics.font())
        .padding(settingsMetrics.contentPadding)
        .frame(width: settingsMetrics.fieldWidth(430))
        .task {
            if deviceCode == nil {
                await start()
            }
        }
    }

    private func start() async {
        isLoading = true
        defer { isLoading = false }
        do {
            deviceCode = try await viewModel.requestDeviceCode()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func poll() async {
        guard let deviceCode else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let credential = try await viewModel.pollDeviceToken(deviceCode: deviceCode.deviceCode)
            viewModel.saveOAuthCredential(credential)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
