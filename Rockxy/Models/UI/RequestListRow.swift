import Foundation

// MARK: - RequestListRow

/// Lightweight projection of `HTTPTransaction` for request-list table rendering.
/// Carries only the fields needed for display, sorting, and custom header column resolution.
/// This is a migration seam: the table renders from `[RequestListRow]` instead of
/// full `[HTTPTransaction]` objects, decoupling display from the heavyweight transaction model
/// and enabling future `SessionStore`-backed windowed browsing.
///
/// Supports all traffic classes that `HTTPTransaction` represents: plain HTTP, HTTPS,
/// WebSocket, GraphQL, and TLS-failure transactions.
struct RequestListRow: Identifiable {
    // MARK: Lifecycle

    init(from transaction: HTTPTransaction) {
        id = transaction.id
        timestamp = transaction.timestamp
        method = transaction.request.method
        scheme = transaction.request.url.scheme ?? "http"
        host = transaction.request.host
        path = transaction.request.path
        httpVersion = transaction.request.httpVersion
        statusCode = transaction.response?.statusCode
        statusMessage = transaction.response?.statusMessage
        state = transaction.state
        totalDuration = transaction.timingInfo?.totalDuration
        requestBodySize = transaction.request.body?.count
        responseBodySize = transaction.response?.body?.count
        clientApp = transaction.clientApp
        requestContentType = transaction.request.contentType
        responseContentType = transaction.response?.contentType
        isPinned = transaction.isPinned
        isSaved = transaction.isSaved
        comment = transaction.comment
        highlightColor = transaction.highlightColor
        isTLSFailure = transaction.isTLSFailure
        graphQLOpName = transaction.graphQLInfo?.operationName
        graphQLOpType = transaction.graphQLInfo?.operationType.rawValue
        isWebSocket = transaction.webSocketConnection != nil
        webSocketFrameCount = transaction.webSocketConnection?.frameCount ?? 0
        sourcePort = transaction.sourcePort
        sequenceNumber = transaction.sequenceNumber
        requestHeaders = transaction.request.headers
        responseHeaders = transaction.response?.headers
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    let method: String
    let scheme: String
    let host: String
    let path: String
    let httpVersion: String
    let statusCode: Int?
    let statusMessage: String?
    let state: TransactionState
    let totalDuration: TimeInterval?
    let requestBodySize: Int?
    let responseBodySize: Int?
    let clientApp: String?
    let requestContentType: ContentType?
    let responseContentType: ContentType?
    let isPinned: Bool
    let isSaved: Bool
    let comment: String?
    let highlightColor: HighlightColor?
    let isTLSFailure: Bool
    let graphQLOpName: String?
    let graphQLOpType: String?
    let isWebSocket: Bool
    let webSocketFrameCount: Int
    let sourcePort: UInt16?

    /// Request-list ordering metadata. Tracks the order transactions were received by the
    /// coordinator, independent of `timestamp`. This must not be used by unrelated features
    /// (export, persistence, inspector, replay).
    let sequenceNumber: Int

    // Headers included for custom header column resolution.
    // Lightweight (string pairs) compared to body Data.
    let requestHeaders: [HTTPHeader]
    let responseHeaders: [HTTPHeader]?
}

// MARK: - Sorting

extension RequestListRow {
    static func compare(
        _ lhs: RequestListRow,
        _ rhs: RequestListRow,
        using descriptors: [NSSortDescriptor]
    )
        -> Bool
    {
        for descriptor in descriptors {
            let result = compareField(lhs, rhs, key: descriptor.key ?? "", ascending: descriptor.ascending)
            if result != .orderedSame {
                return result == .orderedAscending
            }
        }
        return false
    }

    // MARK: Private

    private static func compareField(
        _ lhs: RequestListRow,
        _ rhs: RequestListRow,
        key: String,
        ascending: Bool
    )
        -> ComparisonResult
    {
        let raw: ComparisonResult = switch key {
        case "url":
            (lhs.host + lhs.path).localizedCompare(rhs.host + rhs.path)
        case "method":
            lhs.method.compare(rhs.method)
        case "code":
            compareOptionalInt(lhs.statusCode, rhs.statusCode)
        case "time":
            lhs.timestamp.compare(rhs.timestamp)
        case "duration":
            compareOptionalDouble(lhs.totalDuration, rhs.totalDuration)
        case "size":
            compareOptionalInt(lhs.responseBodySize, rhs.responseBodySize)
        case "queryName":
            compareQueryName(lhs, rhs)
        case "client":
            (lhs.clientApp ?? "").localizedCompare(rhs.clientApp ?? "")
        case "row":
            compareInt(lhs.sequenceNumber, rhs.sequenceNumber)
        default:
            if key.hasPrefix("reqHeader.") || key.hasPrefix("resHeader.") {
                compareHeaderValue(lhs, rhs, columnID: key)
            } else {
                .orderedSame
            }
        }
        return ascending ? raw : raw.inverted
    }

    private static func compareQueryName(_ lhs: RequestListRow, _ rhs: RequestListRow) -> ComparisonResult {
        if lhs.isWebSocket, rhs.isWebSocket {
            return compareInt(lhs.webSocketFrameCount, rhs.webSocketFrameCount)
        }
        let lhsDisplay = lhs.isWebSocket ? "\(lhs.webSocketFrameCount)" : (lhs.graphQLOpName ?? "")
        let rhsDisplay = rhs.isWebSocket ? "\(rhs.webSocketFrameCount)" : (rhs.graphQLOpName ?? "")
        return lhsDisplay.localizedCompare(rhsDisplay)
    }

    private static func compareInt(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }

    private static func compareOptionalInt(_ lhs: Int?, _ rhs: Int?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): .orderedSame
        case (nil, _): .orderedDescending
        case (_, nil): .orderedAscending
        case let (l?, r?): compareInt(l, r)
        }
    }

    private static func compareOptionalDouble(_ lhs: Double?, _ rhs: Double?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (l?, r?):
            if l < r {
                return .orderedAscending
            }
            if l > r {
                return .orderedDescending
            }
            return .orderedSame
        }
    }

    private static func compareHeaderValue(
        _ lhs: RequestListRow,
        _ rhs: RequestListRow,
        columnID: String
    )
        -> ComparisonResult
    {
        let lhsVal = resolveHeaderValue(for: columnID, row: lhs)
        let rhsVal = resolveHeaderValue(for: columnID, row: rhs)
        return lhsVal.localizedCompare(rhsVal)
    }

    static func resolveHeaderValue(for columnID: String, row: RequestListRow) -> String {
        if columnID.hasPrefix("reqHeader.") {
            let headerName = String(columnID.dropFirst("reqHeader.".count))
            return row.requestHeaders
                .first { $0.name.caseInsensitiveCompare(headerName) == .orderedSame }?
                .value ?? ""
        } else if columnID.hasPrefix("resHeader.") {
            let headerName = String(columnID.dropFirst("resHeader.".count))
            return row.responseHeaders?
                .first { $0.name.caseInsensitiveCompare(headerName) == .orderedSame }?
                .value ?? ""
        }
        return ""
    }
}

// MARK: - ComparisonResult + Invert

private extension ComparisonResult {
    var inverted: ComparisonResult {
        switch self {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
}
