import Foundation
import os

// Replays captured requests while bypassing Rockxy's own proxy configuration.

// MARK: - RequestReplay

/// Re-issues a previously captured HTTP request using `URLSession` and returns the new response.
/// Used by the request replay feature to let developers re-send traffic without leaving the app.
enum RequestReplay {
    // MARK: Internal

    static let proxyBypassSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
        ]
        // A fast replay must depend only on the captured request. Persisting or automatically
        // attaching cookies from an earlier replay makes repeated sends change behind the user's
        // back and can leak one replay's session state into another host flow.
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    static func replay(_ request: HTTPRequestData) async throws -> HTTPResponseData {
        logger.info("Replaying request: \(request.method) \(request.url.absoluteString)")

        let urlRequest = makeURLRequest(from: request)

        let responses = BoundedComposeRequestOperation.responses(
            for: urlRequest,
            configuration: proxyBypassSession.configuration,
            followsRedirects: false,
            maximumBytes: ProxyLimits.maxResponseBodySize
        )
        let data: Data
        let httpResponse: HTTPURLResponse
        if let response = try await responses.first(where: { _ in true }) {
            (data, httpResponse) = response
        } else {
            throw ReplayError.invalidResponse
        }

        let headers = httpResponse.allHeaderFields.compactMap { key, value -> HTTPHeader? in
            guard let name = key as? String, let val = value as? String else {
                return nil
            }
            return HTTPHeader(name: name, value: val)
        }

        return HTTPResponseData(
            statusCode: httpResponse.statusCode,
            statusMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
            headers: headers,
            body: data,
            contentType: ContentType.detect(from: httpResponse.value(forHTTPHeaderField: "Content-Type"))
        )
    }

    static func makeURLRequest(from request: HTTPRequestData) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for header in request.headers {
            urlRequest.addValue(header.value, forHTTPHeaderField: header.name)
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "RequestReplay")
}

// MARK: - ReplayError

/// Errors that can occur during request replay.
enum ReplayError: Error {
    case invalidResponse
}
