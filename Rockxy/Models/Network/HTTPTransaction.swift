import AppKit
import Foundation
import os

// Defines `HTTPTransaction`, the model for http transaction used by proxy, storage, and
// inspection flows.

// MARK: - HTTPTransaction

/// The central model for a proxied HTTP exchange — pairs a request with its response,
/// lifecycle state, timing breakdown, and optional protocol-specific data (WebSocket, GraphQL, Web3 RPC).
/// Uses `@Observable` for SwiftUI reactivity.
///
/// `@unchecked Sendable` is a promise, not a proof, and it holds only under this contract:
/// - A *settled* transaction (`isSettledForOffMainRead`) is read off the main actor by the
///   session actor's delivery warm-up, which claims it via `claimForOffMainRead()`. Nothing may
///   write its `request` or `response` after that. Debug builds trap if something does.
/// - Rows that keep changing after delivery — `deliversLiveRow` streams and WebSockets — are
///   mutated on the main actor, and are never claimed for an off-main read.
/// - `clientApp` and the Babylon correlation are written after delivery to any row, but they are
///   distinct stored properties the warm-up never reads.
/// A producer that hands over a transaction it will still mutate must not make it settled.
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
    /// Values of body columns, keyed by column, invalidated whenever request or response evidence changes.
    @ObservationIgnored let customColumnValueCache = CustomColumnValueCache()
    /// Rendering revision, separate from body-analysis caches so cosmetic updates stay cheap.
    @ObservationIgnored private(set) var listPresentationRevision: UInt64 = 0
    /// Whether this transaction reaches the session twice — as an `.active` row when it opens
    /// and again when it finishes. Fixed at creation because the two deliveries travel through
    /// independent tasks: by the time the opening one is taken in, `state` may already read
    /// `.completed`, so routing on the live `state` could append the same transaction twice.
    @ObservationIgnored var deliversLiveRow: Bool
    /// Runtime-only, privacy-preserving scope used by TLS rejection recovery. Local clients use
    /// their application identity; remote clients use a one-way network identifier. The value is
    /// intentionally omitted from portable sessions and exports.
    var tlsClientScopeIdentifier: String?
    /// Loaded from a file or a nearby transfer instead of captured live. The live history cap
    /// neither counts nor evicts imported rows: an import is never trimmed.
    var isImported: Bool = false
    /// Why a raw tunnel was not decrypted, recorded at capture time. `nil` for decrypted traffic
    /// and for rows captured before this was recorded.
    var tunnelReason: TunnelReason?
    /// Protocol Rockxy used to reach the server (`1.1` or `2`); nil for tunnels, local
    /// responses, and sessions saved before it was recorded.
    var serverHTTPVersion: String?
    /// How Rockxy reached the server for this exchange; nil when no upstream connection was
    /// attempted (local responses, imports, sessions saved before it was recorded).
    var connectionLog: ConnectionLog?

    /// Runtime-only ownership. Portable session files intentionally omit this so
    /// an imported capture is assigned to the destination Project chosen by the user.
    private(set) var captureContext: TrafficCaptureContext?

    var state: TransactionState {
        didSet { listPresentationRevision &+= 1 }
    }

    var timingInfo: TimingInfo? {
        didSet { listPresentationRevision &+= 1 }
    }

    var measuredDuration: TimeInterval? {
        didSet { listPresentationRevision &+= 1 }
    }

    /// Live SSE stream diagnostics, present only for `text/event-stream` responses
    /// observed through the proxy. `nil` for non-streaming and imported traffic.
    var streamDiagnostics: StreamDiagnostics? {
        didSet { listPresentationRevision &+= 1 }
    }

    var webSocketConnection: WebSocketConnection? {
        didSet { listPresentationRevision &+= 1 }
    }

    var graphQLInfo: GraphQLInfo? {
        didSet { listPresentationRevision &+= 1 }
    }

    var web3RPCInfo: Web3RPCInfo? {
        didSet { listPresentationRevision &+= 1 }
    }

    var x402Info: X402Info? {
        didSet { listPresentationRevision &+= 1 }
    }

    /// Call shape supplied by a typed Babylon gRPC capture. Persisted for inspection; the
    /// framed request/response remain the source of truth for message bytes.
    var babylonGRPCCallType: String? {
        didSet { listPresentationRevision &+= 1 }
    }

    /// Bounded source, producer capability, correlation, and app-reported error metadata.
    /// Older sessions omit this optional field.
    var babylonCaptureMetadata: BabylonCaptureMetadata? {
        didSet { listPresentationRevision &+= 1 }
    }

    var sourcePort: UInt16? {
        didSet { listPresentationRevision &+= 1 }
    }

    var clientApp: String? {
        didSet { listPresentationRevision &+= 1 }
    }

    /// Runtime-only owning application identity resolved from the accepted connection. Used
    /// for application-scoped SSL proxying attribution. Portable session files intentionally
    /// omit this — it is local to a live capture and never persisted or exported.
    var clientApplicationIdentity: ClientApplicationIdentity? {
        didSet { listPresentationRevision &+= 1 }
    }

    var comment: String? {
        didSet { listPresentationRevision &+= 1 }
    }

    var highlightColor: HighlightColor? {
        didSet { listPresentationRevision &+= 1 }
    }

    var isPinned: Bool = false {
        didSet { listPresentationRevision &+= 1 }
    }

    var isSaved: Bool = false {
        didSet { listPresentationRevision &+= 1 }
    }

    /// Draws the row with struck-through text so a request can be marked as ignorable.
    var isStruckThrough: Bool = false {
        didSet { listPresentationRevision &+= 1 }
    }

    var isTLSFailure: Bool = false {
        didSet { listPresentationRevision &+= 1 }
    }

    /// See `SSLCaptureMode`. Live captures always stamp this: raw tunnels record `.tunneled` and
    /// `HTTPSProxyRelayHandler` stamps every decrypted transaction `.intercepted`. `nil` therefore
    /// only occurs on legacy/reloaded/imported transactions whose capture disposition was not
    /// persisted (and on TLS-failure rows, which are never shown in the request list).
    var sslCapture: SSLCaptureMode? {
        didSet { listPresentationRevision &+= 1 }
    }

    /// The Babylon runtime session, trace, and step the app made this request in. `nil` for
    /// proxied traffic and for Babylon captures sent without a trace.
    var babylonCorrelation: BabylonCorrelation? {
        didSet { listPresentationRevision &+= 1 }
    }

    var webSocketFrameVersion: Int = 0 {
        didSet { listPresentationRevision &+= 1 }
    }

    var matchedRuleID: UUID? {
        didSet { listPresentationRevision &+= 1 }
    }

    var matchedRuleName: String? {
        didSet { listPresentationRevision &+= 1 }
    }

    var matchedRuleActionSummary: String? {
        didSet { listPresentationRevision &+= 1 }
    }

    var matchedRulePattern: String? {
        didSet { listPresentationRevision &+= 1 }
    }

    /// Names of scripts whose request or response hook ran for this exchange.
    var appliedScriptNames: [String] = [] {
        didSet { listPresentationRevision &+= 1 }
    }

    /// Preview tabs scripts published for this exchange (`context.previewTabs`).
    var scriptPreviews: [ScriptPreviewTab] = [] {
        didSet { listPresentationRevision &+= 1 }
    }

    /// True when No Caching rewrote this exchange's cache headers.
    var noCachingApplied = false {
        didSet { listPresentationRevision &+= 1 }
    }

    /// Request-list ordering metadata. Tracks the order this transaction was received by
    /// the coordinator, independent of `timestamp`. Used only for the request-list "row #"
    /// column sort. Must not be used by export, persistence, inspector, or replay.
    var sequenceNumber: Int = 0 {
        didSet { listPresentationRevision &+= 1 }
    }

    var request: HTTPRequestData {
        didSet {
            assertEvidenceNotClaimedForOffMainRead()
            signalEvidenceRevision &+= 1
            listPresentationRevision &+= 1
        }
    }

    var response: HTTPResponseData? {
        didSet {
            assertEvidenceNotClaimedForOffMainRead()
            signalEvidenceRevision &+= 1
            listPresentationRevision &+= 1
        }
    }

    /// The single definition of "no longer changing", shared by every off-main-actor reader.
    /// Open streams and WebSockets keep receiving frames, and TLS failures never get a row.
    ///
    /// A `.completed` row that still has no response is not finished either. The Babylon SDK may
    /// report a request first and its response in a later package with the same id, and that
    /// first package carries no end marker to distinguish it, so the mapper calls it completed.
    /// Claiming such a row would let `BabylonCaptureMapper.applyUpdate` write `response` on the
    /// main actor while a reader walks the same storage off it. Every proxy-built `.completed`
    /// row carries a response, so excluding this shape costs them nothing.
    var isSettledForOffMainRead: Bool {
        !deliversLiveRow
            && webSocketConnection == nil
            && !isTLSFailure
            && state != .active
            && state != .pending
            && !(state == .completed && response == nil)
    }

    /// Whether `claimForOffMainRead()` has run. Once true, `request` and `response` must not be
    /// written unless the row is a live row.
    var isClaimedForOffMainRead: Bool {
        offMainReadClaim.withLock { $0 }
    }

    /// Changes whenever request or response evidence used by cached list signals changes.
    @ObservationIgnored private(set) var signalEvidenceRevision: UInt64 = 0 {
        didSet { customColumnValueCache.removeAll() }
    }

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

    /// Declares that this transaction's request and response are about to be read off the main
    /// actor. Traps in debug builds if the transaction is not settled, so a producer that routes
    /// a still-changing shape here fails at the call instead of racing a later write.
    func claimForOffMainRead() {
        assert(isSettledForOffMainRead, "Only a settled transaction may be read off the main actor")
        offMainReadClaim.withLock { $0 = true }
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

    // MARK: Private

    @ObservationIgnored private let offMainReadClaim = OSAllocatedUnfairLock(initialState: false)

    /// Trips in debug builds when evidence is rewritten after an off-main read was claimed — the
    /// write would race that read on `Data` and `[HTTPHeader]` storage. Live rows are exempt:
    /// they are never claimed, and their writes happen on the main actor.
    private func assertEvidenceNotClaimedForOffMainRead() {
        assert(
            !offMainReadClaim.withLock { $0 } || deliversLiveRow,
            "request/response written after the transaction was claimed for off-main reads"
        )
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
