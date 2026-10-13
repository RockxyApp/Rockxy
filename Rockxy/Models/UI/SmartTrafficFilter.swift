import Foundation

/// Parses search-bar tokens such as `is:ai`, `model:gpt-4o`, `rpc:eth_call`, `has:tool_call`,
/// `streaming:true`, `chain:0x1`, `has:tx_hash`, and `is:x402` into metadata predicates.
/// Unrecognized text remains available for the normal selected-field substring search.
struct SmartTrafficFilter: Equatable {
    enum Predicate: Equatable {
        case isAI
        case isAIAPI
        case isAISession
        case isWeb3
        case rpcError(Bool)
        case rpcMethod(String)
        case provider(String)
        case model(String)
        case hasToolCall
        case streaming(Bool)
        case chain(String)
        case hasTransactionHash
        case isX402
        case babylonTrace(String)
        case babylonStep(String)
    }

    let predicates: [Predicate]
    let remainingSearchText: String

    var hasPredicates: Bool {
        !predicates.isEmpty
    }

    static func parse(_ searchText: String) -> SmartTrafficFilter {
        var predicates: [Predicate] = []
        var remainingTokens: [String] = []

        for token in searchText.split(whereSeparator: \.isWhitespace).map(String.init) {
            guard let parsed = parseToken(token) else {
                remainingTokens.append(token)
                continue
            }
            predicates.append(parsed)
        }

        return SmartTrafficFilter(
            predicates: predicates,
            remainingSearchText: remainingTokens.joined(separator: " ")
        )
    }

    func matches(_ transaction: HTTPTransaction) -> Bool {
        predicates.allSatisfy { predicate in
            switch predicate {
            case .isAI:
                AITrafficDetector.signal(transaction: transaction).isLikelyAI
            case .isAIAPI:
                {
                    let signal = AITrafficDetector.signal(transaction: transaction)
                    return signal.isLikelyAI && signal.kind != .session
                }()
            case .isAISession:
                AITrafficDetector.signal(transaction: transaction).kind == .session
            case .isWeb3:
                transaction.web3RPCInfo != nil
            case let .rpcError(expected):
                (transaction.web3RPCInfo?.error != nil) == expected
            case let .rpcMethod(method):
                rpcMethods(in: transaction).contains { $0.caseInsensitiveCompare(method) == .orderedSame }
            case let .provider(provider):
                providerValues(in: transaction).contains {
                    $0.localizedCaseInsensitiveContains(provider)
                }
            case let .model(model):
                AITrafficDetector.filterFacts(transaction: transaction).model?
                    .localizedCaseInsensitiveContains(model) ?? false
            case .hasToolCall:
                AITrafficDetector.filterFacts(transaction: transaction).hasToolCalls
            case let .streaming(expected):
                AITrafficDetector.filterFacts(transaction: transaction).isStreaming == expected
            case let .chain(chain):
                Self.chainMatches(transaction.web3RPCInfo?.chainHint?.chainID, chain)
            case .hasTransactionHash:
                transaction.web3RPCInfo?.transactionHash != nil
            case .isX402:
                transaction.x402Info?.isX402Like == true
            case let .babylonTrace(traceID):
                transaction.babylonCorrelation?.traceID == traceID
            case let .babylonStep(stepID):
                transaction.babylonCorrelation?.stepID == stepID
            }
        }
    }

    private static func parseToken(_ token: String) -> Predicate? {
        guard let separator = token.firstIndex(of: ":") else {
            return nil
        }

        let key = token[..<separator].lowercased()
        let value = String(token[token.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        switch key {
        case "is":
            switch value.lowercased() {
            case "ai":
                return .isAI
            case "ai_api", "ai-api", "api_ai", "api-ai":
                return .isAIAPI
            case "ai_session", "ai-session", "session_ai", "session-ai":
                return .isAISession
            case "web3":
                return .isWeb3
            case "x402":
                return .isX402
            default:
                return nil
            }
        case "has":
            switch value.lowercased() {
            case "tool_call", "tool-call", "tool_calls", "tools":
                return .hasToolCall
            case "tx_hash", "tx-hash", "txhash", "transaction_hash":
                return .hasTransactionHash
            default:
                return nil
            }
        case "streaming", "stream":
            return parseBool(value).map(Predicate.streaming)
        case "chain":
            // Only names and numbers Rockxy can compare; anything else stays plain search text.
            return isKnownChain(value) ? .chain(value) : nil
        case "rpc_error":
            return parseBool(value).map(Predicate.rpcError)
        case "rpc":
            return .rpcMethod(value)
        case "provider":
            return .provider(value)
        case "model":
            return .model(value)
        case "trace":
            // Runtime identifiers are opaque and compared exactly.
            return .babylonTrace(value)
        case "step":
            return .babylonStep(value)
        default:
            return nil
        }
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "yes", "1":
            true
        case "false", "no", "0":
            false
        default:
            nil
        }
    }

    /// Matches a chain hint by hex (`0x1`), decimal (`1`), or a few common names.
    private static func chainMatches(_ chainID: String?, _ query: String) -> Bool {
        guard let chainID, let actual = chainNumber(chainID) else {
            return false
        }
        let normalized = query.lowercased()
        if let named = namedChains[normalized] {
            return actual == named
        }
        return chainNumber(normalized) == actual
    }

    private static func isKnownChain(_ value: String) -> Bool {
        namedChains[value.lowercased()] != nil || chainNumber(value) != nil
    }

    private static func chainNumber(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasPrefix("0x") {
            return UInt64(trimmed.dropFirst(2), radix: 16)
        }
        return UInt64(trimmed)
    }

    private static let namedChains: [String: UInt64] = [
        "mainnet": 1, "ethereum": 1, "eth": 1,
        "sepolia": 11_155_111, "holesky": 17_000,
        "base": 8_453, "optimism": 10, "arbitrum": 42_161,
        "polygon": 137, "bsc": 56,
    ]

    private func rpcMethods(in transaction: HTTPTransaction) -> [String] {
        guard let info = transaction.web3RPCInfo else {
            return []
        }

        var methods: [String] = []
        if let method = info.method {
            methods.append(method)
        }
        if let batch = info.batch {
            methods.append(contentsOf: batch.methods)
        }
        return methods
    }

    private func providerValues(in transaction: HTTPTransaction) -> [String] {
        var values: [String] = []
        if let info = transaction.web3RPCInfo {
            values.append(info.providerHost)
            values.append(info.family.rawValue)
        }
        if let provider = AITrafficDetector.signal(transaction: transaction).provider {
            values.append(provider.rawValue)
            values.append(provider.displayName)
        }
        return values
    }
}
