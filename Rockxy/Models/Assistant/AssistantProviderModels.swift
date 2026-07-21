import Foundation

// MARK: - AssistantProviderGroup

enum AssistantProviderGroup: String, CaseIterable {
    case global
    case china
    case customAndLocal

    // MARK: Internal

    var title: String {
        switch self {
        case .global: String(localized: "Global Models")
        case .china: String(localized: "China Models")
        case .customAndLocal: String(localized: "Custom & Local")
        }
    }
}

// MARK: - Assistant Provider Architecture

/// Where inference executes. This is deliberately independent from the model family:
/// Qwen, DeepSeek, Llama, and other weights can run locally or behind a cloud API.
enum AssistantExecutionLocation: String, Equatable, Sendable {
    case onDevice
    case localServer
    case remoteServer
    case cloudService

    var isLocal: Bool {
        self == .onDevice || self == .localServer
    }
}

enum AssistantExecutionLocationPolicy: Equatable, Sendable {
    case fixed(AssistantExecutionLocation)
    case endpointDerived

    func resolve(endpointSecurity: AssistantEndpointSecurity) -> AssistantExecutionLocation {
        switch self {
        case let .fixed(location):
            location
        case .endpointDerived:
            endpointSecurity == .localLoopback ? .localServer : .remoteServer
        }
    }
}

/// The wire protocol used by an inference endpoint. Multiple vendors can share one dialect.
enum AssistantAPIDialect: String, Equatable, Sendable {
    case openAIResponses
    case openAIChatCompletions
    case anthropicMessages
    case geminiGenerateContent
    case ollamaNative
    case appleFoundationModels
}

enum AssistantCredentialMode: Equatable, Sendable {
    case none
    case bearerToken
    case header(name: String)
    case queryItem(name: String)

    var isRequired: Bool {
        self != .none
    }
}

enum AssistantEndpointPolicy: Equatable, Sendable {
    case fixedHTTPS(host: String, path: String)
    case trustedHTTPS(hosts: [String], hostSuffixes: [String])
    case secureRemote
    case localOrSecureRemote

    func permits(_ url: URL, security: AssistantEndpointSecurity) -> Bool {
        switch self {
        case let .fixedHTTPS(host, path):
            let normalizedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return url.scheme?.lowercased() == "https"
                && url.host?.lowercased() == host.lowercased()
                && url.port == nil
                && normalizedPath == path
        case let .trustedHTTPS(hosts, hostSuffixes):
            guard security == .encrypted,
                  url.port == nil,
                  let candidate = url.host?.lowercased() else
            {
                return false
            }
            return hosts.contains { candidate == $0.lowercased() }
                || hostSuffixes.contains { candidate.hasSuffix(".\($0.lowercased())") }
        case .secureRemote:
            return security == .encrypted
        case .localOrSecureRemote:
            return security.permitsCapturedData
        }
    }
}

enum AssistantModelCatalogStrategy: Equatable, Sendable {
    case remoteDiscovery
    case remoteDiscoveryWithManualFallback
    case manualEntry
}

enum AssistantCostModel: Equatable, Sendable {
    case localCompute
    case providerBilled
    case endpointDefined
}

struct AssistantProviderDescriptor: Equatable, Sendable {
    let group: AssistantProviderGroup
    let executionLocationPolicy: AssistantExecutionLocationPolicy
    let apiDialect: AssistantAPIDialect
    let credentialMode: AssistantCredentialMode
    let endpointPolicy: AssistantEndpointPolicy
    let modelCatalogStrategy: AssistantModelCatalogStrategy
    let costModel: AssistantCostModel
    let defaultBaseURL: String
    let apiSurface: String
    let capabilities: AssistantProviderCapabilities
    let documentationURL: URL?
    let isImplemented: Bool
}

// MARK: - AssistantProviderKind

/// A saved provider preset, not a model family. Model IDs remain runtime data so the same
/// Qwen, DeepSeek, Llama, or other model family can be used through any compatible runtime.
enum AssistantProviderKind: String, CaseIterable, Codable, Identifiable {
    case openAI
    case anthropic
    case gemini
    case deepSeek
    case qwen
    case kimi
    case doubao
    case glm
    case openAICompatible
    case ollama

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic Claude"
        case .gemini: "Google Gemini"
        case .deepSeek: "DeepSeek"
        case .qwen: "Qwen / DashScope"
        case .kimi: "Kimi / Moonshot"
        case .doubao: "Doubao / Volcengine Ark"
        case .glm: "GLM / Zhipu"
        case .openAICompatible: String(localized: "OpenAI-compatible Endpoint")
        case .ollama: "Ollama"
        }
    }

    var group: AssistantProviderGroup {
        descriptor.group
    }

    var isImplemented: Bool {
        descriptor.isImplemented
    }

    var requiresCredential: Bool {
        descriptor.credentialMode.isRequired
    }

    var usesFixedEndpoint: Bool {
        if case .fixedHTTPS = descriptor.endpointPolicy {
            return true
        }
        return false
    }

    var defaultBaseURL: String {
        descriptor.defaultBaseURL
    }

    var defaultModel: String {
        switch self {
        case .openAI,
             .openAICompatible,
             .ollama: ""
        default: ""
        }
    }

    var apiSurface: String {
        descriptor.apiSurface
    }

    var capabilities: AssistantProviderCapabilities? {
        descriptor.isImplemented ? descriptor.capabilities : nil
    }

    var documentationURL: URL? {
        descriptor.documentationURL
    }

    var descriptor: AssistantProviderDescriptor {
        switch self {
        case .openAI:
            AssistantProviderDescriptor(
                group: .global,
                executionLocationPolicy: .fixed(.cloudService),
                apiDialect: .openAIResponses,
                credentialMode: .bearerToken,
                endpointPolicy: .fixedHTTPS(host: "api.openai.com", path: "v1"),
                modelCatalogStrategy: .remoteDiscovery,
                costModel: .providerBilled,
                defaultBaseURL: "https://api.openai.com/v1",
                apiSurface: "Responses API",
                capabilities: .openAI,
                documentationURL: URL(string: "https://developers.openai.com/api/docs/guides/responses-vs-chat-completions"),
                isImplemented: true
            )
        case .anthropic:
            AssistantProviderDescriptor(
                group: .global,
                executionLocationPolicy: .fixed(.cloudService),
                apiDialect: .anthropicMessages,
                credentialMode: .header(name: "x-api-key"),
                endpointPolicy: .fixedHTTPS(host: "api.anthropic.com", path: "v1"),
                modelCatalogStrategy: .remoteDiscovery,
                costModel: .providerBilled,
                defaultBaseURL: "https://api.anthropic.com/v1",
                apiSurface: "Messages API",
                capabilities: .anthropic,
                documentationURL: URL(string: "https://platform.claude.com/docs/en/api/messages"),
                isImplemented: true
            )
        case .gemini:
            AssistantProviderDescriptor(
                group: .global,
                executionLocationPolicy: .fixed(.cloudService),
                apiDialect: .geminiGenerateContent,
                credentialMode: .queryItem(name: "key"),
                endpointPolicy: .fixedHTTPS(host: "generativelanguage.googleapis.com", path: "v1beta"),
                modelCatalogStrategy: .remoteDiscovery,
                costModel: .providerBilled,
                defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta",
                apiSurface: "GenerateContent API",
                capabilities: .gemini,
                documentationURL: URL(string: "https://ai.google.dev/api/generate-content"),
                isImplemented: true
            )
        case .deepSeek:
            compatibleCloudDescriptor(
                defaultBaseURL: "https://api.deepseek.com/v1",
                documentationURL: "https://api-docs.deepseek.com/",
                endpointPolicy: .fixedHTTPS(host: "api.deepseek.com", path: "v1")
            )
        case .qwen:
            compatibleCloudDescriptor(
                defaultBaseURL: "",
                documentationURL: "https://help.aliyun.com/en/model-studio/qwen-api-via-dashscope",
                catalogStrategy: .manualEntry,
                endpointPolicy: .trustedHTTPS(hosts: [], hostSuffixes: ["aliyuncs.com"])
            )
        case .kimi:
            compatibleCloudDescriptor(
                defaultBaseURL: "https://api.moonshot.ai/v1",
                documentationURL: "https://platform.kimi.ai/docs/api/overview",
                endpointPolicy: .trustedHTTPS(
                    hosts: ["api.moonshot.ai", "api.moonshot.cn"],
                    hostSuffixes: []
                )
            )
        case .doubao:
            compatibleCloudDescriptor(
                defaultBaseURL: "https://ark.cn-beijing.volces.com/api/v3",
                documentationURL: "https://www.volcengine.com/docs/82379/1298454",
                catalogStrategy: .manualEntry,
                endpointPolicy: .trustedHTTPS(hosts: [], hostSuffixes: ["volces.com"])
            )
        case .glm:
            compatibleCloudDescriptor(
                defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4",
                documentationURL: "https://docs.bigmodel.cn/api-reference/%E6%A8%A1%E5%9E%8B-api/%E5%AF%B9%E8%AF%9D%E8%A1%A5%E5%85%A8",
                catalogStrategy: .manualEntry,
                endpointPolicy: .fixedHTTPS(host: "open.bigmodel.cn", path: "api/paas/v4")
            )
        case .openAICompatible:
            AssistantProviderDescriptor(
                group: .customAndLocal,
                executionLocationPolicy: .endpointDerived,
                apiDialect: .openAIChatCompletions,
                credentialMode: .none,
                endpointPolicy: .localOrSecureRemote,
                modelCatalogStrategy: .remoteDiscoveryWithManualFallback,
                costModel: .endpointDefined,
                defaultBaseURL: "http://127.0.0.1:1234/v1",
                apiSurface: "Chat Completions compatible API",
                capabilities: .compatible,
                documentationURL: nil,
                isImplemented: true
            )
        case .ollama:
            AssistantProviderDescriptor(
                group: .customAndLocal,
                executionLocationPolicy: .endpointDerived,
                apiDialect: .ollamaNative,
                credentialMode: .none,
                endpointPolicy: .localOrSecureRemote,
                modelCatalogStrategy: .remoteDiscovery,
                costModel: .endpointDefined,
                defaultBaseURL: "http://127.0.0.1:11434",
                apiSurface: "Ollama native chat API",
                capabilities: .ollama,
                documentationURL: URL(string: "https://docs.ollama.com/api/chat"),
                isImplemented: true
            )
        }
    }

    private func compatibleCloudDescriptor(
        defaultBaseURL: String,
        documentationURL: String,
        catalogStrategy: AssistantModelCatalogStrategy = .remoteDiscoveryWithManualFallback,
        endpointPolicy: AssistantEndpointPolicy
    ) -> AssistantProviderDescriptor {
        let capabilities = catalogStrategy == .manualEntry
            ? AssistantProviderCapabilities.compatibleManualCatalog
            : .compatible
        return AssistantProviderDescriptor(
            group: .china,
            executionLocationPolicy: .fixed(.cloudService),
            apiDialect: .openAIChatCompletions,
            credentialMode: .bearerToken,
            endpointPolicy: endpointPolicy,
            modelCatalogStrategy: catalogStrategy,
            costModel: .providerBilled,
            defaultBaseURL: defaultBaseURL,
            apiSurface: "Chat Completions compatible API",
            capabilities: capabilities,
            documentationURL: URL(string: documentationURL),
            isImplemented: true
        )
    }
}

// MARK: - AssistantProviderConfiguration

struct AssistantProviderConfiguration: Codable, Equatable, Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        kind: AssistantProviderKind,
        baseURL: String? = nil,
        model: String? = nil,
        region: String? = nil,
        contextWindowTokens: Int? = nil,
        maxOutputTokens: Int = Self.defaultMaxOutputTokens,
        storeResponses: Bool = false,
        redactSensitiveData: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.model = model ?? kind.defaultModel
        self.region = region
        self.contextWindowTokens = Self.validContextWindowTokens(contextWindowTokens)
        self.maxOutputTokens = Self.validMaxOutputTokens(maxOutputTokens)
        self.storeResponses = storeResponses
        self.redactSensitiveData = redactSensitiveData
    }

    // MARK: Internal

    var id: UUID
    var kind: AssistantProviderKind
    var baseURL: String
    var model: String
    var region: String?
    var contextWindowTokens: Int?
    var maxOutputTokens: Int
    var storeResponses: Bool
    var redactSensitiveData: Bool

    var endpointURL: URL? {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else
        {
            return nil
        }
        return url
    }

    var endpointHost: String {
        endpointURL?.host ?? String(localized: "Invalid endpoint")
    }

    var endpointSecurity: AssistantEndpointSecurity {
        guard let endpointURL, let scheme = endpointURL.scheme?.lowercased() else {
            return .invalid
        }
        if scheme == "https" {
            return .encrypted
        }
        if scheme == "http", Self.isLoopbackHost(endpointURL.host) {
            return .localLoopback
        }
        return .insecureRemote
    }

    var executionLocation: AssistantExecutionLocation {
        kind.descriptor.executionLocationPolicy.resolve(endpointSecurity: endpointSecurity)
    }

    var isComplete: Bool {
        kind.isImplemented
            && endpointURL?.host != nil
            && endpointSecurity.permitsCapturedData
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let defaultMaxOutputTokens = 2_048
    static let maxAllowedOutputTokens = 32_768
    static let defaultLocalContextWindowTokens = 8_192
    static let minContextWindowTokens = 1_024
    static let maxContextWindowTokens = 1_048_576

    var effectiveContextWindowTokens: Int? {
        if let contextWindowTokens {
            return contextWindowTokens
        }
        return kind == .ollama ? Self.defaultLocalContextWindowTokens : nil
    }

    static func validMaxOutputTokens(_ value: Int) -> Int {
        min(max(value, 1), maxAllowedOutputTokens)
    }

    static func validContextWindowTokens(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }
        return min(max(value, minContextWindowTokens), maxContextWindowTokens)
    }

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(AssistantProviderKind.self, forKey: .kind)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? kind.defaultBaseURL
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? kind.defaultModel
        region = try container.decodeIfPresent(String.self, forKey: .region)
        contextWindowTokens = Self.validContextWindowTokens(
            try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens)
        )
        maxOutputTokens = Self.validMaxOutputTokens(
            try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? Self.defaultMaxOutputTokens
        )
        storeResponses = try container.decodeIfPresent(Bool.self, forKey: .storeResponses) ?? false
        redactSensitiveData = try container.decodeIfPresent(Bool.self, forKey: .redactSensitiveData) ?? true
    }

    private static func isLoopbackHost(_ host: String?) -> Bool {
        guard var host = host?.lowercased() else {
            return false
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host == "::1" {
            return true
        }
        let octets = host.split(separator: ".")
        return octets.count == 4 && octets.first == "127" && octets.allSatisfy { UInt8($0) != nil }
    }
}

// MARK: - AssistantEndpointSecurity

enum AssistantEndpointSecurity: Equatable {
    case encrypted
    case localLoopback
    case insecureRemote
    case invalid

    var permitsCapturedData: Bool {
        self == .encrypted || self == .localLoopback
    }
}

// MARK: - AssistantProviderCapabilities

struct AssistantProviderCapabilities: Equatable {
    static let openAI = AssistantProviderCapabilities(
        streaming: true,
        modelDiscovery: true,
        toolCalling: false,
        usageReporting: true,
        responseStorageControl: true
    )

    static let compatible = AssistantProviderCapabilities(
        streaming: true,
        modelDiscovery: true,
        toolCalling: false,
        usageReporting: false,
        responseStorageControl: false
    )

    static let compatibleManualCatalog = AssistantProviderCapabilities(
        streaming: true,
        modelDiscovery: false,
        toolCalling: false,
        usageReporting: false,
        responseStorageControl: false
    )

    static let anthropic = AssistantProviderCapabilities(
        streaming: true,
        modelDiscovery: true,
        toolCalling: false,
        usageReporting: true,
        responseStorageControl: false
    )

    static let gemini = AssistantProviderCapabilities(
        streaming: true,
        modelDiscovery: true,
        toolCalling: false,
        usageReporting: true,
        responseStorageControl: false
    )

    static let ollama = AssistantProviderCapabilities(
        streaming: true,
        modelDiscovery: true,
        toolCalling: false,
        usageReporting: true,
        responseStorageControl: false
    )

    let streaming: Bool
    let modelDiscovery: Bool
    let toolCalling: Bool
    let usageReporting: Bool
    let responseStorageControl: Bool
}

// MARK: - AssistantModel

enum AssistantModelCapability: String, Hashable, Sendable {
    case completion
    case embedding
    case thinking
    case tools
    case vision
}

struct AssistantModel: Identifiable, Equatable, Sendable {
    init(
        id: String,
        displayName: String,
        inputTokenLimit: Int? = nil,
        outputTokenLimit: Int? = nil,
        sizeBytes: Int64? = nil,
        digest: String? = nil,
        parameterSize: String? = nil,
        quantizationLevel: String? = nil,
        capabilities: Set<AssistantModelCapability> = []
    ) {
        self.id = id
        self.displayName = displayName
        self.inputTokenLimit = inputTokenLimit
        self.outputTokenLimit = outputTokenLimit
        self.sizeBytes = sizeBytes
        self.digest = digest
        self.parameterSize = parameterSize
        self.quantizationLevel = quantizationLevel
        self.capabilities = capabilities
    }

    let id: String
    let displayName: String
    let inputTokenLimit: Int?
    let outputTokenLimit: Int?
    let sizeBytes: Int64?
    let digest: String?
    let parameterSize: String?
    let quantizationLevel: String?
    let capabilities: Set<AssistantModelCapability>
}

// MARK: - AssistantCompletionRequest

struct AssistantCompletionRequest: Equatable {
    init(
        instructions: String,
        input: String,
        model: String,
        maxOutputTokens: Int,
        storeResponse: Bool,
        contextWindowTokens: Int? = nil
    ) {
        self.instructions = instructions
        self.input = input
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.storeResponse = storeResponse
        self.contextWindowTokens = contextWindowTokens
    }

    let instructions: String
    let input: String
    let model: String
    let maxOutputTokens: Int
    let storeResponse: Bool
    let contextWindowTokens: Int?
}

// MARK: - AssistantUsage

struct AssistantUsage: Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
}

// MARK: - AssistantToolCall

struct AssistantToolCall: Equatable {
    let id: String
    let name: String
    let arguments: String
}

// MARK: - AssistantStreamEvent

enum AssistantStreamEvent: Equatable {
    case started(responseID: String?)
    case textDelta(String)
    case toolCallDelta(id: String, name: String?, argumentsDelta: String)
    case toolCallCompleted(AssistantToolCall)
    case usage(AssistantUsage)
    case completed(responseID: String?)
    case unknown(type: String)
}

// MARK: - AssistantConnectionTestResult

struct AssistantConnectionTestResult: Equatable {
    let provider: String
    let endpointHost: String
    let model: String
    let discoveredModelCount: Int
}

// MARK: - ModelInvestigationResult

struct ModelInvestigationResult: Equatable {
    let provider: AssistantProviderKind
    let model: String
    let endpointHost: String
    let text: String
    let usage: AssistantUsage?
    /// Number of model-requested actions discarded at the read-only trust boundary.
    /// Arguments are deliberately not retained after stream validation.
    let blockedToolCallCount: Int
}

// MARK: - ModelInvestigationState

enum ModelInvestigationState: Equatable {
    case idle
    case streaming(
        runID: UUID,
        provider: AssistantProviderKind,
        model: String,
        endpointHost: String,
        text: String
    )
    case completed(ModelInvestigationResult)
    case failed(message: String)
}

// MARK: - AssistantExecutionLimits

enum AssistantExecutionLimits {
    static let maxOutputBytes = 256 * 1_024
    static let maxStreamEventBytes = 256 * 1_024
    static let maxToolArgumentBytes = 64 * 1_024
    static let maxToolCalls = 16
}
