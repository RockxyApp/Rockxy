import Foundation
@testable import Rockxy
import Testing

// MARK: - OpenAIResponsesProviderTests

struct OpenAIResponsesProviderTests {
    @Test("Responses adapter emits fixture text, tool call, usage, and exact request options")
    func fixtureStreamingFlow() async throws {
        let lines = [
            #"data: {"type":"response.created","response":{"id":"resp_fixture"}}"#,
            #"data: {"type":"response.output_text.delta","delta":"Check "}"#,
            #"data: {"type":"response.output_text.delta","delta":"Retry-After."}"#,
            #"data: {"type":"response.output_item.added","item":{"id":"item_1","type":"function_call","call_id":"call_1","name":"lookup_evidence","arguments":""}}"#,
            #"data: {"type":"response.function_call_arguments.delta","item_id":"item_1","delta":"{\"id\":\"EV-1\"}"}"#,
            #"data: {"type":"response.function_call_arguments.done","item_id":"item_1","name":"lookup_evidence","arguments":"{\"id\":\"EV-1\"}"}"#,
            #"data: {"type":"response.future_event","value":"ignored safely"}"#,
            #"data: {"type":"response.completed","response":{"id":"resp_fixture","usage":{"input_tokens":42,"output_tokens":7,"input_tokens_details":{"cached_tokens":5}}}}"#,
        ]
        let transport = FixtureAssistantTransport(streamLines: lines)
        let provider = try OpenAIResponsesProvider(
            baseURL: #require(URL(string: "https://api.openai.com/v1")),
            apiKey: "fixture-secret",
            transport: transport
        )
        let request = AssistantCompletionRequest(
            instructions: "system fixture",
            input: "reviewed fixture",
            model: "fixture-model",
            maxOutputTokens: 321,
            storeResponse: false
        )

        var events: [AssistantStreamEvent] = []
        for try await event in provider.stream(request) {
            events.append(event)
        }

        #expect(events.contains(.started(responseID: "resp_fixture")))
        #expect(events.contains(.textDelta("Check ")))
        #expect(events.contains(.textDelta("Retry-After.")))
        #expect(events.contains(.toolCallCompleted(AssistantToolCall(
            id: "call_1",
            name: "lookup_evidence",
            arguments: #"{"id":"EV-1"}"#
        ))))
        #expect(events.contains(.usage(AssistantUsage(inputTokens: 42, outputTokens: 7, cachedInputTokens: 5))))
        #expect(events.contains(.unknown(type: "response.future_event")))
        #expect(events.contains(.completed(responseID: "resp_fixture")))

        let outbound = try #require(await transport.lastRequest())
        #expect(outbound.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(outbound.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-secret")
        let body = try #require(outbound.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "fixture-model")
        #expect(object["store"] as? Bool == false)
        #expect(object["stream"] as? Bool == true)
        #expect(object["max_output_tokens"] as? Int == 321)
    }

    @Test("Models endpoint is discoverable with fixture data")
    func modelDiscovery() async throws {
        let data = Data(#"{"data":[{"id":"z-model"},{"id":"a-model"}]}"#.utf8)
        let transport = FixtureAssistantTransport(dataBody: data)
        let provider = try OpenAIResponsesProvider(
            baseURL: #require(URL(string: "https://api.openai.com/v1")),
            apiKey: "fixture-secret",
            transport: transport
        )

        let models = try await provider.discoverModels()

        #expect(models.map(\.id) == ["a-model", "z-model"])
        let outbound = try #require(await transport.lastRequest())
        #expect(outbound.url?.absoluteString == "https://api.openai.com/v1/models")
    }

    @Test("HTTP 429 is classified without a live provider")
    func rateLimitFixture() async throws {
        let transport = FixtureAssistantTransport(
            streamStatus: 429,
            streamHeaders: ["Retry-After": "12"],
            streamLines: [#"{"error":{"message":"slow down"}}"#]
        )
        let provider = try OpenAIResponsesProvider(
            baseURL: #require(URL(string: "https://api.openai.com/v1")),
            apiKey: "fixture-secret",
            transport: transport
        )
        let request = AssistantCompletionRequest(
            instructions: "fixture",
            input: "fixture",
            model: "fixture-model",
            maxOutputTokens: 10,
            storeResponse: false
        )

        do {
            for try await _ in provider.stream(request) {}
            Issue.record("Expected rate limit error")
        } catch let error as AssistantProviderError {
            #expect(error == .rateLimited(retryAfterSeconds: 12))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("OpenAI-compatible adapter streams Chat Completions fixtures")
    func compatibleFixture() async throws {
        let transport = FixtureAssistantTransport(streamLines: [
            #"data: {"choices":[{"delta":{"content":"Local result"}}]}"#,
            #"data: {"usage":{"prompt_tokens":9,"completion_tokens":3,"prompt_tokens_details":{"cached_tokens":2}},"choices":[]}"#,
            "data: [DONE]",
        ])
        let provider = try OpenAICompatibleAssistantProvider(
            baseURL: #require(URL(string: "http://127.0.0.1:1234/v1")),
            apiKey: "",
            transport: transport
        )
        let request = AssistantCompletionRequest(
            instructions: "fixture system",
            input: "fixture input",
            model: "local-model",
            maxOutputTokens: 99,
            storeResponse: false
        )

        var events: [AssistantStreamEvent] = []
        for try await event in provider.stream(request) {
            events.append(event)
        }

        #expect(events.contains(.textDelta("Local result")))
        #expect(events.contains(.usage(AssistantUsage(inputTokens: 9, outputTokens: 3, cachedInputTokens: 2))))
        let outbound = try #require(await transport.lastRequest())
        #expect(outbound.url?.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")
        #expect(outbound.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Ollama adapter streams native NDJSON fixtures")
    func ollamaFixture() async throws {
        let transport = FixtureAssistantTransport(streamLines: [
            #"{"message":{"role":"assistant","content":"Inspect DNS."},"done":false}"#,
            #"{"message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":15,"eval_count":4}"#,
        ])
        let provider = try OllamaAssistantProvider(
            baseURL: #require(URL(string: "http://127.0.0.1:11434")),
            transport: transport
        )
        let request = AssistantCompletionRequest(
            instructions: "fixture system",
            input: "fixture input",
            model: "qwen-fixture",
            maxOutputTokens: 99,
            storeResponse: false
        )

        var events: [AssistantStreamEvent] = []
        for try await event in provider.stream(request) {
            events.append(event)
        }

        #expect(events.contains(.textDelta("Inspect DNS.")))
        #expect(events.contains(.usage(AssistantUsage(inputTokens: 15, outputTokens: 4, cachedInputTokens: 0))))
        #expect(events.contains(.completed(responseID: nil)))
        let outbound = try #require(await transport.lastRequest())
        #expect(outbound.url?.absoluteString == "http://127.0.0.1:11434/api/chat")
    }

    @Test("Runtime rejects OpenAI configuration without a Keychain credential")
    func missingCredential() async {
        let runtime = AssistantProviderRuntime(
            transport: FixtureAssistantTransport(),
            credentialStorage: EmptyAssistantCredentialStorage()
        )
        let configuration = AssistantProviderConfiguration(
            kind: .openAI,
            model: "fixture-model"
        )

        do {
            _ = try await runtime.discoverModels(configuration: configuration)
            Issue.record("Expected credential error")
        } catch let error as AssistantProviderError {
            #expect(error == .credentialMissing)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("OpenAI preset cannot be redirected to a custom endpoint")
    func openAIPresetEndpointIsFixed() async {
        let runtime = AssistantProviderRuntime(
            transport: FixtureAssistantTransport(),
            credentialStorage: FixedAssistantCredentialStorage(credential: "fixture-secret")
        )
        let configuration = AssistantProviderConfiguration(
            kind: .openAI,
            baseURL: "https://example.com/v1",
            model: "fixture-model"
        )

        do {
            _ = try await runtime.discoverModels(configuration: configuration)
            Issue.record("Expected endpoint error")
        } catch let error as AssistantProviderError {
            #expect(error == .invalidEndpoint)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Provider configuration rejects credential-bearing and non-HTTP URLs")
    func endpointValidation() {
        let credentialURL = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "https://user:password@example.com/v1",
            model: "fixture"
        )
        let fileURL = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "file:///tmp/provider",
            model: "fixture"
        )

        #expect(credentialURL.endpointURL == nil)
        #expect(fileURL.endpointURL == nil)
        #expect(!credentialURL.isComplete)
        #expect(!fileURL.isComplete)
    }

    @Test("Truncated Responses stream fails instead of presenting partial output as complete")
    func truncatedStream() async throws {
        let transport = FixtureAssistantTransport(streamLines: [
            #"data: {"type":"response.created","response":{"id":"resp_partial"}}"#,
            #"data: {"type":"response.output_text.delta","delta":"partial"}"#,
        ])
        let provider = try OpenAIResponsesProvider(
            baseURL: #require(URL(string: "https://api.openai.com/v1")),
            apiKey: "fixture-secret",
            transport: transport
        )
        let request = AssistantCompletionRequest(
            instructions: "fixture",
            input: "fixture",
            model: "fixture-model",
            maxOutputTokens: 10,
            storeResponse: false
        )

        do {
            for try await _ in provider.stream(request) {}
            Issue.record("Expected truncated stream error")
        } catch let error as AssistantProviderError {
            guard case .malformedResponse = error else {
                Issue.record("Unexpected provider error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Malformed and oversized tool events are rejected")
    func malformedAndOversizedEvents() throws {
        var malformedDecoder = OpenAIResponsesStreamDecoder()
        #expect(throws: (any Error).self) {
            _ = try malformedDecoder.decode(line: "data: not-json")
        }

        var toolDecoder = OpenAIResponsesStreamDecoder()
        let oversized = String(repeating: "a", count: AssistantExecutionLimits.maxToolArgumentBytes + 1)
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "response.output_item.added",
            "item": [
                "id": "item_oversized",
                "type": "function_call",
                "call_id": "call_oversized",
                "name": "fixture",
                "arguments": oversized,
            ],
        ])
        let line = "data: " + (try #require(String(bytes: data, encoding: .utf8)))
        #expect(throws: (any Error).self) {
            _ = try toolDecoder.decode(line: line)
        }
    }

    @Test("HTTP and transport failures retain stable classifications")
    func errorClassification() throws {
        let url = try #require(URL(string: "https://api.openai.com/v1/responses"))
        func response(_ status: Int) throws -> HTTPURLResponse {
            try #require(HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/2",
                headerFields: nil
            ))
        }
        let modelError = Data(#"{"error":{"code":"model_not_found","message":"missing"}}"#.utf8)

        #expect(AssistantHTTPErrorMapper.error(
            response: try response(401),
            body: Data(),
            model: "fixture"
        ) == .authentication)
        #expect(AssistantHTTPErrorMapper.error(
            response: try response(403),
            body: Data(),
            model: "fixture"
        ) == .permission)
        #expect(AssistantHTTPErrorMapper.error(
            response: try response(404),
            body: modelError,
            model: "fixture"
        ) == .modelNotFound("fixture"))
        #expect(AssistantHTTPErrorMapper.translated(URLError(.timedOut)) as? AssistantProviderError == .timedOut)
        let translated = AssistantHTTPErrorMapper.translated(URLError(.notConnectedToInternet))
        guard let providerError = translated as? AssistantProviderError,
              case .network = providerError else
        {
            Issue.record("Expected network classification")
            return
        }
    }
}

// MARK: - EmptyAssistantCredentialStorage

private struct EmptyAssistantCredentialStorage: AssistantCredentialStorage {
    func save(_: String, providerID _: UUID) throws {}
    func load(providerID _: UUID) throws -> String? {
        nil
    }

    func delete(providerID _: UUID) throws {}
}

// MARK: - FixedAssistantCredentialStorage

private struct FixedAssistantCredentialStorage: AssistantCredentialStorage {
    let credential: String

    func save(_: String, providerID _: UUID) throws {}
    func load(providerID _: UUID) throws -> String? {
        credential
    }

    func delete(providerID _: UUID) throws {}
}

// MARK: - FixtureAssistantTransport

private actor FixtureAssistantTransport: AssistantHTTPTransport {
    // MARK: Lifecycle

    init(
        dataBody: Data = Data(#"{"data":[]}"#.utf8),
        dataStatus: Int = 200,
        streamStatus: Int = 200,
        streamHeaders: [String: String]? = nil,
        streamLines: [String] = []
    ) {
        self.dataBody = dataBody
        self.dataStatus = dataStatus
        self.streamStatus = streamStatus
        self.streamHeaders = streamHeaders
        self.streamFixtureLines = streamLines
    }

    // MARK: Internal

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (
            dataBody,
            try response(url: #require(request.url), status: dataStatus, headers: nil)
        )
    }

    func lines(for request: URLRequest) async throws -> AssistantHTTPStream {
        requests.append(request)
        let fixtureLines = streamFixtureLines
        let lines = AsyncThrowingStream<String, Error> { continuation in
            for line in fixtureLines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return AssistantHTTPStream(
            response: try response(
                url: #require(request.url),
                status: streamStatus,
                headers: streamHeaders
            ),
            lines: lines
        )
    }

    func lastRequest() -> URLRequest? {
        requests.last
    }

    // MARK: Private

    private let dataBody: Data
    private let dataStatus: Int
    private let streamStatus: Int
    private let streamHeaders: [String: String]?
    private let streamFixtureLines: [String]
    private var requests: [URLRequest] = []

    private func response(url: URL, status: Int, headers: [String: String]?) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/2",
            headerFields: headers
        ))
    }
}
