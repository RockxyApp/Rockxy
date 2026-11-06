import Foundation

// MARK: - X402Detector

/// Bounded detector for visible HTTP 402 and x402-like payment metadata.
///
/// The detector summarizes lifecycle hints without retaining payment proofs,
/// challenges, receipts, or wallet/payment execution details.
enum X402Detector {
    // MARK: Internal

    static let maxPayloadBytes = 256 * 1_024

    static func detect(request: HTTPRequestData, response: HTTPResponseData? = nil) -> X402Info? {
        guard request.method.caseInsensitiveCompare("CONNECT") != .orderedSame else {
            return nil
        }

        let requestHeaders = HeaderLookup(request.headers)
        let responseHeaders = HeaderLookup(response?.headers ?? [])
        let responseStatus = response?.statusCode
        let isStatus402 = responseStatus == 402
        // Only x402 payment headers count as a proof. A generic Authorization header is
        // ordinary API auth and must not turn a request into a payment retry.
        let hasPaymentProof = paymentProofHeaders.contains { requestHeaders.contains($0) }
        let hasPaymentResponse = paymentResponseHeaders.contains { responseHeaders.contains($0) }
        let hasHeaderChallenge = responseHeaders.contains("payment-required")
        let hasPaymentHeaders = hasPaymentProof
            || hasPaymentResponse
            || hasHeaderChallenge
            || responseHeaders.contains("x-accept-payment")

        // Skip body decoding for ordinary traffic: only 402 responses, exchanges that carry
        // x402 headers, or bodies whose first bytes name an x402 field are worth parsing.
        guard isStatus402 || hasPaymentHeaders || bodyMentionsX402(response?.body) else {
            return nil
        }

        let bodySummary = summarizeBody(response?.decodedBody(limit: maxPayloadBytes))
        let isX402Like = bodySummary.isX402Like || hasPaymentHeaders

        // In a payment-required response the `error` field explains why payment is needed
        // (for example "X-PAYMENT header is required"). It is only a provider error when the
        // client already submitted a payment proof and the server still rejected the request.
        let providerErrorPresent = bodySummary.errorFieldPresent && hasPaymentProof
        let stage = stage(
            statusCode: responseStatus,
            isX402Like: isX402Like,
            hasPaymentProof: hasPaymentProof,
            hasPaymentResponse: hasPaymentResponse,
            providerErrorPresent: providerErrorPresent
        )

        return X402Info(
            stage: stage,
            isX402Like: isX402Like,
            version: bodySummary.version,
            paymentRequired: bodySummary.paymentRequired ?? (isStatus402 ? true : nil),
            hasPaymentProof: hasPaymentProof,
            hasChallenge: bodySummary.hasChallenge || hasHeaderChallenge,
            hasPaymentMetadata: bodySummary.hasPaymentMetadata || hasPaymentResponse,
            providerErrorPresent: providerErrorPresent,
            parseState: bodySummary.parseState,
            redactionFields: redactionFields(
                requestHeaders: requestHeaders,
                responseHeaders: responseHeaders,
                bodySummary: bodySummary
            ),
            requestPayloadSize: request.body?.count,
            responsePayloadSize: response?.body?.count
        )
    }

    // MARK: Private

    private static let bodyHintMarkers = ["x402Version", "paymentMetadata", "paymentRequired"].map { Data($0.utf8) }

    /// A cheap scan of the raw body prefix, so a facilitator reply or a 200 with a receipt is
    /// still recognized without parsing every response on the proxy path.
    private static func bodyMentionsX402(_ body: Data?) -> Bool {
        guard let body, !body.isEmpty else {
            return false
        }
        let prefix = body.prefix(4 * 1_024)
        return bodyHintMarkers.contains { prefix.range(of: $0) != nil }
    }

    private static let paymentProofHeaders = ["x-payment", "payment-signature"]
    private static let paymentResponseHeaders = ["x-payment-response", "payment-response"]

    private struct BodySummary {
        let isX402Like: Bool
        let version: String?
        let paymentRequired: Bool?
        let hasChallenge: Bool
        let hasPaymentMetadata: Bool
        let hasReceipt: Bool
        let errorFieldPresent: Bool
        let parseState: X402ParseState
    }

    private struct HeaderLookup {
        private let names: Set<String>

        init(_ headers: [HTTPHeader]) {
            names = Set(headers.map { $0.name.lowercased() })
        }

        func contains(_ name: String) -> Bool {
            names.contains(name.lowercased())
        }
    }

    private static let emptyBodySummary = BodySummary(
        isX402Like: false,
        version: nil,
        paymentRequired: nil,
        hasChallenge: false,
        hasPaymentMetadata: false,
        hasReceipt: false,
        errorFieldPresent: false,
        parseState: .notApplicable
    )

    private static func summarizeBody(_ body: Data?) -> BodySummary {
        guard let body, !body.isEmpty, body.count <= maxPayloadBytes else {
            return emptyBodySummary
        }

        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            let prefix = String(bytes: body.prefix(8 * 1_024), encoding: .utf8)?.lowercased() ?? ""
            let looksLikeX402 = prefix.contains("x402")
                || prefix.contains("paymentrequired")
                || prefix.contains("paymentmetadata")
                || prefix.contains("challenge")
                || prefix.contains("\"accepts\"")
            guard looksLikeX402 else {
                return emptyBodySummary
            }
            return BodySummary(
                isX402Like: true,
                version: nil,
                paymentRequired: prefix.contains("paymentrequired"),
                hasChallenge: prefix.contains("challenge") || prefix.contains("\"accepts\""),
                hasPaymentMetadata: prefix.contains("paymentmetadata"),
                hasReceipt: prefix.contains("receipt"),
                errorFieldPresent: prefix.contains("\"error\""),
                parseState: .malformed
            )
        }

        let hasPaymentMetadata = object["paymentMetadata"] != nil
        // x402 v1 lists payment requirements in `accepts`; treat them like a challenge.
        let hasChallenge = object["challenge"] != nil || object["accepts"] is [Any]
        let hasReceipt = object["receipt"] != nil || (object["paymentMetadata"] as? [String: Any])?["receipt"] != nil
        let paymentRequired = boolValue(object["paymentRequired"])
        let version = stringValue(object["x402Version"])
        let errorFieldPresent = object["error"] != nil
        let isX402Like = version != nil
            || paymentRequired != nil
            || hasChallenge
            || hasPaymentMetadata

        return BodySummary(
            isX402Like: isX402Like,
            version: version,
            paymentRequired: paymentRequired,
            hasChallenge: hasChallenge,
            hasPaymentMetadata: hasPaymentMetadata,
            hasReceipt: hasReceipt,
            errorFieldPresent: errorFieldPresent,
            parseState: .parsed
        )
    }

    private static func stage(
        statusCode: Int?,
        isX402Like: Bool,
        hasPaymentProof: Bool,
        hasPaymentResponse: Bool,
        providerErrorPresent: Bool
    ) -> X402Stage {
        if providerErrorPresent {
            return .providerError
        }
        if let statusCode, (200 ..< 300).contains(statusCode), hasPaymentProof || hasPaymentResponse {
            return .paymentAccepted
        }
        if hasPaymentProof {
            return .paymentProofSubmitted
        }
        if statusCode == 402, isX402Like {
            return .paymentRequired
        }
        return .ordinaryPaymentRequired
    }

    private static func redactionFields(
        requestHeaders: HeaderLookup,
        responseHeaders: HeaderLookup,
        bodySummary: BodySummary
    ) -> [String] {
        var fields: [String] = []
        if requestHeaders.contains("authorization") {
            fields.append("Authorization")
        }
        if requestHeaders.contains("x-payment") {
            fields.append("X-Payment")
        }
        if requestHeaders.contains("payment-signature") {
            fields.append("Payment-Signature")
        }
        if responseHeaders.contains("x-payment-response") {
            fields.append("X-Payment-Response")
        }
        if responseHeaders.contains("payment-response") {
            fields.append("Payment-Response")
        }
        if responseHeaders.contains("payment-required") {
            fields.append("Payment-Required")
        }
        if bodySummary.hasChallenge {
            fields.append("challenge")
        }
        if bodySummary.hasPaymentMetadata {
            fields.append("paymentMetadata")
        }
        if bodySummary.hasReceipt {
            fields.append("receipt")
        }
        return fields
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            return number.stringValue
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        default:
            return nil
        }
    }
}
