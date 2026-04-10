import Foundation

/// Shared utilities extracted from HTTPProxyHandler and HTTPSProxyRelayHandler
/// to eliminate duplication. Only proven, identical seams are extracted here.
enum ProxyHandlerShared {
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
}
