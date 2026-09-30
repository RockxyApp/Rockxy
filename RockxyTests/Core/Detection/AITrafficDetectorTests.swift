// swiftlint:disable line_length
import Foundation
@testable import Rockxy
import Testing

struct AITrafficDetectorTests {
    // MARK: Internal

    @Test("A stream larger than the size cap is read from its tail")
    func oversizedStreamIsReadFromItsTail() {
        var stream = ""
        while stream.utf8.count < AITrafficDetector.maxBodyBytes * 2 {
            stream += "data: {\"delta\":\"filler\"}\n\n"
        }
        stream += "data: {\"final\":true}\n\ndata: [DONE]\n\n"

        let events = AITrafficDetector.parseSSEEvents(Data(stream.utf8))

        #expect(events.last?.data == "{\"final\":true}")
        #expect(events.first?.data.hasPrefix("{") == true)
    }

    @Test("OpenAI-compatible streaming traffic exposes model, usage, stream events, and tools")
    func openAIStreamingTrafficExposesInspectionSignals() throws {
        let requestBody = Data(
            #"{"model":"gpt-4.1-mini","input":"fixture prompt","stream":true,"tools":[{"name":"lookup_order"}]}"#
                .utf8
        )
        let responseBody = Data("""
        event: response.created
        data: {"type":"response.created","response":{"id":"resp_fixture","model":"gpt-4.1-mini","status":"in_progress"}}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"hello"}

        event: response.output_item.added
        data: {"type":"response.output_item.added","item":{"type":"function_call","id":"fc_1","name":"lookup_order","arguments":""}}

        event: response.function_call_arguments.done
        data: {"type":"response.function_call_arguments.done","item_id":"fc_1","arguments":"{\\"order_id\\":\\"fixture-order\\"}"}

        event: response.completed
        data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":920,"input_tokens_details":{"cached_tokens":100},"output_tokens":568,"total_tokens":1488}}}

        """.utf8)
        let transaction = makeTransaction(
            url: "https://api.openai.com/v1/responses",
            requestBody: requestBody,
            responseHeaders: [
                HTTPHeader(name: "Content-Type", value: "text/event-stream"),
                HTTPHeader(name: "x-request-id", value: "req_fixture"),
            ],
            responseBody: responseBody
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.provider == .openAICompatible)
        #expect(inspection.kind == .api)
        #expect(inspection.model == "gpt-4.1-mini")
        #expect(inspection.isStreaming)
        #expect(inspection.streamTransport == .sse)
        #expect(inspection.requestID == "req_fixture")
        #expect(inspection.finishReason == "completed")
        #expect(inspection.usage?.inputTokens == 920)
        #expect(inspection.usage?.cachedTokens == 100)
        #expect(inspection.usage?.outputTokens == 568)
        #expect(inspection.assembledOutput == "hello")
        #expect(inspection.events
            .contains { $0.title == "response.function_call_arguments.done" && $0.category == .tool })
        #expect(inspection.events.first { $0.title == "response.output_text.delta" }?.preview == "hello")
        #expect(inspection.toolCalls.contains { $0.name == "lookup_order" && $0.state == .declared })
        #expect(inspection.invokedToolCalls == [
            AIToolCall(name: "lookup_order", argumentsPreview: #"{"order_id":"fixture-order"}"#, state: .completed),
        ])
        #expect(inspection.warnings.contains { $0.message.contains("Prompt content") })
        #expect(inspection.unavailableFields.isEmpty)
    }

    @Test("OpenAI chat completion streams surface finish reason, usage chunk, and reassembled text")
    func openAIChatStreamReassemblesTextAndFinishReason() throws {
        let requestBody = Data(
            #"{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"hi"}],"stream":true,"stream_options":{"include_usage":true}}"#
                .utf8
        )
        let responseBody = Data("""
        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","model":"gpt-4.1-mini-2025-04-14","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"The"},"finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" fox"},"finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"length"}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[],"usage":{"prompt_tokens":42,"completion_tokens":10,"total_tokens":52,"prompt_tokens_details":{"cached_tokens":16}}}

        data: [DONE]

        """.utf8)
        let transaction = makeTransaction(
            url: "https://api.openai.com/v1/chat/completions",
            requestBody: requestBody,
            responseHeaders: [HTTPHeader(name: "Content-Type", value: "text/event-stream")],
            responseBody: responseBody
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.finishReason == "length")
        #expect(inspection.model == "gpt-4.1-mini")
        #expect(inspection.servedModel == "gpt-4.1-mini-2025-04-14")
        #expect(inspection.assembledOutput == "The fox")
        #expect(inspection.usage == AIUsage(
            inputTokens: 42,
            cachedTokens: 16,
            outputTokens: 10,
            reasoningTokens: nil,
            totalTokens: 52
        ))
        #expect(inspection.events.map(\.title) == ["role", "text.delta", "text.delta", "finish", "usage"])
        #expect(inspection.events[3].preview == "length")
        #expect(inspection.toolCalls.isEmpty)
        #expect(!inspection.unavailableFields.contains("tool calls"))
    }

    @Test("OpenAI chat tool-call stream reassembles fragmented arguments")
    func openAIChatToolStreamReassemblesArguments() throws {
        let requestBody = Data(
            #"{"model":"gpt-4.1-mini","messages":[],"stream":true,"tools":[{"type":"function","function":{"name":"get_weather"}}]}"#
                .utf8
        )
        let responseBody = Data("""
        data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"get_weather","arguments":""}}]},"finish_reason":null}]}

        data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"ci"}}]},"finish_reason":null}]}

        data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ty\\":\\"Hanoi\\"}"}}]},"finish_reason":null}]}

        data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """.utf8)
        let transaction = makeTransaction(
            url: "https://api.openai.com/v1/chat/completions",
            requestBody: requestBody,
            responseHeaders: [HTTPHeader(name: "Content-Type", value: "text/event-stream")],
            responseBody: responseBody
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.finishReason == "tool_calls")
        #expect(inspection.invokedToolCalls == [
            AIToolCall(name: "get_weather", argumentsPreview: #"{"city":"Hanoi"}"#, state: .completed),
        ])
        #expect(inspection.events.contains { $0.title == "tool_call.delta" && $0.category == .tool })
        #expect(inspection.assembledOutput == nil)
    }

    @Test("Anthropic message stream merges usage across message_start and message_delta")
    func anthropicStreamMergesUsageAndToolUse() throws {
        let requestBody = Data(
            #"{"model":"claude-sonnet-4-5","max_tokens":256,"stream":true,"messages":[{"role":"user","content":"hi"}],"tools":[{"name":"get_weather","input_schema":{}}]}"#
                .utf8
        )
        let responseBody = Data("""
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","model":"claude-sonnet-4-5","usage":{"input_tokens":25,"cache_creation_input_tokens":0,"cache_read_input_tokens":20,"output_tokens":1}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: ping
        data: {"type":"ping"}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"get_weather","input":{}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"city\\":"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\\"Hanoi\\"}"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":1}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":12}}

        event: message_stop
        data: {"type":"message_stop"}

        """.utf8)
        let transaction = makeTransaction(
            url: "https://api.anthropic.com/v1/messages",
            requestHeaders: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "x-api-key", value: "synthetic"),
                HTTPHeader(name: "anthropic-version", value: "2023-06-01"),
            ],
            requestBody: requestBody,
            responseHeaders: [
                HTTPHeader(name: "Content-Type", value: "text/event-stream"),
                HTTPHeader(name: "request-id", value: "req_anthropic"),
            ],
            responseBody: responseBody
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.provider == .anthropic)
        #expect(inspection.requestID == "req_anthropic")
        #expect(inspection.finishReason == "tool_use")
        #expect(inspection.usage == AIUsage(
            inputTokens: 45,
            cachedTokens: 20,
            outputTokens: 12,
            reasoningTokens: nil,
            totalTokens: 57
        ))
        #expect(inspection.assembledOutput == "Hello")
        #expect(inspection.invokedToolCalls == [
            AIToolCall(name: "get_weather", argumentsPreview: #"{"city":"Hanoi"}"#, state: .completed),
        ])
        #expect(inspection.events.contains { $0.title == "content_block_delta" && $0.category == .tool })
        #expect(inspection.events.first { $0.title == "message_delta" }?.preview == "tool_use")
        #expect(inspection.warnings.contains { $0.message.contains("credential") })
    }

    @Test("Anthropic message traffic is detected without inventing missing usage")
    func anthropicTrafficKeepsMissingUsageUnavailable() throws {
        let requestBody = Data(#"{"model":"claude-sonnet-fixture","messages":[{"role":"user","content":"fixture"}]}"#
            .utf8)
        let transaction = makeTransaction(
            url: "https://api.anthropic.com/v1/messages",
            requestHeaders: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "anthropic-version", value: "2023-06-01"),
            ],
            requestBody: requestBody,
            responseBody: Data(#"{"type":"message","model":"claude-sonnet-fixture","content":[]}"#.utf8)
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.provider == .anthropic)
        #expect(inspection.model == "claude-sonnet-fixture")
        #expect(inspection.usage == nil)
        #expect(inspection.finishReason == nil)
        #expect(inspection.unavailableFields == ["usage"])
    }

    @Test("Anthropic non-streamed tool_use blocks and stop_reason are surfaced")
    func anthropicResponseExposesToolUseAndStopReason() throws {
        let requestBody = Data(
            #"{"model":"claude-sonnet-4-5","max_tokens":64,"messages":[{"role":"user","content":"Weather?"}]}"#
                .utf8
        )
        let responseBody = Data(
            #"{"type":"message","model":"claude-sonnet-4-5","content":[{"type":"text","text":"Checking."},{"type":"tool_use","id":"toolu_1","name":"get_weather","input":{"city":"Hanoi"}}],"stop_reason":"tool_use","usage":{"input_tokens":25,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":12}}"#
                .utf8
        )
        let transaction = makeTransaction(
            url: "https://gateway.example.com/v1/messages",
            requestBody: requestBody,
            responseBody: responseBody
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.provider == .anthropic)
        #expect(inspection.finishReason == "tool_use")
        #expect(inspection.assembledOutput == "Checking.")
        #expect(inspection.usage?.inputTokens == 25)
        #expect(inspection.usage?.cachedTokens == 0)
        #expect(inspection.invokedToolCalls == [
            AIToolCall(name: "get_weather", argumentsPreview: #"{"city":"Hanoi"}"#, state: .completed),
        ])
    }

    @Test("A mobile backend's /v1/messages inbox route is not mistaken for the Anthropic Messages API")
    func plainMessagesRouteIsNotAI() {
        let inbox = makeTransaction(
            method: "GET",
            url: "https://api.chatapp.example/v1/messages?since=1700000000",
            requestBody: nil,
            responseBody: Data(#"{"messages":[{"id":"m1","text":"hi"}],"next_cursor":null}"#.utf8)
        )
        let signal = AITrafficDetector.signal(transaction: inbox)
        #expect(!signal.isLikelyAI)
        #expect(signal.provider == nil)
        #expect(AITrafficDetector.detect(transaction: inbox) == nil)

        let versioned = makeTransaction(
            url: "https://gateway.example.com/v1/messages",
            requestHeaders: [HTTPHeader(name: "anthropic-version", value: "2023-06-01")],
            requestBody: Data(#"{"messages":[{"role":"user","content":"hi"}]}"#.utf8),
            responseBody: nil
        )
        #expect(AITrafficDetector.signal(transaction: versioned).provider == .anthropic)
    }

    @Test("Gemini generateContent traffic is detected with usageMetadata and finishReason")
    func geminiTrafficIsDetected() throws {
        let requestBody = Data(#"{"contents":[{"parts":[{"text":"Say hi"}]}]}"#.utf8)
        let responseBody = Data(
            #"{"candidates":[{"content":{"parts":[{"text":"Hi there"}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":18,"candidatesTokenCount":10,"totalTokenCount":28},"modelVersion":"gemini-2.5-flash"}"#
                .utf8
        )
        let transaction = makeTransaction(
            url: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=synthetic",
            requestHeaders: [HTTPHeader(name: "Content-Type", value: "application/json")],
            requestBody: requestBody,
            responseBody: responseBody
        )

        let signal = AITrafficDetector.signal(transaction: transaction)
        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(signal.tableLabel == "AI API")
        #expect(signal.provider == .gemini)
        #expect(inspection.model == "gemini-2.5-flash")
        #expect(inspection.finishReason == "stop")
        #expect(inspection.assembledOutput == "Hi there")
        #expect(inspection.usage == AIUsage(
            inputTokens: 18,
            cachedTokens: nil,
            outputTokens: 10,
            reasoningTokens: nil,
            totalTokens: 28
        ))
        #expect(inspection.warnings.contains { $0.message.contains("credential") })
    }

    @Test("Ollama NDJSON chat streams are detected with eval counts and done_reason")
    func ollamaNDJSONStreamIsDetected() throws {
        let requestBody = Data(#"{"model":"llama3.2","messages":[{"role":"user","content":"hi"}]}"#.utf8)
        let responseBody = Data("""
        {"model":"llama3.2","message":{"role":"assistant","content":"Hel"},"done":false}
        {"model":"llama3.2","message":{"role":"assistant","content":"lo"},"done":false}
        {"model":"llama3.2","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":33,"eval_count":10}

        """.utf8)
        let transaction = makeTransaction(
            url: "http://localhost:11434/api/chat",
            requestHeaders: [HTTPHeader(name: "Content-Type", value: "application/json")],
            requestBody: requestBody,
            responseHeaders: [HTTPHeader(name: "Content-Type", value: "application/x-ndjson")],
            responseBody: responseBody
        )

        let signal = AITrafficDetector.signal(transaction: transaction)
        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(signal.tableLabel == "AI API")
        #expect(inspection.provider == .ollama)
        #expect(inspection.isStreaming)
        #expect(inspection.streamTransport == .ndjson)
        #expect(inspection.finishReason == "stop")
        #expect(inspection.assembledOutput == "Hello")
        #expect(inspection.usage == AIUsage(
            inputTokens: 33,
            cachedTokens: nil,
            outputTokens: 10,
            reasoningTokens: nil,
            totalTokens: 43
        ))
        #expect(inspection.events.map(\.title) == ["message.delta", "message.delta", "done"])
        #expect(inspection.warnings.isEmpty == false)
    }

    @Test("An ordinary app backend route named /api/chat is not mistaken for Ollama")
    func appChatRouteWithoutModelEvidenceIsNotAI() {
        let transaction = makeTransaction(
            url: "https://api.example.com/api/chat",
            requestHeaders: [HTTPHeader(name: "Content-Type", value: "application/json")],
            requestBody: Data(#"{"room":"general","text":"hello"}"#.utf8),
            responseBody: Data(#"{"ok":true}"#.utf8)
        )

        #expect(!AITrafficDetector.isLikelyAI(transaction: transaction))
        #expect(AITrafficDetector.detect(transaction: transaction) == nil)
    }

    @Test("Rate-limited provider errors expose the error body and retry headers")
    func rateLimitedResponseExposesRetryGuidance() throws {
        let requestBody = Data(#"{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"hi"}]}"#.utf8)
        let responseBody = Data(
            #"{"error":{"message":"Rate limit reached. Please try again in 20s.","type":"requests","code":"rate_limit_exceeded"}}"#
                .utf8
        )
        let transaction = makeTransaction(
            url: "https://api.openai.com/v1/chat/completions",
            requestHeaders: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Authorization", value: "Bearer synthetic-token"),
                HTTPHeader(name: "x-stainless-retry-count", value: "2"),
            ],
            requestBody: requestBody,
            responseHeaders: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "retry-after", value: "20"),
                HTTPHeader(name: "x-ratelimit-remaining-requests", value: "0"),
            ],
            responseBody: responseBody,
            statusCode: 429
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.finishReason == nil)
        #expect(inspection.warnings.first?.severity == .error)
        #expect(inspection.warnings.first?.message.contains("Rate limit reached") == true)
        #expect(inspection.warnings.first?.message.contains("rate_limit_exceeded") == true)
        #expect(inspection.warnings.contains { $0.severity == .retry && $0.message.contains("Retry-After 20") })
        #expect(inspection.warnings.contains { $0.severity == .retry && $0.message.contains("attempt 2") })
        #expect(inspection.assembledOutput == nil)
    }

    @Test("Compressed AI responses still expose model and usage")
    func compressedResponseExposesUsage() throws {
        let requestBody = Data(#"{"model":"claude-sonnet-fixture","messages":[{"role":"user","content":"fixture"}]}"#.utf8)
        let plainResponse = Data(
            #"{"type":"message","model":"claude-sonnet-fixture","content":[],"usage":{"input_tokens":12,"output_tokens":7}}"#
                .utf8
        )
        let compressed = try (plainResponse as NSData).compressed(using: .zlib) as Data
        let transaction = makeTransaction(
            url: "https://api.anthropic.com/v1/messages",
            requestHeaders: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "anthropic-version", value: "2023-06-01"),
            ],
            requestBody: requestBody,
            responseHeaders: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Content-Encoding", value: "deflate"),
            ],
            responseBody: compressed
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.provider == .anthropic)
        #expect(inspection.model == "claude-sonnet-fixture")
        #expect(inspection.usage != nil)
        #expect(!inspection.unavailableFields.contains("usage"))
    }

    @Test("Known AI app session is detected without visible body metadata")
    func nativeAISessionIsDetectedFromHostEvidence() throws {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://chatgpt.com/",
            statusCode: nil
        )
        transaction.clientApp = "ChatGPT"

        let signal = AITrafficDetector.signal(transaction: transaction)
        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(signal.tableLabel == "AI Session")
        #expect(signal.evidence.contains("body hidden"))
        #expect(inspection.provider == .chatGPT)
        #expect(inspection.kind == .session)
        #expect(inspection.model == nil)
        #expect(inspection.usage == nil)
    }

    @Test("Ordinary HTTP traffic does not expose AI inspection")
    func ordinaryHTTPTrafficDoesNotExposeAIInspection() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/orders",
            statusCode: 200
        )

        #expect(!AITrafficDetector.isLikelyAI(transaction: transaction))
        #expect(AITrafficDetector.detect(transaction: transaction) == nil)
        #expect(!ResponseInspectorTab.availableTabs().contains(.ai))
    }

    @Test("Cached AI signal follows same-length request and response edits")
    func cachedSignalInvalidatesOnEvidenceEdits() {
        let aiRequest = Data(#"{"model":1,"input":1}"#.utf8)
        let otherRequest = Data(#"{"other":1,"field":1}"#.utf8)
        #expect(aiRequest.count == otherRequest.count)
        let transaction = makeTransaction(url: "https://example.com/invoke", requestBody: aiRequest)

        #expect(AITrafficDetector.signal(transaction: transaction).isLikelyAI)
        transaction.request.body = otherRequest
        #expect(!AITrafficDetector.signal(transaction: transaction).isLikelyAI)

        let aiResponse = Data(#"{"usage":1,"input_tokens":1}"#.utf8)
        let otherResponse = Data(#"{"other":1,"other_tokens":1}"#.utf8)
        #expect(aiResponse.count == otherResponse.count)
        transaction.response?.body = aiResponse
        #expect(AITrafficDetector.signal(transaction: transaction).isLikelyAI)
        transaction.response?.body = otherResponse
        #expect(!AITrafficDetector.signal(transaction: transaction).isLikelyAI)

        let replacement = HTTPTransaction(id: transaction.id, request: HTTPRequestData(
            method: "POST", url: transaction.request.url, httpVersion: "HTTP/1.1",
            headers: [], body: aiRequest, contentType: .json
        ))
        #expect(AITrafficDetector.signal(transaction: replacement).isLikelyAI)
    }

    @Test("AI tab is available only when AI metadata is likely")
    func aiTabAvailabilityFollowsDetection() {
        let requestBody = Data(#"{"model":"gpt-4.1-mini","input":"fixture"}"#.utf8)
        let transaction = makeTransaction(
            url: "https://localhost:11434/v1/responses",
            requestBody: requestBody
        )

        #expect(AITrafficDetector.isLikelyAI(transaction: transaction))
        #expect(!ResponseInspectorTab.availableTabs().contains(.ai))
        #expect(ProtocolTabKind.availableTabs(for: transaction).contains(.ai))
        #expect(ProtocolTabKind.defaultFor(transaction) == .ai)
    }

    // MARK: Private

    private func makeTransaction(
        method: String = "POST",
        url: String,
        requestHeaders: [HTTPHeader] = [
            HTTPHeader(name: "Content-Type", value: "application/json"),
            HTTPHeader(name: "Authorization", value: "Bearer synthetic-token"),
        ],
        requestBody: Data? = nil,
        responseHeaders: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")],
        responseBody: Data? = nil,
        statusCode: Int = 200
    )
        -> HTTPTransaction
    {
        guard let requestURL = URL(string: url) else {
            preconditionFailure("Expected valid fixture URL")
        }
        let request = HTTPRequestData(
            method: method,
            url: requestURL,
            httpVersion: "HTTP/1.1",
            headers: requestHeaders,
            body: requestBody,
            contentType: .json
        )
        let response = HTTPResponseData(
            statusCode: statusCode,
            statusMessage: statusCode == 200 ? "OK" : "Error",
            headers: responseHeaders,
            body: responseBody,
            contentType: .json
        )
        let transaction = HTTPTransaction(request: request, response: response, state: .completed)
        transaction.timingInfo = TimingInfo(
            dnsLookup: 0.001,
            tcpConnection: 0.002,
            tlsHandshake: 0.003,
            timeToFirstByte: 0.642,
            contentTransfer: 3.192
        )
        return transaction
    }
}

// swiftlint:enable line_length
