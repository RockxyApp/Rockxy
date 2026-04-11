import Foundation

// MARK: - BreakpointFilterColumn

/// Column options for filtering breakpoint rules in the filter bar.
enum BreakpointFilterColumn: String, CaseIterable {
    case name
    case matchingRule
    case method

    // MARK: Internal

    var displayName: String {
        switch self {
        case .name: String(localized: "Name")
        case .matchingRule: String(localized: "Matching Rule")
        case .method: String(localized: "Method")
        }
    }
}
