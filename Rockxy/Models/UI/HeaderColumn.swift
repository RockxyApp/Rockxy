import Foundation

// Defines the UI model for configurable request and response table columns.

// MARK: - HeaderColumnSource

enum HeaderColumnSource: String, Codable, CaseIterable {
    case request
    case response
    /// A query parameter of the request URL.
    case query
    /// A value read from a JSON request body with JSONPath (`$…`) or a jq filter.
    case requestBody
    /// A value read from a JSON response body with JSONPath (`$…`) or a jq filter.
    case responseBody

    // MARK: Internal

    /// Prefix of the table column identifier for this source.
    var columnIDPrefix: String {
        switch self {
        case .request: "reqHeader."
        case .response: "resHeader."
        case .query: "reqQuery."
        case .requestBody: "reqBody."
        case .responseBody: "resBody."
        }
    }

    var isHeader: Bool {
        self == .request || self == .response
    }

    var isBody: Bool {
        self == .requestBody || self == .responseBody
    }

    /// Only HTTP field names are case-insensitive (RFC 9110 §5.1). A query parameter
    /// name is not: `?Token=` and `?token=` are two different parameters, and
    /// `HeaderColumnStore.resolveValue` reads one by exact name. Folding case here too
    /// made the duplicate check disagree with the resolver, so a column for `Token`
    /// could not be added beside one for `token` -- `addColumn` returned the existing
    /// row, or enabled it, and the column the user asked for showed the other
    /// parameter's value. Body expressions are exact for the same reason.
    var comparesCaseInsensitively: Bool {
        isHeader
    }

    func normalizedName(_ name: String) -> String {
        comparesCaseInsensitively ? name.lowercased() : name
    }

    func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        comparesCaseInsensitively ? lhs.caseInsensitiveCompare(rhs) == .orderedSame : lhs == rhs
    }
}

// MARK: - HeaderColumn

struct HeaderColumn: Identifiable, Codable, Hashable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        headerName: String,
        source: HeaderColumnSource,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.headerName = headerName
        self.source = source
        self.isEnabled = isEnabled
    }

    // MARK: Internal

    let id: UUID
    /// Header name, query parameter name, or body expression, depending on `source`.
    var headerName: String
    var source: HeaderColumnSource
    var isEnabled: Bool

    var columnIdentifier: String {
        source.columnIDPrefix + headerName
    }

    /// Whether a table column identifier belongs to a custom column of any source.
    static func isCustomColumnID(_ columnID: String) -> Bool {
        parse(columnID: columnID) != nil
    }

    /// Splits a custom column identifier into its source and name.
    static func parse(columnID: String) -> (source: HeaderColumnSource, name: String)? {
        for source in HeaderColumnSource.allCases where columnID.hasPrefix(source.columnIDPrefix) {
            return (source, String(columnID.dropFirst(source.columnIDPrefix.count)))
        }
        return nil
    }

    /// Readable titles for a set of columns, keyed by column id.
    ///
    /// A header or query column's name already reads as a title (`Authorization`, `page`),
    /// but a body column's name is an EXPRESSION, and `$.data.user.name` is not a column
    /// title. The expression stays the column's identity, its sort key and its tooltip;
    /// only what the header draws changes.
    ///
    /// Two expressions can end in the same key (`$.data.user.name` and `$.meta.user.name`),
    /// and two columns both titled `name` would be worse than the raw expressions. So a
    /// title that is not unique among these columns falls back to the full expression for
    /// every column that wanted it.
    static func displayTitles(for columns: [HeaderColumn]) -> [UUID: String] {
        var proposed: [UUID: String] = [:]
        var counts: [String: Int] = [:]
        for column in columns {
            let title = column.source.isBody
                ? (bodyColumnTitle(for: column.headerName) ?? column.headerName)
                : column.headerName
            proposed[column.id] = title
            counts[title, default: 0] += 1
        }
        return columns.reduce(into: [:]) { result, column in
            let title = proposed[column.id] ?? column.headerName
            result[column.id] = counts[title, default: 0] > 1 ? column.headerName : title
        }
    }

    /// The last key of a body expression, or `nil` when the expression is not a plain path.
    ///
    /// Only a plain path earns a shortened title: an optional leading `$`, then a run of
    /// `.key` and `[index]` steps. A filter like `.a + .b` or a pipeline is left whole,
    /// because naming such a column after one of its parts would describe it wrongly.
    static func bodyColumnTitle(for expression: String) -> String? {
        var remainder = Substring(expression)
        if remainder.first == "$" {
            remainder = remainder.dropFirst()
        }
        guard !remainder.isEmpty else {
            return nil
        }
        var lastKey: String?
        while !remainder.isEmpty {
            if remainder.first == "[" {
                guard let close = remainder.firstIndex(of: "]") else {
                    return nil
                }
                let index = remainder[remainder.index(after: remainder.startIndex) ..< close]
                guard index.isEmpty || index.allSatisfy(\.isNumber) else {
                    return nil
                }
                remainder = remainder[remainder.index(after: close)...]
                continue
            }
            guard remainder.first == "." else {
                return nil
            }
            remainder = remainder.dropFirst()
            let key = remainder.prefix { $0 != "." && $0 != "[" }
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
                return nil
            }
            lastKey = String(key)
            remainder = remainder.dropFirst(key.count)
        }
        return lastKey
    }
}
