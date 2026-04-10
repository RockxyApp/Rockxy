import AppKit
import Foundation

// Defines `HTTPTransaction`, the model for http transaction used by proxy, storage, and
// inspection flows.

// MARK: - HTTPTransaction

/// The central model for a proxied HTTP exchange — pairs a request with its response,
/// lifecycle state, timing breakdown, and optional protocol-specific data (WebSocket, GraphQL).
/// Uses `@Observable` for SwiftUI reactivity; marked `@unchecked Sendable` because mutations
/// only occur on the main actor after the proxy pipeline delivers completed transactions.
@Observable
final class HTTPTransaction: Identifiable, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        request: HTTPRequestData,
        response: HTTPResponseData? = nil,
        state: TransactionState = .pending,
        timingInfo: TimingInfo? = nil,
        webSocketConnection: WebSocketConnection? = nil,
        graphQLInfo: GraphQLInfo? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.request = request
        self.response = response
        self.state = state
        self.timingInfo = timingInfo
        self.webSocketConnection = webSocketConnection
        self.graphQLInfo = graphQLInfo
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    var request: HTTPRequestData
    var response: HTTPResponseData?
    var state: TransactionState
    var timingInfo: TimingInfo?
    var webSocketConnection: WebSocketConnection?
    var graphQLInfo: GraphQLInfo?
    var sourcePort: UInt16?
    var clientApp: String?
    var comment: String?
    var highlightColor: HighlightColor?
    var isPinned: Bool = false
    var isSaved: Bool = false
    var isTLSFailure: Bool = false
    var webSocketFrameVersion: Int = 0
    var matchedRuleID: UUID?
    var matchedRuleName: String?
    var matchedRuleActionSummary: String?
    var matchedRulePattern: String?

    /// Request-list ordering metadata. Tracks the order this transaction was received by
    /// the coordinator, independent of `timestamp`. Used only for the request-list "row #"
    /// column sort. Must not be used by export, persistence, inspector, or replay.
    var sequenceNumber: Int = 0

    func applyMatchedRuleMetadata(from rule: ProxyRule) {
        matchedRuleID = rule.id
        matchedRuleName = rule.name
        matchedRuleActionSummary = rule.action.matchedRuleActionSummary
        matchedRulePattern = rule.matchCondition.urlPattern
    }
}

// MARK: - GraphQLInfo

/// Parsed GraphQL operation metadata extracted from a POST request body by the `GraphQLDetector`.
struct GraphQLInfo {
    let operationName: String?
    let operationType: GraphQLOperationType
    let query: String
    let variables: String?
}

// MARK: - GraphQLOperationType

/// The three GraphQL operation types as defined in the GraphQL specification.
enum GraphQLOperationType: String {
    case query
    case mutation
    case subscription
}

// MARK: - HighlightColor

/// Available highlight colors for marking transactions in the request list.
enum HighlightColor: String, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple

    // MARK: Internal

    var nsColor: NSColor {
        switch self {
        case .red: Theme.Highlight.redNS
        case .orange: Theme.Highlight.orangeNS
        case .yellow: Theme.Highlight.yellowNS
        case .green: Theme.Highlight.greenNS
        case .blue: Theme.Highlight.blueNS
        case .purple: Theme.Highlight.purpleNS
        }
    }
}
