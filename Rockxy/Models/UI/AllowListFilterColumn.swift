import Foundation

// MARK: - AllowListFilterColumn

/// Column options for filtering allow list rules in the filter bar.
enum AllowListFilterColumn: String, CaseIterable {
    case name
    case method
    case matchingRule

    // MARK: Internal

    var displayName: String {
        switch self {
        case .name: String(localized: "Name")
        case .method: String(localized: "Method")
        case .matchingRule: String(localized: "Matching Rule")
        }
    }
}
