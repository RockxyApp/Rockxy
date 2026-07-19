import SwiftUI

// MARK: - AssistantSettingsTab

struct AssistantSettingsTab: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSectionCard(String(localized: "AI Assistant")) {
                    accessSection
                }

                SettingsSectionCard(String(localized: "Global Model Library")) {
                    globalModelSection
                }

                SettingsSectionCard(String(localized: "Provider & Model")) {
                    providerSection
                }

                SettingsSectionCard(String(localized: "Connection")) {
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
    }

    // MARK: Private

    @State private var viewModel = AssistantSettingsViewModel()
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
                            localized: "Download once through Ollama, then use the selected model across every Rockxy workspace."
                        )
                    )
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    ForEach(AssistantDownloadableModel.recommended) { model in
                        downloadableModelRow(model)
                    }

                    HStack(spacing: 8) {
                        if viewModel.isRefreshingModelLibrary {
                            ProgressView().controlSize(.small)
                        }
                        Button(String(localized: "Refresh Installed Models")) {
                            viewModel.refreshModelLibrary()
                        }
                        .controlSize(.small)
                        .disabled(viewModel.isRefreshingModelLibrary || viewModel.modelInstallID != nil)
                    }

                    Label(
                        String(
                            localized: "Requires Ollama running at 127.0.0.1:11434. Ollama owns downloaded model files; Rockxy keeps only the global selection."
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
                            localized: "This provider needs its native adapter. Select OpenAI, an OpenAI-compatible endpoint, or Ollama."
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
                    .disabled(viewModel.configuration.kind == .openAI)
            }

            SettingsFieldRow(String(localized: "Model")) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(String(localized: "Exact model ID"), text: $viewModel.configuration.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: settingsMetrics.fieldWidth(420))
                        .frame(minHeight: settingsMetrics.controlHeight)
                    if !viewModel.models.isEmpty {
                        Picker(String(localized: "Discovered Models"), selection: $viewModel.configuration.model) {
                            ForEach(viewModel.models) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: settingsMetrics.fieldWidth(420))
                    }
                }
            }

            if viewModel.configuration.kind == .openAICompatible {
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
                                ? String(localized: "Credential saved in System Keychain")
                                : String(localized: "No credential saved"),
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
                HStack(spacing: 20) {
                    capabilityLabel(String(localized: "Streaming"), supported: capabilities.streaming)
                    capabilityLabel(String(localized: "Model Discovery"), supported: capabilities.modelDiscovery)
                    capabilityLabel(String(localized: "Tool Calls"), supported: capabilities.toolCalling)
                    capabilityLabel(String(localized: "Usage"), supported: capabilities.usageReporting)
                }
                .frame(maxWidth: settingsMetrics.fieldWidth(420), alignment: .leading)
                Text(
                    String(
                        localized: "Vision and reasoning availability remains model-specific and is not inferred from the provider name."
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

                    Button(String(localized: "Fetch Models")) {
                        viewModel.fetchModels()
                    }
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
}

// MARK: - AssistantSettingsViewModel

@MainActor @Observable
final class AssistantSettingsViewModel {
    // MARK: Lifecycle

    init(
        manager: AppSettingsManager? = nil,
        credentialStorage: any AssistantCredentialStorage = KeychainAssistantCredentialStorage(),
        runtime: any AssistantProviderRuntimeProtocol = AssistantProviderRuntime.shared,
        modelInstaller: any AssistantModelInstallerProtocol = OllamaModelInstaller.shared
    ) {
        let manager = manager ?? .shared
        self.manager = manager
        self.credentialStorage = credentialStorage
        self.runtime = runtime
        self.modelInstaller = modelInstaller
        let saved = manager.settings.assistantProviderConfiguration
        savedConfiguration = saved
        savedConfigurations = manager.settings.assistantProviderConfigurations
        configuration = saved ?? AssistantProviderConfiguration(kind: .openAI)
        isEnabled = manager.settings.debugAssistantModelAccessEnabled
    }

    // MARK: Internal

    var configuration: AssistantProviderConfiguration
    private(set) var savedConfiguration: AssistantProviderConfiguration?
    private(set) var savedConfigurations: [AssistantProviderConfiguration]
    var credentialInput = ""
    private(set) var hasStoredCredential = false
    private(set) var models: [AssistantModel] = []
    private(set) var installedOllamaModelIDs = Set<String>()
    private(set) var isEnabled: Bool
    private(set) var isBusy = false
    private(set) var isRefreshingModelLibrary = false
    private(set) var modelInstallID: String?
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
        startConnectionAction { configuration in
            let values = try await self.runtime.discoverModels(configuration: configuration)
            guard !Task.isCancelled else {
                return
            }
            self.models = values
            if configuration.model.isEmpty, let first = values.first {
                self.configuration.model = first.id
            }
            self.setSuccess(String(localized: "Found \(values.count) models."))
        }
    }

    func refreshModelLibrary() {
        guard !isRefreshingModelLibrary, modelInstallID == nil else {
            return
        }
        isRefreshingModelLibrary = true
        let baseURL = ollamaBaseURL
        Task { [weak self] in
            guard let self else {
                return
            }
            defer { self.isRefreshingModelLibrary = false }
            do {
                var inventory = AssistantProviderConfiguration(kind: .ollama, model: "inventory")
                inventory.baseURL = baseURL.absoluteString
                let values = try await self.runtime.discoverModels(configuration: inventory)
                self.installedOllamaModelIDs = Set(values.map(\.id))
            } catch {
                // The provider editor remains usable when Ollama is not running.
            }
        }
    }

    func installAndUse(_ model: AssistantDownloadableModel) {
        guard modelInstallID == nil else {
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
                        self.activateOllamaModel(model, baseURL: baseURL)
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
        activateOllamaModel(model, baseURL: ollamaBaseURL)
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
            configuration = savedConfiguration ?? AssistantProviderConfiguration(kind: .openAI)
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
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var modelInstallTask: Task<Void, Never>?

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

    private func persistDraft() throws {
        configuration.baseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.redactSensitiveData = true
        guard configuration.isComplete else {
            throw AssistantProviderError.notConfigured
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
        savedConfiguration = configuration
        manager.updateAssistantConfiguration(configuration, enabled: isEnabled)
        refreshSavedConfigurations()
    }

    private func activateOllamaModel(_ model: AssistantDownloadableModel, baseURL: URL) {
        var selected = savedConfigurations.first {
            $0.kind == .ollama && $0.model == model.id
        } ?? AssistantProviderConfiguration(kind: .ollama, model: model.id)
        selected.baseURL = baseURL.absoluteString
        selected.redactSensitiveData = true
        manager.updateAssistantConfiguration(selected, enabled: true)
        savedConfiguration = selected
        configuration = selected
        isEnabled = true
        installedOllamaModelIDs.insert(model.id)
        refreshSavedConfigurations()
        setSuccess(String(localized: "\(model.name) is ready and selected globally."))
    }

    private func refreshSavedConfigurations() {
        savedConfigurations = manager.settings.assistantProviderConfigurations
    }

    private func startConnectionAction(
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
                try self.persistDraft()
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
