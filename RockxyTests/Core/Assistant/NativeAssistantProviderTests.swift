import Foundation
@testable import Rockxy
import Testing

struct NativeAssistantProviderTests {
    @Test("Anthropic discovers models and streams text with usage")
    func anthropicFixture() async throws {
        let modelsData = Data(
            #"{"data":[{"id":"claude-fixture","display_name":"Claude Fixture"}]}"#.utf8
        )
        let transport = NativeProviderFixtureTransport(
            data: modelsData,
            lines: [
                #"data: {"type":"message_start","message":{"id":"msg_fixture","usage":{"input_tokens":12,"cache_read_input_tokens":3}}}"#,
                #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
                #"data: {"type":"message_delta","usage":{"output_tokens":4}}"#,
                #"data: {"type":"message_stop"}"#,
            ]
        )
        let provider = AnthropicAssistantProvider(
            baseURL: try #require(URL(string: "https://api.anthropic.com/v1")),
            apiKey: "fixture-secret",
            transport: transport
        )

        let discovered = try await provider.discoverModels()
        #expect(discovered == [AssistantModel(id: "claude-fixture", displayName: "Claude Fixture")])

        let events = try await collect(provider.stream(fixtureRequest(model: "claude-fixture")))
        #expect(events.contains(.textDelta("Hello")))
        #expect(events.contains(.usage(AssistantUsage(inputTokens: 12, outputTokens: 4, cachedInputTokens: 3))))
        #expect(events.last == .completed(responseID: "msg_fixture"))

        let requests = await transport.requests()
        let streamRequest = try #require(requests.last)
        #expect(streamRequest.value(forHTTPHeaderField: "x-api-key") == "fixture-secret")
        #expect(streamRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try jsonBody(streamRequest)
        #expect(body["max_tokens"] as? Int == 321)
    }

    @Test("Gemini filters generative models and streams usage")
    func geminiFixture() async throws {
        let models = #"{"models":[{"name":"models/gemini-fixture","displayName":"Gemini Fixture","#
            + #""inputTokenLimit":1000,"outputTokenLimit":100,"supportedGenerationMethods":["generateContent"]},"#
            + #"{"name":"models/embed-fixture","supportedGenerationMethods":["embedContent"]}]}"#
        let transport = NativeProviderFixtureTransport(
            data: Data(models.utf8),
            lines: [
                #"data: {"candidates":[{"content":{"parts":[{"text":"Hello"}]}}],"usageMetadata":{"promptTokenCount":8}}"#,
                #"data: {"candidates":[{"content":{"parts":[{"text":"!"}]},"finishReason":"STOP"}],"#
                    + #""usageMetadata":{"promptTokenCount":8,"candidatesTokenCount":2,"#
                    + #""cachedContentTokenCount":1}}"#,
            ]
        )
        let provider = GeminiAssistantProvider(
            baseURL: try #require(URL(string: "https://generativelanguage.googleapis.com/v1beta")),
            apiKey: "fixture-secret",
            transport: transport
        )

        let discovered = try await provider.discoverModels()
        #expect(discovered.count == 1)
        #expect(discovered.first?.id == "gemini-fixture")
        #expect(discovered.first?.inputTokenLimit == 1_000)

        let events = try await collect(provider.stream(fixtureRequest(model: "gemini-fixture")))
        #expect(events.contains(.textDelta("Hello")))
        #expect(events.contains(.textDelta("!")))
        #expect(events.contains(.usage(AssistantUsage(inputTokens: 8, outputTokens: 2, cachedInputTokens: 1))))
        #expect(events.last == .completed(responseID: nil))

        let requests = await transport.requests()
        let streamRequest = try #require(requests.last)
        #expect(streamRequest.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-fixture:streamGenerateContent?alt=sse")
        #expect(streamRequest.value(forHTTPHeaderField: "x-goog-api-key") == "fixture-secret")
        let body = try jsonBody(streamRequest)
        let generation = try #require(body["generationConfig"] as? [String: Any])
        #expect(generation["maxOutputTokens"] as? Int == 321)
    }

    @Test("Runtime blocks captured data from remote cleartext endpoints")
    func insecureRemoteEndpoint() async throws {
        let runtime = AssistantProviderRuntime(
            transport: NativeProviderFixtureTransport(data: Data(), lines: []),
            credentialStorage: EmptyAssistantCredentialStorage()
        )
        let configuration = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "http://models.example.com/v1",
            model: "fixture"
        )

        do {
            _ = try await runtime.discoverModels(configuration: configuration)
            Issue.record("Expected insecure endpoint rejection")
        } catch let error as AssistantProviderError {
            #expect(error == .insecureEndpoint)
        }
    }

    @Test("Runtime can discover models before a profile has selected one")
    func discoveryBeforeModelSelection() async throws {
        let transport = NativeProviderFixtureTransport(
            data: Data(#"{"data":[{"id":"fixture-model"}]}"#.utf8),
            lines: []
        )
        let runtime = AssistantProviderRuntime(
            transport: transport,
            credentialStorage: EmptyAssistantCredentialStorage()
        )
        let configuration = AssistantProviderConfiguration(
            kind: .openAICompatible,
            baseURL: "http://localhost:1234/v1"
        )

        let models = try await runtime.discoverModels(configuration: configuration)

        #expect(models.map(\.id) == ["fixture-model"])
    }

    @Test("China cloud presets dispatch through the shared compatible dialect")
    func compatibleChinaProviderDispatch() async throws {
        let transport = NativeProviderFixtureTransport(
            data: Data(#"{"data":[{"id":"deepseek-fixture"}]}"#.utf8),
            lines: []
        )
        let runtime = AssistantProviderRuntime(
            transport: transport,
            credentialStorage: FixtureAssistantCredentialStorage(value: "fixture-secret")
        )
        let configuration = AssistantProviderConfiguration(
            kind: .deepSeek,
            model: "deepseek-fixture"
        )

        let models = try await runtime.discoverModels(configuration: configuration)

        #expect(models.map(\.id) == ["deepseek-fixture"])
        let request = try #require(await transport.requests().first)
        #expect(request.url?.absoluteString == "https://api.deepseek.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-secret")
    }

    private func fixtureRequest(model: String) -> AssistantCompletionRequest {
        AssistantCompletionRequest(
            instructions: "System fixture",
            input: "User fixture",
            model: model,
            maxOutputTokens: 321,
            storeResponse: false
        )
    }

    private func collect(
        _ stream: AsyncThrowingStream<AssistantStreamEvent, Error>
    ) async throws -> [AssistantStreamEvent] {
        var events: [AssistantStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor NativeProviderFixtureTransport: AssistantHTTPTransport {
    init(data: Data, lines: [String], statusCode: Int = 200) {
        fixtureData = data
        fixtureLines = lines
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capturedRequests.append(request)
        return (fixtureData, try response(for: request))
    }

    func lines(for request: URLRequest) async throws -> AssistantHTTPStream {
        capturedRequests.append(request)
        let response = try response(for: request)
        let fixtureLines = fixtureLines
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in fixtureLines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return AssistantHTTPStream(response: response, lines: stream)
    }

    func requests() -> [URLRequest] {
        capturedRequests
    }

    private let fixtureData: Data
    private let fixtureLines: [String]
    private let statusCode: Int
    private var capturedRequests: [URLRequest] = []

    private func response(for request: URLRequest) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/2",
            headerFields: nil
        ))
    }
}

private struct EmptyAssistantCredentialStorage: AssistantCredentialStorage {
    func save(_: String, providerID _: UUID) throws {}
    func load(providerID _: UUID) throws -> String? { nil }
    func delete(providerID _: UUID) throws {}
}

private struct FixtureAssistantCredentialStorage: AssistantCredentialStorage {
    let value: String

    func save(_: String, providerID _: UUID) throws {}
    func load(providerID _: UUID) throws -> String? { value }
    func delete(providerID _: UUID) throws {}
}
