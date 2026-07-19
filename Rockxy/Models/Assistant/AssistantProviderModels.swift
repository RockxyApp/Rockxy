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

// MARK: - AssistantProviderKind

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
        switch self {
        case .openAI,
             .anthropic,
             .gemini: .global
        case .deepSeek,
             .qwen,
             .kimi,
             .doubao,
             .glm: .china
        case .openAICompatible,
             .ollama: .customAndLocal
        }
    }

    var isImplemented: Bool {
        switch self {
        case .openAI,
             .openAICompatible,
             .ollama: true
        default: false
        }
    }

    var requiresCredential: Bool {
        switch self {
        case .openAI: true
        default: false
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .openAICompatible: "http://127.0.0.1:1234/v1"
        case .ollama: "http://127.0.0.1:11434"
        default: ""
        }
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
        switch self {
        case .openAI: "Responses API"
        case .openAICompatible: "Chat Completions compatible API"
        case .ollama: "Ollama native chat API"
        default: String(localized: "Separate adapter required")
        }
    }

    var capabilities: AssistantProviderCapabilities? {
        switch self {
        case .openAI: .openAI
        case .openAICompatible: .compatible
        case .ollama: .ollama
        default: nil
        }
    }

    var documentationURL: URL? {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/docs/api-reference/responses")
        case .ollama: URL(string: "https://docs.ollama.com/api/chat")
        default: nil
        }
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
        storeResponses: Bool = false,
        redactSensitiveData: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.model = model ?? kind.defaultModel
        self.region = region
        self.storeResponses = storeResponses
        self.redactSensitiveData = redactSensitiveData
    }

    // MARK: Internal

    var id: UUID
    var kind: AssistantProviderKind
    var baseURL: String
    var model: String
    var region: String?
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

    var isComplete: Bool {
        kind.isImplemented
            && endpointURL?.host != nil
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - AssistantProviderCapabilities

struct AssistantProviderCapabilities: Equatable {
    static let openAI = AssistantProviderCapabilities(
        streaming: true,
        modelDiscovery: true,
        toolCalling: true,
        usageReporting: true,
        responseStorageControl: true
    )

    static let compatible = AssistantProviderCapabilities(
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

struct AssistantModel: Identifiable, Equatable {
    let id: String
    let displayName: String
}

// MARK: - AssistantCompletionRequest

struct AssistantCompletionRequest: Equatable {
    let instructions: String
    let input: String
    let model: String
    let maxOutputTokens: Int
    let storeResponse: Bool
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
    let toolCalls: [AssistantToolCall]
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
