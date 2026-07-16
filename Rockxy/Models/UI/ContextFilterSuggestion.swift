import Foundation

/// A visible value that can be promoted into Rockxy's existing advanced-filter state.
struct ContextFilterSuggestion: Equatable {
    // MARK: Internal

    let field: FilterField
    let value: String
    let includeOperator: FilterOperator
    let excludeOperator: FilterOperator

    static func header(_ header: HTTPHeader, source: HeaderColumnSource) -> Self? {
        let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !value.isEmpty else {
            return nil
        }
        return Self(
            field: source == .request ? .requestHeader : .responseHeader,
            value: "\(name): \(value)",
            includeOperator: .contains,
            excludeOperator: .doesNotContain
        )
    }

    static func tableCell(columnID: String, transaction: HTTPTransaction) -> Self? {
        switch columnID {
        case "url":
            exact(field: .url, value: transaction.request.url.absoluteString)
        case "method":
            exact(field: .method, value: transaction.request.method)
        case "code":
            transaction.response.flatMap { exact(field: .statusCode, value: String($0.statusCode)) }
        case "client":
            transaction.clientApp.flatMap { exact(field: .clientApp, value: $0) }
        default:
            headerColumn(columnID: columnID, transaction: transaction)
        }
    }

    // MARK: Private

    private static func exact(field: FilterField, value: String) -> Self? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            return nil
        }
        return Self(
            field: field,
            value: normalizedValue,
            includeOperator: .is,
            excludeOperator: .notEqual
        )
    }

    private static func headerColumn(columnID: String, transaction: HTTPTransaction) -> Self? {
        let prefix: String
        let source: HeaderColumnSource
        let headers: [HTTPHeader]
        if columnID.hasPrefix("reqHeader.") {
            prefix = "reqHeader."
            source = .request
            headers = transaction.request.headers
        } else if columnID.hasPrefix("resHeader.") {
            prefix = "resHeader."
            source = .response
            headers = transaction.response?.headers ?? []
        } else {
            return nil
        }

        let headerName = String(columnID.dropFirst(prefix.count))
        guard let capturedHeader = headers.first(where: {
            $0.name.caseInsensitiveCompare(headerName) == .orderedSame
        }) else {
            return nil
        }
        return header(capturedHeader, source: source)
    }
}
