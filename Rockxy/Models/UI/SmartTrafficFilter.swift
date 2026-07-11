import Foundation

/// Parses search-bar tokens such as `is:ai` and `rpc:eth_call` into metadata predicates.
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
            default:
                return nil
            }
        case "rpc_error":
            switch value.lowercased() {
            case "true", "yes", "1":
                return .rpcError(true)
            case "false", "no", "0":
                return .rpcError(false)
            default:
                return nil
            }
        case "rpc":
            return .rpcMethod(value)
        case "provider":
            return .provider(value)
        default:
            return nil
        }
    }

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
