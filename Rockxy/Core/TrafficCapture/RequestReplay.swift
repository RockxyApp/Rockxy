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

    /// A session that sends through Rockxy's own listener, so active rules (Breakpoint,
    /// Map Local, Map Remote, Block, Scripting, Modify Headers) apply and the proxy records
    /// the request itself. Cookie handling matches the bypass session.
    static func configurationThroughProxy(port: Int) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPSPort as String: port,
        ]
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        return config
    }

    /// Re-sends `request` directly to the origin, or through Rockxy's listener on
    /// `throughProxyPort` so the request goes through the active rules.
    static func replay(_ request: HTTPRequestData, throughProxyPort: Int? = nil) async throws -> HTTPResponseData {
        logger.info("Replaying request: \(request.method) \(request.url.absoluteString)")

        let urlRequest = makeURLRequest(from: request)

        let responses = BoundedComposeRequestOperation.responses(
            for: urlRequest,
            configuration: throughProxyPort.map(configurationThroughProxy(port:)) ?? proxyBypassSession.configuration,
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
            statusMessage: HTTPReasonPhrase.standard(for: httpResponse.statusCode),
            headers: headers,
            body: data,
            contentType: ContentType.detect(from: httpResponse.value(forHTTPHeaderField: "Content-Type"))
        )
    }

    static func makeURLRequest(from request: HTTPRequestData) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for header in request.headers where !isTransportManagedHeader(header.name) {
            urlRequest.addValue(header.value, forHTTPHeaderField: header.name)
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    /// Headers the transport derives itself when a captured request is re-sent directly to the
    /// origin. `Host` and `Content-Length` come from the URL and body (a copied `Host` would
    /// otherwise survive a URL edit and hit the wrong virtual host), and the `Proxy-*` hop
    /// headers only meant something between the client and Rockxy. HTTP/2 pseudo-headers
    /// (`:authority`, `:path`, ...) from an imported capture are never valid header fields.
    static func isTransportManagedHeader(_ name: String) -> Bool {
        name.hasPrefix(":") || Self.transportManagedHeaders.contains(name.lowercased())
    }

    private static let transportManagedHeaders: Set<String> = [
        "host",
        "content-length",
        "proxy-connection",
        "proxy-authorization",
    ]

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "RequestReplay")
}

// MARK: - ReplayError

/// Errors that can occur during request replay.
enum ReplayError: LocalizedError {
    case invalidResponse

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(
                localized: "The server closed the connection without sending a response.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

// MARK: - ReplayFailureReason

/// Turns a replay failure into a short sentence a person can act on, instead of the generic
/// "The operation couldn't be completed" text Foundation produces for many network errors.
enum ReplayFailureReason {
    static func message(for error: Error, host: String?) -> String {
        if let urlError = error as? URLError {
            return message(for: urlError, host: host)
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    // MARK: Private

    private static func message(for error: URLError, host: String?) -> String {
        let server = host ?? String(localized: "the server", bundle: RockxyLocalization.bundle)
        switch error.code {
        case .timedOut:
            return String(localized: "The request to \(server) timed out.", bundle: RockxyLocalization.bundle)
        case .cannotFindHost,
             .dnsLookupFailed:
            return String(localized: "Couldn't find \(server). Check the host name.", bundle: RockxyLocalization.bundle)
        case .cannotConnectToHost:
            return String(
                localized: "Couldn't connect to \(server). It may be down or refusing connections.",
                bundle: RockxyLocalization.bundle
            )
        case .networkConnectionLost:
            return String(
                localized: "The connection to \(server) was lost before the response finished.",
                bundle: RockxyLocalization.bundle
            )
        case .notConnectedToInternet:
            return String(localized: "This Mac is offline.", bundle: RockxyLocalization.bundle)
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return String(
                localized: "A secure connection to \(server) couldn't be established.",
                bundle: RockxyLocalization.bundle
            )
        case .badServerResponse,
             .zeroByteResource,
             .cannotParseResponse:
            return String(
                localized: "The response from \(server) couldn't be read.",
                bundle: RockxyLocalization.bundle
            )
        case .unsupportedURL,
             .badURL:
            return String(localized: "The request URL isn't valid.", bundle: RockxyLocalization.bundle)
        default:
            return error.localizedDescription
        }
    }
}
