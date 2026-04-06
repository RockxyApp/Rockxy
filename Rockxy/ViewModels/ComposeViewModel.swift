import Foundation
import os

// Owns editable request state and response handling for the compose window.

// MARK: - ComposeRequestExecutor

/// Abstraction for executing HTTP requests. Enables testing with a mock executor
/// instead of hitting the network.
protocol ComposeRequestExecutor: Sendable {
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

// MARK: - DefaultComposeExecutor

/// Production executor that uses `RequestReplay.proxyBypassSession` to bypass
/// the app's own proxy and avoid recursion.
struct DefaultComposeExecutor: ComposeRequestExecutor {
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await RequestReplay.proxyBypassSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReplayError.invalidResponse
        }
        return (data, httpResponse)
    }
}

// MARK: - ComposeResponseState

/// The four states of the response viewer panel.
enum ComposeResponseState {
    case empty
    case loading
    case success(ComposeResponse)
    case error(String)
    case unsupported(String)
}

// MARK: - ComposeResponse

/// Snapshot of a successful HTTP response from a compose send.
struct ComposeResponse {
    let statusCode: Int
    let statusMessage: String
    let headers: [(name: String, value: String)]
    let bodyData: Data
    let bodyText: String?
    let contentType: ContentType?

    var bodyDisplayText: String {
        if let text = bodyText {
            return text
        }
        return String(localized: "(binary data, \(bodyData.count) bytes)")
    }

    var bodySize: Int {
        bodyData.count
    }
}

// MARK: - ComposeViewModel

/// View model for the Compose window. Owns the active editable request draft
/// and response state. Supports repeated sends with latest-run-wins semantics.
@MainActor @Observable
final class ComposeViewModel {
    // MARK: Lifecycle

    init(executor: ComposeRequestExecutor = DefaultComposeExecutor()) {
        self.executor = executor
    }

    // MARK: Internal

    // MARK: - Request Fields

    var method: String = "GET"
    var url: String = ""
    var headers: [EditableReplayHeader] = []
    var body: String = ""
    var queryItems: [EditableQueryItem] = []

    // MARK: - Response State

    private(set) var responseState: ComposeResponseState = .empty

    /// Whether the original captured transaction was a WebSocket connection.
    /// Immutable per draft — editing the method does not change WebSocket origin.
    private(set) var sourceIsWebSocket = false

    // MARK: - Query Sync

    /// Guards against infinite URL ↔ query sync loops.
    var lastSyncedURL: String = ""

    /// Whether the current draft cannot be faithfully replayed via URLSession.
    var isUnsupportedForReplay: Bool {
        sourceIsWebSocket || method == "CONNECT"
    }

    /// Assembled raw HTTP request text for the Raw tab.
    var rawRequestText: String {
        var lines: [String] = []
        let parsedURL = URL(string: url)
        let path: String = {
            guard let p = parsedURL?.path, !p.isEmpty else {
                return "/"
            }
            return p
        }()
        let query = parsedURL?.query.map { "?\($0)" } ?? ""
        lines.append("\(method) \(path)\(query) HTTP/1.1")

        if let host = parsedURL?.host {
            lines.append("Host: \(host)")
        }

        for header in headers where !header.name.isEmpty {
            lines.append("\(header.name): \(header.value)")
        }

        lines.append("")

        if !body.isEmpty {
            lines.append(body)
        }

        return lines.joined(separator: "\r\n")
    }

    /// Prefill the compose form from a captured transaction. Parses query items
    /// from the URL immediately so the Query tab is always in sync.
    func prefill(from transaction: HTTPTransaction) {
        method = transaction.request.method
        url = transaction.request.url.absoluteString
        headers = transaction.request.headers.map {
            EditableReplayHeader(name: $0.name, value: $0.value)
        }
        if let bodyData = transaction.request.body {
            body = String(data: bodyData, encoding: .utf8) ?? ""
        } else {
            body = ""
        }
        sourceIsWebSocket = transaction.webSocketConnection != nil
        currentRunID = 0
        syncURLToQuery()
        responseState = .empty
        syncUnsupportedState()
    }

    /// Send the current request draft. Uses latest-run-wins: if a newer send
    /// starts before this one completes, the stale result is silently discarded.
    func send() async {
        guard !isUnsupportedForReplay else {
            responseState = .unsupported(
                String(localized: "Replay is not supported for this request type.")
            )
            return
        }

        guard let requestURL = URL(string: url) else {
            responseState = .error(String(localized: "Invalid URL"))
            return
        }

        currentRunID &+= 1
        let runID = currentRunID

        responseState = .loading

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        for header in headers where !header.name.isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if !body.isEmpty {
            request.httpBody = Data(body.utf8)
        }
        request.timeoutInterval = 30

        do {
            let (data, httpResponse) = try await executor.execute(request)

            guard runID == currentRunID else {
                Self.logger.debug("Discarding stale response for runID \(runID)")
                return
            }

            let responseHeaders = httpResponse.allHeaderFields.map { ("\($0.key)", "\($0.value)") }
            let contentTypeHeader = httpResponse.value(forHTTPHeaderField: "Content-Type")
            let contentType = ContentType.detect(from: contentTypeHeader)

            let response = ComposeResponse(
                statusCode: httpResponse.statusCode,
                statusMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                headers: responseHeaders,
                bodyData: data,
                bodyText: String(data: data, encoding: .utf8),
                contentType: contentType
            )
            responseState = .success(response)
            Self.logger.info("Compose send succeeded: \(httpResponse.statusCode)")
        } catch {
            guard runID == currentRunID else {
                Self.logger.debug("Discarding stale error for runID \(runID)")
                return
            }
            responseState = .error(error.localizedDescription)
            Self.logger.error("Compose send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Header Management

    func addHeader() {
        headers.append(EditableReplayHeader(name: "", value: ""))
    }

    func removeHeader(id: UUID) {
        headers.removeAll { $0.id == id }
    }

    // MARK: - Query Management

    func addQueryItem() {
        queryItems.append(EditableQueryItem(name: "", value: ""))
        syncQueryToURL()
    }

    func removeQueryItem(id: UUID) {
        queryItems.removeAll { $0.id == id }
        syncQueryToURL()
    }

    /// Rebuild the URL query string from current query items.
    func syncQueryToURL() {
        guard var components = URLComponents(string: url) else {
            return
        }
        let nonEmpty = queryItems.filter { !$0.name.isEmpty }
        components.queryItems = nonEmpty.isEmpty ? nil : nonEmpty.map {
            URLQueryItem(name: $0.name, value: $0.value)
        }
        if let newURL = components.string {
            lastSyncedURL = newURL
            url = newURL
        }
    }

    /// Parse query items from the current URL string.
    func syncURLToQuery() {
        guard url != lastSyncedURL else {
            return
        }
        lastSyncedURL = url
        let parsed = URLComponents(string: url)?.queryItems ?? []
        queryItems = parsed.map { EditableQueryItem(name: $0.name, value: $0.value ?? "") }
    }

    /// Sync response state when `isUnsupportedForReplay` changes due to method edits.
    /// Strictly transitions only between `.empty` ↔ `.unsupported`. Never touches
    /// `.loading`, `.success`, or `.error` — those belong to the send lifecycle.
    func syncUnsupportedState() {
        switch responseState {
        case .empty where isUnsupportedForReplay:
            responseState = .unsupported(
                String(localized: "WebSocket and CONNECT requests cannot be replayed.")
            )
        case .unsupported where !isUnsupportedForReplay:
            responseState = .empty
        default:
            break
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ComposeViewModel")

    private let executor: ComposeRequestExecutor
    private var currentRunID: UInt64 = 0
}

// MARK: - EditableReplayHeader

/// Identifiable header pair for the compose window's editable header list.
struct EditableReplayHeader: Identifiable {
    let id = UUID()
    var name: String
    var value: String
}
