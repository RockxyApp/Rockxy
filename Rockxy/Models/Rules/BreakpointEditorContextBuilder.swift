import Foundation

/// Testable helper that builds breakpoint editor context from transaction or domain quick-create entrypoints.
enum BreakpointEditorContextBuilder {
    // MARK: Internal

    static func fromTransaction(_ transaction: HTTPTransaction) -> BreakpointEditorContext {
        let host = transaction.request.host
        let patternHost = wildcardAuthority(for: transaction.request, host: host)
        let normalizedPath = normalizePath(transaction.request.path)
        let method = transaction.request.method.uppercased()

        let httpMethod = HTTPMethodFilter.allCases.first {
            $0.rawValue == method
        } ?? .any

        return BreakpointEditorContext(
            origin: .selectedTransaction,
            suggestedName: "Breakpoint — \(method) \(host)\(normalizedPath)",
            sourceURL: transaction.request.url,
            sourceHost: host,
            sourcePath: normalizedPath,
            sourceMethod: method,
            defaultPattern: "*://\(patternHost)\(normalizedPath)",
            defaultMatchType: .wildcard,
            httpMethod: httpMethod,
            includeSubpaths: false,
            breakpointRequest: true,
            breakpointResponse: true
        )
    }

    static func fromDomain(_ domain: String) -> BreakpointEditorContext {
        let patternHost = wildcardHost(domain)
        return BreakpointEditorContext(
            origin: .domainQuickCreate,
            suggestedName: "Breakpoint — \(domain)",
            sourceURL: nil,
            sourceHost: domain,
            sourcePath: nil,
            sourceMethod: nil,
            defaultPattern: "*://\(patternHost)/*",
            defaultMatchType: .wildcard,
            httpMethod: .any,
            includeSubpaths: false,
            breakpointRequest: true,
            breakpointResponse: true
        )
    }

    // MARK: Private

    private static func normalizePath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }

    private static func wildcardHost(_ host: String) -> String {
        let colonCount = host.count(where: { $0 == ":" })
        guard colonCount > 1, !host.hasPrefix("[") else {
            return host
        }
        return "[\(host)]"
    }

    private static func wildcardAuthority(for request: HTTPRequestData, host: String) -> String {
        let patternHost = wildcardHost(host)
        guard let port = request.url.port ?? explicitHostHeaderPort(in: request.headers, matching: host) else {
            return patternHost
        }
        return "\(patternHost):\(port)"
    }

    /// Some captured absolute-form HTTP requests are normalized before they reach the UI model,
    /// leaving the non-default authority port only in the Host header. Use that port only when
    /// the header's parsed host still matches the URL host; an unrelated or malformed Host value
    /// must never broaden the suggested rule.
    private static func explicitHostHeaderPort(in headers: [HTTPHeader], matching urlHost: String) -> Int? {
        guard let authority = headers.first(where: {
            $0.name.caseInsensitiveCompare("Host") == .orderedSame
        })?.value.trimmingCharacters(in: .whitespacesAndNewlines),
            authorityHasExplicitPort(authority),
            let parsed = try? HostPortParser.parse(authority),
            parsed.host.caseInsensitiveCompare(urlHost) == .orderedSame else
        {
            return nil
        }
        return parsed.port
    }

    private static func authorityHasExplicitPort(_ authority: String) -> Bool {
        if authority.hasPrefix("[") {
            guard let closingBracket = authority.firstIndex(of: "]") else {
                return false
            }
            let suffix = authority[authority.index(after: closingBracket)...]
            return suffix.hasPrefix(":") && suffix.count > 1
        }
        return authority.count(where: { $0 == ":" }) == 1
    }
}
