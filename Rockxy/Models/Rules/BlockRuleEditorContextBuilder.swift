import Foundation

/// Builds BlockRuleEditorContext from transaction or domain data.
enum BlockRuleEditorContextBuilder {
    // MARK: Internal

    static func fromTransaction(_ transaction: HTTPTransaction) -> BlockRuleEditorContext {
        let normalizedPath = normalizePath(transaction.request.path)
        let pattern = "*\(transaction.request.host)\(normalizedPath)"

        return BlockRuleEditorContext(
            origin: .selectedTransaction,
            suggestedName: "Block — \(transaction.request.method) \(transaction.request.host)\(normalizedPath)",
            sourceURL: transaction.request.url,
            sourceHost: transaction.request.host,
            sourcePath: normalizedPath,
            sourceMethod: transaction.request.method,
            defaultPattern: pattern,
            defaultMatchType: .wildcard,
            defaultAction: .returnForbidden,
            httpMethod: HTTPMethodFilter(rawValue: transaction.request.method.uppercased()) ?? .any,
            includeSubpaths: true
        )
    }

    static func fromDomain(_ domain: String) -> BlockRuleEditorContext {
        BlockRuleEditorContext(
            origin: .domainQuickCreate,
            suggestedName: "Block — \(domain)",
            sourceURL: nil,
            sourceHost: domain,
            sourcePath: nil,
            sourceMethod: nil,
            defaultPattern: "*\(domain)/",
            defaultMatchType: .wildcard,
            defaultAction: .returnForbidden,
            httpMethod: .any,
            includeSubpaths: true
        )
    }

    // MARK: Private

    private static func normalizePath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }
}
