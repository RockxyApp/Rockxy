import Foundation

/// Captured HTTP response data including status code, headers, and optional body.
/// Provides convenience accessors for cookie parsing and status code classification
/// used by the inspector UI and protocol filters.
struct HTTPResponseData {
    let statusCode: Int
    let statusMessage: String
    var headers: [HTTPHeader]
    var body: Data?
    var bodyTruncated: Bool = false
    var contentType: ContentType?

    var setCookies: [HTTPCookie] {
        let headerFields = Dictionary(
            headers.filter { $0.name.lowercased() == "set-cookie" }
                .map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        // swiftlint:disable:next force_unwrapping
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
