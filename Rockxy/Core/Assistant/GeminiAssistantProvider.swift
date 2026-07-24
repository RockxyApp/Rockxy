import Foundation

struct GeminiAssistantProvider: AssistantModelProvider {
    init(baseURL: URL, apiKey: String, transport: any AssistantHTTPTransport) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.transport = transport
    }

    let kind = AssistantProviderKind.gemini
    let capabilities = AssistantProviderCapabilities.gemini

    func discoverModels() async throws -> [AssistantModel] {
        var request = URLRequest(url: endpoint("models"))
        request.httpMethod = "GET"
        request.timeoutInterval = Self.connectionTimeout
        authorize(&request)
        do {
            let (data, response) = try await transport.data(for: request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw AssistantHTTPErrorMapper.error(response: response, body: data, model: "")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = object["models"] as? [[String: Any]] else
            {
                throw AssistantProviderError.malformedResponse("The Gemini models response has no models array")
            }
            return values.compactMap { value in
                let methods = value["supportedGenerationMethods"] as? [String] ?? []
                guard methods.contains("generateContent"),
                      let name = value["name"] as? String else
                {
                    return nil
                }
                let id = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
                guard !id.isEmpty else {
                    return nil
                }
                return AssistantModel(
                    id: id,
                    displayName: value["displayName"] as? String ?? id,
                    inputTokenLimit: value["inputTokenLimit"] as? Int,
                    outputTokenLimit: value["outputTokenLimit"] as? Int
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            throw AssistantHTTPErrorMapper.translated(error)
        }
    }

    func testConnection(model: String) async throws -> Int {
        let models = try await discoverModels()
        let normalized = Self.normalizedModelID(model)
        guard models.contains(where: { $0.id == normalized }) else {
            throw AssistantProviderError.modelNotFound(model)
        }
        return models.count
    }

    func stream(_ request: AssistantCompletionRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let model = Self.normalizedModelID(request.model)
                    guard !model.isEmpty, !model.contains("/") else {
                        throw AssistantProviderError.modelNotFound(request.model)
                    }
                    var urlRequest = URLRequest(url: try streamEndpoint(model: model))
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = Self.requestTimeout
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    authorize(&urlRequest)
                    urlRequest.httpBody = try JSONSerialization.data(
                        withJSONObject: [
                            "systemInstruction": ["parts": [["text": request.instructions]]],
                            "contents": [["role": "user", "parts": [["text": request.input]]]],
                            "generationConfig": ["maxOutputTokens": request.maxOutputTokens],
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
                    var didFinish = false
                    for try await line in stream.lines {
                        try Task.checkCancellation()
                        let decoded = try GeminiStreamDecoder.decode(line: line)
                        didFinish = didFinish || decoded.finished
                        for event in decoded.events {
                            continuation.yield(event)
                        }
                    }
                    guard didFinish else {
                        throw AssistantProviderError.malformedResponse(
                            "The Gemini stream ended without a finish reason"
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

    private static let connectionTimeout: TimeInterval = 15
    private static let requestTimeout: TimeInterval = 90

    private let baseURL: URL
    private let apiKey: String
    private let transport: any AssistantHTTPTransport

    private static func normalizedModelID(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("models/") ? String(trimmed.dropFirst("models/".count)) : trimmed
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func streamEndpoint(model: String) throws -> URL {
        let path = baseURL
            .appendingPathComponent("models")
            .appendingPathComponent("\(model):streamGenerateContent")
        guard var components = URLComponents(url: path, resolvingAgainstBaseURL: false) else {
            throw AssistantProviderError.invalidEndpoint
        }
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        guard let url = components.url else {
            throw AssistantProviderError.invalidEndpoint
        }
        return url
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
    }
}

enum GeminiStreamDecoder {
    struct Result {
        let events: [AssistantStreamEvent]
        let finished: Bool
    }

    static func decode(line: String) throws -> Result {
        guard line.utf8.count <= AssistantExecutionLimits.maxStreamEventBytes else {
            throw AssistantProviderError.malformedResponse("A Gemini streaming event exceeded Rockxy's size limit")
        }
        guard line.hasPrefix("data:") else {
            return Result(events: [], finished: false)
        }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            throw AssistantProviderError.malformedResponse("A Gemini streaming event is invalid")
        }
        if let error = object["error"] as? [String: Any] {
            throw AssistantProviderError.validation(
                String((error["message"] as? String ?? "Gemini stream failed").prefix(1_024))
            )
        }

        var events: [AssistantStreamEvent] = []
        let candidates = object["candidates"] as? [[String: Any]] ?? []
        for candidate in candidates {
            let content = candidate["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]] ?? []
            for part in parts {
                if let text = part["text"] as? String, !text.isEmpty {
                    events.append(.textDelta(text))
                }
            }
        }
        if let usage = object["usageMetadata"] as? [String: Any] {
            events.append(.usage(AssistantUsage(
                inputTokens: usage["promptTokenCount"] as? Int ?? 0,
                outputTokens: usage["candidatesTokenCount"] as? Int ?? 0,
                cachedInputTokens: usage["cachedContentTokenCount"] as? Int ?? 0
            )))
        }
        let finished = candidates.contains { $0["finishReason"] is String }
        return Result(events: events, finished: finished)
    }
}
