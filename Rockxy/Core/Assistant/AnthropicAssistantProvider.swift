import Foundation

struct AnthropicAssistantProvider: AssistantModelProvider {
    init(baseURL: URL, apiKey: String, transport: any AssistantHTTPTransport) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.transport = transport
    }

    let kind = AssistantProviderKind.anthropic
    let capabilities = AssistantProviderCapabilities.anthropic

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
                  let values = object["data"] as? [[String: Any]] else
            {
                throw AssistantProviderError.malformedResponse("The Anthropic models response has no data array")
            }
            return values.compactMap { value in
                guard let id = value["id"] as? String, !id.isEmpty else {
                    return nil
                }
                return AssistantModel(
                    id: id,
                    displayName: value["display_name"] as? String ?? id
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
                    var urlRequest = URLRequest(url: endpoint("messages"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = Self.requestTimeout
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    authorize(&urlRequest)
                    urlRequest.httpBody = try JSONSerialization.data(
                        withJSONObject: [
                            "model": request.model,
                            "system": request.instructions,
                            "messages": [["role": "user", "content": request.input]],
                            "max_tokens": request.maxOutputTokens,
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

                    var decoder = AnthropicStreamDecoder()
                    var didComplete = false
                    for try await line in stream.lines {
                        try Task.checkCancellation()
                        for event in try decoder.decode(line: line) {
                            if case .completed = event {
                                didComplete = true
                            }
                            continuation.yield(event)
                        }
                    }
                    guard didComplete else {
                        throw AssistantProviderError.malformedResponse(
                            "The Anthropic stream ended before message_stop"
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

    private static let connectionTimeout: TimeInterval = 15
    private static let requestTimeout: TimeInterval = 90
    private static let apiVersion = "2023-06-01"

    private let baseURL: URL
    private let apiKey: String
    private let transport: any AssistantHTTPTransport

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
    }
}

struct AnthropicStreamDecoder {
    mutating func decode(line: String) throws -> [AssistantStreamEvent] {
        guard line.utf8.count <= AssistantExecutionLimits.maxStreamEventBytes else {
            throw AssistantProviderError.malformedResponse("An Anthropic streaming event exceeded Rockxy's size limit")
        }
        guard line.hasPrefix("data:") else {
            return []
        }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else {
            return []
        }
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else
        {
            throw AssistantProviderError.malformedResponse("An Anthropic streaming event is invalid")
        }

        switch type {
        case "message_start":
            let message = object["message"] as? [String: Any]
            responseID = message?["id"] as? String
            updateInputUsage(message?["usage"] as? [String: Any])
            return [.started(responseID: responseID)]
        case "content_block_start":
            return startContentBlock(object)
        case "content_block_delta":
            return try contentDelta(object)
        case "content_block_stop":
            return stopContentBlock(object)
        case "message_delta":
            let usage = object["usage"] as? [String: Any]
            outputTokens = usage?["output_tokens"] as? Int ?? outputTokens
            return [.usage(currentUsage)]
        case "message_stop":
            return [.completed(responseID: responseID)]
        case "error":
            let error = object["error"] as? [String: Any]
            throw AssistantProviderError.validation(
                String((error?["message"] as? String ?? "Anthropic stream failed").prefix(1_024))
            )
        case "ping":
            return []
        default:
            return [.unknown(type: type)]
        }
    }

    private struct ToolBuffer {
        let id: String
        let name: String
        var arguments: String
    }

    private var responseID: String?
    private var inputTokens = 0
    private var outputTokens = 0
    private var cachedInputTokens = 0
    private var tools: [Int: ToolBuffer] = [:]

    private var currentUsage: AssistantUsage {
        AssistantUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: cachedInputTokens
        )
    }

    private mutating func updateInputUsage(_ usage: [String: Any]?) {
        inputTokens = usage?["input_tokens"] as? Int ?? inputTokens
        cachedInputTokens = usage?["cache_read_input_tokens"] as? Int ?? cachedInputTokens
    }

    private mutating func startContentBlock(_ object: [String: Any]) -> [AssistantStreamEvent] {
        guard let index = object["index"] as? Int,
              let block = object["content_block"] as? [String: Any],
              block["type"] as? String == "tool_use",
              let id = block["id"] as? String,
              let name = block["name"] as? String else
        {
            return []
        }
        tools[index] = ToolBuffer(id: id, name: name, arguments: "")
        return [.toolCallDelta(id: id, name: name, argumentsDelta: "")]
    }

    private mutating func contentDelta(_ object: [String: Any]) throws -> [AssistantStreamEvent] {
        guard let delta = object["delta"] as? [String: Any], let type = delta["type"] as? String else {
            throw AssistantProviderError.malformedResponse("An Anthropic content delta is invalid")
        }
        if type == "text_delta", let text = delta["text"] as? String {
            return text.isEmpty ? [] : [.textDelta(text)]
        }
        guard type == "input_json_delta",
              let index = object["index"] as? Int,
              let partial = delta["partial_json"] as? String,
              var tool = tools[index] else
        {
            return []
        }
        guard tool.arguments.utf8.count + partial.utf8.count <= AssistantExecutionLimits.maxToolArgumentBytes else {
            throw AssistantProviderError.malformedResponse("Anthropic tool arguments exceeded Rockxy's size limit")
        }
        tool.arguments += partial
        tools[index] = tool
        return [.toolCallDelta(id: tool.id, name: nil, argumentsDelta: partial)]
    }

    private mutating func stopContentBlock(_ object: [String: Any]) -> [AssistantStreamEvent] {
        guard let index = object["index"] as? Int, let tool = tools.removeValue(forKey: index) else {
            return []
        }
        return [.toolCallCompleted(AssistantToolCall(
            id: tool.id,
            name: tool.name,
            arguments: tool.arguments
        ))]
    }
}
