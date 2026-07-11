import Foundation

// MARK: - X402Info

/// Privacy-safe metadata for HTTP 402 and x402-like payment flows.
///
/// This model intentionally records only lifecycle hints and redaction field names.
/// It must not hold payment proofs, challenges, receipts, wallet addresses, or payment execution state.
struct X402Info: Equatable, Sendable {
    let stage: X402Stage
    let isX402Like: Bool
    let version: String?
    let paymentRequired: Bool?
    let hasPaymentProof: Bool
    let hasChallenge: Bool
    let hasPaymentMetadata: Bool
    let providerErrorPresent: Bool
    let parseState: X402ParseState
    let redactionFields: [String]
    let requestPayloadSize: Int?
    let responsePayloadSize: Int?
}

// MARK: - X402Stage

enum X402Stage: String, Equatable, Sendable {
    case ordinaryPaymentRequired
    case paymentRequired
    case paymentProofSubmitted
    case paymentAccepted
    case providerError
}

// MARK: - X402ParseState

enum X402ParseState: String, Equatable, Sendable {
    case notApplicable
    case parsed
    case malformed
}
