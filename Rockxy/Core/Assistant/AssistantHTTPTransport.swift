import Foundation

// MARK: - AssistantHTTPStream

struct AssistantHTTPStream {
    let response: HTTPURLResponse
    let lines: AsyncThrowingStream<String, Error>
}

// MARK: - AssistantHTTPTransport

protocol AssistantHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func lines(for request: URLRequest) async throws -> AssistantHTTPStream
}

// MARK: - URLSessionAssistantHTTPTransport

final class URLSessionAssistantHTTPTransport: AssistantHTTPTransport, @unchecked Sendable {
    // MARK: Lifecycle

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Internal

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AssistantProviderError.malformedResponse("Missing HTTP response metadata")
        }
        return (data, response)
    }

    func lines(for request: URLRequest) async throws -> AssistantHTTPStream {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AssistantProviderError.malformedResponse("Missing HTTP response metadata")
        }
        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AssistantProviderError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return AssistantHTTPStream(response: response, lines: lines)
    }

    // MARK: Private

    private let session: URLSession
}

// MARK: - AssistantHTTPErrorMapper

enum AssistantHTTPErrorMapper {
    // MARK: Internal

    static func error(
        response: HTTPURLResponse,
        body: Data,
        model: String
    )
        -> AssistantProviderError
    {
        let detail = providerMessage(from: body)
        let code = providerCode(from: body)
        switch response.statusCode {
        case 400,
             409,
             422:
            if code == "model_not_found" {
                return .modelNotFound(model)
            }
            return .validation(detail)
        case 401:
            return .authentication
        case 403:
            return .permission
        case 404:
            if code == "model_not_found" || detail.localizedCaseInsensitiveContains("model") {
                return .modelNotFound(model)
            }
            return .server(statusCode: 404, message: detail)
        case 429:
            return .rateLimited(retryAfterSeconds: retryAfterSeconds(response))
        case 500 ... 599:
            return .server(statusCode: response.statusCode, message: detail)
        default:
            return .server(statusCode: response.statusCode, message: detail)
        }
    }

    static func translated(_ error: Error) -> Error {
        if error is CancellationError || Task.isCancelled {
            return AssistantProviderError.cancelled
        }
        if let error = error as? AssistantProviderError {
            return error
        }
        if let error = error as? URLError {
            if error.code == .timedOut {
                return AssistantProviderError.timedOut
            }
            if error.code == .cancelled {
                return AssistantProviderError.cancelled
            }
            return AssistantProviderError.network(error.localizedDescription)
        }
        return AssistantProviderError.network(error.localizedDescription)
    }

    static func boundedBody(from lines: AsyncThrowingStream<String, Error>, limit: Int = 8_192) async -> Data {
        var data = Data()
        do {
            for try await line in lines {
                let bytes = Data((line + "\n").utf8)
                let remaining = max(0, limit - data.count)
                data.append(bytes.prefix(remaining))
                if data.count >= limit {
                    break
                }
            }
        } catch {
            return data
        }
        return data
    }

    // MARK: Private

    private static func providerMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data.prefix(1_024), encoding: .utf8) ?? "Unknown provider error"
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return String(message.prefix(1_024))
        }
        if let message = object["message"] as? String {
            return String(message.prefix(1_024))
        }
        return "Unknown provider error"
    }

    private static func providerCode(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else
        {
            return nil
        }
        return error["code"] as? String
    }

    private static func retryAfterSeconds(_ response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        return Int(value)
    }
}
