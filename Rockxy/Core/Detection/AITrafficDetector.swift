import Foundation

// MARK: - AITrafficDetector

/// Lightweight, bounded parser for AI-model HTTP traffic.
///
/// The detector intentionally works from captured HTTP evidence only. It does not infer
/// provider internals, token boundaries, or pricing when those fields are not present.
///
/// `signal(...)` runs for every request-list row, so it only scans bounded prefixes.
/// `detect(...)` runs for the selected transaction and parses the full (bounded) bodies,
/// including OpenAI chat/Responses, Anthropic Messages, Gemini, and Ollama shapes, in both
/// their JSON and streamed (SSE / NDJSON) forms.
nonisolated enum AITrafficDetector {
    struct ParsedStreamEvent {
        let event: AIStreamEvent
        let json: [String: Any]?
    }

    static let maxBodyBytes = 256 * 1_024
    static let maxQuickScanBytes = 16 * 1_024
    static let maxStreamEvents = 400
    static let maxAssembledOutputCharacters = 20_000

    static func isLikelyAI(transaction: HTTPTransaction) -> Bool {
        isLikelyAI(snapshot: AITrafficSnapshot(transaction: transaction))
    }

    /// Memoized per transaction: the request list rebuilds every row on each capture batch, and
    /// a body scan per row per batch made that quadratic. The entry is reused only while the
    /// same transaction's request and response evidence is unchanged.
    static func signal(transaction: HTTPTransaction) -> AITrafficSignal {
        let cacheKey = transaction.id as NSUUID
        if let cached = signalCache.object(forKey: cacheKey),
           cached.transaction === transaction, cached.revision == transaction.signalEvidenceRevision
        {
            return cached.signal
        }
        let signal = signal(snapshot: AITrafficSnapshot(transaction: transaction))
        signalCache.setObject(SignalCacheEntry(transaction: transaction, signal: signal), forKey: cacheKey)
        return signal
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

        let requestPrefix = lowercasedPrefix(of: snapshot.requestBody)
        if contains(requestPrefix, #""model""#),
           contains(requestPrefix, #""messages""#)
           || contains(requestPrefix, #""input""#)
           || contains(requestPrefix, #""tools""#)
           || contains(requestPrefix, #""prompt""#)
        {
            return true
        }
        if contains(requestPrefix, #""contents""#), contains(requestPrefix, #""parts""#) {
            return true
        }

        let responsePrefix = lowercasedPrefix(of: snapshot.responseBody)
        if contains(responsePrefix, #""usagemetadata""#), contains(responsePrefix, #""candidates""#) {
            return true
        }
        if contains(responsePrefix, #""prompt_eval_count""#) || contains(responsePrefix, #""eval_count""#) {
            return true
        }
        return contains(responsePrefix, #""usage""#)
            && (contains(responsePrefix, #""input_tokens""#)
                || contains(responsePrefix, #""output_tokens""#)
                || contains(responsePrefix, #""prompt_tokens""#)
                || contains(responsePrefix, #""completion_tokens""#))
    }

    static func detect(transaction: HTTPTransaction) -> AIInspection? {
        detect(snapshot: AITrafficSnapshot(transaction: transaction))
    }

    static func detect(snapshot: AITrafficSnapshot) -> AIInspection? {
        let requestJSON = parseJSONObject(snapshot.requestBody)
        let responseJSON = parseJSONObject(snapshot.responseBody)
        let transport = streamTransport(snapshot: snapshot, responseJSON: responseJSON)
        let streamEvents: [AIStreamEvent] = switch transport {
        case .sse: parseSSEEvents(snapshot.responseBody)
        case .ndjson: parseNDJSONEvents(snapshot.responseBody)
        case .none: []
        }
        let resolvedProvider = provider(from: snapshot)
            ?? provider(from: requestJSON, responseJSON: responseJSON, streamEvents: streamEvents)

        guard let resolvedProvider,
              isLikelyAI(snapshot: snapshot) else
        {
            return nil
        }

        let parsedEvents = streamEvents.map { ParsedStreamEvent(event: $0, json: parseJSONObject(Data($0.data.utf8))) }
        let usage = usage(provider: resolvedProvider, responseJSON: responseJSON, streamEvents: parsedEvents)
        let declaredTools = declaredTools(from: requestJSON)
        let invokedTools = invokedToolCalls(
            provider: resolvedProvider,
            responseJSON: responseJSON,
            streamEvents: parsedEvents
        )
        let toolCalls = Array((declaredTools + invokedTools).prefix(24))
        let finishReason = finishReason(
            provider: resolvedProvider,
            responseJSON: responseJSON,
            streamEvents: parsedEvents
        )
        let assembledOutput = assembledOutput(
            provider: resolvedProvider,
            responseJSON: responseJSON,
            streamEvents: parsedEvents
        )
        let events = eventSummaries(
            snapshot: snapshot,
            responseJSON: responseJSON,
            streamEvents: parsedEvents,
            toolCalls: invokedTools,
            finishReason: finishReason
        )
        let retrieval = retrievalMatches(snapshot: snapshot, responseJSON: responseJSON)
        let warnings = warnings(
            snapshot: snapshot,
            requestJSON: requestJSON,
            responseJSON: responseJSON,
            toolCalls: invokedTools,
            retrieval: retrieval
        )
        let requestedModel = stringValue(forKey: "model", in: requestJSON) ?? modelFromGeminiPath(snapshot.path)
        let servedModel = servedModel(responseJSON: responseJSON, streamEvents: parsedEvents)
        let isStreaming = isStreaming(
            snapshot: snapshot,
            requestJSON: requestJSON,
            transport: transport,
            streamEvents: streamEvents
        )

        return AIInspection(
            provider: resolvedProvider,
            kind: signalKind(for: snapshot),
            evidence: evidence(for: snapshot),
            model: requestedModel ?? servedModel,
            servedModel: servedModel.flatMap { $0 == requestedModel ? nil : $0 },
            endpoint: snapshot.path.isEmpty ? snapshot.urlString : snapshot.path,
            isStreaming: isStreaming,
            streamTransport: transport,
            httpStatusCode: snapshot.responseStatusCode,
            duration: snapshot.duration,
            requestID: requestID(in: snapshot.responseHeaders),
            finishReason: finishReason,
            usage: usage,
            toolCalls: toolCalls,
            events: events,
            retrieval: retrieval,
            warnings: warnings,
            assembledOutput: assembledOutput,
            unavailableFields: unavailableFields(
                usage: usage,
                events: events,
                declaredTools: declaredTools,
                invokedTools: invokedTools,
                isStreaming: isStreaming
            )
        )
    }

    static func lowercasedPrefix(of data: Data?) -> String {
        data.flatMap { String(bytes: $0.prefix(maxQuickScanBytes), encoding: .utf8)?.lowercased() } ?? ""
    }

    private final class SignalCacheEntry {
        weak var transaction: HTTPTransaction?
        let revision: UInt64
        let signal: AITrafficSignal

        init(transaction: HTTPTransaction, signal: AITrafficSignal) {
            self.transaction = transaction
            revision = transaction.signalEvidenceRevision
            self.signal = signal
        }
    }

    /// `NSCache` is thread-safe and sheds entries under memory pressure; the count limit keeps
    /// it in step with the largest live session buffer.
    nonisolated(unsafe) private static let signalCache: NSCache<NSUUID, SignalCacheEntry> = {
        let cache = NSCache<NSUUID, SignalCacheEntry>()
        cache.countLimit = 100_000
        return cache
    }()

    /// Byte-wise substring search. Foundation's `StringProtocol.contains` walks the text with
    /// locale-aware comparison and dominated request-list derivation on busy sessions.
    private static func contains(_ text: String, _ needle: String) -> Bool {
        text.utf8.firstRange(of: needle.utf8) != nil
    }

    // MARK: Provider

    static func provider(from snapshot: AITrafficSnapshot) -> AIProvider? {
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
        if host.contains("anthropic.com")
            || headerNames.contains("anthropic-version")
            || (path.contains("/v1/messages") && looksLikeMessagesAPI(snapshot))
        {
            return .anthropic
        }
        if host == "generativelanguage.googleapis.com"
            || host.hasSuffix(".generativelanguage.googleapis.com")
            || headerNames.contains("x-goog-api-key")
            || path.contains(":generatecontent")
            || path.contains(":streamgeneratecontent")
            || path.contains(":counttokens")
            || path.contains(":embedcontent")
        {
            return .gemini
        }
        if path.hasSuffix("/api/chat")
            || path.hasSuffix("/api/generate")
            || path.hasSuffix("/api/embed")
            || path.hasSuffix("/api/embeddings")
        {
            // Ordinary app backends also expose `/api/chat`; only treat the Ollama routes as AI
            // when they run where Ollama runs or the request carries a model field.
            if isLocalOllamaHost(snapshot) || lowercasedPrefix(of: snapshot.requestBody).contains(#""model""#) {
                return .ollama
            }
        }
        if host.contains("openai.com")
            || path.contains("/v1/responses")
            || path.contains("/v1/chat/completions")
            || path.contains("/v1/completions")
            || path.contains("/v1/embeddings")
        {
            return .openAICompatible
        }
        if path.contains("/chat/completions") || path.contains("/embeddings") {
            return .openAICompatible
        }
        return nil
    }

    static func provider(
        from requestJSON: [String: Any]?,
        responseJSON: [String: Any]?,
        streamEvents: [AIStreamEvent]
    )
        -> AIProvider?
    {
        if requestJSON?["contents"] != nil || responseJSON?["candidates"] != nil {
            return .gemini
        }
        if responseJSON?["prompt_eval_count"] != nil
            || responseJSON?["eval_count"] != nil
            || responseJSON?["done_reason"] != nil
        {
            return .ollama
        }
        if responseJSON?["stop_reason"] != nil {
            return .anthropic
        }
        if stringValue(forKey: "model", in: requestJSON) != nil
            || stringValue(forKey: "model", in: responseJSON) != nil
            || !streamEvents.isEmpty
        {
            return .openAICompatible
        }
        return nil
    }

    static func isLocalOllamaHost(_ snapshot: AITrafficSnapshot) -> Bool {
        let host = snapshot.host.lowercased()
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") {
            return true
        }
        return URL(string: snapshot.urlString)?.port == 11_434
    }

    static func signalKind(for snapshot: AITrafficSnapshot) -> AITrafficSignalKind {
        if hasVisibleAIAPIEvidence(snapshot) {
            return .api
        }
        if isKnownNativeSession(snapshot) || hasHiddenTLSOnlyBody(snapshot) {
            return .session
        }
        return .heuristic
    }

    static func hasVisibleAIAPIEvidence(_ snapshot: AITrafficSnapshot) -> Bool {
        let path = snapshot.path.lowercased()
        if path.contains("/v1/responses")
            || path.contains("/v1/chat/completions")
            || (path.contains("/v1/messages") && looksLikeMessagesAPI(snapshot))
            || path.contains("/v1/embeddings")
            || path.contains("/chat/completions")
            || path.contains("/embeddings")
            || path.contains(":generatecontent")
            || path.contains(":streamgeneratecontent")
            || path.hasSuffix("/api/chat")
            || path.hasSuffix("/api/generate")
        {
            return true
        }

        let requestPrefix = lowercasedPrefix(of: snapshot.requestBody)
        let responsePrefix = lowercasedPrefix(of: snapshot.responseBody)
        return requestPrefix.contains(#""model""#)
            || requestPrefix.contains(#""contents""#)
            || responsePrefix.contains(#""usage""#)
            || responsePrefix.contains(#""usagemetadata""#)
            || headerValue(named: "anthropic-version", in: snapshot.requestHeaders) != nil
    }

    /// `/v1/messages` is also a common REST route for chat and inbox backends. Off the
    /// Anthropic host it only counts as the Messages API when the exchange carries Messages
    /// API shape: the version header, a `model` field, or a `stop_reason` in the response.
    static func looksLikeMessagesAPI(_ snapshot: AITrafficSnapshot) -> Bool {
        if headerValue(named: "anthropic-version", in: snapshot.requestHeaders) != nil {
            return true
        }
        if lowercasedPrefix(of: snapshot.requestBody).contains(#""model""#) {
            return true
        }
        let responsePrefix = lowercasedPrefix(of: snapshot.responseBody)
        return responsePrefix.contains(#""stop_reason""#) || responsePrefix.contains(#"event: message_start"#)
    }

    static func isKnownNativeSession(_ snapshot: AITrafficSnapshot) -> Bool {
        let host = snapshot.host.lowercased()
        return host == "chatgpt.com"
            || host.hasSuffix(".chatgpt.com")
            || host == "desktop.chat.openai.com"
            || host.hasSuffix(".desktop.chat.openai.com")
            || host == "claude.ai"
            || host.hasSuffix(".claude.ai")
    }

    static func hasHiddenTLSOnlyBody(_ snapshot: AITrafficSnapshot) -> Bool {
        let method = snapshot.requestMethod.uppercased()
        let scheme = snapshot.scheme.lowercased()
        return method == "CONNECT"
            || ((scheme == "https" || scheme == "wss") && snapshot.requestBody == nil && snapshot.responseBody == nil)
    }

    static func evidence(for snapshot: AITrafficSnapshot) -> [String] {
        var values: [String] = []
        if provider(from: snapshot) != nil {
            values.append("known host")
        }
        if hasVisibleAIAPIEvidence(snapshot) {
            values.append("api fields")
        }
        if snapshot.scheme.lowercased() == "wss" || headerValue(named: "upgrade", in: snapshot.requestHeaders)?
            .lowercased() == "websocket"
        {
            values.append("websocket")
        }
        if hasHiddenTLSOnlyBody(snapshot) {
            values.append("body hidden")
        }
        return Array(NSOrderedSet(array: values).compactMap { $0 as? String })
    }

    // MARK: JSON helpers

    static func parseJSONObject(_ data: Data?) -> [String: Any]? {
        guard let data, !data.isEmpty, data.count <= maxBodyBytes else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func stringValue(forKey key: String, in json: [String: Any]?) -> String? {
        json?[key] as? String
    }

    static func intValue(forKey key: String, in json: [String: Any]?) -> Int? {
        if let int = json?[key] as? Int {
            return int
        }
        if let number = json?[key] as? NSNumber {
            return number.intValue
        }
        return nil
    }

    static func boolValue(forKey key: String, in json: [String: Any]?) -> Bool? {
        if let bool = json?[key] as? Bool {
            return bool
        }
        if let number = json?[key] as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    static func compactJSONString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else
        {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// The model the client asked for, from the request body or the Gemini path.
    /// Cheap enough for search tokens: it only parses the bounded request body.
    static func requestedModel(transaction: HTTPTransaction) -> String? {
        let snapshot = AITrafficSnapshot(transaction: transaction)
        guard isLikelyAI(snapshot: snapshot) else {
            return nil
        }
        return stringValue(forKey: "model", in: parseJSONObject(snapshot.requestBody))
            ?? modelFromGeminiPath(snapshot.path)
    }

    static func modelFromGeminiPath(_ path: String) -> String? {
        guard let range = path.range(of: "/models/") else {
            return nil
        }
        let remainder = path[range.upperBound...]
        let model = remainder.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        return model.isEmpty ? nil : model
    }

    static func servedModel(responseJSON: [String: Any]?, streamEvents: [ParsedStreamEvent]) -> String? {
        if let model = stringValue(forKey: "model", in: responseJSON)
            ?? stringValue(forKey: "modelVersion", in: responseJSON)
        {
            return model
        }
        for event in streamEvents {
            if let model = stringValue(forKey: "model", in: event.json)
                ?? stringValue(forKey: "modelVersion", in: event.json)
                ?? stringValue(forKey: "model", in: event.json?["message"] as? [String: Any])
                ?? stringValue(forKey: "model", in: event.json?["response"] as? [String: Any])
            {
                return model
            }
        }
        return nil
    }

    static func requestID(in headers: [HTTPHeader]) -> String? {
        for name in ["x-request-id", "request-id", "openai-request-id", "x-goog-request-id"] {
            if let value = headerValue(named: name, in: headers)?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: Streaming

    static func streamTransport(
        snapshot: AITrafficSnapshot,
        responseJSON: [String: Any]?
    )
        -> AIStreamTransport
    {
        let contentType = headerValue(named: "content-type", in: snapshot.responseHeaders)?.lowercased() ?? ""
        if contentType.contains("text/event-stream") {
            return .sse
        }
        if contentType.contains("ndjson") || contentType.contains("jsonl") || contentType.contains("json-seq") {
            return .ndjson
        }
        guard responseJSON == nil,
              let body = snapshot.responseBody,
              let text = String(data: boundedTail(body), encoding: .utf8) else
        {
            return .none
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("data:") || trimmed.hasPrefix("event:") || trimmed.contains("\ndata:") {
            return .sse
        }
        if trimmed.hasPrefix("{"), trimmed.contains("}\n{") || trimmed.contains("}\r\n{") {
            return .ndjson
        }
        return .none
    }

    static func isStreaming(
        snapshot: AITrafficSnapshot,
        requestJSON: [String: Any]?,
        transport: AIStreamTransport,
        streamEvents: [AIStreamEvent]
    )
        -> Bool
    {
        transport != .none
            || !streamEvents.isEmpty
            || boolValue(forKey: "stream", in: requestJSON) == true
    }

    /// A long stream is analyzed from its tail: the final events carry the usage and the
    /// finish reason, and the leading partial event is dropped so parsing starts on a boundary.
    static func boundedTail(_ data: Data) -> Data {
        guard data.count > maxBodyBytes else {
            return data
        }
        let tail = data.suffix(maxBodyBytes)
        let separator = Data("\n\n".utf8)
        if let boundary = tail.range(of: separator) {
            return Data(tail[boundary.upperBound...])
        }
        return Data(tail)
    }

    static func parseSSEEvents(_ data: Data?) -> [AIStreamEvent] {
        guard let data,
              let text = String(data: boundedTail(data), encoding: .utf8),
              text.contains("data:") else
        {
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
        guard events.count > maxStreamEvents else {
            return events
        }
        // Keep the start of the stream and its end, where usage and the finish reason arrive.
        return Array(events.prefix(maxStreamEvents / 2) + events.suffix(maxStreamEvents / 2))
    }

    static func parseNDJSONEvents(_ data: Data?) -> [AIStreamEvent] {
        guard let data,
              data.count <= maxBodyBytes,
              let text = String(data: data, encoding: .utf8) else
        {
            return []
        }
        var events: [AIStreamEvent] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("{") else {
                continue
            }
            events.append(AIStreamEvent(event: nil, data: line))
            if events.count >= maxStreamEvents {
                break
            }
        }
        return events
    }

    static func headerValue(named name: String, in headers: [HTTPHeader]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
