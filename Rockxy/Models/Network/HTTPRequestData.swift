import Foundation

private func boundedBodyOmissionReason(_ value: String) -> String {
    var bytes = Array(value.filter { $0.isASCII && !$0.isNewline }.utf8.prefix(128))
    while !bytes.isEmpty {
        if let reason = String(bytes: bytes, encoding: .utf8) {
            return reason
        }
        bytes.removeLast()
    }
    return ""
}

// MARK: - BodyOmissionMetadata

struct BodyOmissionMetadata: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    init(reason: String, observedBytes: Int, originalBytes: Int?) {
        self.reason = boundedBodyOmissionReason(reason)
        self.observedBytes = observedBytes
        self.originalBytes = originalBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawReason = try container.decode(String.self, forKey: .reason)
        let reason = boundedBodyOmissionReason(rawReason)
        let observedBytes = try container.decode(Int.self, forKey: .observedBytes)
        let originalBytes = try container.decodeIfPresent(Int.self, forKey: .originalBytes)
        guard !reason.isEmpty,
              observedBytes >= 0,
              observedBytes <= 1_000_000_000,
              originalBytes.map({ $0 >= observedBytes && $0 <= 1_000_000_000 }) ?? true else
        {
            throw DecodingError.dataCorruptedError(
                forKey: .observedBytes,
                in: container,
                debugDescription: "Invalid Babylon body omission metadata."
            )
        }
        self.reason = reason
        self.observedBytes = observedBytes
        self.originalBytes = originalBytes
    }

    // MARK: Internal

    let reason: String
    let observedBytes: Int
    let originalBytes: Int?

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case reason
        case observedBytes
        case originalBytes
    }
}

// Defines `HTTPRequestData`, the model for http request data used by proxy, storage, and
// inspection flows.

// MARK: - HTTPRequestData

/// Captured HTTP request data including method, URL, headers, and optional body.
/// This is a value type snapshot — mutating headers or body creates a modified copy
/// used by the rule engine (breakpoint editing) and request replay.
struct HTTPRequestData: Sendable {
    // MARK: Lifecycle

    init(
        method: String,
        url: URL,
        httpVersion: String,
        headers: [HTTPHeader],
        body: Data? = nil,
        bodyTruncated: Bool = false,
        bodyOmission: BodyOmissionMetadata? = nil,
        contentType: ContentType? = nil,
        captureContext: TrafficCaptureContext? = nil,
        flowID: UUID = UUID()
    ) {
        self.method = method
        self.url = url
        self.httpVersion = httpVersion
        self.headers = headers
        self.body = body
        self.bodyTruncated = bodyTruncated
        self.bodyOmission = bodyOmission
        self.contentType = contentType
        self.captureContext = captureContext
        self.flowID = flowID
    }

    // MARK: Internal

    let method: String
    let url: URL
    let httpVersion: String
    var headers: [HTTPHeader]
    var body: Data?
    /// True when the producing client observed a body but omitted it from the capture.
    var bodyTruncated: Bool
    var bodyOmission: BodyOmissionMetadata?

    var contentType: ContentType?
    /// Logical Project/session ownership captured at request start. It is runtime
    /// routing metadata and is deliberately excluded from HAR/session serializers.
    let captureContext: TrafficCaptureContext?
    /// Identifies one client exchange across the request and response phases so
    /// script state set in `onRequest` is visible to the same flow's `onResponse`.
    /// Runtime-only: rebuilt copies of a request carry it forward; serializers ignore it.
    let flowID: UUID

    var isBodyIncomplete: Bool {
        bodyTruncated || bodyOmission != nil
    }

    var host: String {
        url.host() ?? ""
    }

    var path: String {
        url.path()
    }

    var cookies: [HTTPCookie] {
        guard let headerValue = headers.first(where: { $0.name.lowercased() == "cookie" })?.value else {
            return []
        }
        return HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": headerValue],
            for: url
        )
    }
}

// MARK: - HTTPHeader

/// A single HTTP header name-value pair, used in both requests and responses.
struct HTTPHeader: Equatable, Sendable, Codable {
    let name: String
    let value: String
}
