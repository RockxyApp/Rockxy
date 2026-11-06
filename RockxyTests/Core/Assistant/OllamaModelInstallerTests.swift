import Foundation
@testable import Rockxy
import Testing

// MARK: - OllamaModelInstallerTests

struct OllamaModelInstallerTests {
    @Test("Curated catalog spans independent local model families")
    func curatedCatalog() {
        let models = AssistantDownloadableModel.recommended

        #expect(Set(models.map(\.family)) == [
            "Qwen",
            "Llama",
            "Gemma",
            "DeepSeek",
        ])
        #expect(Set(models.map(\.id)).count == models.count)
        #expect(models.allSatisfy { ($0.approximateDownloadBytes ?? 0) > 0 })
        #expect(models.allSatisfy { ($0.recommendedUnifiedMemoryBytes ?? 0) > 0 })
        #expect(models.allSatisfy { !$0.roles.isEmpty })
        #expect(models.allSatisfy { !OllamaAssistantProvider.denotesCloudModel(id: $0.id) })
    }

    @Test("Curated catalog covers every role and includes at most one 30B-class model")
    func curatedCatalogRoles() {
        let models = AssistantDownloadableModel.recommended

        for role in AssistantLocalModelRole.allCases {
            #expect(!AssistantDownloadableModel.models(models, withRole: role).isEmpty, "Missing role \(role)")
        }
        let gibibyte: Int64 = 1_024 * 1_024 * 1_024
        let large = models.filter { ($0.approximateDownloadBytes ?? 0) >= 15_000_000_000 }
        #expect(large.count == 1)
        #expect(large.first?.id == "qwen3-coder:30b")
        #expect(large.first?.recommendedUnifiedMemoryBytes == 32 * gibibyte)

        let lowMemory = AssistantDownloadableModel.models(models, withRole: .lowMemory)
        #expect(lowMemory.allSatisfy { ($0.recommendedUnifiedMemoryBytes ?? .max) <= 8 * gibibyte })
    }

    @Test("Role filtering preserves catalog order and matches only tagged models")
    func roleFiltering() {
        let coding = AssistantDownloadableModel(
            id: "coder:7b",
            name: "Coder",
            roles: [.coding],
            detail: "fixture"
        )
        let balanced = AssistantDownloadableModel(
            id: "chat:4b",
            name: "Chat",
            roles: [.balanced, .lowMemory],
            detail: "fixture"
        )
        let untagged = AssistantDownloadableModel(id: "custom", name: "Custom", detail: "fixture")
        let models = [coding, balanced, untagged]

        #expect(AssistantDownloadableModel.models(models, withRole: .coding) == [coding])
        #expect(AssistantDownloadableModel.models(models, withRole: .lowMemory) == [balanced])
        #expect(AssistantDownloadableModel.models(models, withRole: .reasoning).isEmpty)
    }

    @Test("Hardware fit classifies physical memory against the recommendation")
    func hardwareFit() {
        let gibibyte: Int64 = 1_024 * 1_024 * 1_024
        let sixteen = 16 * gibibyte

        #expect(AssistantDownloadableModel.hardwareFit(
            recommendedUnifiedMemoryBytes: sixteen,
            physicalMemoryBytes: UInt64(16 * gibibyte)
        ) == .recommended)
        #expect(AssistantDownloadableModel.hardwareFit(
            recommendedUnifiedMemoryBytes: sixteen,
            physicalMemoryBytes: UInt64(24 * gibibyte)
        ) == .recommended)
        #expect(AssistantDownloadableModel.hardwareFit(
            recommendedUnifiedMemoryBytes: sixteen,
            physicalMemoryBytes: UInt64(12 * gibibyte)
        ) == .tight)
        #expect(AssistantDownloadableModel.hardwareFit(
            recommendedUnifiedMemoryBytes: sixteen,
            physicalMemoryBytes: UInt64(8 * gibibyte)
        ) == .exceedsMemory)
        #expect(AssistantDownloadableModel.hardwareFit(
            recommendedUnifiedMemoryBytes: nil,
            physicalMemoryBytes: UInt64(8 * gibibyte)
        ) == .unknown)
        #expect(AssistantDownloadableModel.hardwareFit(
            recommendedUnifiedMemoryBytes: 0,
            physicalMemoryBytes: UInt64(8 * gibibyte)
        ) == .unknown)

        let model = AssistantDownloadableModel(
            id: "fixture:30b",
            name: "Fixture",
            recommendedUnifiedMemoryBytes: 32 * gibibyte,
            detail: "fixture"
        )
        #expect(model.hardwareFit(physicalMemoryBytes: UInt64(24 * gibibyte)) == .tight)
        #expect(model.hardwareFit(physicalMemoryBytes: UInt64(64 * gibibyte)) == .recommended)
    }

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

    @Test("A malformed Ollama pull line is reported instead of being skipped")
    func malformedPullLine() async throws {
        let installer = OllamaModelInstaller(transport: OllamaPullFixtureTransport(lines: [
            #"{"status":"pulling manifest"}"#,
            "not json",
            #"{"status":"success"}"#,
        ]))

        do {
            for try await _ in try installer.install(
                modelID: "fixture",
                baseURL: #require(URL(string: "http://127.0.0.1:11434"))
            ) {}
            Issue.record("Expected malformed response error")
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
