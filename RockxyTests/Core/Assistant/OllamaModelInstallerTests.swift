import Foundation
@testable import Rockxy
import Testing

// MARK: - OllamaModelInstallerTests

struct OllamaModelInstallerTests {
    @Test("Ollama pull streams progress and requires an explicit success event")
    func pullFixture() async throws {
        let transport = OllamaPullFixtureTransport(lines: [
            #"{"status":"pulling manifest"}"#,
            #"{"status":"downloading","completed":25,"total":100}"#,
            #"{"status":"success"}"#,
        ])
        let installer = OllamaModelInstaller(transport: transport)

        var events: [AssistantModelInstallEvent] = []
        for try await event in try installer.install(
            modelID: "qwen3:4b",
            baseURL: #require(URL(string: "http://127.0.0.1:11434/v1"))
        ) {
            events.append(event)
        }

        #expect(events == [
            .status("pulling manifest"),
            .progress(completed: 25, total: 100),
            .completed,
        ])
        let request = try #require(await transport.lastRequest())
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/pull")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "qwen3:4b")
        #expect(object["stream"] as? Bool == true)
    }

    @Test("Truncated Ollama pull is rejected")
    func truncatedPull() async throws {
        let installer = OllamaModelInstaller(transport: OllamaPullFixtureTransport(lines: [
            #"{"status":"downloading","completed":25,"total":100}"#,
        ]))

        do {
            for try await _ in try installer.install(
                modelID: "fixture",
                baseURL: #require(URL(string: "http://127.0.0.1:11434"))
            ) {}
            Issue.record("Expected truncated download error")
        } catch let error as AssistantProviderError {
            guard case .malformedResponse = error else {
                Issue.record("Unexpected provider error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Ollama pull provider errors remain visible")
    func providerError() async throws {
        let installer = OllamaModelInstaller(transport: OllamaPullFixtureTransport(lines: [
            #"{"error":"model is not available"}"#,
        ]))

        do {
            for try await _ in try installer.install(
                modelID: "missing",
                baseURL: #require(URL(string: "http://127.0.0.1:11434"))
            ) {}
            Issue.record("Expected validation error")
        } catch let error as AssistantProviderError {
            #expect(error == .validation("model is not available"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Ollama delete uses the native model lifecycle endpoint")
    func deleteFixture() async throws {
        let transport = OllamaPullFixtureTransport(lines: [])
        let installer = OllamaModelInstaller(transport: transport)

        try await installer.remove(
            modelID: "registry.example/model:4b",
            baseURL: #require(URL(string: "http://127.0.0.1:11434/v1"))
        )

        let request = try #require(await transport.lastRequest())
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/delete")
        #expect(request.httpMethod == "DELETE")
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "registry.example/model:4b")
    }

    @Test("Ollama rejects unsafe model identifiers before network access")
    func invalidModelID() async throws {
        let installer = OllamaModelInstaller(transport: OllamaPullFixtureTransport(lines: []))

        do {
            for try await _ in try installer.install(
                modelID: "../unsafe\nmodel",
                baseURL: #require(URL(string: "http://127.0.0.1:11434"))
            ) {}
            Issue.record("Expected invalid model ID error")
        } catch let error as AssistantProviderError {
            #expect(error == .validation("The local model ID is invalid"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - OllamaPullFixtureTransport

private actor OllamaPullFixtureTransport: AssistantHTTPTransport {
    // MARK: Lifecycle

    init(lines: [String], status: Int = 200) {
        fixtureLines = lines
        self.status = status
    }

    // MARK: Internal

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard let url = request.url else {
            throw AssistantProviderError.invalidEndpoint
        }
        return (Data(), response(url: url))
    }

    func lines(for request: URLRequest) async throws -> AssistantHTTPStream {
        requests.append(request)
        guard let url = request.url else {
            throw AssistantProviderError.invalidEndpoint
        }
        let fixtureLines = fixtureLines
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in fixtureLines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return AssistantHTTPStream(response: response(url: url), lines: stream)
    }

    func lastRequest() -> URLRequest? {
        requests.last
    }

    // MARK: Private

    private let fixtureLines: [String]
    private let status: Int
    private var requests: [URLRequest] = []

    private func response(url: URL) -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/2",
            headerFields: nil
        ) else {
            preconditionFailure("Fixture response must remain valid")
        }
        return response
    }
}
