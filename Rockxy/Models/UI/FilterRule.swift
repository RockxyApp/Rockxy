import Foundation

enum FilterLogicConnector: String, CaseIterable, Codable, Hashable {
    case and
    case or

    var displayName: String {
        switch self {
        case .and: "AND"
        case .or: "OR"
        }
    }
}

/// A single row in the advanced filter builder. Combines a target field, comparison operator,
/// and match value into a toggleable predicate applied to the traffic list.
struct FilterRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var isEnabled: Bool = true
    var connector: FilterLogicConnector = .and
    var field: FilterField = .url
    var filterOperator: FilterOperator = .contains
    var value: String = ""
}
