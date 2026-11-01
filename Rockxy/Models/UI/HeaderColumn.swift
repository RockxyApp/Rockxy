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
}
