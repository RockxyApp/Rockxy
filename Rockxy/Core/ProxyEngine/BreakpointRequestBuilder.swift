import Foundation
import NIOHTTP1

// Defines `BreakpointRequestBuilder`, which builds breakpoint request values for the proxy
// engine.

// MARK: - BreakpointRequestBuilder

/// Centralises the logic for rebuilding an HTTP request from user-edited breakpoint data.
/// Extracted from `HTTPProxyHandler` and `HTTPSProxyRelayHandler` so the URL-reconstruction
/// and host-pinning behaviour can be unit-tested without a live NIO pipeline.
enum BreakpointRequestBuilder {
    // MARK: Internal

    struct Result {
        let head: HTTPRequestHead
        let requestData: HTTPRequestData
        /// Set when an HTTPS request was edited to a different scheme, host, or port. The
        /// tunnel's upstream connection cannot serve it, so the relay opens a new one there.
        let upstreamRedirect: UpstreamRedirect?
    }

    struct UpstreamRedirect: Equatable {
        let scheme: String
        let host: String
        let port: Int?

        /// Connects to the new server while keeping the edited path, query, and Host header.
        var mapRemoteConfiguration: MapRemoteConfiguration {
            MapRemoteConfiguration(
                scheme: scheme,
                host: host,
                port: port,
                preserveOriginalURL: true,
                preserveHostHeader: true
            )
        }
    }

    /// Builds a NIO request head and `HTTPRequestData` from the user-modified breakpoint
    /// snapshot. An origin-form (path-only) edit keeps the original authority; an absolute
    /// URL may change the scheme, host, and port, which sends the request to that server.
    ///
    /// - Parameters:
    ///   - modifiedData: The snapshot edited by the user in the breakpoint sheet.
    ///   - originalHead: The original NIO request head captured before the breakpoint.
    ///   - originalRequestData: The original `HTTPRequestData` with a fully-qualified URL.
    ///   - isHTTPS: Whether the request arrived on a decrypted HTTPS tunnel.
    ///   - originalHost: The CONNECT-tunnel host for HTTPS; ignored for plain HTTP.
    static func build(
        from modifiedData: BreakpointRequestData,
        originalHead: HTTPRequestHead,
        originalRequestData: HTTPRequestData,
        isHTTPS: Bool = false,
        originalHost: String? = nil,
        originalPort: Int? = nil
    )
        -> Result
    {
        // 1. Resolve URL — preserve original authority for origin-form edits
        var editedURL: URL
        var upstreamRedirect: UpstreamRedirect?
        if let parsed = URL(string: modifiedData.url), parsed.host != nil,
           let editedScheme = parsed.scheme?.lowercased(), editedScheme == "http" || editedScheme == "https"
        {
            if isHTTPS, let host = originalHost {
                upstreamRedirect = redirect(
                    for: parsed,
                    scheme: editedScheme,
                    tunnelScheme: originalRequestData.url.scheme?.lowercased() ?? "https",
                    tunnelHost: host,
                    tunnelPort: originalPort
                )
                if upstreamRedirect == nil {
                    // Same server: keep the tunnel's exact authority spelling.
                    var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false) ?? URLComponents()
                    components.scheme = editedScheme
                    components.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    components.port = originalPort
                    editedURL = components.url ?? originalRequestData.url
                } else {
                    editedURL = parsed
                }
            } else {
                editedURL = parsed
            }
        } else {
            // Path-only (origin-form) — rebuild against original host
            var components = URLComponents(
                url: originalRequestData.url,
                resolvingAgainstBaseURL: false
            ) ?? URLComponents()
            let pathQuery = modifiedData.url
            let parts = pathQuery.split(separator: "?", maxSplits: 1)
            components.path = parts.first.map { String($0) } ?? "/"
            if !components.path.hasPrefix("/") {
                components.path = "/" + components.path
            }
            components.query = parts.count > 1 ? String(parts[1]) : nil
            editedURL = components.url ?? originalRequestData.url
        }

        let pinsTunnelAuthority = isHTTPS && upstreamRedirect == nil

        // 2. Build headers from the edited list
        var resolvedHeaders = modifiedData.headers.compactMap { header -> HTTPHeader? in
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard BreakpointRequestData.isValidHTTPHeaderName(name),
                  BreakpointRequestData.isValidHTTPHeaderValue(header.value) else
            {
                return nil
            }
            return HTTPHeader(name: name, value: header.value)
        }

        // 3. For HTTPS to the same server, pin the Host header to the tunnel authority
        if pinsTunnelAuthority, let host = originalHost {
            let authority = ProxyHandlerShared.authority(host: host, port: originalPort, scheme: "https")
            resolvedHeaders.removeAll {
                $0.name.caseInsensitiveCompare("Host") == .orderedSame
            }
            resolvedHeaders.append(HTTPHeader(name: "Host", value: authority))
        } else {
            // Otherwise reconcile the Host header with the edited URL authority.
            // An untouched original Host (still pointing at the original authority) must
            // follow the edited URL — including a non-default explicit port — so a URL
            // redirect actually reaches the new origin. A Host the user deliberately
            // changed to something other than the original is a virtual-host override and
            // is preserved. An absent Host is added from the edited authority.
            reconcilePlainHTTPHost(
                in: &resolvedHeaders,
                editedURL: editedURL,
                originalRequestData: originalRequestData
            )
        }

        // 4. Build body
        let body: Data? = if modifiedData.isBodyEditable {
            modifiedData.body.isEmpty ? nil : modifiedData.body.data(using: .utf8)
        } else {
            originalRequestData.body
        }

        // 5. Reconcile Content-Length and Transfer-Encoding with the actual body
        if let body, !body.isEmpty {
            resolvedHeaders.removeAll {
                $0.name.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame
                    || $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame
            }
            resolvedHeaders.append(HTTPHeader(name: "Content-Length", value: "\(body.count)"))
        } else {
            resolvedHeaders.removeAll {
                $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame
                    || $0.name.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame
            }
        }

        // 6. Build NIO head
        var head = originalHead
        head.method = HTTPMethod(rawValue: modifiedData.method)
        let encodedComponents = URLComponents(url: editedURL, resolvingAgainstBaseURL: false)
        let encodedPath = encodedComponents?.percentEncodedPath ?? editedURL.path
        let pathComponent = encodedPath.isEmpty ? "/" : encodedPath
        let queryComponent = encodedComponents?.percentEncodedQuery.map { "?\($0)" } ?? ""
        head.uri = pathComponent + queryComponent
        head.headers = HTTPHeaders(resolvedHeaders.map { ($0.name, $0.value) })
        if pinsTunnelAuthority, let host = originalHost {
            head.headers.replaceOrAdd(
                name: "Host",
                value: ProxyHandlerShared.authority(host: host, port: originalPort, scheme: "https")
            )
        }

        // 7. Build request data
        let requestData = HTTPRequestData(
            method: modifiedData.method,
            url: editedURL,
            httpVersion: originalRequestData.httpVersion,
            headers: resolvedHeaders,
            body: body,
            contentType: ContentTypeDetector.detect(headers: resolvedHeaders, body: body),
            captureContext: originalRequestData.captureContext,
            flowID: originalRequestData.flowID
        )

        return Result(head: head, requestData: requestData, upstreamRedirect: upstreamRedirect)
    }

    // MARK: Private

    /// The new upstream for an HTTPS request whose edited URL names a different scheme,
    /// host, or port than the tunnel, or `nil` when it still targets the tunnel's server.
    private static func redirect(
        for url: URL,
        scheme: String,
        tunnelScheme: String,
        tunnelHost: String,
        tunnelPort: Int?
    )
        -> UpstreamRedirect?
    {
        guard let rawHost = url.host(percentEncoded: false), !rawHost.isEmpty else {
            return nil
        }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let normalizedTunnelHost = tunnelHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let editedPort = url.port ?? (scheme == "https" ? 443 : 80)
        let tunnelEffectivePort = tunnelPort ?? (tunnelScheme == "https" ? 443 : 80)
        if scheme == tunnelScheme,
           host.caseInsensitiveCompare(normalizedTunnelHost) == .orderedSame,
           editedPort == tunnelEffectivePort
        {
            return nil
        }
        return UpstreamRedirect(scheme: scheme, host: host, port: url.port)
    }

    /// Reconciles the Host header of a plain-HTTP request with the edited URL authority.
    /// See the call site for the untouched-vs-override policy.
    private static func reconcilePlainHTTPHost(
        in headers: inout [HTTPHeader],
        editedURL: URL,
        originalRequestData: HTTPRequestData
    ) {
        guard let editedAuthority = authority(for: editedURL) else {
            return
        }

        let originalAuthority = headerHost(in: originalRequestData.headers)
            ?? authority(for: originalRequestData.url)

        let currentHost = headers.first {
            $0.name.caseInsensitiveCompare("Host") == .orderedSame
        }?.value.trimmingCharacters(in: .whitespaces)
        let isUntouched = originalAuthority.map {
            currentHost?.caseInsensitiveCompare($0) == .orderedSame
        } ?? (currentHost?.isEmpty ?? true)
        let resolvedHost = isUntouched ? editedAuthority : currentHost ?? editedAuthority

        // Host is a singleton routing field. Keeping multiple user-entered values
        // would make the captured request disagree with what an upstream parser uses.
        headers.removeAll {
            $0.name.caseInsensitiveCompare("Host") == .orderedSame
        }
        headers.append(HTTPHeader(name: "Host", value: resolvedHost))
    }

    /// The `host[:port]` authority for a URL, omitting the default port for its scheme.
    private static func authority(for url: URL) -> String? {
        guard let rawHost = url.host, !rawHost.isEmpty else {
            return nil
        }
        let host = rawHost.contains(":") && !rawHost.hasPrefix("[") ? "[\(rawHost)]" : rawHost
        guard let port = url.port, !isDefaultPort(port, scheme: url.scheme) else {
            return host
        }
        return "\(host):\(port)"
    }

    private static func headerHost(in headers: [HTTPHeader]) -> String? {
        headers.first {
            $0.name.caseInsensitiveCompare("Host") == .orderedSame
        }?.value.trimmingCharacters(in: .whitespaces)
    }

    private static func isDefaultPort(_ port: Int, scheme: String?) -> Bool {
        switch scheme?.lowercased() {
        case "http":
            port == 80
        case "https":
            port == 443
        default:
            false
        }
    }
}
