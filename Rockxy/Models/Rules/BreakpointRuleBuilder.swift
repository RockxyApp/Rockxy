import Foundation

/// Testable helper that builds breakpoint rules from transaction or domain quick-create entrypoints.
enum BreakpointRuleBuilder {
    // MARK: Internal

    static func fromTransaction(_ transaction: HTTPTransaction) -> ProxyRule {
        let host = transaction.request.host
        let normalizedPath = normalizePath(transaction.request.path)
        let escapedHost = NSRegularExpression.escapedPattern(for: host)
        let escapedPath = NSRegularExpression.escapedPattern(for: normalizedPath)

        return ProxyRule(
            name: "Breakpoint — \(transaction.request.method.uppercased()) \(host)\(normalizedPath)",
            matchCondition: RuleMatchCondition(
                urlPattern: ".*\(escapedHost)\(escapedPath)(\\?.*)?$",
                method: transaction.request.method
            ),
            action: .breakpoint(phase: .both)
        )
    }

    static func fromDomain(_ domain: String) -> ProxyRule {
        let escapedDomain = NSRegularExpression.escapedPattern(for: domain)

        return ProxyRule(
            name: "Breakpoint — \(domain)",
            matchCondition: RuleMatchCondition(
                urlPattern: ".*\(escapedDomain)(?:[/?#].*)?$",
                method: nil
            ),
            action: .breakpoint(phase: .both)
        )
    }

    // MARK: Private

    private static func normalizePath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }
}
