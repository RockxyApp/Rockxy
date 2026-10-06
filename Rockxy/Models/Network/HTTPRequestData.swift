import Foundation

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
        contentType: ContentType? = nil,
        captureContext: TrafficCaptureContext? = nil,
        flowID: UUID = UUID()
    ) {
        self.method = method
        self.url = url
        self.httpVersion = httpVersion
        self.headers = headers
        self.body = body
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
    var contentType: ContentType?
    /// Logical Project/session ownership captured at request start. It is runtime
    /// routing metadata and is deliberately excluded from HAR/session serializers.
    let captureContext: TrafficCaptureContext?
    /// Identifies one client exchange across the request and response phases so
    /// script state set in `onRequest` is visible to the same flow's `onResponse`.
    /// Runtime-only: rebuilt copies of a request carry it forward; serializers ignore it.
    let flowID: UUID

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
