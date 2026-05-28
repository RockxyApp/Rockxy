import Foundation

/// String comparison operators used by `FilterRule` in the advanced filter builder.
/// All comparisons are case-insensitive.
enum FilterOperator: String, CaseIterable, Codable, Hashable {
    case contains
    case `is`
    case startsWith
    case endsWith
    case doesNotContain
    case notEqual
    case regex

    // MARK: Internal

    var displayName: String {
        switch self {
        case .contains: String(localized: "Contains")
        case .is: String(localized: "Is")
        case .startsWith: String(localized: "Starts With")
        case .endsWith: String(localized: "Ends With")
        case .doesNotContain: String(localized: "Does Not Contain")
        case .notEqual: String(localized: "Is Not")
        case .regex: String(localized: "Regex")
        }
    }

    func matches(_ fieldValue: String, against text: String) -> Bool {
        guard !text.isEmpty else {
            return true
        }
        let lowerField = fieldValue.lowercased()
        let lowerText = text.lowercased()
        switch self {
        case .contains: return lowerField.contains(lowerText)
        case .is: return lowerField == lowerText
        case .startsWith: return lowerField.hasPrefix(lowerText)
        case .endsWith: return lowerField.hasSuffix(lowerText)
        case .doesNotContain: return !lowerField.contains(lowerText)
        case .notEqual: return lowerField != lowerText
        case .regex:
            guard let pattern = try? NSRegularExpression(pattern: text, options: .caseInsensitive) else {
                return false
            }
            let range = NSRange(fieldValue.startIndex..., in: fieldValue)
            return pattern.firstMatch(in: fieldValue, range: range) != nil
        }
    }

    var contributesHighlight: Bool {
        switch self {
        case .doesNotContain,
             .notEqual:
            false
        case .contains,
             .is,
             .startsWith,
             .endsWith,
             .regex:
            true
        }
    }
}
