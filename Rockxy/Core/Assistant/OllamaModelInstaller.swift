import Foundation

// MARK: - AssistantDownloadableModel

struct AssistantDownloadableModel: Identifiable, Equatable, Sendable {
    static let recommended = [
        AssistantDownloadableModel(
            id: "qwen3:4b",
            name: "Qwen 3 4B",
            detail: String(localized: "Balanced local model for debugging and tool-oriented prompts")
        ),
        AssistantDownloadableModel(
            id: "llama3.2:3b",
            name: "Llama 3.2 3B",
            detail: String(localized: "Compact general-purpose model for Apple silicon Macs")
        ),
        AssistantDownloadableModel(
            id: "gemma3:4b",
            name: "Gemma 3 4B",
            detail: String(localized: "Small multilingual model with a strong quality-to-size balance")
        ),
    ]

    let id: String
    let name: String
    let detail: String
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
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else
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
