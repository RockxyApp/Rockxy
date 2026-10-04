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
        let responses = BoundedComposeRequestOperation.responses(
            for: request,
            configuration: RequestReplay.proxyBypassSession.configuration,
            followsRedirects: followsRedirects,
            maximumBytes: ProxyLimits.maxResponseBodySize
        )
        for try await response in responses {
            return response
        }
        throw ReplayError.invalidResponse
    }
}

// MARK: - ComposeResponseError

enum ComposeResponseError: LocalizedError, Equatable {
    case bodyTooLarge(limitBytes: Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .bodyTooLarge(limitBytes):
            let limitMB = Double(limitBytes) / (1_024 * 1_024)
            return String(
                localized: "The response body exceeded the \(DecimalFormatter.format(limitMB, fractionDigits: 0)) MB Compose limit.",
                bundle: RockxyLocalization.bundle
            )
        }
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
            String(localized: "15 seconds", bundle: RockxyLocalization.bundle)
        case .thirty:
            String(localized: "30 seconds", bundle: RockxyLocalization.bundle)
        case .sixty:
            String(localized: "60 seconds", bundle: RockxyLocalization.bundle)
        case .none:
            String(localized: "0 (No Timeout)", bundle: RockxyLocalization.bundle)
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
            String(localized: "Empty Request", bundle: RockxyLocalization.bundle)
        case .getWithQuery:
            String(localized: "GET with Query", bundle: RockxyLocalization.bundle)
        case .postJSON:
            String(localized: "POST with JSON", bundle: RockxyLocalization.bundle)
        case .postForm:
            String(localized: "POST with Form", bundle: RockxyLocalization.bundle)
        case .postMultipart:
            String(localized: "POST with Multiparts", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ComposeImportError

enum ComposeImportError: LocalizedError, Equatable {
    case emptyCommand
    case unsupportedCommand
    case missingURL
    case fileBackedBodyUnsupported

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            String(localized: "Pasteboard does not contain a cURL command.", bundle: RockxyLocalization.bundle)
        case .unsupportedCommand:
            String(localized: "Only cURL commands can be imported.", bundle: RockxyLocalization.bundle)
        case .missingURL:
            String(localized: "The cURL command does not contain a URL.", bundle: RockxyLocalization.bundle)
        case .fileBackedBodyUnsupported:
            String(
                localized: "File-backed cURL bodies are not imported automatically. Load the file from the Body tab instead.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

// MARK: - ComposeBodyImportError

enum ComposeBodyImportError: LocalizedError, Equatable {
    case unsupportedTextEncoding

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .unsupportedTextEncoding:
            String(localized: "The selected file is not valid UTF-8 text.", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ComposeHistoryEntry

struct ComposeHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

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

    // MARK: Internal

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

    var menuTitle: String {
        let status = statusCode.map { "\($0)" } ?? String(localized: "No Response", bundle: RockxyLocalization.bundle)
        return "[\(method)] \(url) • \(status) • \(TimestampFormatter.relative(timestamp, unitsStyle: .abbreviated))"
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
    let bodyTruncated: Bool

    var bodyDisplayText: String {
        if let text = bodyText {
            return text
        }
        return String(AttributedString(
            localized: "(binary data, ^[\(bodyData.count) byte](inflect: true))",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
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
        historyStore: ComposeHistoryStore = .live,
        bodyImportSizeLimit: UInt64 = UInt64(ProxyLimits.maxRequestBodySize)
    ) {
        self.executor = executor
        self.historyStore = historyStore
        self.bodyImportSizeLimit = bodyImportSizeLimit
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
    /// Receives each finished send as a session row. The default hands it to the workspace so
    /// Compose and Edit and Repeat results can be inspected and exported like a Repeat.
    var onExchangeCompleted: @MainActor (HTTPTransaction) -> Void = { transaction in
        NotificationCenter.default.post(name: .composeExchangeDidComplete, object: transaction)
    }
    private(set) var history: [ComposeHistoryEntry] = []
    private(set) var lastFormattingError: String?
    private(set) var restoreConfirmationID = UUID()
    private(set) var restoreConfirmationMessage: String?

    // MARK: - Response State

    private(set) var responseState: ComposeResponseState = .empty

    /// Whether the original captured transaction was a WebSocket connection.
    /// Immutable per draft — editing the method does not change WebSocket origin.
    private(set) var sourceIsWebSocket = false
    /// Prevents Edit & Repeat from silently dropping captured binary request bodies
    /// that the text-only Compose editor cannot represent faithfully.
    private(set) var sourceHasUnsupportedBinaryBody = false
    /// Prevents a body capped for on-disk history from being sent as though it
    /// were the original complete request.
    private(set) var sourceHasTruncatedHistoryBody = false

    // MARK: - Query Sync

    /// Guards against infinite URL ↔ query sync loops.
    var lastSyncedURL: String = ""

    /// Whether the current draft cannot be faithfully replayed via URLSession.
    var isUnsupportedForReplay: Bool {
        replayRestrictionMessage != nil
    }

    var replayRestrictionMessage: String? {
        if sourceIsWebSocket {
            return String(
                localized: "WebSocket requests cannot be replayed as HTTP requests.",
                bundle: RockxyLocalization.bundle
            )
        }
        if method == "CONNECT" {
            return String(
                localized: "CONNECT requests cannot be replayed from Compose.",
                bundle: RockxyLocalization.bundle
            )
        }
        if sourceHasUnsupportedBinaryBody {
            return String(
                localized: "This captured request has a binary body that the text editor cannot replay safely. Replace it in the Body tab or use an empty body.",
                bundle: RockxyLocalization.bundle
            )
        }
        if sourceHasTruncatedHistoryBody {
            return String(
                localized: "This request body was shortened for local history storage. Replace it in the Body tab before sending.",
                bundle: RockxyLocalization.bundle
            )
        }
        return nil
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
            lines.append("Host: \(host)\(parsedURL?.port.map { ":\($0)" } ?? "")")
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
        invalidateActiveRun()
        clearRestoreConfirmation()
        method = transaction.request.method
        url = transaction.request.url.absoluteString
        headers = transaction.request.headers
            .filter { !RequestReplay.isTransportManagedHeader($0.name) }
            .map { EditableReplayHeader(name: $0.name, value: $0.value) }
        if let bodyData = transaction.request.body {
            if let bodyText = String(data: bodyData, encoding: .utf8) {
                body = bodyText
                sourceHasUnsupportedBinaryBody = false
            } else {
                body = ""
                sourceHasUnsupportedBinaryBody = true
            }
        } else {
            body = ""
            sourceHasUnsupportedBinaryBody = false
        }
        sourceHasTruncatedHistoryBody = false
        sourceIsWebSocket = transaction.webSocketConnection != nil
        syncURLToQuery()
        responseState = .empty
        syncUnsupportedState()
    }

    /// Reset only the active editor draft. History and request options remain intact,
    /// so opening a fresh Compose window feels native without erasing user preferences.
    func resetDraft() {
        invalidateActiveRun()
        clearRestoreConfirmation()
        method = "GET"
        url = ""
        headers = []
        body = ""
        queryItems = []
        lastFormattingError = nil
        sourceIsWebSocket = false
        sourceHasUnsupportedBinaryBody = false
        sourceHasTruncatedHistoryBody = false
        lastSyncedURL = ""
        responseState = .empty
    }

    /// Send the current request draft. Uses latest-run-wins: if a newer send
    /// starts before this one completes, the stale result is silently discarded.
    func send() async {
        guard !Task.isCancelled else {
            return
        }
        let runID = UUID()
        activeRunID = runID
        clearRestoreConfirmation()

        if let replayRestrictionMessage {
            activeRunID = nil
            responseState = .unsupported(replayRestrictionMessage)
            return
        }

        guard let requestURL = URL(string: url) else {
            activeRunID = nil
            responseState = .error(String(localized: "Invalid URL", bundle: RockxyLocalization.bundle))
            return
        }

        let requestSnapshot = sentRequestSnapshot()
        responseState = .loading

        var request = URLRequest(url: requestURL)
        request.httpMethod = requestSnapshot.method
        for header in requestSnapshot.headers where header.isEnabled && !header.name.isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if !requestSnapshot.body.isEmpty {
            request.httpBody = Data(requestSnapshot.body.utf8)
        }
        request.timeoutInterval = requestTimeout.interval
        let startedAt = Date()

        do {
            let (data, httpResponse) = try await executor.execute(request, followsRedirects: followsRedirects)

            guard runID == activeRunID else {
                Self.logger.debug("Discarding stale Compose response")
                return
            }
            let bodyText = try await Self.decodeUTF8Body(data)
            try Task.checkCancellation()
            guard runID == activeRunID else {
                Self.logger.debug("Discarding stale Compose response")
                return
            }

            let responseHeaders = httpResponse.allHeaderFields.map { ("\($0.key)", "\($0.value)") }
            let contentTypeHeader = httpResponse.value(forHTTPHeaderField: "Content-Type")
            let contentType = ContentType.detect(from: contentTypeHeader)

            let response = ComposeResponse(
                statusCode: httpResponse.statusCode,
                statusMessage: HTTPReasonPhrase.standard(for: httpResponse.statusCode),
                headers: responseHeaders,
                bodyData: data,
                bodyText: bodyText,
                contentType: contentType,
                bodyTruncated: false
            )
            activeRunID = nil
            responseState = .success(response)
            onExchangeCompleted(Self.makeSessionTransaction(
                url: requestURL,
                method: requestSnapshot.method,
                headers: requestSnapshot.headers,
                requestBody: requestSnapshot.body,
                response: httpResponse,
                body: data,
                startedAt: startedAt
            ))
            await recordHistory(request: requestSnapshot, response: response)
            Self.logger.info("Compose send succeeded: \(httpResponse.statusCode)")
        } catch {
            if Task.isCancelled ||
                error is CancellationError ||
                (error as? URLError)?.code == .cancelled
            {
                if runID == activeRunID {
                    activeRunID = nil
                    responseState = .empty
                }
                return
            }
            guard runID == activeRunID else {
                Self.logger.debug("Discarding stale Compose error")
                return
            }
            activeRunID = nil
            responseState = .error(error.localizedDescription)
            onExchangeCompleted(Self.makeSessionTransaction(
                url: requestURL,
                method: requestSnapshot.method,
                headers: requestSnapshot.headers,
                requestBody: requestSnapshot.body,
                response: nil,
                body: nil,
                startedAt: startedAt
            ))
            await recordHistory(request: requestSnapshot, response: nil)
            Self.logger.error("Compose send failed: \(error.localizedDescription)")
        }
    }

    func cancelActiveSend() {
        guard activeRunID != nil else {
            return
        }
        activeRunID = nil
        responseState = .empty
    }

    // MARK: - Templates

    func applyTemplate(_ template: ComposeTemplate) {
        invalidateActiveRun()
        clearRestoreConfirmation()
        sourceIsWebSocket = false
        sourceHasUnsupportedBinaryBody = false
        sourceHasTruncatedHistoryBody = false
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

    /// Imports the URL field's text when it is a cURL command, so a command pasted straight into
    /// the URL bar behaves like the explicit import. Returns `false` when the field holds a
    /// plain URL. A failed parse rethrows without leaving a stale formatting notice behind, so
    /// callers can stay silent while the command is still being typed.
    func importCurlCommandFromURLFieldIfNeeded() throws -> Bool {
        let candidate = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate == "curl" || candidate.hasPrefix("curl ") else {
            return false
        }
        let previousFormattingError = lastFormattingError
        do {
            try importCurlCommand(candidate)
        } catch {
            lastFormattingError = previousFormattingError
            throw error
        }
        return true
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
            case "-X",
                 "--request":
                if let value = tokens[safe: index + 1] {
                    importedMethod = value
                    index += 1
                }
            case let value where value.hasPrefix("-X") && value.count > 2:
                importedMethod = String(value.dropFirst(2))
            case let value where value.hasPrefix("--request="):
                importedMethod = String(value.dropFirst("--request=".count))
            case "-H",
                 "--header":
                if let value = tokens[safe: index + 1] {
                    appendHeader(value, to: &importedHeaders)
                    index += 1
                }
            case let value where value.hasPrefix("--header="):
                appendHeader(String(value.dropFirst("--header=".count)), to: &importedHeaders)
            case "--data-raw":
                if let value = tokens[safe: index + 1] {
                    importedBody = value
                    if importedMethod == "GET" {
                        importedMethod = "POST"
                    }
                    index += 1
                }
            case "-d",
                 "--data",
                 "--data-binary",
                 "--data-ascii":
                if let value = tokens[safe: index + 1] {
                    try rejectFileBackedCurlBody(value)
                    importedBody = value
                    if importedMethod == "GET" {
                        importedMethod = "POST"
                    }
                    index += 1
                }
            case let value where value.hasPrefix("-d") && value.count > 2:
                let bodyValue = String(value.dropFirst(2))
                try rejectFileBackedCurlBody(bodyValue)
                importedBody = bodyValue
                if importedMethod == "GET" {
                    importedMethod = "POST"
                }
            case let value where value.hasPrefix("--data-raw="):
                importedBody = String(value.dropFirst("--data-raw=".count))
                if importedMethod == "GET" {
                    importedMethod = "POST"
                }
            case let value where value.hasPrefix("--data="):
                let bodyValue = String(value.dropFirst("--data=".count))
                try rejectFileBackedCurlBody(bodyValue)
                importedBody = bodyValue
                if importedMethod == "GET" {
                    importedMethod = "POST"
                }
            case let value where value.hasPrefix("--data-binary="):
                let bodyValue = String(value.dropFirst("--data-binary=".count))
                try rejectFileBackedCurlBody(bodyValue)
                importedBody = bodyValue
                if importedMethod == "GET" {
                    importedMethod = "POST"
                }
            case let value where value.hasPrefix("--data-ascii="):
                let bodyValue = String(value.dropFirst("--data-ascii=".count))
                try rejectFileBackedCurlBody(bodyValue)
                importedBody = bodyValue
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

        invalidateActiveRun()
        method = importedMethod.uppercased()
        url = importedURL
        headers = importedHeaders
        body = importedBody ?? ""
        sourceIsWebSocket = false
        sourceHasUnsupportedBinaryBody = false
        sourceHasTruncatedHistoryBody = false
        responseState = .empty
        lastFormattingError = nil
        clearRestoreConfirmation()
        syncURLToQuery(force: true)
    }

    // MARK: - History

    func removeHistoryEntry(id: UUID) async {
        history.removeAll { $0.id == id }
        await persistHistory()
    }

    func clearHistory() async {
        historyClearGeneration += 1
        history.removeAll()
        await persistHistory()
    }

    func restoreHistoryEntry(id: UUID) {
        guard let entry = history.first(where: { $0.id == id }) else {
            return
        }
        invalidateActiveRun()
        method = entry.method
        url = entry.url
        headers = entry.headers
        queryItems = entry.queryItems
        body = entry.body
        lastFormattingError = nil
        sourceIsWebSocket = false
        sourceHasUnsupportedBinaryBody = false
        sourceHasTruncatedHistoryBody = entry.bodyTruncated
        lastSyncedURL = entry.url
        if let statusCode = entry.statusCode {
            let responseBody = entry.responseBody ?? ""
            let contentType = ContentType.detect(from: entry.responseHeaders?.first {
                $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
            }?.value)
            let response = ComposeResponse(
                statusCode: statusCode,
                statusMessage: HTTPReasonPhrase.standard(for: statusCode),
                headers: (entry.responseHeaders ?? []).map { ($0.name, $0.value) },
                bodyData: Data(responseBody.utf8),
                bodyText: responseBody,
                contentType: contentType,
                bodyTruncated: entry.responseBodyTruncated
            )
            responseState = .success(response)
        } else {
            responseState = .empty
        }
        restoreConfirmationID = UUID()
        restoreConfirmationMessage = String(localized: "Restored from history", bundle: RockxyLocalization.bundle)
    }

    func clearRestoreConfirmation() {
        restoreConfirmationMessage = nil
    }

    // MARK: - Body Import And Formatting

    func loadBodyFromFile(url fileURL: URL) async throws {
        let isSecurityScoped = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let importedBody = try await Self.readUTF8Body(
                from: fileURL,
                maximumBytes: bodyImportSizeLimit
            )
            replaceUnavailableBody(with: importedBody)
            lastFormattingError = nil
            clearRestoreConfirmation()
        } catch {
            lastFormattingError = error.localizedDescription
            throw error
        }
    }

    func replaceUnavailableBody(with replacement: String) {
        body = replacement
        sourceHasUnsupportedBinaryBody = false
        sourceHasTruncatedHistoryBody = false
        syncUnsupportedState()
    }

    func prettifyJSONBody() {
        lastFormattingError = nil
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let pretty = String(data: prettyData, encoding: .utf8) else
        {
            lastFormattingError = String(localized: "Body is not valid JSON.", bundle: RockxyLocalization.bundle)
            return
        }
        body = pretty
        clearRestoreConfirmation()
    }

    func prettifyXMLBody() {
        lastFormattingError = nil
        guard let data = body.data(using: .utf8),
              let document = try? XMLDocument(data: data, options: [.nodePreserveWhitespace]) else
        {
            lastFormattingError = String(localized: "Body is not valid XML.", bundle: RockxyLocalization.bundle)
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
                replayRestrictionMessage ?? String(
                    localized: "Replay is not supported for this request type.",
                    bundle: RockxyLocalization.bundle
                )
            )
        case .unsupported where !isUnsupportedForReplay:
            responseState = .empty
        default:
            break
        }
    }

    // MARK: Private

    private struct SentRequestSnapshot {
        let method: String
        let url: String
        let headers: [EditableReplayHeader]
        let queryItems: [EditableQueryItem]
        let body: String
        let bodyContentType: String?
        let sourceIsWebSocket: Bool
    }

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ComposeViewModel")

    private var historyClearGeneration = 0

    private let executor: ComposeRequestExecutor
    private let historyStore: ComposeHistoryStore
    private let bodyImportSizeLimit: UInt64
    private var activeRunID: UUID?

    nonisolated private static func readUTF8Body(
        from fileURL: URL,
        maximumBytes: UInt64
    )
        async throws -> String
    {
        let readTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? fileHandle.close() }

            var data = Data()
            let chunkSize = 64 * 1_024
            while let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty {
                try Task.checkCancellation()
                let nextSize = UInt64(data.count) + UInt64(chunk.count)
                guard nextSize <= maximumBytes else {
                    throw ImportSizeError.fileTooLarge(
                        actualBytes: nextSize,
                        limitBytes: maximumBytes
                    )
                }
                data.append(chunk)
            }
            guard let importedBody = String(data: data, encoding: .utf8) else {
                throw ComposeBodyImportError.unsupportedTextEncoding
            }
            return importedBody
        }
        return try await withTaskCancellationHandler {
            try await readTask.value
        } onCancel: {
            readTask.cancel()
        }
    }

    nonisolated private static func decodeUTF8Body(_ data: Data) async throws -> String? {
        let decodeTask = Task.detached(priority: .userInitiated) { () throws -> String? in
            var decoded = ""
            decoded.reserveCapacity(data.count)
            var start = data.startIndex
            let chunkSize = 1_024 * 1_024

            while start < data.endIndex {
                try Task.checkCancellation()
                let remaining = data.distance(from: start, to: data.endIndex)
                let tentativeEnd = data.index(start, offsetBy: min(chunkSize, remaining))
                var end = tentativeEnd
                if end < data.endIndex {
                    while end > start, data[end] & 0b11000000 == 0b10000000 {
                        end = data.index(before: end)
                    }
                }
                guard end > start,
                      let chunk = String(data: Data(data[start ..< end]), encoding: .utf8) else
                {
                    return nil
                }
                decoded.append(chunk)
                start = end
            }
            try Task.checkCancellation()
            return decoded
        }
        return try await withTaskCancellationHandler {
            try await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }
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

    private func invalidateActiveRun() {
        activeRunID = nil
    }

    private func sentRequestSnapshot() -> SentRequestSnapshot {
        SentRequestSnapshot(
            method: method,
            url: url,
            headers: headers,
            queryItems: queryItems,
            body: body,
            bodyContentType: headerValue(named: "Content-Type", in: headers),
            sourceIsWebSocket: sourceIsWebSocket
        )
    }

    private func recordHistory(request: SentRequestSnapshot, response: ComposeResponse?) async {
        guard !request.sourceIsWebSocket else {
            return
        }
        let clearGeneration = historyClearGeneration
        let fullEntry = ComposeHistoryEntry(
            method: request.method,
            url: request.url,
            headers: request.headers,
            queryItems: request.queryItems,
            body: request.body,
            bodyContentType: request.bodyContentType,
            statusCode: response?.statusCode,
            responseHeaders: response?.headers.map {
                EditableReplayHeader(name: $0.name, value: $0.value)
            },
            responseBody: response?.bodyDisplayText,
            timestamp: Date()
        )
        let entry = await historyStore.boundedEntry(fullEntry)
        guard clearGeneration == historyClearGeneration else {
            return
        }
        history.removeAll { $0.requestFingerprint == entry.requestFingerprint }
        history.append(entry)
        history.sort { $0.timestamp > $1.timestamp }
        if history.count > historyStore.maxEntries {
            history.removeLast(history.count - historyStore.maxEntries)
        }
        await persistHistory()
    }

    private func persistHistory() async {
        do {
            try await historyStore.save(history)
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

    private func rejectFileBackedCurlBody(_ value: String) throws {
        guard value.hasPrefix("@") else {
            return
        }
        lastFormattingError = ComposeImportError.fileBackedBodyUnsupported.localizedDescription
        throw ComposeImportError.fileBackedBodyUnsupported
    }
}

// MARK: - EditableReplayHeader

/// Identifiable header pair for the compose window's editable header list.
struct EditableReplayHeader: Codable, Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), name: String, value: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.value = value
        self.isEnabled = isEnabled
    }

    // MARK: Internal

    let id: UUID
    var name: String
    var value: String
    var isEnabled = true
}

// MARK: - BoundedComposeRequestOperation

final class BoundedComposeRequestOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        request: URLRequest,
        configuration: URLSessionConfiguration,
        followsRedirects: Bool,
        maximumBytes: Int,
        continuation: AsyncThrowingStream<(Data, HTTPURLResponse), Error>.Continuation
    ) {
        self.request = request
        self.configuration = configuration
        self.followsRedirects = followsRedirects
        self.maximumBytes = maximumBytes
        self.continuation = continuation
    }

    // MARK: Internal

    static func responses(
        for request: URLRequest,
        configuration: URLSessionConfiguration,
        followsRedirects: Bool,
        maximumBytes: Int
    )
        -> AsyncThrowingStream<(Data, HTTPURLResponse), Error>
    {
        AsyncThrowingStream { continuation in
            let operation = BoundedComposeRequestOperation(
                request: request,
                configuration: configuration,
                followsRedirects: followsRedirects,
                maximumBytes: maximumBytes,
                continuation: continuation
            )
            continuation.onTermination = { _ in
                operation.cancel()
            }
            if Task.isCancelled {
                continuation.finish(throwing: CancellationError())
            } else {
                operation.start()
            }
        }
    }

    static func redirectedRequest(_ request: URLRequest, followsRedirects: Bool) -> URLRequest? {
        followsRedirects ? request : nil
    }

    func start() {
        delegateQueue.addOperation { [weak self] in
            self?.startOnDelegateQueue()
        }
    }

    func cancel() {
        cancellationLock.lock()
        cancellationRequested = true
        let task = dataTask
        cancellationLock.unlock()
        task?.cancel()
        delegateQueue.addOperation { [weak self] in
            self?.cancelOnDelegateQueue()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Self.redirectedRequest(request, followsRedirects: followsRedirects))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(throwing: ReplayError.invalidResponse)
            return
        }
        if response.expectedContentLength > Int64(maximumBytes) {
            completionHandler(.cancel)
            finish(throwing: ComposeResponseError.bodyTooLarge(limitBytes: maximumBytes))
            return
        }
        self.response = httpResponse
        if response.expectedContentLength > 0 {
            let reserveLimit = 1_024 * 1_024
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumBytes, reserveLimit))
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard !isFinished else {
            return
        }
        guard chunk.count <= maximumBytes,
              data.count <= maximumBytes - chunk.count else
        {
            dataTask.cancel()
            finish(throwing: ComposeResponseError.bodyTooLarge(limitBytes: maximumBytes))
            return
        }
        data.append(chunk)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard !isFinished else {
            return
        }
        if let error {
            finish(throwing: error)
            return
        }
        guard let response else {
            finish(throwing: ReplayError.invalidResponse)
            return
        }
        finish(returning: (data, response))
    }

    // MARK: Private

    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let followsRedirects: Bool
    private let maximumBytes: Int
    private let continuation: AsyncThrowingStream<(Data, HTTPURLResponse), Error>.Continuation
    private let cancellationLock = NSLock()
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.amunx.rockxy.compose-response"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var isFinished = false
    private var cancellationRequested = false

    private func startOnDelegateQueue() {
        guard !isFinished else {
            return
        }
        cancellationLock.lock()
        let wasCancelled = cancellationRequested
        cancellationLock.unlock()
        guard !wasCancelled else {
            finish(throwing: CancellationError())
            return
        }
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
        self.session = session
        let task = session.dataTask(with: request)
        cancellationLock.lock()
        dataTask = task
        let wasCancelledAfterCreation = cancellationRequested
        cancellationLock.unlock()
        guard !wasCancelledAfterCreation else {
            task.cancel()
            finish(throwing: CancellationError())
            return
        }
        task.resume()
    }

    private func cancelOnDelegateQueue() {
        guard !isFinished else {
            return
        }
        finish(throwing: CancellationError())
    }

    private func finish(returning result: (Data, HTTPURLResponse)) {
        guard !isFinished else {
            return
        }
        isFinished = true
        continuation.yield(result)
        continuation.finish()
        session?.finishTasksAndInvalidate()
    }

    private func finish(throwing error: Error) {
        guard !isFinished else {
            return
        }
        isFinished = true
        session?.invalidateAndCancel()
        continuation.finish(throwing: error)
    }
}

// MARK: - Collection Safe Subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
