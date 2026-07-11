import Foundation

// MARK: - AITrafficDetector

/// Lightweight, bounded parser for AI-model HTTP traffic.
///
/// The detector intentionally works from captured HTTP evidence only. It does not infer
/// provider internals, token boundaries, or pricing when those fields are not present.
nonisolated enum AITrafficDetector {
    // MARK: Internal

    static let maxBodyBytes = 256 * 1_024
    static let maxQuickScanBytes = 16 * 1_024

    static func isLikelyAI(transaction: HTTPTransaction) -> Bool {
        isLikelyAI(snapshot: AITrafficSnapshot(transaction: transaction))
    }

    static func signal(transaction: HTTPTransaction) -> AITrafficSignal {
        signal(snapshot: AITrafficSnapshot(transaction: transaction))
    }

    static func signal(snapshot: AITrafficSnapshot) -> AITrafficSignal {
        if let provider = provider(from: snapshot) {
            return AITrafficSignal(
                isLikelyAI: true,
                provider: provider,
                kind: signalKind(for: snapshot),
                evidence: evidence(for: snapshot)
            )
        }
        let likely = isLikelyAI(snapshot: snapshot)
        return AITrafficSignal(
            isLikelyAI: likely,
            provider: nil,
            kind: likely ? .heuristic : .none,
            evidence: likely ? evidence(for: snapshot) : []
        )
    }

    static func isLikelyAI(snapshot: AITrafficSnapshot) -> Bool {
        if provider(from: snapshot) != nil {
            return true
        }

        let requestPrefix = snapshot.requestBody
            .flatMap { String(bytes: $0.prefix(maxQuickScanBytes), encoding: .utf8)?.lowercased() } ?? ""
        if requestPrefix.contains(#""model""#),
           requestPrefix.contains(#""messages""#)
            || requestPrefix.contains(#""input""#)
            || requestPrefix.contains(#""tools""#)
        {
            return true
        }

        let responsePrefix = snapshot.responseBody
            .flatMap { String(bytes: $0.prefix(maxQuickScanBytes), encoding: .utf8)?.lowercased() } ?? ""
        return responsePrefix.contains(#""usage""#)
            && (responsePrefix.contains(#""input_tokens""#)
                || responsePrefix.contains(#""output_tokens""#)
                || responsePrefix.contains(#""prompt_tokens""#)
                || responsePrefix.contains(#""completion_tokens""#))
    }

    static func detect(transaction: HTTPTransaction) -> AIInspection? {
        detect(snapshot: AITrafficSnapshot(transaction: transaction))
    }

    static func detect(snapshot: AITrafficSnapshot) -> AIInspection? {
        let requestJSON = parseJSONObject(snapshot.requestBody)
        let responseJSON = parseJSONObject(snapshot.responseBody)
        let streamEvents = parseSSEEvents(snapshot.responseBody)
        let resolvedProvider = provider(from: snapshot) ?? provider(from: requestJSON, responseJSON: responseJSON)

        guard let resolvedProvider,
              isLikelyAI(snapshot: snapshot)
        else {
            return nil
        }

        let usage = usage(from: responseJSON, streamEvents: streamEvents)
        let toolCalls = toolCalls(from: requestJSON, responseJSON: responseJSON, streamEvents: streamEvents)
        let events = eventSummaries(
            snapshot: snapshot,
            responseJSON: responseJSON,
            streamEvents: streamEvents,
            toolCalls: toolCalls
        )
        let retrieval = retrievalMatches(snapshot: snapshot, responseJSON: responseJSON)
        let warnings = warnings(
            snapshot: snapshot,
            requestJSON: requestJSON,
            toolCalls: toolCalls,
            retrieval: retrieval
        )

        return AIInspection(
            provider: resolvedProvider,
            kind: signalKind(for: snapshot),
            evidence: evidence(for: snapshot),
            model: stringValue(forKey: "model", in: requestJSON)
                ?? stringValue(forKey: "model", in: responseJSON),
            endpoint: snapshot.path.isEmpty ? snapshot.urlString : snapshot.path,
            isStreaming: isStreaming(snapshot: snapshot, requestJSON: requestJSON, streamEvents: streamEvents),
            httpStatusCode: snapshot.responseStatusCode,
            duration: snapshot.duration,
            usage: usage,
            toolCalls: toolCalls,
            events: events,
            retrieval: retrieval,
            warnings: warnings,
            unavailableFields: unavailableFields(usage: usage, events: events, toolCalls: toolCalls)
        )
    }

    // MARK: Private

    private static func provider(from snapshot: AITrafficSnapshot) -> AIProvider? {
        let host = snapshot.host.lowercased()
        let path = snapshot.path.lowercased()
        let headerNames = snapshot.requestHeaders.map { $0.name.lowercased() }

        if host == "chatgpt.com"
            || host.hasSuffix(".chatgpt.com")
            || host == "desktop.chat.openai.com"
            || host.hasSuffix(".desktop.chat.openai.com")
        {
            return .chatGPT
        }
        if host == "claude.ai"
            || host.hasSuffix(".claude.ai")
        {
            return .claude
        }
        if host.contains("anthropic.com") || headerNames.contains("anthropic-version") {
            return .anthropic
        }
        if host.contains("openai.com")
            || path.contains("/v1/responses")
            || path.contains("/v1/chat/completions")
            || path.contains("/v1/embeddings")
        {
            return .openAICompatible
        }
        if path.contains("/chat/completions") || path.contains("/embeddings") {
            return .openAICompatible
        }
        return nil
    }

    private static func signalKind(for snapshot: AITrafficSnapshot) -> AITrafficSignalKind {
        if hasVisibleAIAPIEvidence(snapshot) {
            return .api
        }
        if isKnownNativeSession(snapshot) || hasHiddenTLSOnlyBody(snapshot) {
            return .session
        }
        return .heuristic
    }

    private static func hasVisibleAIAPIEvidence(_ snapshot: AITrafficSnapshot) -> Bool {
        let path = snapshot.path.lowercased()
        if path.contains("/v1/responses")
            || path.contains("/v1/chat/completions")
            || path.contains("/v1/messages")
            || path.contains("/v1/embeddings")
            || path.contains("/chat/completions")
            || path.contains("/embeddings")
        {
            return true
        }

        let requestPrefix = snapshot.requestBody
            .flatMap { String(bytes: $0.prefix(maxQuickScanBytes), encoding: .utf8)?.lowercased() } ?? ""
        let responsePrefix = snapshot.responseBody
            .flatMap { String(bytes: $0.prefix(maxQuickScanBytes), encoding: .utf8)?.lowercased() } ?? ""
        return requestPrefix.contains(#""model""#)
            || responsePrefix.contains(#""usage""#)
            || headerValue(named: "anthropic-version", in: snapshot.requestHeaders) != nil
    }

    private static func isKnownNativeSession(_ snapshot: AITrafficSnapshot) -> Bool {
        let host = snapshot.host.lowercased()
        return host == "chatgpt.com"
            || host.hasSuffix(".chatgpt.com")
            || host == "desktop.chat.openai.com"
            || host.hasSuffix(".desktop.chat.openai.com")
            || host == "claude.ai"
            || host.hasSuffix(".claude.ai")
    }

    private static func hasHiddenTLSOnlyBody(_ snapshot: AITrafficSnapshot) -> Bool {
        let method = snapshot.requestMethod.uppercased()
        let scheme = snapshot.scheme.lowercased()
        return method == "CONNECT"
            || ((scheme == "https" || scheme == "wss") && snapshot.requestBody == nil && snapshot.responseBody == nil)
    }

    private static func evidence(for snapshot: AITrafficSnapshot) -> [String] {
        var values: [String] = []
        if provider(from: snapshot) != nil {
            values.append("known host")
        }
        if hasVisibleAIAPIEvidence(snapshot) {
            values.append("api fields")
        }
        if snapshot.scheme.lowercased() == "wss" || headerValue(named: "upgrade", in: snapshot.requestHeaders)?.lowercased() == "websocket" {
            values.append("websocket")
        }
        if hasHiddenTLSOnlyBody(snapshot) {
            values.append("body hidden")
        }
        return Array(NSOrderedSet(array: values).compactMap { $0 as? String })
    }

    private static func provider(from requestJSON: [String: Any]?, responseJSON: [String: Any]?) -> AIProvider? {
        if stringValue(forKey: "model", in: requestJSON) != nil || stringValue(forKey: "model", in: responseJSON) != nil {
            return .openAICompatible
        }
        return nil
    }

    private static func parseJSONObject(_ data: Data?) -> [String: Any]? {
        guard let data, !data.isEmpty, data.count <= maxBodyBytes else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func stringValue(forKey key: String, in json: [String: Any]?) -> String? {
        json?[key] as? String
    }

    private static func intValue(forKey key: String, in json: [String: Any]?) -> Int? {
        if let int = json?[key] as? Int {
            return int
        }
        if let number = json?[key] as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func boolValue(forKey key: String, in json: [String: Any]?) -> Bool? {
        if let bool = json?[key] as? Bool {
            return bool
        }
        if let number = json?[key] as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private static func usage(from responseJSON: [String: Any]?, streamEvents: [AIStreamEvent]) -> AIUsage? {
        if let usage = usageObject(from: responseJSON) {
            return usage
        }

        for event in streamEvents.reversed() {
            guard let json = parseJSONObject(Data(event.data.utf8)),
                  let usage = usageObject(from: json)
            else {
                continue
            }
            return usage
        }
        return nil
    }

    private static func usageObject(from json: [String: Any]?) -> AIUsage? {
        guard let raw = json?["usage"] as? [String: Any] else {
            return nil
        }

        let cached = (raw["prompt_tokens_details"] as? [String: Any])
            .flatMap { intValue(forKey: "cached_tokens", in: $0) }
        let input = intValue(forKey: "input_tokens", in: raw)
            ?? intValue(forKey: "prompt_tokens", in: raw)
        let output = intValue(forKey: "output_tokens", in: raw)
            ?? intValue(forKey: "completion_tokens", in: raw)
        let total = intValue(forKey: "total_tokens", in: raw)
            ?? [input, output].compactMap { $0 }.reduce(0, +)

        guard input != nil || output != nil || total > 0 else {
            return nil
        }
        return AIUsage(inputTokens: input, cachedTokens: cached, outputTokens: output, totalTokens: total)
    }

    private static func toolCalls(
        from requestJSON: [String: Any]?,
        responseJSON: [String: Any]?,
        streamEvents: [AIStreamEvent]
    )
        -> [AIToolCall]
    {
        var calls: [AIToolCall] = []
        if let tools = requestJSON?["tools"] as? [[String: Any]] {
            calls += tools.compactMap { tool in
                let name = tool["name"] as? String
                    ?? (tool["function"] as? [String: Any])?["name"] as? String
                return name.map {
                    AIToolCall(name: $0, argumentsPreview: nil, state: .declared)
                }
            }
        }

        calls += responseToolCalls(from: responseJSON)

        for event in streamEvents where event.event?.lowercased().contains("tool") == true || event.data.contains("tool") {
            guard let json = parseJSONObject(Data(event.data.utf8)) else {
                calls.append(AIToolCall(name: "tool_call", argumentsPreview: event.data, state: .partial))
                continue
            }
            if let name = stringValue(forKey: "name", in: json) {
                calls.append(AIToolCall(
                    name: name,
                    argumentsPreview: stringValue(forKey: "arguments", in: json),
                    state: .streaming
                ))
            }
        }

        return Array(calls.prefix(12))
    }

    private static func responseToolCalls(from responseJSON: [String: Any]?) -> [AIToolCall] {
        if let output = responseJSON?["output"] as? [[String: Any]] {
            return output.compactMap { item in
                guard (item["type"] as? String)?.contains("function") == true else {
                    return nil
                }
                return AIToolCall(
                    name: item["name"] as? String ?? "tool_call",
                    argumentsPreview: item["arguments"] as? String,
                    state: .completed
                )
            }
        }

        let choices = responseJSON?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let calls = message?["tool_calls"] as? [[String: Any]] ?? []
        return calls.compactMap { call in
            let function = call["function"] as? [String: Any]
            return AIToolCall(
                name: function?["name"] as? String ?? "tool_call",
                argumentsPreview: function?["arguments"] as? String,
                state: .completed
            )
        }
    }

    private static func eventSummaries(
        snapshot: AITrafficSnapshot,
        responseJSON: [String: Any]?,
        streamEvents: [AIStreamEvent],
        toolCalls: [AIToolCall]
    )
        -> [AIEventSummary]
    {
        if !streamEvents.isEmpty {
            return streamEvents.enumerated().map { index, event in
                let eventName = event.event ?? "data"
                let category: AIEventCategory = eventName.lowercased().contains("tool") ? .tool : .stream
                let severity: AIEventSeverity = eventName.lowercased().contains("error") ? .error : .normal
                return AIEventSummary(
                    id: "stream-\(index)",
                    title: eventName,
                    detail: event.data,
                    offsetLabel: "#\(index + 1)",
                    category: category,
                    severity: severity
                )
            }
        }

        var events: [AIEventSummary] = [
            AIEventSummary(
                id: "request",
                title: "model request",
                detail: snapshot.urlString,
                offsetLabel: "request",
                category: .request,
                severity: .normal
            )
        ]
        events += toolCalls.enumerated().map { index, tool in
            AIEventSummary(
                id: "tool-\(index)",
                title: tool.name,
                detail: tool.argumentsPreview ?? tool.state.displayName,
                offsetLabel: tool.state.displayName,
                category: .tool,
                severity: .normal
            )
        }
        if let status = snapshot.responseStatusCode {
            events.append(AIEventSummary(
                id: "response",
                title: "response",
                detail: responseJSON?["status"] as? String ?? "HTTP \(status)",
                offsetLabel: "\(status)",
                category: .response,
                severity: status >= 400 ? .error : .normal
            ))
        }
        return events
    }

    private static func retrievalMatches(
        snapshot: AITrafficSnapshot,
        responseJSON: [String: Any]?
    )
        -> [AIRetrievalMatch]
    {
        let path = snapshot.path.lowercased()
        guard path.contains("search") || path.contains("embedding") || path.contains("retrieval") else {
            return []
        }

        let matches = responseJSON?["matches"] as? [[String: Any]]
            ?? responseJSON?["data"] as? [[String: Any]]
            ?? []
        return matches.prefix(8).enumerated().map { index, match in
            let source = match["id"] as? String ?? "match-\(index + 1)"
            let score = (match["score"] as? NSNumber)?.doubleValue
            return AIRetrievalMatch(
                source: source,
                score: score,
                signal: path.contains("embedding") ? "embedding" : "retrieval",
                risk: (match["snippet"] as? String)?.lowercased().contains("secret") == true ? "sensitive-context" : "visible"
            )
        }
    }

    private static func warnings(
        snapshot: AITrafficSnapshot,
        requestJSON: [String: Any]?,
        toolCalls: [AIToolCall],
        retrieval: [AIRetrievalMatch]
    )
        -> [AIWarning]
    {
        var warnings: [AIWarning] = []
        if headerValue(named: "authorization", in: snapshot.requestHeaders) != nil
            || headerValue(named: "x-api-key", in: snapshot.requestHeaders) != nil
        {
            warnings.append(AIWarning(message: "Authentication header is present.", severity: .redaction))
        }
        if requestJSON?["input"] != nil || requestJSON?["messages"] != nil {
            warnings.append(AIWarning(message: "Prompt content may require redaction.", severity: .redaction))
        }
        if !toolCalls.isEmpty {
            warnings.append(AIWarning(message: "Tool arguments may contain sensitive data.", severity: .redaction))
        }
        if retrieval.contains(where: { $0.risk == "sensitive-context" }) {
            warnings.append(AIWarning(message: "Retrieved context includes sensitive-looking snippets.", severity: .redaction))
        }
        if let status = snapshot.responseStatusCode, status >= 400 {
            warnings.append(AIWarning(message: "Provider returned HTTP \(status).", severity: .error))
        }
        return warnings
    }

    private static func unavailableFields(
        usage: AIUsage?,
        events: [AIEventSummary],
        toolCalls: [AIToolCall]
    )
        -> [String]
    {
        var fields: [String] = []
        if usage == nil {
            fields.append("usage")
        }
        if events.allSatisfy({ $0.category != .stream }) {
            fields.append("stream events")
        }
        if toolCalls.isEmpty {
            fields.append("tool calls")
        }
        return fields
    }

    private static func isStreaming(
        snapshot: AITrafficSnapshot,
        requestJSON: [String: Any]?,
        streamEvents: [AIStreamEvent]
    )
        -> Bool
    {
        boolValue(forKey: "stream", in: requestJSON) == true
            || !streamEvents.isEmpty
            || headerValue(named: "content-type", in: snapshot.responseHeaders)?.lowercased().contains("text/event-stream") == true
    }

    private static func parseSSEEvents(_ data: Data?) -> [AIStreamEvent] {
        guard let data,
              data.count <= maxBodyBytes,
              let text = String(data: data, encoding: .utf8),
              text.contains("data:")
        else {
            return []
        }

        var events: [AIStreamEvent] = []
        var currentEvent: String?
        var currentData: [String] = []

        func flush() {
            guard !currentData.isEmpty else {
                currentEvent = nil
                return
            }
            let data = currentData.joined(separator: "\n")
            if data.trimmingCharacters(in: .whitespacesAndNewlines) != "[DONE]" {
                events.append(AIStreamEvent(event: currentEvent, data: data))
            }
            currentEvent = nil
            currentData = []
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("event:") {
                currentEvent = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                currentData.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
            }
        }
        flush()
        return Array(events.prefix(200))
    }

    private static func headerValue(named name: String, in headers: [HTTPHeader]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

// MARK: - AITrafficSnapshot

struct AITrafficSnapshot: Sendable {
    init(transaction: HTTPTransaction) {
        requestMethod = transaction.request.method
        urlString = transaction.request.url.absoluteString
        scheme = transaction.request.url.scheme ?? ""
        host = transaction.request.host
        path = transaction.request.path
        requestHeaders = transaction.request.headers
        requestBody = transaction.request.body
        responseStatusCode = transaction.response?.statusCode
        responseHeaders = transaction.response?.headers ?? []
        responseBody = transaction.response?.body
        duration = transaction.timingInfo?.totalDuration ?? transaction.measuredDuration
    }

    let requestMethod: String
    let urlString: String
    let scheme: String
    let host: String
    let path: String
    let requestHeaders: [HTTPHeader]
    let requestBody: Data?
    let responseStatusCode: Int?
    let responseHeaders: [HTTPHeader]
    let responseBody: Data?
    let duration: TimeInterval?
}

// MARK: - AIInspection

struct AIInspection: Equatable, Sendable {
    let provider: AIProvider
    let kind: AITrafficSignalKind
    let evidence: [String]
    let model: String?
    let endpoint: String
    let isStreaming: Bool
    let httpStatusCode: Int?
    let duration: TimeInterval?
    let usage: AIUsage?
    let toolCalls: [AIToolCall]
    let events: [AIEventSummary]
    let retrieval: [AIRetrievalMatch]
    let warnings: [AIWarning]
    let unavailableFields: [String]
}

enum AIProvider: String, Sendable {
    case openAICompatible
    case anthropic
    case chatGPT
    case claude

    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        }
    }
}

enum AITrafficSignalKind: String, Equatable, Sendable {
    case none
    case api
    case session
    case heuristic
}

struct AITrafficSignal: Equatable, Sendable {
    let isLikelyAI: Bool
    let provider: AIProvider?
    let kind: AITrafficSignalKind
    let evidence: [String]

    var tableLabel: String {
        guard isLikelyAI else {
            return ""
        }
        switch kind {
        case .api:
            return "AI API"
        case .session:
            return "AI Session"
        case .heuristic:
            return "Likely AI"
        case .none:
            return "AI"
        }
    }

    var accessibilityLabel: String {
        guard isLikelyAI else {
            return ""
        }
        if let provider {
            let evidenceLabel = evidence.isEmpty ? "" : " (\(evidence.joined(separator: ", ")))"
            return "\(tableLabel): \(provider.displayName)\(evidenceLabel)"
        }
        return tableLabel
    }
}

struct AIUsage: Equatable, Sendable {
    let inputTokens: Int?
    let cachedTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int
}

struct AIToolCall: Equatable, Sendable {
    let name: String
    let argumentsPreview: String?
    let state: AIToolCallState
}

enum AIToolCallState: String, Sendable {
    case declared
    case streaming
    case completed
    case partial

    var displayName: String {
        rawValue
    }
}

struct AIEventSummary: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let offsetLabel: String
    let category: AIEventCategory
    let severity: AIEventSeverity
}

enum AIEventCategory: String, Sendable {
    case request
    case stream
    case tool
    case response
}

enum AIEventSeverity: String, Sendable {
    case normal
    case warning
    case error
}

struct AIRetrievalMatch: Equatable, Sendable {
    let source: String
    let score: Double?
    let signal: String
    let risk: String
}

struct AIWarning: Equatable, Sendable {
    let message: String
    let severity: AIWarningSeverity
}

enum AIWarningSeverity: String, Sendable {
    case redaction
    case error
}

private struct AIStreamEvent: Equatable {
    let event: String?
    let data: String
}
