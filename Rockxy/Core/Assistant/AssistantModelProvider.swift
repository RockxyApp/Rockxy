import Foundation

// MARK: - AssistantModelProvider

protocol AssistantModelProvider: Sendable {
    var kind: AssistantProviderKind { get }
    var capabilities: AssistantProviderCapabilities { get }

    func discoverModels() async throws -> [AssistantModel]
    func testConnection(model: String) async throws -> Int
    func stream(_ request: AssistantCompletionRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error>
}

// MARK: - AssistantProviderRuntimeProtocol

protocol AssistantProviderRuntimeProtocol: Sendable {
    func discoverModels(configuration: AssistantProviderConfiguration) async throws -> [AssistantModel]
    func testConnection(configuration: AssistantProviderConfiguration) async throws -> AssistantConnectionTestResult
    func stream(
        request: AssistantCompletionRequest,
        configuration: AssistantProviderConfiguration
    )
        async throws -> AsyncThrowingStream<AssistantStreamEvent, Error>
}

// MARK: - AssistantProviderRuntime

actor AssistantProviderRuntime: AssistantProviderRuntimeProtocol {
    // MARK: Lifecycle

    init(
        transport: any AssistantHTTPTransport = URLSessionAssistantHTTPTransport(),
        credentialStorage: any AssistantCredentialStorage = KeychainAssistantCredentialStorage()
    ) {
        self.transport = transport
        self.credentialStorage = credentialStorage
    }

    // MARK: Internal

    static let shared = AssistantProviderRuntime()

    func discoverModels(configuration: AssistantProviderConfiguration) async throws -> [AssistantModel] {
        try await provider(for: configuration, requiresModel: false).discoverModels()
    }

    func testConnection(
        configuration: AssistantProviderConfiguration
    )
        async throws -> AssistantConnectionTestResult
    {
        let provider = try provider(for: configuration, requiresModel: true)
        let count = try await provider.testConnection(model: configuration.model)
        return AssistantConnectionTestResult(
            provider: configuration.kind.title,
            endpointHost: configuration.endpointHost,
            model: configuration.model,
            discoveredModelCount: count
        )
    }

    func stream(
        request: AssistantCompletionRequest,
        configuration: AssistantProviderConfiguration
    )
        async throws -> AsyncThrowingStream<AssistantStreamEvent, Error>
    {
        let provider = try provider(for: configuration, requiresModel: true)
        if configuration.kind == .ollama {
            _ = try await provider.testConnection(model: configuration.model)
        }
        return provider.stream(request)
    }

    // MARK: Private

    private let transport: any AssistantHTTPTransport
    private let credentialStorage: any AssistantCredentialStorage

    private func provider(
        for configuration: AssistantProviderConfiguration,
        requiresModel: Bool
    )
        throws -> any AssistantModelProvider
    {
        guard configuration.kind.isImplemented else {
            throw AssistantProviderError.capabilityMismatch(
                "\(configuration.kind.title) has a separate provider adapter that is not installed."
            )
        }
        guard let endpoint = configuration.endpointURL else {
            throw AssistantProviderError.notConfigured
        }
        if requiresModel, configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AssistantProviderError.notConfigured
        }
        guard configuration.endpointSecurity.permitsCapturedData else {
            throw AssistantProviderError.insecureEndpoint
        }
        let descriptor = configuration.kind.descriptor
        if !descriptor.endpointPolicy.permits(endpoint, security: configuration.endpointSecurity) {
            throw AssistantProviderError.invalidEndpoint
        }
        let credential = try credentialStorage.load(providerID: configuration.id) ?? ""
        if configuration.kind.requiresCredential, credential.isEmpty {
            throw AssistantProviderError.credentialMissing
        }
        switch descriptor.apiDialect {
        case .openAIResponses:
            return OpenAIResponsesProvider(
                baseURL: endpoint,
                apiKey: credential,
                transport: transport
            )
        case .anthropicMessages:
            return AnthropicAssistantProvider(
                baseURL: endpoint,
                apiKey: credential,
                transport: transport
            )
        case .geminiGenerateContent:
            return GeminiAssistantProvider(
                baseURL: endpoint,
                apiKey: credential,
                transport: transport
            )
        case .openAIChatCompletions:
            return OpenAICompatibleAssistantProvider(
                kind: configuration.kind,
                capabilities: descriptor.capabilities,
                baseURL: endpoint,
                apiKey: credential,
                transport: transport
            )
        case .ollamaNative:
            return OllamaAssistantProvider(baseURL: endpoint, transport: transport)
        case .appleFoundationModels:
            throw AssistantProviderError.capabilityMismatch(
                "The Apple Foundation Models adapter is unavailable on this macOS version."
            )
        }
    }
}
