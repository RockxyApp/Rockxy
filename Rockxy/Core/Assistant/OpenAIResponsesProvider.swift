import Foundation

// MARK: - OpenAIResponsesProvider

struct OpenAIResponsesProvider: AssistantModelProvider {
    // MARK: Lifecycle

    init(baseURL: URL, apiKey: String, transport: any AssistantHTTPTransport) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.transport = transport
    }

    // MARK: Internal

    let kind = AssistantProviderKind.openAI
    let capabilities = AssistantProviderCapabilities.openAI

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
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
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
                    var urlRequest = URLRequest(url: endpoint("responses"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = Self.requestTimeout
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    authorize(&urlRequest)
                    urlRequest.httpBody = try JSONSerialization.data(
                        withJSONObject: [
                            "model": request.model,
                            "instructions": request.instructions,
                            "input": request.input,
                            "max_output_tokens": request.maxOutputTokens,
                            "store": request.storeResponse,
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

                    var decoder = OpenAIResponsesStreamDecoder()
                    var receivedTerminalEvent = false
                    for try await line in stream.lines {
                        try Task.checkCancellation()
                        for event in try decoder.decode(line: line) {
                            if case .completed = event {
                                receivedTerminalEvent = true
                            }
                            continuation.yield(event)
                        }
                    }
                    guard receivedTerminalEvent else {
                        throw AssistantProviderError.malformedResponse(
                            "The Responses stream ended before response.completed"
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

    private static let connectionTimeout: TimeInterval = 15
    private static let requestTimeout: TimeInterval = 90

    private let baseURL: URL
    private let apiKey: String
    private let transport: any AssistantHTTPTransport

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
}

// MARK: - OpenAIResponsesStreamDecoder

struct OpenAIResponsesStreamDecoder {
    // MARK: Internal

    mutating func decode(line: String) throws -> [AssistantStreamEvent] {
        guard line.utf8.count <= AssistantExecutionLimits.maxStreamEventBytes else {
            throw AssistantProviderError.malformedResponse("A streaming event exceeded Rockxy's size limit")
        }
        guard line.hasPrefix("data:") else {
            return []
        }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else {
            return []
        }
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else
        {
            throw AssistantProviderError.malformedResponse("A streaming event is not valid JSON")
        }

        switch type {
        case "response.created":
            return [.started(responseID: responseID(in: object))]
        case "response.output_text.delta":
            guard let delta = object["delta"] as? String else {
                throw AssistantProviderError.malformedResponse("Text delta is missing its content")
            }
            return [.textDelta(delta)]
        case "response.output_item.added":
            return try addedToolItem(in: object)
        case "response.function_call_arguments.delta":
            return try toolArgumentsDelta(in: object)
        case "response.function_call_arguments.done":
            return try completedToolCall(in: object)
        case "response.completed":
            return completionEvents(in: object)
        case "response.failed",
             "response.incomplete",
             "error":
            throw providerFailure(in: object)
        default:
            return [.unknown(type: type)]
        }
    }

    // MARK: Private

    private struct ToolAccumulator {
        var callID: String
        var name: String
        var arguments: String
    }

    private var toolsByItemID: [String: ToolAccumulator] = [:]

    private mutating func addedToolItem(in object: [String: Any]) throws -> [AssistantStreamEvent] {
        guard let item = object["item"] as? [String: Any],
              item["type"] as? String == "function_call" else
        {
            return []
        }
        let itemID = item["id"] as? String ?? UUID().uuidString
        let callID = item["call_id"] as? String ?? itemID
        let name = item["name"] as? String ?? ""
        let arguments = item["arguments"] as? String ?? ""
        guard toolsByItemID.count < AssistantExecutionLimits.maxToolCalls,
              arguments.utf8.count <= AssistantExecutionLimits.maxToolArgumentBytes else
        {
            throw AssistantProviderError.malformedResponse("Tool-call data exceeded Rockxy's size limit")
        }
        toolsByItemID[itemID] = ToolAccumulator(callID: callID, name: name, arguments: arguments)
        return [.toolCallDelta(id: callID, name: name.isEmpty ? nil : name, argumentsDelta: arguments)]
    }

    private mutating func toolArgumentsDelta(in object: [String: Any]) throws -> [AssistantStreamEvent] {
        let itemID = object["item_id"] as? String ?? ""
        let delta = object["delta"] as? String ?? ""
        var accumulator = toolsByItemID[itemID]
            ?? ToolAccumulator(callID: itemID, name: "", arguments: "")
        guard accumulator.arguments.utf8.count + delta.utf8.count
            <= AssistantExecutionLimits.maxToolArgumentBytes else
        {
            throw AssistantProviderError.malformedResponse("Tool-call arguments exceeded Rockxy's size limit")
        }
        accumulator.arguments += delta
        toolsByItemID[itemID] = accumulator
        return [
            .toolCallDelta(
                id: accumulator.callID,
                name: accumulator.name.isEmpty ? nil : accumulator.name,
                argumentsDelta: delta
            ),
        ]
    }

    private mutating func completedToolCall(in object: [String: Any]) throws -> [AssistantStreamEvent] {
        let itemID = object["item_id"] as? String ?? ""
        var accumulator = toolsByItemID[itemID]
            ?? ToolAccumulator(callID: itemID, name: "", arguments: "")
        if let name = object["name"] as? String {
            accumulator.name = name
        }
        if let arguments = object["arguments"] as? String {
            accumulator.arguments = arguments
        }
        guard !accumulator.callID.isEmpty, !accumulator.name.isEmpty else {
            throw AssistantProviderError.malformedResponse("A completed tool call is missing its ID or name")
        }
        guard accumulator.arguments.utf8.count <= AssistantExecutionLimits.maxToolArgumentBytes else {
            throw AssistantProviderError.malformedResponse("Tool-call arguments exceeded Rockxy's size limit")
        }
        toolsByItemID.removeValue(forKey: itemID)
        return [
            .toolCallCompleted(AssistantToolCall(
                id: accumulator.callID,
                name: accumulator.name,
                arguments: accumulator.arguments
            )),
        ]
    }

    private func completionEvents(in object: [String: Any]) -> [AssistantStreamEvent] {
        guard let response = object["response"] as? [String: Any] else {
            return [.completed(responseID: nil)]
        }
        var events: [AssistantStreamEvent] = []
        if let usage = response["usage"] as? [String: Any] {
            let details = usage["input_tokens_details"] as? [String: Any]
            events.append(.usage(AssistantUsage(
                inputTokens: usage["input_tokens"] as? Int ?? 0,
                outputTokens: usage["output_tokens"] as? Int ?? 0,
                cachedInputTokens: details?["cached_tokens"] as? Int ?? 0
            )))
        }
        events.append(.completed(responseID: response["id"] as? String))
        return events
    }

    private func responseID(in object: [String: Any]) -> String? {
        (object["response"] as? [String: Any])?["id"] as? String
    }

    private func providerFailure(in object: [String: Any]) -> AssistantProviderError {
        let response = object["response"] as? [String: Any]
        let error = (object["error"] as? [String: Any]) ?? (response?["error"] as? [String: Any])
        let message = error?["message"] as? String ?? "The response stream failed"
        return .server(statusCode: 200, message: String(message.prefix(1_024)))
    }
}
