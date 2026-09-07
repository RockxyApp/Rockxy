import Foundation

// MARK: - RuleMatchCondition

/// Defines the criteria a request must satisfy for a `ProxyRule` to fire.
/// All non-nil fields must match (AND logic). URL patterns use regex matching.
struct RuleMatchCondition: Codable, Equatable {
    // MARK: Lifecycle

    init(
        urlPattern: String? = nil,
        sourceURLPattern: String? = nil,
        method: String? = nil,
        headerName: String? = nil,
        headerValue: String? = nil,
        matchType: RuleMatchType? = nil,
        includeSubpaths: Bool? = nil
    ) {
        self.urlPattern = urlPattern
        self.sourceURLPattern = sourceURLPattern
        self.method = method
        self.headerName = headerName
        self.headerValue = headerValue
        self.matchType = matchType
        self.includeSubpaths = includeSubpaths
    }

    // MARK: Internal

    var urlPattern: String?
    /// Optional user-authored pattern retained for editors when `urlPattern`
    /// contains the compiled regex used by the runtime.
    var sourceURLPattern: String?
    var method: String?
    var headerName: String?
    var headerValue: String?
    var matchType: RuleMatchType?
    var includeSubpaths: Bool?

    /// The regex source the runtime should compile and match against. When the editor
    /// persisted authoring metadata (`matchType`/`sourceURLPattern`/`includeSubpaths`)
    /// the pattern is rebuilt from that authored intent so a stale compiled `urlPattern`
    /// never wins. Legacy rules without metadata fall back to the stored `urlPattern`.
    var runtimeURLPattern: String? {
        guard let urlPattern else {
            return nil
        }
        guard let matchType else {
            return urlPattern
        }
        let authoredPattern = sourceURLPattern ?? urlPattern
        let includeSub = matchType == .wildcard ? includeSubpaths ?? false : false
        let source = RulePatternBuilder.regexSource(
            rawPattern: authoredPattern,
            matchType: matchType,
            includeSubpaths: includeSub
        )
        guard matchType == .wildcard else {
            return source
        }
        return Self.applyWildcardEndBoundary(
            source: source,
            authoredPattern: authoredPattern,
            includeSubpaths: includeSub
        )
    }

    func matches(
        method requestMethod: String,
        url: URL,
        headers: [HTTPHeader],
        compiledPattern: NSRegularExpression? = nil
    )
        -> Bool
    {
        if let regex = compiledPattern {
            let urlString = String(url.absoluteString.prefix(ProxyLimits.maxURILength))
            let range = NSRange(urlString.startIndex..., in: urlString)
            guard regex.firstMatch(in: urlString, range: range) != nil else {
                return false
            }
        } else if let pattern = runtimeURLPattern {
            let urlString = String(url.absoluteString.prefix(ProxyLimits.maxURILength))
            guard urlString.range(of: pattern, options: .regularExpression) != nil else {
                return false
            }
        }
        if let requiredMethod = method {
            guard requestMethod.uppercased() == requiredMethod.uppercased() else {
                return false
            }
        }
        if let name = headerName, let value = headerValue {
            guard headers.contains(where: { $0.name.lowercased() == name.lowercased() && $0.value == value }) else {
                return false
            }
        }
        return true
    }
}

// MARK: - Wildcard end boundaries

private extension RuleMatchCondition {
    /// The suffix `RulePatternBuilder` appends for an anchored (non-subpath) wildcard rule.
    static let anchoredWildcardSuffix = "($|[?#])"
    /// The suffix `RulePatternBuilder` appends for a subpath-including wildcard rule.
    static let subpathWildcardSuffix = ".*"

    /// Corrects the end-boundary `RulePatternBuilder` produces so wildcard matching remains
    /// predictable across full URLs. The core escaping is left to `RulePatternBuilder`; only
    /// the trailing boundary is rewritten here.
    ///
    /// Two corrections:
    /// - **Trailing `?` wildcard, no subpaths:** the single-character wildcard already consumes
    ///   the position a query separator would occupy, so a trailing `?query` must NOT match.
    ///   The boundary is anchored to end-of-string (`$`) instead of allowing `[?#]`. Patterns
    ///   ending in a literal keep the query-tolerant `($|[?#])` boundary.
    /// - **Subpaths on a bare path (no trailing `/`, `*`, or `?`):** the base must match itself,
    ///   slash children, and a query — but not a sibling that merely shares the prefix. The
    ///   greedy `.*` (which sibling-matches) is replaced with `($|[/?#])`. Patterns already
    ///   ending in `/` or a wildcard keep `.*`, which is sibling-safe or intentionally broad.
    static func applyWildcardEndBoundary(
        source: String,
        authoredPattern: String,
        includeSubpaths: Bool
    )
        -> String
    {
        if includeSubpaths {
            guard !authoredPattern.hasSuffix("*"),
                  !authoredPattern.hasSuffix("?"),
                  !authoredPattern.hasSuffix("/"),
                  source.hasSuffix(subpathWildcardSuffix) else
            {
                return source
            }
            return String(source.dropLast(subpathWildcardSuffix.count)) + "($|[/?#])"
        }

        guard authoredPattern.hasSuffix("?"), source.hasSuffix(anchoredWildcardSuffix) else {
            return source
        }
        return String(source.dropLast(anchoredWildcardSuffix.count)) + "$"
    }
}
