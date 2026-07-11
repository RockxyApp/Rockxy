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
        let hasPaymentProof = requestHeaders.contains("x-payment")
            || requestHeaders.contains("authorization")
        let hasPaymentResponse = responseHeaders.contains("x-payment-response")
        let bodySummary = summarizeBody(response?.body)
        let isStatus402 = responseStatus == 402
        let isX402Like = bodySummary.isX402Like
            || requestHeaders.contains("x-payment")
            || responseHeaders.contains("x-accept-payment")
            || responseHeaders.contains("x-payment-response")

        guard isStatus402 || isX402Like || hasPaymentResponse else {
            return nil
        }

        let providerErrorPresent = bodySummary.providerErrorPresent
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
            hasChallenge: bodySummary.hasChallenge,
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

    private struct BodySummary {
        let isX402Like: Bool
        let version: String?
        let paymentRequired: Bool?
        let hasChallenge: Bool
        let hasPaymentMetadata: Bool
        let hasReceipt: Bool
        let providerErrorPresent: Bool
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
        providerErrorPresent: false,
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
            guard looksLikeX402 else {
                return emptyBodySummary
            }
            return BodySummary(
                isX402Like: true,
                version: nil,
                paymentRequired: prefix.contains("paymentrequired"),
                hasChallenge: prefix.contains("challenge"),
                hasPaymentMetadata: prefix.contains("paymentmetadata"),
                hasReceipt: prefix.contains("receipt"),
                providerErrorPresent: prefix.contains("\"error\"") || prefix.contains("error"),
                parseState: .malformed
            )
        }

        let hasPaymentMetadata = object["paymentMetadata"] != nil
        let hasChallenge = object["challenge"] != nil
        let hasReceipt = object["receipt"] != nil || (object["paymentMetadata"] as? [String: Any])?["receipt"] != nil
        let paymentRequired = boolValue(object["paymentRequired"])
        let version = stringValue(object["x402Version"])
        let providerErrorPresent = object["error"] != nil
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
            providerErrorPresent: providerErrorPresent,
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
        if responseHeaders.contains("x-payment-response") {
            fields.append("X-Payment-Response")
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
