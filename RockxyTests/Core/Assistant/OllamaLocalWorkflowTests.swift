import Foundation
@testable import Rockxy
import Testing

// MARK: - OllamaLocalWorkflowTests

struct OllamaLocalWorkflowTests {
    @Test("Local Ollama workflow reaches ready, inventory, pull, chat, and remove endpoints")
    func completeLocalWorkflow() async throws {
        let transport = OllamaWorkflowFixtureTransport()
        let baseURL = try #require(URL(string: "http://127.0.0.1:11434/v1"))
        let checker = OllamaRuntimeChecker(transport: transport)
        let installer = OllamaModelInstaller(transport: transport)
        let provider = OllamaAssistantProvider(baseURL: baseURL, transport: transport)

        let runtime = try await checker.check(baseURL: baseURL)
        #expect(runtime == OllamaRuntimeInfo(version: "0.9.6"))

        let models = try await provider.discoverModels()
        #expect(models.map(\.id) == ["qwen3:4b"])
        #expect(models.first?.parameterSize == "4.0B")

        var installEvents: [AssistantModelInstallEvent] = []
        for try await event in installer.install(modelID: "qwen3:4b", baseURL: baseURL) {
            installEvents.append(event)
        }
        #expect(installEvents == [
            .status("pulling manifest"),
            .progress(completed: 50, total: 100),
            .completed,
        ])

        let request = AssistantCompletionRequest(
            instructions: "Use only the reviewed traffic.",
            input: "Explain the failure.",
            model: "qwen3:4b",
            maxOutputTokens: 512,
            storeResponse: false
        )
        var streamEvents: [AssistantStreamEvent] = []
        for try await event in provider.stream(request) {
            streamEvents.append(event)
        }
        #expect(streamEvents.contains(.textDelta("The upstream timed out.")))
        #expect(streamEvents.contains(.completed(responseID: nil)))

        try await installer.remove(modelID: "qwen3:4b", baseURL: baseURL)

        #expect(await transport.requestPaths() == [
            "/api/version",
            "/api/tags",
            "/api/pull",
            "/api/chat",
            "/api/delete",
        ])
    }

    @Test("Runtime checker rejects a response without a version")
    func malformedRuntimeResponse() async throws {
        let transport = OllamaWorkflowFixtureTransport(versionData: Data(#"{}"#.utf8))
        let checker = OllamaRuntimeChecker(transport: transport)

        do {
            _ = try await checker.check(
                baseURL: #require(URL(string: "http://127.0.0.1:11434"))
            )
            Issue.record("Expected malformed runtime response")
        } catch let error as AssistantProviderError {
            guard case .malformedResponse = error else {
                Issue.record("Unexpected provider error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - OllamaWorkflowFixtureTransport

private actor OllamaWorkflowFixtureTransport: AssistantHTTPTransport {
    // MARK: Lifecycle

    init(versionData: Data = Data(#"{"version":"0.9.6"}"#.utf8)) {
        self.versionData = versionData
    }

    // MARK: Internal

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = try record(request)
        let data: Data
        switch path {
        case "/api/version":
            data = versionData
        case "/api/tags":
            data = Data(
                #"{"models":[{"name":"qwen3:4b","size":2500000000,"details":{"parameter_size":"4.0B","quantization_level":"Q4_K_M"}}]}"#.utf8
            )
        case "/api/delete":
            data = Data()
        default:
            throw AssistantProviderError.invalidEndpoint
        }
        return (data, response(for: request))
    }

    func lines(for request: URLRequest) async throws -> AssistantHTTPStream {
        let path = try record(request)
        let values: [String]
        switch path {
        case "/api/pull":
            values = [
                #"{"status":"pulling manifest"}"#,
                #"{"status":"downloading","completed":50,"total":100}"#,
                #"{"status":"success"}"#,
            ]
        case "/api/chat":
            values = [
                #"{"message":{"role":"assistant","content":"The upstream timed out."},"done":false}"#,
                #"{"message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":12,"eval_count":5}"#,
            ]
        default:
            throw AssistantProviderError.invalidEndpoint
        }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for value in values {
                continuation.yield(value)
            }
            continuation.finish()
        }
        return AssistantHTTPStream(response: response(for: request), lines: stream)
    }

    func requestPaths() -> [String] {
        requests.compactMap { $0.url?.path }
    }

    // MARK: Private

    private let versionData: Data
    private var requests: [URLRequest] = []

    private func record(_ request: URLRequest) throws -> String {
        requests.append(request)
        guard let path = request.url?.path else {
            throw AssistantProviderError.invalidEndpoint
        }
        return path
    }

    private func response(for request: URLRequest) -> HTTPURLResponse {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/2",
                  headerFields: nil
              ) else
        {
            preconditionFailure("Fixture response must remain valid")
        }
        return response
    }
}
