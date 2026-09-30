import AppKit
import Foundation

// Defines `HTTPTransaction`, the model for http transaction used by proxy, storage, and
// inspection flows.

// MARK: - HTTPTransaction

/// The central model for a proxied HTTP exchange — pairs a request with its response,
/// lifecycle state, timing breakdown, and optional protocol-specific data (WebSocket, GraphQL, Web3 RPC).
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
        graphQLInfo: GraphQLInfo? = nil,
        web3RPCInfo: Web3RPCInfo? = nil,
        x402Info: X402Info? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.request = request
        self.response = response
        self.state = state
        self.timingInfo = timingInfo
        self.webSocketConnection = webSocketConnection
        self.graphQLInfo = graphQLInfo
        self.web3RPCInfo = web3RPCInfo
        self.x402Info = x402Info
        deliversLiveRow = state == .active
        captureContext = request.captureContext
    }

    // MARK: Internal

    /// Capture-time TLS disposition of a transaction: whether it was passed through raw
    /// (`.tunneled`) or man-in-the-middled (`.intercepted`) at the moment of capture. The
    /// request list uses this so a historical row reports capture truth instead of recomputing
    /// its SSL badge from the *current* host policy — a raw CONNECT must stay tunneled even
    /// after the host's rule is later enabled. Runtime-only: portable/persisted sessions omit
    /// it; on reload the badge is derived deterministically from the record's own shape
    /// (CONNECT → tunneled, decrypted non-CONNECT HTTPS/WSS → intercepted), never from policy.
    enum SSLCaptureMode: Sendable {
        case tunneled
        case intercepted
    }

    let id: UUID
    let timestamp: Date
    var request: HTTPRequestData {
        didSet { signalEvidenceRevision &+= 1 }
    }
    var response: HTTPResponseData? {
        didSet { signalEvidenceRevision &+= 1 }
    }
    /// Changes whenever request or response evidence used by cached list signals changes.
    @ObservationIgnored private(set) var signalEvidenceRevision: UInt64 = 0 {
        didSet { customColumnValueCache.removeAll() }
    }
    /// Values of body columns, keyed by column, kept once the transaction has finished.
    @ObservationIgnored let customColumnValueCache = CustomColumnValueCache()
    var state: TransactionState
    /// Whether this transaction reaches the session twice — as an `.active` row when it opens
    /// and again when it finishes. Fixed at creation because the two deliveries travel through
    /// independent tasks: by the time the opening one is taken in, `state` may already read
    /// `.completed`, so routing on the live `state` could append the same transaction twice.
    @ObservationIgnored var deliversLiveRow: Bool
    var timingInfo: TimingInfo?
    var measuredDuration: TimeInterval?
    var webSocketConnection: WebSocketConnection?
    var graphQLInfo: GraphQLInfo?
    var web3RPCInfo: Web3RPCInfo?
    var x402Info: X402Info?
    var sourcePort: UInt16?
    var clientApp: String?

    /// Runtime-only owning application identity resolved from the accepted connection. Used
    /// for application-scoped SSL proxying attribution. Portable session files intentionally
    /// omit this — it is local to a live capture and never persisted or exported.
    var clientApplicationIdentity: ClientApplicationIdentity?
    /// Runtime-only, privacy-preserving scope used by TLS rejection recovery. Local clients use
    /// their application identity; remote clients use a one-way network identifier. The value is
    /// intentionally omitted from portable sessions and exports.
    var tlsClientScopeIdentifier: String?
    var comment: String?
    var highlightColor: HighlightColor?
    var isPinned: Bool = false
    var isSaved: Bool = false
    var isTLSFailure: Bool = false
    /// See `SSLCaptureMode`. Live captures always stamp this: raw tunnels record `.tunneled` and
    /// `HTTPSProxyRelayHandler` stamps every decrypted transaction `.intercepted`. `nil` therefore
    /// only occurs on legacy/reloaded/imported transactions whose capture disposition was not
    /// persisted (and on TLS-failure rows, which are never shown in the request list).
    var sslCapture: SSLCaptureMode?
    var webSocketFrameVersion: Int = 0
    var matchedRuleID: UUID?
    var matchedRuleName: String?
    var matchedRuleActionSummary: String?
    var matchedRulePattern: String?
    /// Names of scripts whose request or response hook ran for this exchange.
    var appliedScriptNames: [String] = []
    /// True when No Caching rewrote this exchange's cache headers.
    var noCachingApplied = false
    /// Protocol Rockxy used to reach the server (`1.1` or `2`); nil for tunnels, local
    /// responses, and sessions saved before it was recorded.
    var serverHTTPVersion: String?
    /// How Rockxy reached the server for this exchange; nil when no upstream connection was
    /// attempted (local responses, imports, sessions saved before it was recorded).
    var connectionLog: ConnectionLog?

    /// Runtime-only ownership. Portable session files intentionally omit this so
    /// an imported capture is assigned to the destination Project chosen by the user.
    private(set) var captureContext: TrafficCaptureContext?

    /// Request-list ordering metadata. Tracks the order this transaction was received by
    /// the coordinator, independent of `timestamp`. Used only for the request-list "row #"
    /// column sort. Must not be used by export, persistence, inspector, or replay.
    var sequenceNumber: Int = 0

    /// Whether this transaction carries a user note. Membership in the Library's Notes
    /// collection is derived from a non-empty, whitespace-trimmed `comment` — there is no
    /// separate stored flag, unlike `isPinned` / `isSaved`.
    var hasNote: Bool {
        guard let comment else {
            return false
        }
        return !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Duration shown in list rows and summaries. A WebSocket row reports the connection
    /// lifetime measured at close (its `timingInfo` only covers the upgrade handshake); every
    /// other transaction reports the timing breakdown total, falling back to the wall-clock
    /// measurement.
    var displayDuration: TimeInterval? {
        if webSocketConnection != nil {
            return measuredDuration
        }
        return timingInfo?.totalDuration ?? measuredDuration
    }

    /// Identifies what an inspector derived from this transaction. A live row keeps its id but
    /// gains its body when it completes, so an analysis keyed on the id alone stayed on the
    /// empty-body snapshot taken while the stream was running.
    var inspectionKey: String {
        "\(id.uuidString)|\(state.rawValue)"
    }

    /// Whether this row is a connection or stream that is still open, so its duration is not
    /// final yet.
    var isRunning: Bool {
        state == .active && displayDuration == nil
    }

    /// The duration a detail surface shows at `now`: the final value once known, otherwise the
    /// running time of a connection or stream that is still open. The request list keeps `—` for
    /// a running row instead — a per-second redraw belongs to the one selected row, not the
    /// capture hot path.
    func displayDuration(at now: Date) -> TimeInterval? {
        if let displayDuration {
            return displayDuration
        }
        guard state == .active else {
            return nil
        }
        return max(0, now.timeIntervalSince(timestamp))
    }

    func applyMatchedRuleMetadata(from rule: ProxyRule) {
        matchedRuleID = rule.id
        matchedRuleName = rule.name
        matchedRuleActionSummary = rule.action.matchedRuleActionSummary
        matchedRulePattern = rule.matchCondition.urlPattern
    }

    /// Assigns ownership to locally-created/imported transactions while preserving
    /// a proxy-captured request's immutable request-start route.
    func assignCaptureContextIfMissing(_ context: TrafficCaptureContext) {
        guard captureContext == nil else {
            return
        }
        captureContext = context
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
    case gray

    // MARK: Internal

    var displayName: String {
        switch self {
        case .red: String(localized: "Red", bundle: RockxyLocalization.bundle)
        case .orange: String(localized: "Orange", bundle: RockxyLocalization.bundle)
        case .yellow: String(localized: "Yellow", bundle: RockxyLocalization.bundle)
        case .green: String(localized: "Green", bundle: RockxyLocalization.bundle)
        case .blue: String(localized: "Blue", bundle: RockxyLocalization.bundle)
        case .purple: String(localized: "Purple", bundle: RockxyLocalization.bundle)
        case .gray: String(localized: "Gray", bundle: RockxyLocalization.bundle)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red: Theme.Highlight.redNS
        case .orange: Theme.Highlight.orangeNS
        case .yellow: Theme.Highlight.yellowNS
        case .green: Theme.Highlight.greenNS
        case .blue: Theme.Highlight.blueNS
        case .purple: Theme.Highlight.purpleNS
        case .gray: Theme.Highlight.grayNS
        }
    }
}
