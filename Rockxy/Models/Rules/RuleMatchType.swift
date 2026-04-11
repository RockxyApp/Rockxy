import Foundation

// MARK: - RuleMatchType

/// Shared match type for URL pattern matching across all rule editors (Block List, Breakpoint, etc.).
enum RuleMatchType: String, CaseIterable {
    case wildcard = "Use Wildcard"
    case regex = "Use Regex"
}
