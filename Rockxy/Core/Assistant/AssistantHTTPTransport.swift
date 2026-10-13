import Foundation

// MARK: - AssistantHTTPStream

struct AssistantHTTPStream {
    let response: HTTPURLResponse
    let lines: AsyncThrowingStream<String, Error>
}

// MARK: - AssistantHTTPTransportLimits

/// Provider-neutral network bounds shared by local and remote model adapters.
/// Individual providers may impose tighter semantic limits after framing, but
/// no adapter can make the transport allocate an unbounded response first.
struct AssistantHTTPTransportLimits: Equatable, Sendable {
    static let `default` = AssistantHTTPTransportLimits()

    var maximumDataBytes = 2 * 1_024 * 1_024
    var maximumStreamLineBytes = 256 * 1_024
    var maximumBufferedLines = 32
}

// MARK: - AssistantHTTPTransport

protocol AssistantHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func lines(for request: URLRequest) async throws -> AssistantHTTPStream
}

// MARK: - URLSessionAssistantHTTPTransport

final class URLSessionAssistantHTTPTransport: AssistantHTTPTransport, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        session: URLSession? = nil,
        limits: AssistantHTTPTransportLimits = .default
    ) {
        self.session = session ?? URLSession(configuration: Self.proxyBypassConfiguration())
        self.limits = limits
    }

    // MARK: Internal

    static func proxyBypassConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
        ]
        return configuration
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AssistantProviderError.malformedResponse("Missing HTTP response metadata")
        }

        if response.expectedContentLength > limits.maximumDataBytes {
            throw AssistantProviderError.malformedResponse(
                "The provider response exceeded Rockxy's \(limits.maximumDataBytes)-byte limit"
            )
        }

        var data = Data()
        data.reserveCapacity(min(
            max(0, Int(response.expectedContentLength)),
            limits.maximumDataBytes
        ))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limits.maximumDataBytes else {
                throw AssistantProviderError.malformedResponse(
                    "The provider response exceeded Rockxy's \(limits.maximumDataBytes)-byte limit"
                )
            }
            data.append(byte)
        }
        return (data, response)
    }

    func lines(for request: URLRequest) async throws -> AssistantHTTPStream {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AssistantProviderError.malformedResponse("Missing HTTP response metadata")
        }
        let lines = AsyncThrowingStream<String, Error>(
            bufferingPolicy: .bufferingOldest(max(1, limits.maximumBufferedLines))
        ) { continuation in
            let task = Task {
                do {
                    var framer = AssistantHTTPLineFramer(
                        maximumLineBytes: limits.maximumStreamLineBytes
                    )
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard let line = try framer.append(byte) else {
                            continue
                        }
                        try Self.yield(line, to: continuation)
                    }
                    if let finalLine = try framer.finish() {
                        try Self.yield(finalLine, to: continuation)
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
    private let limits: AssistantHTTPTransportLimits

    private static func yield(
        _ line: String,
        to continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws {
        switch continuation.yield(line) {
        case .enqueued:
            break
        case .dropped:
            throw AssistantProviderError.malformedResponse(
                "The provider stream produced data faster than Rockxy could safely process it"
            )
        case .terminated:
            throw CancellationError()
        @unknown default:
            throw AssistantProviderError.malformedResponse("The provider stream ended unexpectedly")
        }
    }
}

// MARK: - AssistantHTTPLineFramer

/// Incrementally frames UTF-8 lines without first constructing an unbounded
/// `String`. This is deliberately independent of any provider's SSE/NDJSON
/// grammar so future adapters inherit the same memory boundary.
struct AssistantHTTPLineFramer {
    // MARK: Lifecycle

    init(maximumLineBytes: Int) {
        self.maximumLineBytes = max(1, maximumLineBytes)
    }

    // MARK: Internal

    mutating func append(_ byte: UInt8) throws -> String? {
        guard byte != Self.lineFeed else {
            return try consumeLine()
        }
        guard buffer.count < maximumLineBytes else {
            throw AssistantProviderError.malformedResponse(
                "A provider stream line exceeded Rockxy's \(maximumLineBytes)-byte limit"
            )
        }
        buffer.append(byte)
        return nil
    }

    mutating func finish() throws -> String? {
        guard !buffer.isEmpty else {
            return nil
        }
        return try consumeLine()
    }

    // MARK: Private

    private static let carriageReturn: UInt8 = 0x0D
    private static let lineFeed: UInt8 = 0x0A

    private let maximumLineBytes: Int
    private var buffer = Data()

    private mutating func consumeLine() throws -> String {
        if buffer.last == Self.carriageReturn {
            buffer.removeLast()
        }
        defer {
            buffer.removeAll(keepingCapacity: true)
        }
        guard let line = String(data: buffer, encoding: .utf8) else {
            throw AssistantProviderError.malformedResponse(
                "The provider stream contained invalid UTF-8"
            )
        }
        return line
    }
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
        case 529:
            return .overloaded(retryAfterSeconds: retryAfterSeconds(response))
        case 503 where errorType(from: body) == "overloaded_error" || detail.localizedCaseInsensitiveContains("overloaded"):
            return .overloaded(retryAfterSeconds: retryAfterSeconds(response))
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

    private static func errorType(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else
        {
            return nil
        }
        return error["type"] as? String
    }

    private static func retryAfterSeconds(_ response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        return Int(value)
    }
}
