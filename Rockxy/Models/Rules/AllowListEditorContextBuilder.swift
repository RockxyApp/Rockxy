import Foundation

/// Testable helper that builds `AllowListEditorContext` from transaction or domain quick-create entrypoints.
enum AllowListEditorContextBuilder {
    // MARK: Internal

    static func fromTransaction(_ transaction: HTTPTransaction) -> AllowListEditorContext {
        let host = transaction.request.host
        let normalizedPath = normalizePath(transaction.request.path)
        let method = transaction.request.method.uppercased()

        let httpMethod = HTTPMethodFilter(rawValue: method) ?? .any

        return AllowListEditorContext(
            origin: .selectedTransaction,
            suggestedName: "Allow — \(method) \(host)\(normalizedPath)",
            sourceURL: transaction.request.url,
            sourceHost: host,
            sourcePath: normalizedPath,
            sourceMethod: method,
            defaultPattern: "*\(host)\(normalizedPath)*",
            defaultMatchType: .wildcard,
            httpMethod: httpMethod,
            includeSubpaths: true
        )
    }

    static func fromDomain(_ domain: String) -> AllowListEditorContext {
        AllowListEditorContext(
            origin: .domainQuickCreate,
            suggestedName: "Allow — \(domain)",
            sourceURL: nil,
            sourceHost: domain,
            sourcePath: nil,
            sourceMethod: nil,
            defaultPattern: "*\(domain)/*",
            defaultMatchType: .wildcard,
            httpMethod: .any,
            includeSubpaths: true
        )
    }

    // MARK: Private

    private static func normalizePath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }
}
