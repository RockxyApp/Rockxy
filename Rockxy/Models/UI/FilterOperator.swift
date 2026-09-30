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
        case .contains: String(localized: "Contains", bundle: RockxyLocalization.bundle)
        case .is: String(localized: "Is", bundle: RockxyLocalization.bundle)
        case .startsWith: String(localized: "Starts With", bundle: RockxyLocalization.bundle)
        case .endsWith: String(localized: "Ends With", bundle: RockxyLocalization.bundle)
        case .doesNotContain: String(localized: "Does Not Contain", bundle: RockxyLocalization.bundle)
        case .notEqual: String(localized: "Is Not", bundle: RockxyLocalization.bundle)
        case .regex: String(localized: "Regex", bundle: RockxyLocalization.bundle)
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
            guard let pattern = FilterRegexCache.regex(for: text) else {
                return false
            }
            let range = NSRange(fieldValue.startIndex..., in: fieldValue)
            return pattern.firstMatch(in: fieldValue, range: range) != nil
        }
    }
}

// MARK: - FilterRegexCache

/// Compiles each filter pattern once. A regex filter is evaluated for every row on every
/// recompute, so recompiling per row is the dominant cost on a large capture.
enum FilterRegexCache {
    static func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] {
            return cached
        }
        let compiled = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        if cache.count >= maxEntries {
            cache.removeAll(keepingCapacity: true)
        }
        cache[pattern] = .some(compiled)
        return compiled
    }

    /// Whether `pattern` compiles; the filter bar uses it to flag an unfinished expression.
    static func isValid(_ pattern: String) -> Bool {
        regex(for: pattern) != nil
    }

    private static let maxEntries = 256
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression?] = [:]
}
