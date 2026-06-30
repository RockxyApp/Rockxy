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
