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

    /// Header and query names compare without case; body expressions are exact.
    var comparesCaseInsensitively: Bool {
        !isBody
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
