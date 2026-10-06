import Foundation

/// Captured HTTP response data including status code, headers, and optional body.
/// Provides convenience accessors for cookie parsing and status code classification
/// used by the inspector UI and protocol filters.
struct HTTPResponseData: Sendable {
    let statusCode: Int
    let statusMessage: String
    var headers: [HTTPHeader]
    var body: Data?
    var bodyTruncated: Bool = false
    /// Headers sent after the body, such as gRPC's `grpc-status`; nil when none were sent.
    var trailers: [HTTPHeader]?
    var contentType: ContentType?

    var setCookies: [HTTPCookie] {
        let headerFields = Dictionary(
            headers.filter { $0.name.lowercased() == "set-cookie" }
                .map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        let localhostURL = URL(string: "https://localhost")!
        return HTTPCookie.cookies(
            withResponseHeaderFields: headerFields,
            for: localhostURL
        )
    }

    var isSuccess: Bool {
        (200 ..< 300).contains(statusCode)
    }

    var isRedirect: Bool {
        (300 ..< 400).contains(statusCode)
    }

    var isClientError: Bool {
        (400 ..< 500).contains(statusCode)
    }

    var isServerError: Bool {
        (500 ..< 600).contains(statusCode)
    }
}

// MARK: - HTTPReasonPhrase

/// Standard HTTP reason phrases for responses Rockxy produces itself (replay, Compose,
/// Nearby, Babylon) instead of reading them off the wire.
/// `HTTPURLResponse.localizedString(forStatusCode:)` returns CFNetwork error wording
/// ("no error" for 200), which reads wrong next to proxy-captured rows.
enum HTTPReasonPhrase {
    static func standard(for statusCode: Int) -> String {
        switch statusCode {
        case 100: "Continue"
        case 101: "Switching Protocols"
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 204: "No Content"
        case 206: "Partial Content"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 303: "See Other"
        case 304: "Not Modified"
        case 307: "Temporary Redirect"
        case 308: "Permanent Redirect"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 408: "Request Timeout"
        case 409: "Conflict"
        case 410: "Gone"
        case 413: "Payload Too Large"
        case 415: "Unsupported Media Type"
        case 422: "Unprocessable Content"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        case 504: "Gateway Timeout"
        default: HTTPURLResponse.localizedString(forStatusCode: statusCode).localizedCapitalized
        }
    }
}
