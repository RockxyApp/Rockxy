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
        try await provider(for: configuration).discoverModels()
    }

    func testConnection(
        configuration: AssistantProviderConfiguration
    )
        async throws -> AssistantConnectionTestResult
    {
        let provider = try provider(for: configuration)
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
        try provider(for: configuration).stream(request)
    }

    // MARK: Private

    private let transport: any AssistantHTTPTransport
    private let credentialStorage: any AssistantCredentialStorage

    private func provider(
        for configuration: AssistantProviderConfiguration
    )
        throws -> any AssistantModelProvider
    {
        guard configuration.kind.isImplemented else {
            throw AssistantProviderError.capabilityMismatch(
                "\(configuration.kind.title) has a separate provider adapter that is not installed."
            )
        }
        guard configuration.isComplete, let endpoint = configuration.endpointURL else {
            throw AssistantProviderError.notConfigured
        }
        if configuration.kind == .openAI, !isOfficialOpenAIEndpoint(endpoint) {
            throw AssistantProviderError.invalidEndpoint
        }
        let credential = try credentialStorage.load(providerID: configuration.id) ?? ""
        if configuration.kind.requiresCredential, credential.isEmpty {
            throw AssistantProviderError.credentialMissing
        }
        switch configuration.kind {
        case .openAI:
            return OpenAIResponsesProvider(
                baseURL: endpoint,
                apiKey: credential,
                transport: transport
            )
        case .openAICompatible:
            return OpenAICompatibleAssistantProvider(
                baseURL: endpoint,
                apiKey: credential,
                transport: transport
            )
        case .ollama:
            return OllamaAssistantProvider(baseURL: endpoint, transport: transport)
        default:
            throw AssistantProviderError.capabilityMismatch(
                "\(configuration.kind.title) requires its native provider adapter."
            )
        }
    }

    private func isOfficialOpenAIEndpoint(_ url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "api.openai.com"
            && url.port == nil
            && path == "v1"
    }
}
