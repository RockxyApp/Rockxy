import Foundation
import os

// Owns editable request state and response handling for the compose window.

// MARK: - ComposeRequestExecutor

/// Abstraction for executing HTTP requests. Enables testing with a mock executor
/// instead of hitting the network.
protocol ComposeRequestExecutor: Sendable {
    func execute(_ request: URLRequest, followsRedirects: Bool) async throws -> (Data, HTTPURLResponse)
}

// MARK: - DefaultComposeExecutor

/// Production executor that uses `RequestReplay.proxyBypassSession` to bypass
/// the app's own proxy and avoid recursion.
struct DefaultComposeExecutor: ComposeRequestExecutor {
    func execute(_ request: URLRequest, followsRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
        let session = followsRedirects ? RequestReplay.proxyBypassSession : Self.noRedirectSession
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReplayError.invalidResponse
        }
        return (data, httpResponse)
    }

    // MARK: Private

    private static let noRedirectSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
        ]
        return URLSession(configuration: config, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
    }()
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

// MARK: - ComposeRequestTimeout

enum ComposeRequestTimeout: Int, CaseIterable, Identifiable {
    case fifteen = 15
    case thirty = 30
    case sixty = 60
    case none = 0

    // MARK: Internal

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .fifteen:
            String(localized: "15 seconds")
        case .thirty:
            String(localized: "30 seconds")
        case .sixty:
            String(localized: "60 seconds")
        case .none:
            String(localized: "0 (No Timeout)")
        }
    }

    var interval: TimeInterval {
        switch self {
        case .none:
            TimeInterval.greatestFiniteMagnitude
        default:
            TimeInterval(rawValue)
        }
    }
}

// MARK: - ComposeTemplate

enum ComposeTemplate: CaseIterable, Identifiable {
    case empty
    case getWithQuery
    case postJSON
    case postForm
    case postMultipart

    // MARK: Internal

    var id: String {
        switch self {
        case .empty: "empty"
        case .getWithQuery: "getWithQuery"
        case .postJSON: "postJSON"
        case .postForm: "postForm"
        case .postMultipart: "postMultipart"
        }
    }

    var title: String {
        switch self {
        case .empty:
            String(localized: "Empty Request")
        case .getWithQuery:
            String(localized: "GET with Query")
        case .postJSON:
            String(localized: "POST with JSON")
        case .postForm:
            String(localized: "POST with Form")
        case .postMultipart:
            String(localized: "POST with Multiparts")
        }
    }
}

// MARK: - ComposeImportError

enum ComposeImportError: LocalizedError, Equatable {
    case emptyCommand
    case unsupportedCommand
    case missingURL

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            String(localized: "Pasteboard does not contain a cURL command.")
        case .unsupportedCommand:
            String(localized: "Only cURL commands can be imported.")
        case .missingURL:
            String(localized: "The cURL command does not contain a URL.")
        }
    }
}

// MARK: - ComposeHistoryEntry

struct ComposeHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let method: String
    let url: String
    let headers: [EditableReplayHeader]
    let queryItems: [EditableQueryItem]
    let body: String
    let bodyContentType: String?
    let statusCode: Int?
    let responseHeaders: [EditableReplayHeader]?
    let responseBody: String?
    let bodyTruncated: Bool
    let responseBodyTruncated: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        method: String,
        url: String,
        headers: [EditableReplayHeader],
        queryItems: [EditableQueryItem],
        body: String,
        bodyContentType: String?,
        statusCode: Int?,
        responseHeaders: [EditableReplayHeader]? = nil,
        responseBody: String? = nil,
        bodyTruncated: Bool = false,
        responseBodyTruncated: Bool = false,
        timestamp: Date
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.headers = headers
        self.queryItems = queryItems
        self.body = body
        self.bodyContentType = bodyContentType
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.bodyTruncated = bodyTruncated
        self.responseBodyTruncated = responseBodyTruncated
        self.timestamp = timestamp
    }

    var menuTitle: String {
        let status = statusCode.map { "\($0)" } ?? String(localized: "No Response")
        return "[\(method)] \(url) • \(status) • \(Self.relativeFormatter.localizedString(for: timestamp, relativeTo: Date()))"
    }

    var requestFingerprint: String {
        let headerFingerprint = headers
            .map { "\($0.isEnabled)|\($0.name.lowercased())|\($0.value)" }
            .joined(separator: "\u{1F}")
        let queryFingerprint = queryItems
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "\u{1F}")
        return [
            method,
            url,
            headerFingerprint,
            queryFingerprint,
            body,
            bodyContentType ?? "",
        ].joined(separator: "\u{1E}")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
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

    init(
        executor: ComposeRequestExecutor = DefaultComposeExecutor(),
        historyStore: ComposeHistoryStore = .live
    ) {
        self.executor = executor
        self.historyStore = historyStore
        history = historyStore.load()
    }

    // MARK: Internal

    // MARK: - Request Fields

    var method: String = "GET"
    var url: String = ""
    var headers: [EditableReplayHeader] = []
    var body: String = ""
    var queryItems: [EditableQueryItem] = []
    var requestTimeout: ComposeRequestTimeout = .thirty
    var followsRedirects = true
    private(set) var history: [ComposeHistoryEntry] = []
    private(set) var lastFormattingError: String?
    private(set) var restoreConfirmationID = UUID()
    private(set) var restoreConfirmationMessage: String?

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

        for header in headers where header.isEnabled && !header.name.isEmpty {
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
        clearRestoreConfirmation()
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

    /// Reset only the active editor draft. History and request options remain intact,
    /// so opening a fresh Compose window feels native without erasing user preferences.
    func resetDraft() {
        clearRestoreConfirmation()
        method = "GET"
        url = ""
        headers = []
        body = ""
        queryItems = []
        lastFormattingError = nil
        sourceIsWebSocket = false
        currentRunID = 0
        lastSyncedURL = ""
        responseState = .empty
    }

    /// Send the current request draft. Uses latest-run-wins: if a newer send
    /// starts before this one completes, the stale result is silently discarded.
    func send() async {
        guard !isUnsupportedForReplay else {
            clearRestoreConfirmation()
            responseState = .unsupported(
                String(localized: "Replay is not supported for this request type.")
            )
            return
        }

        guard let requestURL = URL(string: url) else {
            clearRestoreConfirmation()
            responseState = .error(String(localized: "Invalid URL"))
            return
        }

        clearRestoreConfirmation()
        currentRunID &+= 1
        let runID = currentRunID

        responseState = .loading

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        for header in headers where header.isEnabled && !header.name.isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if !body.isEmpty {
            request.httpBody = Data(body.utf8)
        }
        request.timeoutInterval = requestTimeout.interval

        do {
            let (data, httpResponse) = try await executor.execute(request, followsRedirects: followsRedirects)

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
            recordHistory(response: response)
            Self.logger.info("Compose send succeeded: \(httpResponse.statusCode)")
        } catch {
            guard runID == currentRunID else {
                Self.logger.debug("Discarding stale error for runID \(runID)")
                return
            }
            responseState = .error(error.localizedDescription)
            recordHistory(response: nil)
            Self.logger.error("Compose send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Templates

    func applyTemplate(_ template: ComposeTemplate) {
        clearRestoreConfirmation()
        sourceIsWebSocket = false
        responseState = .empty
        lastFormattingError = nil

        switch template {
        case .empty:
            method = "GET"
            url = ""
            headers = []
            body = ""
            queryItems = []
            lastSyncedURL = ""
        case .getWithQuery:
            method = "GET"
            url = "https://example.com/api?name=value"
            headers = [EditableReplayHeader(name: "Accept", value: "application/json")]
            body = ""
            syncURLToQuery(force: true)
        case .postJSON:
            method = "POST"
            url = "https://example.com/api"
            headers = [
                EditableReplayHeader(name: "Content-Type", value: "application/json"),
                EditableReplayHeader(name: "Accept", value: "application/json"),
            ]
            body = "{\n  \"key\": \"value\"\n}"
            syncURLToQuery(force: true)
        case .postForm:
            method = "POST"
            url = "https://example.com/api"
            headers = [EditableReplayHeader(name: "Content-Type", value: "application/x-www-form-urlencoded")]
            body = "key=value"
            syncURLToQuery(force: true)
        case .postMultipart:
            let boundary = "----RockxyBoundary"
            method = "POST"
            url = "https://example.com/upload"
            headers = [EditableReplayHeader(name: "Content-Type", value: "multipart/form-data; boundary=\(boundary)")]
            body = """
            --\(boundary)
            Content-Disposition: form-data; name="file"; filename="example.txt"
            Content-Type: text/plain

            Hello from Rockxy
            --\(boundary)--
            """
            syncURLToQuery(force: true)
        }
    }

    func importCurlCommand(_ command: String) throws {
        let tokens = Self.shellTokens(from: command)
        guard !tokens.isEmpty else {
            lastFormattingError = ComposeImportError.emptyCommand.localizedDescription
            throw ComposeImportError.emptyCommand
        }
        guard tokens.first == "curl" else {
            lastFormattingError = ComposeImportError.unsupportedCommand.localizedDescription
            throw ComposeImportError.unsupportedCommand
        }

        var importedMethod = "GET"
        var importedURL: String?
        var importedHeaders: [EditableReplayHeader] = []
        var importedBody: String?

        var index = 1
        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case "-X", "--request":
                if let value = tokens[safe: index + 1] {
                    importedMethod = value
                    index += 1
                }
            case let value where value.hasPrefix("-X") && value.count > 2:
                importedMethod = String(value.dropFirst(2))
            case let value where value.hasPrefix("--request="):
                importedMethod = String(value.dropFirst("--request=".count))
            case "-H", "--header":
                if let value = tokens[safe: index + 1] {
                    appendHeader(value, to: &importedHeaders)
                    index += 1
                }
            case let value where value.hasPrefix("--header="):
                appendHeader(String(value.dropFirst("--header=".count)), to: &importedHeaders)
            case "-d", "--data", "--data-raw", "--data-binary", "--data-ascii":
                if let value = tokens[safe: index + 1] {
                    importedBody = value
                    if importedMethod == "GET" {
                        importedMethod = "POST"
                    }
                    index += 1
                }
            case let value where value.hasPrefix("--data="):
                importedBody = String(value.dropFirst("--data=".count))
                if importedMethod == "GET" {
                    importedMethod = "POST"
                }
            case let value where value.hasPrefix("-"):
                break
            default:
                if importedURL == nil {
                    importedURL = token
                }
            }
            index += 1
        }

        guard let importedURL else {
            lastFormattingError = ComposeImportError.missingURL.localizedDescription
            throw ComposeImportError.missingURL
        }

        method = importedMethod.uppercased()
        url = importedURL
        headers = importedHeaders
        body = importedBody ?? ""
        sourceIsWebSocket = false
        responseState = .empty
        lastFormattingError = nil
        clearRestoreConfirmation()
        syncURLToQuery(force: true)
    }

    // MARK: - History

    func removeHistoryEntry(id: UUID) {
        history.removeAll { $0.id == id }
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    func restoreHistoryEntry(id: UUID) {
        guard let entry = history.first(where: { $0.id == id }) else {
            return
        }
        method = entry.method
        url = entry.url
        headers = entry.headers
        queryItems = entry.queryItems
        body = entry.body
        lastFormattingError = nil
        sourceIsWebSocket = false
        lastSyncedURL = entry.url
        if let statusCode = entry.statusCode {
            let responseBody = entry.responseBody ?? ""
            let contentType = ContentType.detect(from: entry.responseHeaders?.first {
                $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
            }?.value)
            let response = ComposeResponse(
                statusCode: statusCode,
                statusMessage: HTTPURLResponse.localizedString(forStatusCode: statusCode),
                headers: (entry.responseHeaders ?? []).map { ($0.name, $0.value) },
                bodyData: Data(responseBody.utf8),
                bodyText: responseBody,
                contentType: contentType
            )
            responseState = .success(response)
        } else {
            responseState = .empty
        }
        restoreConfirmationID = UUID()
        restoreConfirmationMessage = String(localized: "Restored from history")
    }

    func clearRestoreConfirmation() {
        restoreConfirmationMessage = nil
    }

    // MARK: - Body Import And Formatting

    func loadBodyFromFile(url fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL)
        body = String(data: data, encoding: .utf8) ?? ""
        lastFormattingError = nil
        clearRestoreConfirmation()
    }

    func prettifyJSONBody() {
        lastFormattingError = nil
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            lastFormattingError = String(localized: "Body is not valid JSON.")
            return
        }
        body = pretty
        clearRestoreConfirmation()
    }

    func prettifyXMLBody() {
        lastFormattingError = nil
        guard let data = body.data(using: .utf8),
              let document = try? XMLDocument(data: data, options: [.nodePreserveWhitespace]) else {
            lastFormattingError = String(localized: "Body is not valid XML.")
            return
        }
        body = document.xmlString(options: [.nodePrettyPrint])
        clearRestoreConfirmation()
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
    func syncURLToQuery(force: Bool = false) {
        guard force || url != lastSyncedURL else {
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
    private let historyStore: ComposeHistoryStore
    private var currentRunID: UInt64 = 0

    private func recordHistory(response: ComposeResponse?) {
        guard !sourceIsWebSocket else {
            return
        }
        let entry = ComposeHistoryEntry(
            method: method,
            url: url,
            headers: headers,
            queryItems: queryItems,
            body: body,
            bodyContentType: headerValue(named: "Content-Type", in: headers),
            statusCode: response?.statusCode,
            responseHeaders: response?.headers.map {
                EditableReplayHeader(name: $0.name, value: $0.value)
            },
            responseBody: response?.bodyDisplayText,
            timestamp: Date()
        )
        history.removeAll { $0.requestFingerprint == entry.requestFingerprint }
        history.insert(entry, at: 0)
        if history.count > historyStore.maxEntries {
            history.removeLast(history.count - historyStore.maxEntries)
        }
        persistHistory()
    }

    private func persistHistory() {
        do {
            try historyStore.save(history)
        } catch {
            Self.logger.error("Failed to persist compose history: \(error.localizedDescription)")
        }
    }

    private func headerValue(named name: String, in headers: [EditableReplayHeader]) -> String? {
        headers.first { $0.isEnabled && $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private func appendHeader(_ rawHeader: String, to headers: inout [EditableReplayHeader]) {
        guard let separator = rawHeader.firstIndex(of: ":") else {
            return
        }
        let name = rawHeader[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = rawHeader[rawHeader.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }
        headers.append(EditableReplayHeader(name: name, value: value))
    }

    private static func shellTokens(from command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for character in command {
            if isEscaping {
                if character != "\n" {
                    current.append(character)
                }
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

// MARK: - EditableReplayHeader

/// Identifiable header pair for the compose window's editable header list.
struct EditableReplayHeader: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var value: String
    var isEnabled = true

    init(id: UUID = UUID(), name: String, value: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.value = value
        self.isEnabled = isEnabled
    }
}

// MARK: - NoRedirectSessionDelegate

private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// MARK: - Collection Safe Subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
