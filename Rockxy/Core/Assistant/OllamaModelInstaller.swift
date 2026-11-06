import Foundation

// MARK: - AssistantLocalModelRole

/// Curated intent for a starter model. Roles describe what Rockxy recommends a model
/// for; they are not runtime-reported capabilities.
enum AssistantLocalModelRole: String, CaseIterable, Equatable, Sendable {
    case balanced
    case coding
    case reasoning
    case lowMemory
}

// MARK: - AssistantLocalModelHardwareFit

/// How a curated model's recommended unified memory compares with this Mac.
enum AssistantLocalModelHardwareFit: Equatable, Sendable {
    /// Physical memory meets or exceeds the recommendation.
    case recommended
    /// Physical memory is below the recommendation but within the tight-fit tolerance.
    case tight
    /// Physical memory is well below the recommendation.
    case exceedsMemory
    /// The model has no memory recommendation.
    case unknown
}

// MARK: - AssistantDownloadableModel

struct AssistantDownloadableModel: Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    init(
        id: String,
        name: String,
        family: String = "Custom",
        approximateDownloadBytes: Int64? = nil,
        recommendedUnifiedMemoryBytes: Int64? = nil,
        roles: Set<AssistantLocalModelRole> = [],
        detail: String
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.approximateDownloadBytes = approximateDownloadBytes
        self.recommendedUnifiedMemoryBytes = recommendedUnifiedMemoryBytes
        self.roles = roles
        self.detail = detail
    }

    // MARK: Internal

    /// Fraction of the recommended memory below which a model no longer fits at all.
    static let tightFitTolerance = 0.75

    /// Small starter catalog of Ollama library tags suited to traffic debugging.
    /// Recomputed on access so runtime language changes refresh the localized details.
    static var recommended: [AssistantDownloadableModel] {
        [
            AssistantDownloadableModel(
                id: "qwen3.5:4b",
                name: "Qwen 3.5 4B",
                family: "Qwen",
                approximateDownloadBytes: 3_400_000_000,
                recommendedUnifiedMemoryBytes: 8 * gibibyte,
                roles: [.balanced],
                detail: String(
                    localized: "Balanced starter model for explaining requests, responses, and failures",
                    bundle: RockxyLocalization.bundle
                )
            ),
            AssistantDownloadableModel(
                id: "gemma3:4b",
                name: "Gemma 3 4B",
                family: "Gemma",
                approximateDownloadBytes: 3_300_000_000,
                recommendedUnifiedMemoryBytes: 8 * gibibyte,
                roles: [.balanced],
                detail: String(
                    localized: "Small multilingual model with a strong quality-to-size balance",
                    bundle: RockxyLocalization.bundle
                )
            ),
            AssistantDownloadableModel(
                id: "qwen2.5-coder:7b",
                name: "Qwen 2.5 Coder 7B",
                family: "Qwen",
                approximateDownloadBytes: 4_700_000_000,
                recommendedUnifiedMemoryBytes: 16 * gibibyte,
                roles: [.coding],
                detail: String(
                    localized: "Code-focused model for reading payloads, headers, and client code paths",
                    bundle: RockxyLocalization.bundle
                )
            ),
            AssistantDownloadableModel(
                id: "deepseek-r1:8b",
                name: "DeepSeek R1 8B",
                family: "DeepSeek",
                approximateDownloadBytes: 5_200_000_000,
                recommendedUnifiedMemoryBytes: 16 * gibibyte,
                roles: [.reasoning],
                detail: String(
                    localized: "Step-by-step reasoning model for tracing multi-request failures",
                    bundle: RockxyLocalization.bundle
                )
            ),
            AssistantDownloadableModel(
                id: "llama3.2:3b",
                name: "Llama 3.2 3B",
                family: "Llama",
                approximateDownloadBytes: 2_000_000_000,
                recommendedUnifiedMemoryBytes: 8 * gibibyte,
                roles: [.lowMemory, .balanced],
                detail: String(
                    localized: "Compact general-purpose model for Apple silicon Macs",
                    bundle: RockxyLocalization.bundle
                )
            ),
            AssistantDownloadableModel(
                id: "gemma3:1b",
                name: "Gemma 3 1B",
                family: "Gemma",
                approximateDownloadBytes: 815_000_000,
                recommendedUnifiedMemoryBytes: 8 * gibibyte,
                roles: [.lowMemory],
                detail: String(
                    localized: "Smallest starter model for lower-memory Macs and quick summaries",
                    bundle: RockxyLocalization.bundle
                )
            ),
            AssistantDownloadableModel(
                id: "qwen3-coder:30b",
                name: "Qwen 3 Coder 30B",
                family: "Qwen",
                approximateDownloadBytes: 19_000_000_000,
                recommendedUnifiedMemoryBytes: 32 * gibibyte,
                roles: [.coding],
                detail: String(
                    localized: "Large coding model for Macs with 32 GB or more unified memory",
                    bundle: RockxyLocalization.bundle
                )
            ),
        ]
    }

    let id: String
    let name: String
    let family: String
    let approximateDownloadBytes: Int64?
    /// Minimum unified memory Rockxy recommends for comfortable local use of this model.
    let recommendedUnifiedMemoryBytes: Int64?
    let roles: Set<AssistantLocalModelRole>
    let detail: String

    var catalogDetail: String {
        guard let approximateDownloadBytes else {
            return family
        }
        return "\(family) · ~\(ByteCountFormatter.string(fromByteCount: approximateDownloadBytes, countStyle: .file))"
    }

    /// Models recommended for a role, preserving catalog order.
    static func models(
        _ models: [AssistantDownloadableModel],
        withRole role: AssistantLocalModelRole
    )
        -> [AssistantDownloadableModel]
    {
        models.filter { $0.roles.contains(role) }
    }

    /// Classifies a memory recommendation against the physical memory of this Mac
    /// (typically `ProcessInfo.processInfo.physicalMemory`).
    static func hardwareFit(
        recommendedUnifiedMemoryBytes: Int64?,
        physicalMemoryBytes: UInt64
    )
        -> AssistantLocalModelHardwareFit
    {
        guard let recommendedUnifiedMemoryBytes, recommendedUnifiedMemoryBytes > 0 else {
            return .unknown
        }
        let physical = Double(physicalMemoryBytes)
        let recommended = Double(recommendedUnifiedMemoryBytes)
        if physical >= recommended {
            return .recommended
        }
        if physical >= recommended * tightFitTolerance {
            return .tight
        }
        return .exceedsMemory
    }

    func hardwareFit(physicalMemoryBytes: UInt64) -> AssistantLocalModelHardwareFit {
        Self.hardwareFit(
            recommendedUnifiedMemoryBytes: recommendedUnifiedMemoryBytes,
            physicalMemoryBytes: physicalMemoryBytes
        )
    }

    // MARK: Private

    private static let gibibyte: Int64 = 1_024 * 1_024 * 1_024
}

// MARK: - AssistantModelInstallEvent

enum AssistantModelInstallEvent: Equatable, Sendable {
    case status(String)
    case progress(completed: Int64, total: Int64?)
    case completed
}

// MARK: - AssistantModelInstallerProtocol

protocol AssistantModelInstallerProtocol: Sendable {
    func install(
        modelID: String,
        baseURL: URL
    )
        -> AsyncThrowingStream<AssistantModelInstallEvent, Error>

    func remove(modelID: String, baseURL: URL) async throws
}

// MARK: - OllamaModelInstaller

struct OllamaModelInstaller: AssistantModelInstallerProtocol {
    // MARK: Lifecycle

    init(transport: any AssistantHTTPTransport) {
        self.transport = transport
    }

    // MARK: Internal

    static let shared = OllamaModelInstaller(
        transport: URLSessionAssistantHTTPTransport()
    )

    func install(
        modelID: String,
        baseURL: URL
    )
        -> AsyncThrowingStream<AssistantModelInstallEvent, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let modelID = try validatedModelID(modelID)
                    var request = URLRequest(url: endpoint("api/pull", baseURL: baseURL))
                    request.httpMethod = "POST"
                    request.timeoutInterval = Self.downloadTimeout
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(
                        withJSONObject: ["model": modelID, "stream": true],
                        options: [.sortedKeys]
                    )
                    let stream = try await transport.lines(for: request)
                    guard (200 ... 299).contains(stream.response.statusCode) else {
                        let body = await AssistantHTTPErrorMapper.boundedBody(from: stream.lines)
                        throw AssistantHTTPErrorMapper.error(
                            response: stream.response,
                            body: body,
                            model: modelID
                        )
                    }

                    var didComplete = false
                    for try await line in stream.lines where !line.isEmpty {
                        try Task.checkCancellation()
                        let event = try decode(line: line)
                        if case .completed = event {
                            didComplete = true
                        }
                        continuation.yield(event)
                    }
                    guard didComplete else {
                        throw AssistantProviderError.malformedResponse(
                            "The Ollama model download ended before status=success"
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AssistantHTTPErrorMapper.translated(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func remove(modelID: String, baseURL: URL) async throws {
        do {
            let modelID = try validatedModelID(modelID)
            var request = URLRequest(url: endpoint("api/delete", baseURL: baseURL))
            request.httpMethod = "DELETE"
            request.timeoutInterval = Self.connectionTimeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["model": modelID],
                options: [.sortedKeys]
            )
            let (data, response) = try await transport.data(for: request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw AssistantHTTPErrorMapper.error(response: response, body: data, model: modelID)
            }
        } catch {
            throw AssistantHTTPErrorMapper.translated(error)
        }
    }

    // MARK: Private

    private static let downloadTimeout: TimeInterval = 60 * 60
    private static let connectionTimeout: TimeInterval = 30
    private static let maxModelIDLength = 256
    private static let allowedModelIDCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/-"
    )

    private let transport: any AssistantHTTPTransport

    private func endpoint(_ path: String, baseURL: URL) -> URL {
        var normalized = baseURL
        if normalized.path.hasSuffix("/v1") {
            normalized.deleteLastPathComponent()
        }
        return normalized.appendingPathComponent(path)
    }

    private func validatedModelID(_ value: String) throws -> String {
        let modelID = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty,
              modelID.count <= Self.maxModelIDLength,
              modelID.unicodeScalars.allSatisfy(Self.allowedModelIDCharacters.contains),
              !modelID.contains("..") else
        {
            throw AssistantProviderError.validation("The local model ID is invalid")
        }
        return modelID
    }

    private func decode(line: String) throws -> AssistantModelInstallEvent {
        guard line.utf8.count <= AssistantExecutionLimits.maxStreamEventBytes else {
            throw AssistantProviderError.malformedResponse(
                "An Ollama model download event exceeded Rockxy's size limit"
            )
        }
        // A line that is not JSON is a malformed event, not a network failure.
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else
        {
            throw AssistantProviderError.malformedResponse(
                "Ollama returned an invalid model download event"
            )
        }
        if let error = object["error"] as? String {
            throw AssistantProviderError.validation(String(error.prefix(1_024)))
        }
        if object["status"] as? String == "success" {
            return .completed
        }
        if let completed = (object["completed"] as? NSNumber)?.int64Value {
            let total = (object["total"] as? NSNumber)?.int64Value
            return .progress(completed: completed, total: total)
        }
        if let status = object["status"] as? String, !status.isEmpty {
            return .status(status)
        }
        throw AssistantProviderError.malformedResponse(
            "Ollama returned an unrecognized model download event"
        )
    }
}
