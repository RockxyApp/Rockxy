import Foundation
@testable import Rockxy
import Testing

// MARK: - NativeAssistantProviderTests

struct NativeAssistantProviderTests {
    // MARK: Internal

    @Test("Default assistant networking bypasses the system HTTP proxy")
    func defaultTransportBypassesSystemProxy() {
        let dictionary = URLSessionAssistantHTTPTransport.proxyBypassConfiguration()
            .connectionProxyDictionary

        #expect(dictionary?[kCFNetworkProxiesHTTPEnable as String] as? Bool == false)
        #expect(dictionary?[kCFNetworkProxiesHTTPSEnable as String] as? Bool == false)
    }

    @Test("Shared transport frames CRLF incrementally without leaking delimiters")
    func boundedLineFraming() throws {
        var framer = AssistantHTTPLineFramer(maximumLineBytes: 16)
        var lines: [String] = []

        for byte in Data("first\r\n\nlast".utf8) {
            if let line = try framer.append(byte) {
                lines.append(line)
            }
        }
        if let line = try framer.finish() {
            lines.append(line)
        }

        #expect(lines == ["first", "", "last"])
    }

    @Test("Shared transport rejects an oversized line before String allocation")
    func oversizedLineFraming() throws {
        var framer = AssistantHTTPLineFramer(maximumLineBytes: 4)

        for byte in Data("four".utf8) {
            #expect(try framer.append(byte) == nil)
        }
        #expect(throws: AssistantProviderError.self) {
            _ = try framer.append(UInt8(ascii: "x"))
        }
    }

    @Test("Shared transport rejects malformed UTF-8")
    func malformedLineFraming() throws {
        var framer = AssistantHTTPLineFramer(maximumLineBytes: 4)
        _ = try framer.append(0xFF)

        #expect(throws: AssistantProviderError.self) {
            _ = try framer.append(0x0A)
        }
    }

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
        let provider = try AnthropicAssistantProvider(
            baseURL: #require(URL(string: "https://api.anthropic.com/v1")),
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

    @Test("Anthropic correlates interleaved tool inputs and rejects malformed JSON")
    func anthropicToolInputValidation() async throws {
        let provider = try AnthropicAssistantProvider(
            baseURL: #require(URL(string: "https://api.anthropic.com/v1")),
            apiKey: "fixture-secret",
            transport: NativeProviderFixtureTransport(
                data: Data(),
                lines: [
                    #"data: {"type":"message_start","message":{"id":"msg_tools","usage":{"input_tokens":2}}}"#,
                    #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tool_alpha","name":"lookup_alpha","input":{}}}"#,
                    #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tool_beta","name":"lookup_beta","input":{}}}"#,
                    #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"beta\":"}}"#,
                    #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"alpha\":"}}"#,
                    #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"2}"}}"#,
                    #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"1}"}}"#,
                    #"data: {"type":"content_block_stop","index":1}"#,
                    #"data: {"type":"content_block_stop","index":0}"#,
                    #"data: {"type":"message_stop"}"#,
                ]
            )
        )

        let events = try await collect(provider.stream(fixtureRequest(model: "claude-fixture")))
        #expect(events.contains(.toolCallCompleted(AssistantToolCall(
            id: "tool_beta",
            name: "lookup_beta",
            arguments: #"{"beta":2}"#
        ))))
        #expect(events.contains(.toolCallCompleted(AssistantToolCall(
            id: "tool_alpha",
            name: "lookup_alpha",
            arguments: #"{"alpha":1}"#
        ))))
        #expect(events.contains(.usage(AssistantUsage(inputTokens: 2, outputTokens: 0, cachedInputTokens: 0))))

        var emptyInputDecoder = AnthropicStreamDecoder()
        _ = try emptyInputDecoder.decode(
            line: #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tool_empty","name":"empty_lookup","input":{}}}"#
        )
        let emptyInputEvents = try emptyInputDecoder.decode(
            line: #"data: {"type":"content_block_stop","index":0}"#
        )
        #expect(emptyInputEvents.contains(.toolCallCompleted(AssistantToolCall(
            id: "tool_empty",
            name: "empty_lookup",
            arguments: "{}"
        ))))

        let malformedProvider = try AnthropicAssistantProvider(
            baseURL: #require(URL(string: "https://api.anthropic.com/v1")),
            apiKey: "fixture-secret",
            transport: NativeProviderFixtureTransport(
                data: Data(),
                lines: [
                    #"data: {"type":"message_start","message":{"id":"msg_bad_tools"}}"#,
                    #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tool_bad","name":"lookup","input":{}}}"#,
                    #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{invalid"}}"#,
                    #"data: {"type":"content_block_stop","index":0}"#,
                ]
            )
        )
        await expectStreamFailure(malformedProvider.stream(fixtureRequest(model: "claude-fixture"))) { error in
            #expect(error == .malformedResponse("Anthropic tool input must be a valid JSON object"))
        }
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
        let provider = try GeminiAssistantProvider(
            baseURL: #require(URL(string: "https://generativelanguage.googleapis.com/v1beta")),
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
        #expect(streamRequest.url?
            .absoluteString ==
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-fixture:streamGenerateContent?alt=sse")
        #expect(streamRequest.value(forHTTPHeaderField: "x-goog-api-key") == "fixture-secret")
        let body = try jsonBody(streamRequest)
        let generation = try #require(body["generationConfig"] as? [String: Any])
        #expect(generation["maxOutputTokens"] as? Int == 321)
    }

    @Test("Gemini does not silently discard function calls or thought signatures")
    func geminiRejectsUnpreservedToolState() throws {
        let unsupportedEvents = [
            #"data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"lookup","args":{"id":"EV-1"}},"thoughtSignature":"fixture-signature"}]},"finishReason":"STOP"}]}"#,
            #"data: {"candidates":[{"content":{"parts":[{"thoughtSignature":"fixture-signature"}]},"finishReason":"STOP"}]}"#,
        ]

        for line in unsupportedEvents {
            #expect(throws: AssistantProviderError.capabilityMismatch(
                "Gemini function calls and thought signatures require signature-preserving tool support"
            )) {
                _ = try GeminiStreamDecoder.decode(line: line)
            }
        }
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

    @Test("Ark validates a separate deployment ID before network access")
    func arkDeploymentIdentityValidation() async throws {
        let transport = NativeProviderFixtureTransport(data: Data(), lines: [])
        let runtime = AssistantProviderRuntime(
            transport: transport,
            credentialStorage: EmptyAssistantCredentialStorage()
        )
        let configuration = AssistantProviderConfiguration(
            kind: .doubao,
            model: "doubao-seed-2-1-pro-260915",
            arkDeploymentID: "   "
        )

        #expect(configuration.model == "doubao-seed-2-1-pro-260915")
        #expect(configuration.apiModelIdentifier.isEmpty)
        #expect(!configuration.isComplete)
        do {
            _ = try await runtime.discoverModels(configuration: configuration)
            Issue.record("Expected the invalid deployment ID to fail before networking")
        } catch let error as AssistantProviderError {
            #expect(error == .invalidDeploymentID)
        }
        #expect(await transport.requests().isEmpty)

        var oversized = configuration
        oversized.arkDeploymentID = String(
            repeating: "a",
            count: AssistantProviderConfiguration.maxArkDeploymentIDBytes + 1
        )
        #expect(!oversized.hasValidArkDeploymentID)
        #expect(!oversized.isComplete)
    }

    @Test("Qwen regional profiles keep their endpoint and credential paired")
    func qwenRegionalProfilesStayPaired() async throws {
        let beijing = AssistantProviderConfiguration(
            kind: .qwen,
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen-fixture-cn",
            region: "cn-beijing"
        )
        let singapore = AssistantProviderConfiguration(
            kind: .qwen,
            baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
            model: "qwen-fixture-sg",
            region: "ap-southeast-1"
        )
        let transport = NativeProviderFixtureTransport(
            data: Data(#"{"data":[{"id":"qwen-fixture"}]}"#.utf8),
            lines: []
        )
        let runtime = AssistantProviderRuntime(
            transport: transport,
            credentialStorage: ProfileAssistantCredentialStorage(values: [
                beijing.id: "beijing-fixture-key",
                singapore.id: "singapore-fixture-key",
            ])
        )

        _ = try await runtime.discoverModels(configuration: beijing)
        _ = try await runtime.discoverModels(configuration: singapore)

        let requests = await transport.requests()
        #expect(requests.count == 2)
        #expect(requests[0].url?.host == "dashscope.aliyuncs.com")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer beijing-fixture-key")
        #expect(requests[1].url?.host == "dashscope-intl.aliyuncs.com")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer singapore-fixture-key")
    }

    @Test("Kimi China and global profiles keep their endpoint and credential paired")
    func kimiPlatformProfilesStayPaired() async throws {
        let global = AssistantProviderConfiguration(
            kind: .kimi,
            baseURL: "https://api.moonshot.ai/v1",
            model: "kimi-global-fixture",
            region: "global"
        )
        let china = AssistantProviderConfiguration(
            kind: .kimi,
            baseURL: "https://api.moonshot.cn/v1",
            model: "kimi-cn-fixture",
            region: "china"
        )
        let transport = NativeProviderFixtureTransport(
            data: Data(#"{"data":[{"id":"kimi-fixture"}]}"#.utf8),
            lines: []
        )
        let runtime = AssistantProviderRuntime(
            transport: transport,
            credentialStorage: ProfileAssistantCredentialStorage(values: [
                global.id: "global-fixture-key",
                china.id: "china-fixture-key",
            ])
        )

        _ = try await runtime.discoverModels(configuration: global)
        _ = try await runtime.discoverModels(configuration: china)

        let requests = await transport.requests()
        #expect(requests.count == 2)
        #expect(requests[0].url?.host == "api.moonshot.ai")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer global-fixture-key")
        #expect(requests[1].url?.host == "api.moonshot.cn")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer china-fixture-key")
    }

    @MainActor
    @Test("Model discovery cannot overwrite a provider selected while discovery is in flight")
    func staleModelDiscoveryIsIgnored() async throws {
        let runtime = DelayedSettingsAssistantRuntime()
        let manager = FixtureAssistantSettingsManager()
        let viewModel = AssistantSettingsViewModel(
            manager: manager,
            credentialStorage: EmptyAssistantCredentialStorage(),
            runtime: runtime
        )

        viewModel.fetchModels()
        for _ in 0 ..< 500 {
            if await runtime.hasStarted {
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await runtime.hasStarted)

        viewModel.selectProvider(.openAICompatible)
        await runtime.complete(with: [
            AssistantModel(id: "stale-ollama-model", displayName: "Stale Ollama Model"),
        ])
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(viewModel.configuration.kind == .openAICompatible)
        #expect(viewModel.models.isEmpty)
        #expect(!viewModel.isBusy)
        #expect(!viewModel.isRefreshingProviderModels)
    }

    @MainActor
    @Test("Connection result cannot confirm a model changed while the check is in flight")
    func staleConnectionResultAfterModelChangeIsIgnored() async throws {
        let runtime = DelayedSettingsAssistantRuntime()
        let viewModel = AssistantSettingsViewModel(
            manager: FixtureAssistantSettingsManager(),
            credentialStorage: EmptyAssistantCredentialStorage(),
            runtime: runtime
        )
        viewModel.configuration.model = "model-before-check"

        viewModel.testConnection()
        for _ in 0 ..< 500 {
            if await runtime.hasConnectionStarted {
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await runtime.hasConnectionStarted)

        viewModel.configuration.model = "model-after-check"
        await runtime.completeConnection()
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(viewModel.configuration.model == "model-after-check")
        #expect(viewModel.statusMessage == nil)
        #expect(!viewModel.isBusy)
    }

    @MainActor
    @Test("Model availability detail matches local and remote providers")
    func modelAvailabilityDetailMatchesProvider() {
        let viewModel = AssistantSettingsViewModel(
            manager: FixtureAssistantSettingsManager(),
            credentialStorage: EmptyAssistantCredentialStorage(),
            runtime: DelayedSettingsAssistantRuntime()
        )

        #expect(viewModel.availableModelsDetail.contains("local downloads"))

        viewModel.selectProvider(.openAICompatible)

        #expect(!viewModel.availableModelsDetail.contains("local downloads"))
        #expect(viewModel.availableModelsDetail.contains(AssistantProviderKind.openAICompatible.title))
    }

    @Test("Anthropic rejects a non-2xx streaming response with a typed error")
    func anthropicStreamRejectsHTTPFailure() async throws {
        let provider = try AnthropicAssistantProvider(
            baseURL: #require(URL(string: "https://api.anthropic.com/v1")),
            apiKey: "fixture-secret",
            transport: NativeProviderFixtureTransport(
                data: Data(),
                lines: [#"{"error":{"message":"unauthorized"}}"#],
                statusCode: 401
            )
        )

        await expectStreamFailure(provider.stream(fixtureRequest(model: "claude-fixture"))) { error in
            #expect(error == .authentication)
        }
    }

    @Test("Anthropic stream without message_stop fails instead of presenting partial output")
    func anthropicStreamRejectsPrematureEOF() async throws {
        let provider = try AnthropicAssistantProvider(
            baseURL: #require(URL(string: "https://api.anthropic.com/v1")),
            apiKey: "fixture-secret",
            transport: NativeProviderFixtureTransport(
                data: Data(),
                lines: [
                    #"data: {"type":"message_start","message":{"id":"msg_partial"}}"#,
                    #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}"#,
                ]
            )
        )

        await expectStreamFailure(provider.stream(fixtureRequest(model: "claude-fixture"))) { error in
            guard case .malformedResponse = error else {
                Issue.record("Expected malformedResponse, got \(error)")
                return
            }
        }
    }

    @Test("Gemini rejects a non-2xx streaming response with a typed error")
    func geminiStreamRejectsHTTPFailure() async throws {
        let provider = try GeminiAssistantProvider(
            baseURL: #require(URL(string: "https://generativelanguage.googleapis.com/v1beta")),
            apiKey: "fixture-secret",
            transport: NativeProviderFixtureTransport(
                data: Data(),
                lines: [#"{"error":{"message":"unauthorized"}}"#],
                statusCode: 401
            )
        )

        await expectStreamFailure(provider.stream(fixtureRequest(model: "gemini-fixture"))) { error in
            #expect(error == .authentication)
        }
    }

    @Test("Gemini stream without a finish reason fails instead of presenting partial output")
    func geminiStreamRejectsPrematureEOF() async throws {
        let provider = try GeminiAssistantProvider(
            baseURL: #require(URL(string: "https://generativelanguage.googleapis.com/v1beta")),
            apiKey: "fixture-secret",
            transport: NativeProviderFixtureTransport(
                data: Data(),
                lines: [#"data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}"#]
            )
        )

        await expectStreamFailure(provider.stream(fixtureRequest(model: "gemini-fixture"))) { error in
            guard case .malformedResponse = error else {
                Issue.record("Expected malformedResponse, got \(error)")
                return
            }
        }
    }

    // MARK: Private

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
    )
        async throws -> [AssistantStreamEvent]
    {
        var events: [AssistantStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func expectStreamFailure(
        _ stream: AsyncThrowingStream<AssistantStreamEvent, Error>,
        _ validate: (AssistantProviderError) -> Void
    )
        async
    {
        do {
            for try await _ in stream {}
            Issue.record("Expected the stream to fail before completing normally")
        } catch let error as AssistantProviderError {
            validate(error)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// MARK: - NativeProviderFixtureTransport

private actor NativeProviderFixtureTransport: AssistantHTTPTransport {
    // MARK: Lifecycle

    init(data: Data, lines: [String], statusCode: Int = 200) {
        fixtureData = data
        fixtureLines = lines
        self.statusCode = statusCode
    }

    // MARK: Internal

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capturedRequests.append(request)
        return try (fixtureData, response(for: request))
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

    // MARK: Private

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

// MARK: - ProfileAssistantCredentialStorage

private struct ProfileAssistantCredentialStorage: AssistantCredentialStorage {
    let values: [UUID: String]

    func save(_: String, providerID _: UUID) throws {}

    func load(providerID: UUID) throws -> String? {
        values[providerID]
    }

    func delete(providerID _: UUID) throws {}
}

// MARK: - EmptyAssistantCredentialStorage

private struct EmptyAssistantCredentialStorage: AssistantCredentialStorage {
    func save(_: String, providerID _: UUID) throws {}
    func load(providerID _: UUID) throws -> String? {
        nil
    }

    func delete(providerID _: UUID) throws {}
}

// MARK: - FixtureAssistantCredentialStorage

private struct FixtureAssistantCredentialStorage: AssistantCredentialStorage {
    let value: String

    func save(_: String, providerID _: UUID) throws {}
    func load(providerID _: UUID) throws -> String? {
        value
    }

    func delete(providerID _: UUID) throws {}
}

// MARK: - FixtureAssistantSettingsManager

@MainActor
private final class FixtureAssistantSettingsManager: AssistantSettingsManaging {
    var settings = AppSettings()

    func updateAssistantConfiguration(
        _ configuration: AssistantProviderConfiguration?,
        enabled: Bool?
    ) {
        settings.assistantProviderConfiguration = configuration
        if let enabled {
            settings.debugAssistantModelAccessEnabled = enabled
        }
    }

    func selectAssistantConfiguration(_ configurationID: UUID) {
        settings.activeAssistantProviderID = configurationID
    }

    func removeAssistantConfiguration(_ configurationID: UUID) {
        settings.assistantProviderConfigurations.removeAll { $0.id == configurationID }
    }
}

// MARK: - DelayedSettingsAssistantRuntime

private actor DelayedSettingsAssistantRuntime: AssistantProviderRuntimeProtocol {
    // MARK: Internal

    var hasStarted = false
    var hasConnectionStarted = false

    func discoverModels(
        configuration _: AssistantProviderConfiguration
    )
        async throws -> [AssistantModel]
    {
        hasStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            discoveryContinuation = continuation
        }
    }

    func testConnection(
        configuration: AssistantProviderConfiguration
    )
        async throws -> AssistantConnectionTestResult
    {
        hasConnectionStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            connectionContinuation = continuation
            pendingConnectionConfiguration = configuration
        }
    }

    func stream(
        request _: AssistantCompletionRequest,
        configuration _: AssistantProviderConfiguration
    )
        async throws -> AsyncThrowingStream<AssistantStreamEvent, Error>
    {
        AsyncThrowingStream { $0.finish() }
    }

    func complete(with models: [AssistantModel]) {
        discoveryContinuation?.resume(returning: models)
        discoveryContinuation = nil
    }

    func completeConnection() {
        guard let configuration = pendingConnectionConfiguration else {
            return
        }
        connectionContinuation?.resume(returning: AssistantConnectionTestResult(
            provider: configuration.kind.title,
            endpointHost: configuration.endpointHost,
            model: configuration.model,
            discoveredModelCount: 0
        ))
        connectionContinuation = nil
        pendingConnectionConfiguration = nil
    }

    // MARK: Private

    private var discoveryContinuation: CheckedContinuation<[AssistantModel], Error>?
    private var connectionContinuation: CheckedContinuation<AssistantConnectionTestResult, Error>?
    private var pendingConnectionConfiguration: AssistantProviderConfiguration?
}
