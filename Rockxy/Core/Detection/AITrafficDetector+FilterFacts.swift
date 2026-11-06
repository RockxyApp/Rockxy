import Foundation

// Cheap, memoized facts about AI traffic for search tokens, so filtering a large session never
// re-parses bodies on every pass.

// MARK: - AIFilterFacts

struct AIFilterFacts: Equatable, Sendable {
    static let none = AIFilterFacts(model: nil, hasToolCalls: false, isStreaming: false)

    /// The model the client asked for.
    let model: String?
    /// Whether the model asked for a tool call or the client returned a tool result.
    let hasToolCalls: Bool
    /// Whether the response was streamed (SSE or NDJSON), for any traffic, or an AI request
    /// asked for a stream.
    let isStreaming: Bool
}

extension AITrafficDetector {
    // MARK: Internal

    /// Memoized like `signal(transaction:)`: reused only while the transaction's request and
    /// response evidence is unchanged.
    static func filterFacts(transaction: HTTPTransaction) -> AIFilterFacts {
        if let cached = factsCache.entry(for: transaction.id),
           cached.transaction === transaction, cached.revision == transaction.signalEvidenceRevision
        {
            return cached.facts
        }
        let facts = filterFacts(snapshot: AITrafficSnapshot(transaction: transaction))
        factsCache.store(FactsCacheEntry(transaction: transaction, facts: facts))
        return facts
    }

    /// Entries the filter-facts cache currently holds, as an upper bound.
    static var cachedFilterFactsCount: Int {
        factsCache.count
    }

    /// Drops filter facts for rows that have gone. Lives here because `factsCache` is private
    /// to this file; `discardCachedEvidence(for:)` calls it alongside the signal cache.
    static func discardCachedFilterFacts(for ids: some Collection<UUID>) {
        factsCache.discard(ids)
    }

    /// The cached filter facts when they are still valid for the transaction's current evidence.
    static func cachedFilterFacts(transaction: HTTPTransaction) -> AIFilterFacts? {
        guard let cached = factsCache.entry(for: transaction.id),
              cached.transaction === transaction, cached.revision == transaction.signalEvidenceRevision else
        {
            return nil
        }
        return cached.facts
    }

    static func filterFacts(snapshot: AITrafficSnapshot) -> AIFilterFacts {
        // Streaming is a property of any response, not only AI traffic.
        let streamingResponse = snapshot.responseHeaders.contains { header in
            header.name.caseInsensitiveCompare("Content-Type") == .orderedSame
                && (header.value.localizedCaseInsensitiveContains("text/event-stream")
                    || header.value.localizedCaseInsensitiveContains("ndjson"))
        }
        guard isLikelyAI(snapshot: snapshot) else {
            return AIFilterFacts(model: nil, hasToolCalls: false, isStreaming: streamingResponse)
        }
        let requestJSON = parseJSONObject(snapshot.requestBody)
        let model = stringValue(forKey: "model", in: requestJSON) ?? modelFromGeminiPath(snapshot.path)
        let isStreaming = streamingResponse || boolValue(forKey: "stream", in: requestJSON) == true
        return AIFilterFacts(
            model: model,
            hasToolCalls: containsToolCallMarker(snapshot.requestBody)
                || containsToolCallMarker(snapshot.responseBody),
            isStreaming: isStreaming
        )
    }

    // MARK: Private

    private final class FactsCacheEntry: TransactionCacheEntry {
        // MARK: Lifecycle

        init(transaction: HTTPTransaction, facts: AIFilterFacts) {
            self.transaction = transaction
            cacheID = transaction.id
            revision = transaction.signalEvidenceRevision
            self.facts = facts
        }

        // MARK: Internal

        let cacheID: UUID
        weak var transaction: HTTPTransaction?
        let revision: UInt64
        let facts: AIFilterFacts
    }

    /// Pinned against shedding inside a test host; see `AITrafficDetector.signalCache`.
    private static let factsCache: TransactionEvidenceCache<FactsCacheEntry> = {
        let cache = TransactionEvidenceCache<FactsCacheEntry>(countLimit: 100_000)
        if RockxyIdentity.isRunningTests {
            cache.pinEntriesAgainstShedding()
        }
        return cache
    }()

    /// Field names that only appear when a tool is called or answered, across the
    /// OpenAI, Anthropic, and Gemini wire formats.
    private static let toolCallMarkers: [Data] = [
        "\"tool_calls\"", "\"tool_use\"", "\"tool_result\"", "\"function_call\"",
        "\"functionCall\"", "\"functionResponse\"", "\"tool_call_id\"",
    ].map { Data($0.utf8) }

    private static func containsToolCallMarker(_ body: Data?) -> Bool {
        guard let body, !body.isEmpty else {
            return false
        }
        let window = body.prefix(maxBodyBytes)
        return toolCallMarkers.contains { window.range(of: $0) != nil }
    }
}
