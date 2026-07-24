import AppKit
import SwiftUI

// swiftlint:disable file_length

// MARK: - AssistantSettingsTab

struct AssistantSettingsTab: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSectionCard(String(localized: "1. Local Model Setup")) {
                    globalModelSection
                }

                SettingsSectionCard(String(localized: "2. Provider & Model")) {
                    providerSection
                }

                SettingsSectionCard(String(localized: "3. Connection")) {
                    connectionSection
                }

                SettingsSectionCard(String(localized: "Data Handling")) {
                    privacySection
                }
            }
            .padding(.horizontal, settingsMetrics.contentPadding)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .font(settingsMetrics.font())
        .task {
            viewModel.refreshCredentialState()
            viewModel.refreshModelLibrary()
        }
        .alert(
            String(localized: "Remove Local Model?"),
            isPresented: Binding(
                get: { pendingModelRemoval != nil },
                set: { if !$0 { pendingModelRemoval = nil } }
            )
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingModelRemoval = nil
            }
            Button(String(localized: "Remove"), role: .destructive) {
                if let model = pendingModelRemoval {
                    viewModel.removeInstalledModel(model)
                }
                pendingModelRemoval = nil
            }
        } message: {
            Text(
                String(
                    localized: "This deletes \(pendingModelRemoval?.displayName ?? "the model") from Ollama. Rockxy cannot undo this action."
                )
            )
        }
        .sheet(isPresented: $isRuntimeSetupPresented) {
            AssistantRuntimeSetupSheet(viewModel: viewModel)
        }
    }

    // MARK: Private

    @State private var viewModel = AssistantSettingsViewModel()
    @State private var pendingModelRemoval: AssistantModel?
    @State private var isRuntimeSetupPresented = false
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var accessSection: some View {
        SettingsIndentedContent {
            VStack(alignment: .leading, spacing: 5) {
                Toggle(String(localized: "Enable model access"), isOn: Binding(
                    get: { viewModel.isEnabled },
                    set: viewModel.setEnabled
                ))
                .toggleStyle(.checkbox)
                .disabled(!viewModel.canEnable && !viewModel.isEnabled)

                Text(
                    String(
                        localized: "Local investigation is always available. Sending a prompt to a configured model requires an explicit Review Data confirmation."
                    )
                )
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if !viewModel.canEnable, !viewModel.isEnabled {
                    Label(
                        String(localized: "Save a complete provider configuration to enable model access."),
                        systemImage: "info.circle"
                    )
                    .font(settingsMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var globalModelSection: some View {
        Group {
            if let activeID = viewModel.savedConfiguration?.id,
               !viewModel.savedConfigurations.isEmpty
            {
                SettingsFieldRow(String(localized: "Global Default")) {
                    Picker(String(localized: "Global Default"), selection: Binding(
                        get: { activeID },
                        set: viewModel.selectSavedConfiguration
                    )) {
                        ForEach(viewModel.savedConfigurations) { configuration in
                            Text(viewModel.profileLabel(configuration)).tag(configuration.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: settingsMetrics.fieldWidth(420))
                }
            }

            SettingsIndentedContent {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        String(
                            localized: "Run the model on this Mac with no API usage fees. Rockxy checks the local runtime before model and traffic actions."
                        )
                    )
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    ollamaRuntimeStatus

                    if viewModel.isOllamaReady {
                        Text(String(localized: "Installed Models"))
                            .font(settingsMetrics.secondaryFont(weight: .medium))

                        if viewModel.installedOllamaModels.isEmpty {
                            Label(
                                String(localized: "No local models installed yet."),
                                systemImage: "shippingbox"
                            )
                            .font(settingsMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                Color(nsColor: .textBackgroundColor).opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                        } else {
                            ForEach(viewModel.installedOllamaModels) { model in
                                installedModelRow(model)
                            }
                        }

                        Text(String(localized: "Curated Local Models"))
                            .font(settingsMetrics.secondaryFont(weight: .medium))

                        ForEach(AssistantDownloadableModel.recommended) { model in
                            downloadableModelRow(model)
                        }

                        customModelDownload
                    }

                    HStack(spacing: 8) {
                        if viewModel.isRefreshingModelLibrary {
                            ProgressView().controlSize(.small)
                        }
                        Button(String(localized: "Check Again")) {
                            viewModel.refreshModelLibrary()
                        }
                        .controlSize(.small)
                        .disabled(viewModel.isRefreshingModelLibrary || viewModel.modelInstallID != nil)
                        if viewModel.isOllamaReady {
                            Button(String(localized: "Show Models Folder")) {
                                viewModel.revealOllamaModelsFolder()
                            }
                            .controlSize(.small)
                        }
                    }

                    Label(
                        String(
                            localized: "Model files remain managed by Ollama. Downloads can require several GB of disk and memory; model license terms vary."
                        ),
                        systemImage: "externaldrive"
                    )
                    .font(settingsMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: settingsMetrics.fieldWidth(520), alignment: .leading)
            }
        }
    }

    private var ollamaRuntimeStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            runtimeStatusIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.ollamaRuntimeTitle)
                    .font(settingsMetrics.secondaryFont(weight: .medium))
                Text(viewModel.ollamaRuntimeDetail)
                    .font(settingsMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if !viewModel.isOllamaReady {
                if viewModel.ollamaApplicationURL != nil {
                    Button(String(localized: "Open Ollama")) {
                        viewModel.openOllama()
                    }
                    .controlSize(.small)
                } else {
                    Button(String(localized: "Set Up Ollama…")) {
                        viewModel.prepareRuntimeSetup()
                        isRuntimeSetupPresented = true
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 0.5)
        }
    }

    @ViewBuilder private var runtimeStatusIcon: some View {
        switch viewModel.ollamaRuntimeState {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var customModelDownload: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Download Another Ollama Model"))
                .font(settingsMetrics.secondaryFont(weight: .medium))
            HStack(spacing: 8) {
                TextField(String(localized: "Model ID, for example qwen3:8b"), text: $viewModel.customModelID)
                    .textFieldStyle(.roundedBorder)
                Button(String(localized: "Download & Use")) {
                    viewModel.installCustomModel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canInstallCustomModel)
            }
            Text(String(localized: "Enter an exact model tag from the Ollama model library."))
                .font(settingsMetrics.metadataFont())
                .foregroundStyle(.secondary)

            if viewModel.modelInstallID == viewModel.customModelID.trimmingCharacters(in: .whitespacesAndNewlines) {
                if let progress = viewModel.modelInstallProgress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                HStack(spacing: 8) {
                    Text(viewModel.modelInstallStatus ?? String(localized: "Preparing download…"))
                        .font(settingsMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Cancel")) {
                        viewModel.cancelModelInstall()
                    }
                    .controlSize(.mini)
                }
            }
        }
        .padding(.top, 2)
    }

    private var providerSection: some View {
        Group {
            SettingsFieldRow(String(localized: "Provider")) {
                Picker(String(localized: "Provider"), selection: Binding(
                    get: { viewModel.configuration.kind },
                    set: viewModel.selectProvider
                )) {
                    ForEach(AssistantProviderGroup.allCases, id: \.self) { group in
                        Section(group.title) {
                            ForEach(AssistantProviderKind.allCases.filter { $0.group == group }) { provider in
                                Text(providerDisplayTitle(provider))
                                    .tag(provider)
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(width: settingsMetrics.fieldWidth(420))
            }

            if !viewModel.configuration.kind.isImplemented {
                SettingsIndentedContent {
                    Label(
                        String(
                            localized: "This provider needs its native adapter. Select OpenAI, Anthropic, Gemini, an OpenAI-compatible endpoint, or Ollama."
                        ),
                        systemImage: "hammer"
                    )
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.orange)
                }
            }

            SettingsFieldRow(String(localized: "API Surface")) {
                Text(viewModel.configuration.kind.apiSurface)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: settingsMetrics.controlHeight, alignment: .leading)
            }

            SettingsFieldRow(String(localized: "Base URL")) {
                TextField(String(localized: "Provider API base URL"), text: $viewModel.configuration.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: settingsMetrics.fieldWidth(420))
                    .frame(minHeight: settingsMetrics.controlHeight)
                    .disabled(viewModel.configuration.kind.usesFixedEndpoint)
            }

            SettingsIndentedContent {
                endpointSecurityLabel
            }

            SettingsFieldRow(String(localized: "Model")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if viewModel.models.isEmpty {
                            TextField(String(localized: "Exact model ID"), text: $viewModel.configuration.model)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Picker(String(localized: "Available Models"), selection: $viewModel.configuration.model) {
                                ForEach(viewModel.models) { model in
                                    Text(modelPickerTitle(model)).tag(model.id)
                                }
                            }
                            .labelsHidden()
                        }

                        Button {
                            viewModel.fetchModels()
                        } label: {
                            if viewModel.isRefreshingProviderModels {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(
                            viewModel.isBusy
                                || !viewModel.configuration.kind.isImplemented
                                || !(viewModel.configuration.kind.capabilities?.modelDiscovery ?? false)
                        )
                        .help(String(localized: "Refresh available models"))
                        .accessibilityLabel(String(localized: "Refresh Available Models"))
                    }
                    .frame(width: settingsMetrics.fieldWidth(420))
                    .frame(minHeight: settingsMetrics.controlHeight)

                    if viewModel.models.isEmpty,
                       viewModel.configuration.kind.capabilities?.modelDiscovery == true
                    {
                        Text(String(localized: "Refresh to discover models available from this provider."))
                            .font(settingsMetrics.metadataFont())
                            .foregroundStyle(.secondary)
                    } else if !viewModel.models.isEmpty {
                        Text(viewModel.availableModelsDetail)
                        .font(settingsMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.configuration.kind == .ollama {
                AssistantContextWindowSettingsField(configuration: $viewModel.configuration)
            }

            SettingsFieldRow(String(localized: "Output Limit")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        TextField(
                            String(localized: "Maximum output tokens"),
                            value: $viewModel.configuration.maxOutputTokens,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: settingsMetrics.fieldWidth(120))
                        Text(String(localized: "tokens per response"))
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: "Rockxy safety range: 1–32,768. The selected model may allow less."))
                        .font(settingsMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: settingsMetrics.controlHeight)
            }

            if viewModel.configuration.kind == .openAICompatible
                || viewModel.configuration.kind.group == .china
            {
                SettingsFieldRow(String(localized: "Platform / Region")) {
                    TextField(
                        String(localized: "Optional deployment or region label"),
                        text: Binding(
                            get: { viewModel.configuration.region ?? "" },
                            set: { viewModel.configuration.region = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: settingsMetrics.fieldWidth(420))
                    .frame(minHeight: settingsMetrics.controlHeight)
                }
            }

            if viewModel.configuration.kind != .ollama {
                SettingsFieldRow(String(localized: "Credential")) {
                    VStack(alignment: .leading, spacing: 6) {
                        SecureField(
                            viewModel.hasStoredCredential
                                ? String(localized: "Saved in Keychain · enter to replace")
                                : String(localized: "API key"),
                            text: $viewModel.credentialInput
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: settingsMetrics.fieldWidth(420))
                        .frame(minHeight: settingsMetrics.controlHeight)
                        Label(
                            viewModel.hasStoredCredential
                                ? String(localized: "Saved locally in macOS Keychain for this profile")
                                : String(localized: "No credential saved in settings or Keychain"),
                            systemImage: viewModel.hasStoredCredential ? "key.fill" : "key"
                        )
                        .font(settingsMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                        if viewModel.hasStoredCredential {
                            Button(String(localized: "Remove Credential"), role: .destructive) {
                                viewModel.removeCredential()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            SettingsIndentedContent {
                capabilitySummary
            }
        }
    }

    @ViewBuilder private var capabilitySummary: some View {
        if let capabilities = viewModel.configuration.kind.capabilities {
            VStack(alignment: .leading, spacing: 7) {
                Text(String(localized: "Adapter Capabilities"))
                    .font(settingsMetrics.secondaryFont(weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    capabilityLabel(String(localized: "Streaming"), supported: capabilities.streaming)
                    capabilityLabel(String(localized: "Discovery"), supported: capabilities.modelDiscovery)
                    capabilityLabel(String(localized: "Tools"), supported: capabilities.toolCalling)
                    capabilityLabel(String(localized: "Usage"), supported: capabilities.usageReporting)
                }
                .frame(maxWidth: settingsMetrics.fieldWidth(520), alignment: .leading)
                Text(
                    String(
                        localized: "These badges reflect Rockxy's current adapter path. Vision, reasoning, and model-level tool support are not inferred from the provider name."
                    )
                )
                .font(settingsMetrics.metadataFont())
                .foregroundStyle(.secondary)
                .frame(maxWidth: settingsMetrics.fieldWidth(420), alignment: .leading)
            }
        }
    }

    private var connectionSection: some View {
        Group {
            SettingsIndentedContent {
                HStack(spacing: 10) {
                    Button(String(localized: "Save Configuration")) {
                        viewModel.save()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isBusy || !viewModel.configuration.kind.isImplemented)

                    Button(String(localized: "Test Connection")) {
                        viewModel.testConnection()
                    }
                    .disabled(viewModel.isBusy || !viewModel.configuration.isComplete)

                    if viewModel.isBusy {
                        ProgressView().controlSize(.small)
                        Button(String(localized: "Cancel")) {
                            viewModel.cancelConnection()
                        }
                        .controlSize(.small)
                    }
                }
            }

            if let status = viewModel.statusMessage {
                SettingsIndentedContent {
                    Label(
                        status,
                        systemImage: viewModel.hasError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(viewModel.hasError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            accessSection

            SettingsIndentedContent {
                Button(String(localized: "Remove Provider"), role: .destructive) {
                    viewModel.removeProvider()
                }
                .disabled(viewModel.savedConfiguration == nil || viewModel.isBusy)
            }
        }
    }

    private var privacySection: some View {
        Group {
            SettingsIndentedContent {
                Label(
                    String(
                        localized: "Sensitive headers, query values, and body fields are redacted before Review Data."
                    ),
                    systemImage: "checkmark.shield.fill"
                )
                .foregroundStyle(.green)
                .fixedSize(horizontal: false, vertical: true)
            }
            if viewModel.configuration.kind == .openAI {
                SettingsIndentedContent {
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle(
                            String(localized: "Allow provider response storage"),
                            isOn: $viewModel.configuration.storeResponses
                        )
                        .toggleStyle(.checkbox)
                        Text(String(localized: "When off, Rockxy sends store=false with every Responses API request."))
                            .font(settingsMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            SettingsFieldRow(String(localized: "Destination")) {
                Text(viewModel.configuration.endpointHost)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: settingsMetrics.controlHeight, alignment: .leading)
            }
            if let documentationURL = viewModel.configuration.kind.documentationURL {
                SettingsIndentedContent {
                    Link(String(localized: "Provider data and API documentation"), destination: documentationURL)
                }
            }
        }
    }

    private func downloadableModelRow(_ model: AssistantDownloadableModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .font(settingsMetrics.secondaryFont(weight: .medium))
                    Text(model.detail)
                        .font(settingsMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.catalogDetail)
                        .font(settingsMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                    Text(model.id)
                        .font(settingsMetrics.metadataFont(monospaced: true))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 12)
                modelAction(model)
            }

            if viewModel.modelInstallID == model.id {
                if let progress = viewModel.modelInstallProgress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                HStack(spacing: 8) {
                    Text(viewModel.modelInstallStatus ?? String(localized: "Preparing download…"))
                        .font(settingsMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Cancel")) {
                        viewModel.cancelModelInstall()
                    }
                    .controlSize(.mini)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 0.5)
        }
    }

    private func installedModelRow(_ model: AssistantModel) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                    .font(settingsMetrics.secondaryFont(weight: .medium))
                Text(AssistantInstalledModelDetailFormatter.text(for: model))
                    .font(settingsMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                Text(model.id)
                    .font(settingsMetrics.metadataFont(monospaced: true))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            if viewModel.isGlobalModel(model.id) {
                Label(String(localized: "In Use"), systemImage: "checkmark.circle.fill")
                    .font(settingsMetrics.metadataFont(weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button(String(localized: "Use Globally")) {
                    viewModel.useGlobally(model)
                }
                .controlSize(.small)
            }
            Button(role: .destructive) {
                pendingModelRemoval = model
            } label: {
                Image(systemName: "trash")
            }
            .help(String(localized: "Remove model from Ollama"))
            .disabled(viewModel.modelRemovalID != nil || viewModel.modelInstallID != nil)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func modelAction(_ model: AssistantDownloadableModel) -> some View {
        if viewModel.isGlobalModel(model.id) {
            Label(String(localized: "In Use"), systemImage: "checkmark.circle.fill")
                .font(settingsMetrics.metadataFont(weight: .medium))
                .foregroundStyle(.green)
        } else if viewModel.installedOllamaModelIDs.contains(model.id) {
            Button(String(localized: "Use Globally")) {
                viewModel.useGlobally(model)
            }
            .controlSize(.small)
            .disabled(viewModel.modelInstallID != nil)
        } else {
            Button(String(localized: "Download & Use")) {
                viewModel.installAndUse(model)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.modelInstallID != nil)
        }
    }

    private func capabilityLabel(_ title: String, supported: Bool) -> some View {
        Label(title, systemImage: supported ? "checkmark.circle.fill" : "minus.circle")
            .font(settingsMetrics.metadataFont())
            .foregroundStyle(supported ? Color.green : Color.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func providerDisplayTitle(_ provider: AssistantProviderKind) -> String {
        guard !provider.isImplemented else {
            return provider.title
        }
        return String(localized: "\(provider.title) · adapter pending")
    }

    @ViewBuilder private var endpointSecurityLabel: some View {
        switch viewModel.configuration.endpointSecurity {
        case .encrypted:
            Label(String(localized: "Encrypted HTTPS connection"), systemImage: "lock.fill")
                .foregroundStyle(.green)
        case .localLoopback:
            Label(String(localized: "Local-only connection on this Mac"), systemImage: "desktopcomputer")
                .foregroundStyle(.green)
        case .insecureRemote:
            Label(
                String(localized: "Blocked: remote endpoints must use HTTPS"),
                systemImage: "exclamationmark.shield.fill"
            )
            .foregroundStyle(.red)
        case .invalid:
            Label(String(localized: "Enter a valid HTTP or HTTPS base URL"), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    private func modelPickerTitle(_ model: AssistantModel) -> String {
        var details: [String] = []
        if let limit = model.inputTokenLimit {
            details.append(String(localized: "\(limit.formatted()) input"))
        }
        if let limit = model.outputTokenLimit {
            details.append(String(localized: "\(limit.formatted()) output"))
        }
        return details.isEmpty ? model.displayName : "\(model.displayName) · \(details.joined(separator: " / "))"
    }
}

// MARK: - OllamaRuntimeState

enum OllamaRuntimeState: Equatable {
    case checking
    case ready(version: String)
    case unavailable(message: String)
}

// MARK: - AssistantSettingsViewModel

@MainActor @Observable
final class AssistantSettingsViewModel {
    // MARK: Lifecycle

    init(
        manager: AppSettingsManager? = nil,
        credentialStorage: any AssistantCredentialStorage = KeychainAssistantCredentialStorage(),
        runtime: any AssistantProviderRuntimeProtocol = AssistantProviderRuntime.shared,
        modelInstaller: any AssistantModelInstallerProtocol = OllamaModelInstaller.shared,
        ollamaRuntime: any OllamaRuntimeChecking = OllamaRuntimeChecker.shared,
        runtimeInstaller: any AssistantLocalRuntimeInstalling = OllamaRuntimeInstaller.shared,
        applicationOpener: any AssistantRuntimeApplicationOpening = NSWorkspaceAssistantRuntimeApplicationOpener()
    ) {
        let manager = manager ?? .shared
        self.manager = manager
        self.credentialStorage = credentialStorage
        self.runtime = runtime
        self.modelInstaller = modelInstaller
        self.ollamaRuntime = ollamaRuntime
        self.runtimeInstaller = runtimeInstaller
        self.applicationOpener = applicationOpener
        let saved = manager.settings.assistantProviderConfiguration
        savedConfiguration = saved
        savedConfigurations = manager.settings.assistantProviderConfigurations
        configuration = saved ?? AssistantProviderConfiguration(kind: .ollama)
        isEnabled = manager.settings.debugAssistantModelAccessEnabled
    }

    // MARK: Internal

    var configuration: AssistantProviderConfiguration
    private(set) var savedConfiguration: AssistantProviderConfiguration?
    private(set) var savedConfigurations: [AssistantProviderConfiguration]
    var credentialInput = ""
    var customModelID = ""
    private(set) var hasStoredCredential = false
    private(set) var models: [AssistantModel] = []
    private(set) var installedOllamaModels: [AssistantModel] = []
    private(set) var installedOllamaModelIDs = Set<String>()
    private(set) var isEnabled: Bool
    private(set) var isBusy = false
    private(set) var isRefreshingProviderModels = false
    private(set) var isRefreshingModelLibrary = false
    private(set) var ollamaRuntimeState = OllamaRuntimeState.checking
    private(set) var runtimeSetupState = AssistantRuntimeSetupState.idle
    private(set) var runtimeInstallDestination = AssistantSettingsViewModel.defaultRuntimeInstallDestination
    private(set) var modelInstallID: String?
    private(set) var modelRemovalID: String?
    private(set) var modelInstallProgress: Double?
    private(set) var modelInstallStatus: String?
    private(set) var statusMessage: String?
    private(set) var hasError = false

    var canEnable: Bool {
        guard let savedConfiguration, savedConfiguration.isComplete else {
            return false
        }
        return !savedConfiguration.kind.requiresCredential || hasStoredCredential
    }

    var isOllamaReady: Bool {
        if case .ready = ollamaRuntimeState {
            return true
        }
        return false
    }

    var canInstallCustomModel: Bool {
        isOllamaReady
            && modelInstallID == nil
            && !customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var availableModelsDetail: String {
        if models.count == 1 {
            return String(localized: "1 model available · refreshes automatically after local downloads.")
        }
        return String(localized: "\(models.count) models available · refreshes automatically after local downloads.")
    }

    var ollamaRuntimeTitle: String {
        switch ollamaRuntimeState {
        case .checking:
            String(localized: "Checking Ollama Runtime…")
        case let .ready(version):
            String(localized: "Ollama \(version) Ready")
        case .unavailable:
            String(localized: "Ollama Runtime Unavailable")
        }
    }

    var ollamaRuntimeDetail: String {
        switch ollamaRuntimeState {
        case .checking:
            String(
                localized: "Connecting to the local service at \(ollamaBaseURL.host() ?? "127.0.0.1")."
            )
        case .ready:
            String(localized: "Models and reviewed traffic stay on this Mac through this local endpoint.")
        case let .unavailable(message):
            message
        }
    }

    var ollamaApplicationURL: URL? {
        if let lastInstalledRuntimeURL,
           FileManager.default.fileExists(atPath: lastInstalledRuntimeURL.path)
        {
            return lastInstalledRuntimeURL
        }
        if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama") {
            return applicationURL
        }
        let standardURL = URL(fileURLWithPath: "/Applications/Ollama.app", isDirectory: true)
        return FileManager.default.fileExists(atPath: standardURL.path) ? standardURL : nil
    }

    var runtimeInstallDestinationDisplayPath: String {
        runtimeInstallDestination.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~",
            options: .anchored
        )
    }

    func refreshCredentialState() {
        do {
            hasStoredCredential = try credentialStorage.load(providerID: configuration.id) != nil
        } catch {
            setError(error)
        }
    }

    func selectProvider(_ kind: AssistantProviderKind) {
        guard configuration.kind != kind else {
            return
        }
        configuration = AssistantProviderConfiguration(kind: kind)
        credentialInput = ""
        hasStoredCredential = false
        models = []
        statusMessage = nil
        hasError = false
        refreshCredentialState()
        if kind == .ollama {
            models = installedOllamaModels
            refreshModelLibrary()
        }
    }

    func selectSavedConfiguration(_ configurationID: UUID) {
        guard let selected = savedConfigurations.first(where: { $0.id == configurationID }) else {
            return
        }
        manager.selectAssistantConfiguration(configurationID)
        savedConfiguration = selected
        configuration = selected
        credentialInput = ""
        models = []
        statusMessage = nil
        hasError = false
        refreshCredentialState()
        if selected.kind == .ollama {
            models = installedOllamaModels
        }
    }

    func profileLabel(_ configuration: AssistantProviderConfiguration) -> String {
        "\(configuration.kind.title) · \(configuration.model)"
    }

    func isGlobalModel(_ modelID: String) -> Bool {
        isEnabled && savedConfiguration?.kind == .ollama && savedConfiguration?.model == modelID
    }

    func save() {
        do {
            try persistDraft()
            setSuccess(String(localized: "AI Assistant configuration saved as the global default."))
        } catch {
            setError(error)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, !canEnable {
            setError(AssistantProviderError.notConfigured)
            isEnabled = false
            return
        }
        isEnabled = enabled
        manager.updateAssistantConfiguration(savedConfiguration, enabled: enabled)
    }

    func fetchModels() {
        guard !isBusy, !isRefreshingProviderModels else {
            return
        }
        isRefreshingProviderModels = true
        startConnectionAction(requiresModel: false) { configuration in
            defer { self.isRefreshingProviderModels = false }
            let previousModelID = self.configuration.model
            let values = try await self.runtime.discoverModels(configuration: configuration)
            guard !Task.isCancelled else {
                return
            }
            self.models = values
            if !values.contains(where: { $0.id == self.configuration.model }),
               let first = values.first
            {
                self.configuration.model = first.id
            }
            if let selected = values.first(where: { $0.id == self.configuration.model }),
               let providerLimit = selected.outputTokenLimit
            {
                self.configuration.maxOutputTokens = min(
                    self.configuration.maxOutputTokens,
                    providerLimit
                )
            }
            if let selected = values.first(where: { $0.id == self.configuration.model }) {
                let modelChanged = previousModelID != selected.id
                self.applyDiscoveredContextWindow(
                    selected,
                    modelChanged: modelChanged
                )
            }
            if !self.configuration.model.isEmpty {
                try self.persistDraft()
            }
            self.setSuccess(String(localized: "Found \(values.count) models."))
        }
    }

    func refreshModelLibrary() {
        guard !isRefreshingModelLibrary, modelInstallID == nil else {
            return
        }
        isRefreshingModelLibrary = true
        ollamaRuntimeState = .checking
        let baseURL = ollamaBaseURL
        Task { [weak self] in
            guard let self else {
                return
            }
            defer { self.isRefreshingModelLibrary = false }
            do {
                let info = try await self.ollamaRuntime.check(baseURL: baseURL)
                guard !Task.isCancelled else {
                    return
                }
                self.ollamaRuntimeState = .ready(version: info.version)
                var inventory = AssistantProviderConfiguration(kind: .ollama, model: "inventory")
                inventory.baseURL = baseURL.absoluteString
                let values = try await self.runtime.discoverModels(configuration: inventory)
                guard !Task.isCancelled, self.ollamaBaseURL == baseURL else {
                    return
                }
                self.installedOllamaModels = values
                self.installedOllamaModelIDs = Set(values.map(\.id))
                if self.configuration.kind == .ollama {
                    self.models = values
                    if !values.contains(where: { $0.id == self.configuration.model }),
                       let first = values.first
                    {
                        self.configuration.model = first.id
                    }
                }
                if var selected = self.savedConfiguration,
                   selected.kind == .ollama,
                   let model = values.first(where: { $0.id == selected.model })
                {
                    let normalizedContext = self.normalizedOllamaContextWindow(
                        selected.contextWindowTokens,
                        modelLimit: model.inputTokenLimit
                    )
                    if selected.contextWindowTokens != normalizedContext {
                        selected.contextWindowTokens = normalizedContext
                        self.manager.updateAssistantConfiguration(selected, enabled: self.isEnabled)
                        self.savedConfiguration = selected
                        self.configuration = selected
                        self.refreshSavedConfigurations()
                    }
                }
            } catch {
                guard !Task.isCancelled, self.ollamaBaseURL == baseURL else {
                    return
                }
                self.installedOllamaModels = []
                self.installedOllamaModelIDs = []
                if self.configuration.kind == .ollama {
                    self.models = []
                }
                self.ollamaRuntimeState = .unavailable(
                    message: String(
                        localized: "Start Ollama on this Mac, then check again. (\(error.localizedDescription))"
                    )
                )
            }
        }
    }

    func openOllama() {
        guard let applicationURL = ollamaApplicationURL else {
            return
        }
        NSWorkspace.shared.open(applicationURL)
    }

    func prepareRuntimeSetup() {
        guard !runtimeSetupState.isBusy else {
            return
        }
        runtimeSetupState = .idle
    }

    func chooseRuntimeInstallDestination() {
        guard !runtimeSetupState.isBusy else {
            return
        }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Ollama Install Location")
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Rockxy will install Ollama.app inside the selected folder.")
        panel.directoryURL = runtimeInstallDestination
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }
        runtimeInstallDestination = selectedURL.standardizedFileURL
        runtimeSetupState = .idle
    }

    func installOllamaRuntime() {
        guard !runtimeSetupState.isBusy else {
            return
        }
        let destination = runtimeInstallDestination
        runtimeSetupState = .downloading(receivedBytes: 0, totalBytes: nil)
        hasError = false
        runtimeInstallTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let events = self.runtimeInstaller.install(
                    runtime: .ollama,
                    destinationDirectory: destination
                )
                for try await event in events {
                    try Task.checkCancellation()
                    switch event {
                    case let .downloading(receivedBytes, totalBytes):
                        self.runtimeSetupState = .downloading(
                            receivedBytes: receivedBytes,
                            totalBytes: totalBytes
                        )
                    case .verifying:
                        self.runtimeSetupState = .verifying
                    case .installing:
                        self.runtimeSetupState = .installing
                    case let .completed(installation):
                        self.lastInstalledRuntimeURL = installation.applicationURL
                        self.runtimeSetupState = .starting
                        try await self.startAndVerifyOllama(at: installation.applicationURL)
                    }
                }
            } catch is CancellationError {
                self.runtimeSetupState = .idle
            } catch AssistantProviderError.cancelled {
                self.runtimeSetupState = .idle
            } catch {
                self.runtimeSetupState = .failed(message: error.localizedDescription)
            }
            self.runtimeInstallTask = nil
        }
    }

    func retryInstalledOllamaRuntime() {
        guard !runtimeSetupState.isBusy,
              let applicationURL = ollamaApplicationURL else {
            return
        }
        runtimeSetupState = .starting
        hasError = false
        runtimeInstallTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await self.startAndVerifyOllama(at: applicationURL)
            } catch is CancellationError {
                self.runtimeSetupState = .idle
            } catch AssistantProviderError.cancelled {
                self.runtimeSetupState = .idle
            } catch {
                self.runtimeSetupState = .failed(message: error.localizedDescription)
            }
            self.runtimeInstallTask = nil
        }
    }

    func cancelRuntimeInstall() {
        runtimeInstallTask?.cancel()
        runtimeInstallTask = nil
        runtimeSetupState = .idle
    }

    func revealOllamaModelsFolder() {
        let modelsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ollama/models", isDirectory: true)
        if FileManager.default.fileExists(atPath: modelsURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([modelsURL])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: modelsURL.deletingLastPathComponent().path)
        }
    }

    func installCustomModel() {
        let modelID = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else {
            return
        }
        installAndUse(AssistantDownloadableModel(
            id: modelID,
            name: modelID,
            detail: String(localized: "Custom model from the Ollama library")
        ))
    }

    func installAndUse(_ model: AssistantDownloadableModel) {
        guard modelInstallID == nil, isOllamaReady else {
            setError(AssistantProviderError.notConfigured)
            return
        }
        let baseURL = ollamaBaseURL
        modelInstallID = model.id
        modelInstallProgress = nil
        modelInstallStatus = String(localized: "Connecting to Ollama…")
        hasError = false
        modelInstallTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                for try await event in self.modelInstaller.install(modelID: model.id, baseURL: baseURL) {
                    guard !Task.isCancelled else {
                        return
                    }
                    switch event {
                    case let .status(value):
                        self.modelInstallStatus = value
                    case let .progress(completed, total):
                        self.modelInstallStatus = String(localized: "Downloading \(model.name)…")
                        if let total, total > 0 {
                            self.modelInstallProgress = min(1, Double(completed) / Double(total))
                        }
                    case .completed:
                        var inventory = AssistantProviderConfiguration(kind: .ollama, model: model.id)
                        inventory.baseURL = baseURL.absoluteString
                        let installedModel = try? await self.runtime
                            .discoverModels(configuration: inventory)
                            .first { $0.id == model.id }
                        guard !Task.isCancelled else {
                            return
                        }
                        self.activateOllamaModel(
                            id: model.id,
                            name: model.name,
                            baseURL: baseURL,
                            contextWindowTokens: installedModel?.inputTokenLimit
                        )
                        if let installedModel {
                            self.installedOllamaModels.removeAll { $0.id == model.id }
                            self.installedOllamaModels.append(installedModel)
                            self.installedOllamaModels.sort {
                                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                            }
                        }
                        if self.customModelID.trimmingCharacters(in: .whitespacesAndNewlines) == model.id {
                            self.customModelID = ""
                        }
                    }
                }
            } catch is CancellationError {
                self.modelInstallStatus = String(localized: "Download cancelled.")
            } catch AssistantProviderError.cancelled {
                self.modelInstallStatus = String(localized: "Download cancelled.")
            } catch {
                self.setError(error)
                self.modelInstallStatus = error.localizedDescription
            }
            self.modelInstallID = nil
            self.modelInstallProgress = nil
            self.modelInstallTask = nil
        }
    }

    func cancelModelInstall() {
        modelInstallTask?.cancel()
        modelInstallTask = nil
        modelInstallID = nil
        modelInstallProgress = nil
        modelInstallStatus = String(localized: "Download cancelled.")
    }

    func useGlobally(_ model: AssistantDownloadableModel) {
        activateOllamaModel(
            id: model.id,
            name: model.name,
            baseURL: ollamaBaseURL,
            contextWindowTokens: nil
        )
    }

    func useGlobally(_ model: AssistantModel) {
        activateOllamaModel(
            id: model.id,
            name: model.displayName,
            baseURL: ollamaBaseURL,
            contextWindowTokens: model.inputTokenLimit
        )
    }

    func removeInstalledModel(_ model: AssistantModel) {
        guard modelRemovalID == nil, modelInstallID == nil, isOllamaReady else {
            return
        }
        modelRemovalID = model.id
        let baseURL = ollamaBaseURL
        Task { [weak self] in
            guard let self else {
                return
            }
            defer { self.modelRemovalID = nil }
            do {
                try await self.modelInstaller.remove(modelID: model.id, baseURL: baseURL)
                self.installedOllamaModels.removeAll { $0.id == model.id }
                self.installedOllamaModelIDs.remove(model.id)
                if self.configuration.kind == .ollama {
                    self.models.removeAll { $0.id == model.id }
                }
                if self.savedConfiguration?.kind == .ollama,
                   self.savedConfiguration?.model == model.id
                {
                    self.isEnabled = false
                    self.manager.updateAssistantConfiguration(self.savedConfiguration, enabled: false)
                }
                self.setSuccess(String(localized: "Removed \(model.displayName) from Ollama."))
            } catch {
                self.setError(error)
            }
        }
    }

    func testConnection() {
        startConnectionAction { configuration in
            let result = try await self.runtime.testConnection(configuration: configuration)
            guard !Task.isCancelled else {
                return
            }
            self.setSuccess(
                String(localized: "Connected to \(result.provider) at \(result.endpointHost) with \(result.model).")
            )
        }
    }

    func cancelConnection() {
        connectionTask?.cancel()
        connectionTask = nil
        isBusy = false
        isRefreshingProviderModels = false
        hasError = false
        statusMessage = String(localized: "Connection check cancelled.")
    }

    func removeCredential() {
        do {
            try credentialStorage.delete(providerID: configuration.id)
            hasStoredCredential = false
            credentialInput = ""
            if configuration.kind.requiresCredential {
                isEnabled = false
                manager.updateAssistantConfiguration(savedConfiguration, enabled: false)
            }
            setSuccess(String(localized: "Saved credential removed."))
        } catch {
            setError(error)
        }
    }

    func removeProvider() {
        do {
            guard let removed = savedConfiguration else {
                return
            }
            try credentialStorage.delete(providerID: removed.id)
            manager.removeAssistantConfiguration(removed.id)
            refreshSavedConfigurations()
            savedConfiguration = manager.settings.assistantProviderConfiguration
            configuration = savedConfiguration ?? AssistantProviderConfiguration(kind: .ollama)
            credentialInput = ""
            models = []
            isEnabled = manager.settings.debugAssistantModelAccessEnabled
            refreshCredentialState()
            setSuccess(String(localized: "Provider profile and its saved credential removed."))
        } catch {
            setError(error)
        }
    }

    // MARK: Private

    private let manager: AppSettingsManager
    private let credentialStorage: any AssistantCredentialStorage
    private let runtime: any AssistantProviderRuntimeProtocol
    private let modelInstaller: any AssistantModelInstallerProtocol
    private let ollamaRuntime: any OllamaRuntimeChecking
    private let runtimeInstaller: any AssistantLocalRuntimeInstalling
    private let applicationOpener: any AssistantRuntimeApplicationOpening
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var modelInstallTask: Task<Void, Never>?
    @ObservationIgnored private var runtimeInstallTask: Task<Void, Never>?
    private var lastInstalledRuntimeURL: URL?

    private static var defaultRuntimeInstallDestination: URL {
        let fileManager = FileManager.default
        if let applications = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first,
           fileManager.isWritableFile(atPath: applications.path)
        {
            return applications
        }
        if let userApplications = fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first,
           fileManager.fileExists(atPath: userApplications.path)
        {
            return userApplications
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    private var ollamaBaseURL: URL {
        if configuration.kind == .ollama, let endpointURL = configuration.endpointURL {
            return endpointURL
        }
        if let savedOllama = savedConfigurations.first(where: { $0.kind == .ollama }),
           let endpointURL = savedOllama.endpointURL
        {
            return endpointURL
        }
        guard let defaultURL = URL(string: AssistantProviderKind.ollama.defaultBaseURL) else {
            preconditionFailure("The built-in Ollama URL must remain valid")
        }
        return defaultURL
    }

    private func startAndVerifyOllama(at applicationURL: URL) async throws {
        try await applicationOpener.open(applicationURL: applicationURL)
        let info = try await waitForOllamaReadiness()
        ollamaRuntimeState = .ready(version: info.version)
        runtimeSetupState = .ready(version: info.version)
        refreshModelLibrary()
    }

    private func waitForOllamaReadiness() async throws -> OllamaRuntimeInfo {
        var latestError: Error = AssistantProviderError.network(
            String(localized: "Ollama did not start its local service.")
        )
        for attempt in 0 ..< 30 {
            try Task.checkCancellation()
            do {
                return try await ollamaRuntime.check(baseURL: ollamaBaseURL)
            } catch {
                latestError = error
            }
            if attempt < 29 {
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw latestError
    }

    private func persistDraft() throws {
        try prepareDraft(requiresModel: true)
        savedConfiguration = configuration
        manager.updateAssistantConfiguration(configuration, enabled: isEnabled)
        refreshSavedConfigurations()
    }

    private func prepareDraft(requiresModel: Bool) throws {
        configuration.baseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.maxOutputTokens = AssistantProviderConfiguration.validMaxOutputTokens(
            configuration.maxOutputTokens
        )
        configuration.contextWindowTokens = AssistantProviderConfiguration.normalizedContextWindowTokens(
            configuration.contextWindowTokens,
            for: configuration.kind
        )
        configuration.redactSensitiveData = true
        guard configuration.kind.isImplemented,
              configuration.endpointURL != nil,
              !requiresModel || !configuration.model.isEmpty else
        {
            throw AssistantProviderError.notConfigured
        }
        guard configuration.endpointSecurity.permitsCapturedData else {
            throw AssistantProviderError.insecureEndpoint
        }
        let trimmedCredential = credentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCredential.isEmpty {
            try credentialStorage.save(trimmedCredential, providerID: configuration.id)
            credentialInput = ""
            hasStoredCredential = true
        }
        if configuration.kind.requiresCredential, !hasStoredCredential {
            throw AssistantProviderError.credentialMissing
        }
    }

    private func activateOllamaModel(
        id: String,
        name: String,
        baseURL: URL,
        contextWindowTokens: Int?
    ) {
        var selected = savedConfigurations.first {
            $0.kind == .ollama && $0.model == id
        } ?? AssistantProviderConfiguration(kind: .ollama, model: id)
        selected.baseURL = baseURL.absoluteString
        selected.contextWindowTokens = AssistantProviderConfiguration
            .recommendedLocalContextWindowTokens(modelLimit: contextWindowTokens)
        selected.redactSensitiveData = true
        manager.updateAssistantConfiguration(selected, enabled: true)
        savedConfiguration = selected
        configuration = selected
        isEnabled = true
        installedOllamaModelIDs.insert(id)
        if !installedOllamaModels.contains(where: { $0.id == id }) {
            installedOllamaModels.append(AssistantModel(id: id, displayName: name))
            installedOllamaModels.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
        models = installedOllamaModels
        if !models.contains(where: { $0.id == id }) {
            models.append(AssistantModel(id: id, displayName: name))
            models.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
        refreshSavedConfigurations()
        setSuccess(String(localized: "\(name) is ready and selected globally."))
    }

    private func applyDiscoveredContextWindow(
        _ model: AssistantModel,
        modelChanged: Bool
    ) {
        if configuration.kind == .ollama {
            let normalized = normalizedOllamaContextWindow(
                configuration.contextWindowTokens,
                modelLimit: model.inputTokenLimit
            )
            if modelChanged || configuration.contextWindowTokens != normalized {
                configuration.contextWindowTokens = normalized
            }
        } else {
            configuration.contextWindowTokens = model.inputTokenLimit
        }
    }

    private func normalizedOllamaContextWindow(
        _ current: Int?,
        modelLimit: Int?
    )
        -> Int
    {
        let recommended = AssistantProviderConfiguration
            .recommendedLocalContextWindowTokens(modelLimit: modelLimit)
        guard let current else {
            return recommended
        }
        guard current <= AssistantProviderConfiguration.maxLocalContextWindowTokens,
              modelLimit.map({ current <= $0 }) ?? true else
        {
            return recommended
        }
        return current
    }

    private func refreshSavedConfigurations() {
        savedConfigurations = manager.settings.assistantProviderConfigurations
    }

    private func startConnectionAction(
        requiresModel: Bool = true,
        _ operation: @escaping (AssistantProviderConfiguration) async throws -> Void
    ) {
        guard !isBusy else {
            return
        }
        isBusy = true
        statusMessage = nil
        connectionTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                if !Task.isCancelled {
                    self.isBusy = false
                    self.connectionTask = nil
                }
            }
            do {
                try self.prepareDraft(requiresModel: requiresModel)
                try await operation(self.configuration)
            } catch is CancellationError {
                return
            } catch AssistantProviderError.cancelled {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self.setError(error)
                self.isRefreshingProviderModels = false
            }
        }
    }

    private func setSuccess(_ message: String) {
        hasError = false
        statusMessage = message
    }

    private func setError(_ error: Error) {
        hasError = true
        statusMessage = error.localizedDescription
    }
}
