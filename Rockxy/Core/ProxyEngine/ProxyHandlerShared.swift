import Foundation
import NIOHTTP1
import os

nonisolated(unsafe) private let proxyHandlerSharedLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "ProxyHandlerShared"
)

// MARK: - ProxyHandlerShared

/// Shared utilities extracted from HTTPProxyHandler and HTTPSProxyRelayHandler
/// to eliminate duplication. Only proven, identical seams are extracted here.
enum ProxyHandlerShared {
    // MARK: Internal

    /// Decision returned by `oversizeRelayDecision` when a response body chunk
    /// pushes the capture buffer past the cap. Drives both the script-deferral
    /// flush logic and the response-breakpoint preservation.
    enum OversizeRelayDecision: Equatable {
        /// Continue buffering for the breakpoint UI, do not flush. Reached when
        /// a response breakpoint is armed even if the script hook was deferring.
        case keepBufferingForBreakpoint
        /// Flush the buffered head + body to the client and resume streaming.
        /// Reached when scripting was deferring but no breakpoint is in play.
        case flushBufferedAndResumeStreaming
        /// Streaming was already happening (no script defer, no breakpoint defer);
        /// nothing to flush, just continue.
        case alreadyStreaming
    }

    /// Pure helper that codifies the truncation-branch decision in
    /// `UpstreamResponseHandler.channelRead(.body)`. Extracted so the behavior
    /// can be unit-tested without a full NIO channel test harness.
    nonisolated static func oversizeRelayDecision(
        deferRelayForScript: Bool,
        shouldBreakOnResponse: Bool
    )
        -> OversizeRelayDecision
    {
        if deferRelayForScript, shouldBreakOnResponse {
            return .keepBufferingForBreakpoint
        }
        if deferRelayForScript {
            return .flushBufferedAndResumeStreaming
        }
        return .alreadyStreaming
    }

    /// Determines whether the next response body chunk should be captured or dropped.
    /// Returns `true` if the buffer is already at or past the capture limit.
    nonisolated static func shouldTruncateCapture(
        currentBufferSize: Int,
        incomingChunkSize: Int,
        maxSize: Int = ProxyLimits.maxResponseBodySize
    )
        -> Bool
    {
        currentBufferSize + incomingChunkSize > maxSize
    }

    /// Wraps a downstream transaction callback with matched-rule metadata injection.
    /// Used by both HTTP and HTTPS handlers to decorate transactions before delivery.
    nonisolated static func makeTransactionCallback(
        for matchedRule: ProxyRule?,
        downstream: @escaping @Sendable (HTTPTransaction) -> Void
    )
        -> @Sendable (HTTPTransaction) -> Void
    {
        let matchedRuleID = matchedRule?.id
        let matchedRuleName = matchedRule?.name
        let matchedRuleActionSummary = matchedRule?.action.matchedRuleActionSummary
        let matchedRulePattern = matchedRule?.matchCondition.urlPattern

        return { transaction in
            transaction.matchedRuleID = matchedRuleID
            transaction.matchedRuleName = matchedRuleName
            transaction.matchedRuleActionSummary = matchedRuleActionSummary
            transaction.matchedRulePattern = matchedRulePattern
            downstream(transaction)
        }
    }

    /// Rebuild the outbound `HTTPRequestHead` from a (possibly script-mutated)
    /// `HTTPRequestData`, scoped to the safe mutation kinds: method, origin-form
    /// path + query, headers, and a recomputed `Content-Length` when the original
    /// carried one.
    ///
    /// Host / port / scheme changes are intentionally NOT propagated here — those
    /// are discarded during `ScriptRequestContext.apply(to:pluginID:)` before
    /// this function ever sees the request. Cross-host rewrite remains the
    /// responsibility of the `MapRemote` rule action.
    ///
    /// `Transfer-Encoding: chunked` bodies keep their chunked framing; no
    /// `Content-Length` is added. Requests that originally had `Content-Length`
    /// get it recomputed from `requestData.body?.count ?? 0`.
    nonisolated static func buildForwardHead(
        from requestData: HTTPRequestData,
        originalHead: HTTPRequestHead
    )
        -> HTTPRequestHead
    {
        let resolvedMethod: HTTPMethod
        if HTTPMethodRawValues.contains(requestData.method.uppercased()) {
            resolvedMethod = HTTPMethod(rawValue: requestData.method.uppercased())
        } else {
            warnOnce(kind: "invalid-method", details: "\(requestData.method)")
            resolvedMethod = originalHead.method
        }

        let uri: String
        let path = requestData.url.path.isEmpty ? "/" : requestData.url.path
        if let query = requestData.url.query, !query.isEmpty {
            uri = "\(path)?\(query)"
        } else {
            uri = path
        }

        var headers = HTTPHeaders(requestData.headers.map { ($0.name, $0.value) })

        // Framing policy: scripts may have mutated the body, so we must always
        // make the framing reflect the actual outgoing bytes:
        //
        // - Chunked uploads: drop any Content-Length (they're mutually exclusive
        //   per RFC 9112 §6) and keep the chunked framing.
        // - Otherwise: write Content-Length matching the mutated body size,
        //   even if the original request had no body / no Content-Length. This
        //   prevents downstream servers from hanging on a missing length when a
        //   script added a body to a previously bodyless request.
        let isChunked = headers["Transfer-Encoding"].contains(where: {
            $0.lowercased().contains("chunked")
        })
        if isChunked {
            headers.remove(name: "Content-Length")
        } else {
            let size = requestData.body?.count ?? 0
            headers.replaceOrAdd(name: "Content-Length", value: "\(size)")
        }

        return HTTPRequestHead(
            version: originalHead.version,
            method: resolvedMethod,
            uri: uri,
            headers: headers
        )
    }

    /// Rebuild the outbound response head from a script-mutated `HTTPResponseData`.
    ///
    /// The relay path sends the full mutated body in a fixed-length write, so
    /// any stale `Transfer-Encoding` is removed and `Content-Length` is replaced
    /// with the actual mutated body size.
    nonisolated static func buildRelayResponseHead(
        from responseData: HTTPResponseData,
        originalHead: HTTPResponseHead?
    )
        -> HTTPResponseHead
    {
        let status = HTTPResponseStatus(statusCode: responseData.statusCode)
        var head = HTTPResponseHead(
            version: originalHead?.version ?? .http1_1,
            status: status
        )
        head.headers = HTTPHeaders(responseData.headers.map { ($0.name, $0.value) })

        let bodySize = responseData.body?.count ?? 0
        head.headers.remove(name: "Transfer-Encoding")
        head.headers.replaceOrAdd(name: "Content-Length", value: "\(bodySize)")
        return head
    }

    // MARK: Private

    /// Lowercase set of RFC-defined methods we accept from scripts.
    nonisolated private static let HTTPMethodRawValues: Set<String> = [
        "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE", "CONNECT",
    ]

    nonisolated(unsafe) private static var warned: Set<String> = []
    private static let warnedLock = NSLock()

    private static func warnOnce(kind: String, details: String) {
        let key = "\(kind)|\(details)"
        warnedLock.lock()
        defer { warnedLock.unlock() }
        guard !warned.contains(key) else {
            return
        }
        warned.insert(key)
        proxyHandlerSharedLogger.warning("buildForwardHead: \(kind) \(details)")
    }
}
