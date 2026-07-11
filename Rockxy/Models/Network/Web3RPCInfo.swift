import Foundation

// MARK: - Web3RPCInfo

/// Derived Web3 JSON-RPC metadata extracted from visible HTTP request and response bodies.
struct Web3RPCInfo: Equatable, Sendable {
    let family: Web3RPCFamily
    let providerHost: String
    let method: String?
    let requestID: String?
    let batch: Web3RPCBatchSummary?
    let error: Web3RPCError?
    let chainHint: Web3RPCChainHint?
    let transactionHash: String?
    let blockIdentifier: String?
    let requestPayloadSize: Int?
    let responsePayloadSize: Int?

    var debugIntent: Web3RPCDebugIntent {
        if batch != nil {
            return .batch
        }

        guard let method = method?.trimmingCharacters(in: .whitespacesAndNewlines),
              !method.isEmpty else
        {
            return .unknown
        }

        let normalized = method.lowercased()

        if Web3RPCDebugIntent.broadcastMethods.contains(normalized) {
            return .broadcast
        }
        if Web3RPCDebugIntent.simulationMethods.contains(normalized) {
            return .simulation
        }
        if Web3RPCDebugIntent.logMethods.contains(normalized) {
            return .logs
        }
        if Web3RPCDebugIntent.subscriptionMethods.contains(where: { normalized.hasSuffix($0) }) {
            return .subscription
        }
        if Web3RPCDebugIntent.providerMethods.contains(normalized) {
            return .provider
        }
        if normalized.hasPrefix("eth_get") || normalized.hasPrefix("get") || normalized.hasPrefix("net_") {
            return .read
        }

        return .unknown
    }
}

// MARK: - Web3RPCDebugIntent

enum Web3RPCDebugIntent: String, Equatable, Sendable {
    case batch
    case broadcast
    case simulation
    case logs
    case subscription
    case provider
    case read
    case unknown

    fileprivate static let broadcastMethods: Set<String> = [
        "eth_sendrawtransaction",
        "eth_sendtransaction",
        "wallet_sendcalls",
        "wallet_sendsitepermission",
        "personal_sign",
        "eth_sign",
        "eth_signtypeddata",
        "eth_signtypeddata_v4",
        "sendtransaction",
        "requestairdrop",
    ]

    fileprivate static let simulationMethods: Set<String> = [
        "eth_call",
        "eth_estimategas",
        "simulatetransaction",
    ]

    fileprivate static let logMethods: Set<String> = [
        "eth_getlogs",
        "eth_gettransactionreceipt",
        "eth_gettransactionbyhash",
        "gettransaction",
        "getsignaturesforaddress",
        "getsignaturestatuses",
    ]

    fileprivate static let providerMethods: Set<String> = [
        "eth_chainid",
        "eth_blocknumber",
        "net_version",
        "web3_clientversion",
        "web3_sha3",
        "getlatestblockhash",
        "gethealth",
        "getversion",
        "getepochinfo",
    ]

    fileprivate static let subscriptionMethods = [
        "subscribe",
        "unsubscribe",
    ]
}

// MARK: - Web3RPCFamily

enum Web3RPCFamily: String, Equatable, Sendable {
    case evm
    case solana
}

// MARK: - Web3RPCBatchSummary

struct Web3RPCBatchSummary: Equatable, Sendable {
    let requestCount: Int
    let web3RequestCount: Int
    let responseCount: Int?
    let errorCount: Int
    let methods: [String]
}

// MARK: - Web3RPCError

struct Web3RPCError: Equatable, Sendable {
    let code: Int?
    let message: String?
}

// MARK: - Web3RPCChainHint

struct Web3RPCChainHint: Equatable, Sendable {
    let chainID: String?
}
