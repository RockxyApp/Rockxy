import Foundation

/// Testable helper that builds breakpoint editor context from transaction or domain quick-create entrypoints.
enum BreakpointEditorContextBuilder {
    // MARK: Internal

    static func fromTransaction(_ transaction: HTTPTransaction) -> BreakpointEditorContext {
        let host = transaction.request.host
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
            defaultPattern: "*\(host)\(normalizedPath)",
            defaultMatchType: .wildcard,
            httpMethod: httpMethod,
            includeSubpaths: true,
            breakpointRequest: true,
            breakpointResponse: true
        )
    }

    static func fromDomain(_ domain: String) -> BreakpointEditorContext {
        BreakpointEditorContext(
            origin: .domainQuickCreate,
            suggestedName: "Breakpoint — \(domain)",
            sourceURL: nil,
            sourceHost: domain,
            sourcePath: nil,
            sourceMethod: nil,
            defaultPattern: "*\(domain)/",
            defaultMatchType: .wildcard,
            httpMethod: .any,
            includeSubpaths: true,
            breakpointRequest: true,
            breakpointResponse: true
        )
    }

    // MARK: Private

    private static func normalizePath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }
}
