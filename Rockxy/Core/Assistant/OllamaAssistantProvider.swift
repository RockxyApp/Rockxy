import Foundation

struct OllamaAssistantProvider: AssistantModelProvider {
    // MARK: Lifecycle

    init(baseURL: URL, transport: any AssistantHTTPTransport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    // MARK: Internal

    let kind = AssistantProviderKind.ollama
    let capabilities = AssistantProviderCapabilities.ollama

    func discoverModels() async throws -> [AssistantModel] {
        var request = URLRequest(url: endpoint("api/tags"))
        request.timeoutInterval = Self.connectionTimeout
        do {
            let (data, response) = try await transport.data(for: request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw AssistantHTTPErrorMapper.error(response: response, body: data, model: "")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = object["models"] as? [[String: Any]] else
            {
                throw AssistantProviderError.malformedResponse("Ollama returned no models array")
            }
            return values.compactMap { value in
                guard let id = value["name"] as? String, !id.isEmpty else {
                    return nil
                }
                let details = value["details"] as? [String: Any]
                return AssistantModel(
                    id: id,
                    displayName: id,
                    sizeBytes: (value["size"] as? NSNumber)?.int64Value,
                    digest: value["digest"] as? String,
                    parameterSize: details?["parameter_size"] as? String,
                    quantizationLevel: details?["quantization_level"] as? String
                )
            }
        } catch {
            throw AssistantHTTPErrorMapper.translated(error)
        }
    }

    func testConnection(model: String) async throws -> Int {
        let models = try await discoverModels()
        guard models.contains(where: { $0.id == model }) else {
            throw AssistantProviderError.modelNotFound(model)
        }
        return models.count
    }

    func stream(_ request: AssistantCompletionRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: endpoint("api/chat"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = Self.requestTimeout
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try JSONSerialization.data(
                        withJSONObject: [
                            "model": request.model,
                            "messages": [
                                ["role": "system", "content": request.instructions],
                                ["role": "user", "content": request.input],
                            ],
                            "options": ["num_predict": request.maxOutputTokens],
                            "stream": true,
                        ],
                        options: [.sortedKeys]
                    )
                    let stream = try await transport.lines(for: urlRequest)
                    guard (200 ... 299).contains(stream.response.statusCode) else {
                        let body = await AssistantHTTPErrorMapper.boundedBody(from: stream.lines)
                        throw AssistantHTTPErrorMapper.error(
                            response: stream.response,
                            body: body,
                            model: request.model
                        )
                    }
                    continuation.yield(.started(responseID: nil))
                    var receivedTerminalEvent = false
                    for try await line in stream.lines {
                        try Task.checkCancellation()
                        for event in try decode(line: line) {
                            if case .completed = event {
                                receivedTerminalEvent = true
                            }
                            continuation.yield(event)
                        }
                    }
                    guard receivedTerminalEvent else {
                        throw AssistantProviderError.malformedResponse(
                            "The Ollama stream ended before done=true"
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

    // MARK: Private

    private static let connectionTimeout: TimeInterval = 5
    private static let requestTimeout: TimeInterval = 90

    private let baseURL: URL
    private let transport: any AssistantHTTPTransport

    private func endpoint(_ path: String) -> URL {
        var normalized = baseURL
        if normalized.path.hasSuffix("/v1") {
            normalized.deleteLastPathComponent()
        }
        return normalized.appendingPathComponent(path)
    }

    private func decode(line: String) throws -> [AssistantStreamEvent] {
        guard line.utf8.count <= AssistantExecutionLimits.maxStreamEventBytes else {
            throw AssistantProviderError.malformedResponse("An Ollama stream event exceeded Rockxy's size limit")
        }
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            throw AssistantProviderError.malformedResponse("Ollama returned an invalid stream line")
        }
        if let error = object["error"] as? String {
            throw AssistantProviderError.validation(String(error.prefix(1_024)))
        }
        var events: [AssistantStreamEvent] = []
        if let message = object["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.isEmpty
        {
            events.append(.textDelta(content))
        }
        if object["done"] as? Bool == true {
            events.append(.usage(AssistantUsage(
                inputTokens: object["prompt_eval_count"] as? Int ?? 0,
                outputTokens: object["eval_count"] as? Int ?? 0,
                cachedInputTokens: 0
            )))
            events.append(.completed(responseID: nil))
        }
        return events
    }
}
