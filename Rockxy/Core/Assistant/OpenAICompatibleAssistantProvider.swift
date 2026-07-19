import Foundation

struct OpenAICompatibleAssistantProvider: AssistantModelProvider {
    // MARK: Lifecycle

    init(baseURL: URL, apiKey: String, transport: any AssistantHTTPTransport) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.transport = transport
    }

    // MARK: Internal

    let kind = AssistantProviderKind.openAICompatible
    let capabilities = AssistantProviderCapabilities.compatible

    func discoverModels() async throws -> [AssistantModel] {
        var request = URLRequest(url: endpoint("models"))
        request.httpMethod = "GET"
        authorize(&request)
        request.timeoutInterval = Self.connectionTimeout
        do {
            let (data, response) = try await transport.data(for: request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw AssistantHTTPErrorMapper.error(response: response, body: data, model: "")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = object["data"] as? [[String: Any]] else
            {
                throw AssistantProviderError.malformedResponse("The models response has no data array")
            }
            return values.compactMap { value in
                guard let id = value["id"] as? String, !id.isEmpty else {
                    return nil
                }
                return AssistantModel(id: id, displayName: id)
            }
        } catch {
            throw AssistantHTTPErrorMapper.translated(error)
        }
    }

    func testConnection(model: String) async throws -> Int {
        do {
            let models = try await discoverModels()
            if !models.isEmpty, !models.contains(where: { $0.id == model }) {
                throw AssistantProviderError.modelNotFound(model)
            }
            return models.count
        } catch let error as AssistantProviderError {
            if case .server(statusCode: 404, message: _) = error {
                return try await probe(model: model)
            }
            throw error
        }
    }

    func stream(_ request: AssistantCompletionRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: endpoint("chat/completions"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = Self.requestTimeout
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    authorize(&urlRequest)
                    urlRequest.httpBody = try body(for: request, streaming: true)
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
                    var receivedDone = false
                    for try await line in stream.lines {
                        try Task.checkCancellation()
                        if line.trimmingCharacters(in: .whitespacesAndNewlines) == "data: [DONE]" {
                            receivedDone = true
                            continue
                        }
                        for event in try decode(line: line) {
                            continuation.yield(event)
                        }
                    }
                    guard receivedDone else {
                        throw AssistantProviderError.malformedResponse(
                            "The compatible stream ended before data: [DONE]"
                        )
                    }
                    continuation.yield(.completed(responseID: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AssistantHTTPErrorMapper.translated(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Private

    private static let connectionTimeout: TimeInterval = 15
    private static let requestTimeout: TimeInterval = 90

    private let baseURL: URL
    private let apiKey: String
    private let transport: any AssistantHTTPTransport

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func authorize(_ request: inout URLRequest) {
        guard !apiKey.isEmpty else {
            return
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func body(for request: AssistantCompletionRequest, streaming: Bool) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "model": request.model,
                "messages": [
                    ["role": "system", "content": request.instructions],
                    ["role": "user", "content": request.input],
                ],
                "max_tokens": request.maxOutputTokens,
                "stream": streaming,
            ],
            options: [.sortedKeys]
        )
    }

    private func probe(model: String) async throws -> Int {
        let request = AssistantCompletionRequest(
            instructions: "Return one word.",
            input: "ready",
            model: model,
            maxOutputTokens: 1,
            storeResponse: false
        )
        for try await event in stream(request) {
            if case .textDelta = event {
                return 0
            }
        }
        throw AssistantProviderError.malformedResponse("The endpoint returned no text")
    }

    private func decode(line: String) throws -> [AssistantStreamEvent] {
        guard line.utf8.count <= AssistantExecutionLimits.maxStreamEventBytes else {
            throw AssistantProviderError.malformedResponse("A compatible stream event exceeded Rockxy's size limit")
        }
        guard line.hasPrefix("data:") else {
            return []
        }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else {
            return []
        }
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            throw AssistantProviderError.malformedResponse("A compatible streaming event is invalid")
        }
        var events: [AssistantStreamEvent] = []
        if let usage = object["usage"] as? [String: Any] {
            let details = usage["prompt_tokens_details"] as? [String: Any]
            events.append(.usage(AssistantUsage(
                inputTokens: usage["prompt_tokens"] as? Int ?? 0,
                outputTokens: usage["completion_tokens"] as? Int ?? 0,
                cachedInputTokens: details?["cached_tokens"] as? Int ?? 0
            )))
        }
        if let choices = object["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any],
           let content = delta["content"] as? String,
           !content.isEmpty
        {
            events.append(.textDelta(content))
        }
        return events
    }
}
