import Foundation

// MARK: - AllowListRule

/// A capture-level allow rule. When the Allow List is active, only traffic matching
/// an enabled rule is recorded in the session. Non-matching traffic is still proxied
/// (forwarded) but not displayed or stored.
///
/// The model holds only source-of-truth user-facing fields. Regex compilation for
/// runtime matching happens exclusively in `AllowListManager.rebuildCache()` and
/// is never persisted.
struct AllowListRule: Identifiable, Codable, Hashable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        rawPattern: String,
        method: String? = nil,
        matchType: RuleMatchType = .wildcard,
        includeSubpaths: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.rawPattern = rawPattern
        self.method = method
        self.matchType = matchType
        self.includeSubpaths = includeSubpaths
    }

    // MARK: Internal

    let id: UUID
    var name: String
    var isEnabled: Bool
    /// User-facing pattern. For `.wildcard` rules this is e.g. `*example.com/v1/*`.
    /// For `.regex` rules this is the raw regex source.
    var rawPattern: String
    /// HTTP method filter. `nil` matches any method.
    var method: String?
    var matchType: RuleMatchType
    /// Display flag for wildcard rules. Ignored at runtime for `.regex` rules.
    var includeSubpaths: Bool
}
