import Foundation

// MARK: - OllamaRuntimeInfo

struct OllamaRuntimeInfo: Equatable, Sendable {
    let version: String
}

// MARK: - OllamaRuntimeChecking

protocol OllamaRuntimeChecking: Sendable {
    func check(baseURL: URL) async throws -> OllamaRuntimeInfo
}

// MARK: - OllamaRuntimeChecker

struct OllamaRuntimeChecker: OllamaRuntimeChecking {
    // MARK: Lifecycle

    init(transport: any AssistantHTTPTransport) {
        self.transport = transport
    }

    // MARK: Internal

    static let shared = OllamaRuntimeChecker(
        transport: URLSessionAssistantHTTPTransport()
    )

    func check(baseURL: URL) async throws -> OllamaRuntimeInfo {
        var request = URLRequest(url: endpoint("api/version", baseURL: baseURL))
        request.timeoutInterval = Self.connectionTimeout
        do {
            let (data, response) = try await transport.data(for: request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw AssistantHTTPErrorMapper.error(response: response, body: data, model: "")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = object["version"] as? String,
                  !version.isEmpty else
            {
                throw AssistantProviderError.malformedResponse("Ollama returned no runtime version")
            }
            return OllamaRuntimeInfo(version: version)
        } catch {
            throw AssistantHTTPErrorMapper.translated(error)
        }
    }

    // MARK: Private

    private static let connectionTimeout: TimeInterval = 3

    private let transport: any AssistantHTTPTransport

    private func endpoint(_ path: String, baseURL: URL) -> URL {
        var normalized = baseURL
        if normalized.path.hasSuffix("/v1") {
            normalized.deleteLastPathComponent()
        }
        return normalized.appendingPathComponent(path)
    }
}
