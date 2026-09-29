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
    }

    /// Builds a NIO request head and `HTTPRequestData` from the user-modified breakpoint
    /// snapshot, falling back to the original request's authority when the edited URL is
    /// origin-form (path-only) or when the HTTPS tunnel requires a fixed host.
    ///
    /// - Parameters:
    ///   - modifiedData: The snapshot edited by the user in the breakpoint sheet.
    ///   - originalHead: The original NIO request head captured before the breakpoint.
    ///   - originalRequestData: The original `HTTPRequestData` with a fully-qualified URL.
    ///   - isHTTPS: Whether the request is on an HTTPS tunnel (forces original host).
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
        if let parsed = URL(string: modifiedData.url), parsed.host != nil {
            if isHTTPS, let host = originalHost {
                // Force the tunnel host even if the user typed a different absolute URL
                var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false) ?? URLComponents()
                components.scheme = "https"
                components.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                components.port = originalPort
                editedURL = components.url ?? originalRequestData.url
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

        // 1b. Force original scheme for non-HTTPS — the user can type "https://" but the
        // transport is cleartext, so the scheme must match the actual connection.
        if !isHTTPS, let originalScheme = originalRequestData.url.scheme {
            var components = URLComponents(url: editedURL, resolvingAgainstBaseURL: false)
                ?? URLComponents()
            if components.scheme != originalScheme {
                components.scheme = originalScheme
                editedURL = components.url ?? editedURL
            }
        }

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

        // 3. For HTTPS, pin the Host header to the tunnel authority
        if isHTTPS, let host = originalHost {
            let authority = ProxyHandlerShared.authority(host: host, port: originalPort, scheme: "https")
            resolvedHeaders.removeAll {
                $0.name.caseInsensitiveCompare("Host") == .orderedSame
            }
            resolvedHeaders.append(HTTPHeader(name: "Host", value: authority))
        } else if !isHTTPS {
            // For plain HTTP, reconcile the Host header with the edited URL authority.
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
        if isHTTPS, let host = originalHost {
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

        return Result(head: head, requestData: requestData)
    }

    // MARK: Private

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
