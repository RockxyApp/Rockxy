import Foundation
@testable import Rockxy
import Testing

struct X402DetectorTests {
    @Test("X402Detector detects payment-required metadata from fixture corpus")
    func detectsPaymentRequiredMetadata() throws {
        let exchange = try firstExchange(in: ProtocolFixture.x402ContractSmoke)
        let responseMessage = try responseMessage(in: exchange)
        let info = try detectedInfo(
            request: try request(from: exchange.request),
            response: try response(from: responseMessage)
        )

        #expect(info.stage == .paymentRequired)
        #expect(info.isX402Like)
        #expect(info.version == "1")
        #expect(info.paymentRequired == true)
        #expect(info.hasChallenge)
        #expect(!info.hasPaymentProof)
        #expect(info.parseState == .parsed)
        #expect(info.redactionFields.contains("challenge"))
    }

    @Test("X402Detector detects retry success without retaining payment proof values")
    func detectsRetrySuccessMetadata() throws {
        let exchange = try secondExchange(in: ProtocolFixture.x402ContractSmoke)
        let responseMessage = try responseMessage(in: exchange)
        let info = try detectedInfo(
            request: try request(from: exchange.request),
            response: try response(from: responseMessage)
        )

        #expect(info.stage == .paymentAccepted)
        #expect(info.isX402Like)
        #expect(info.hasPaymentProof)
        #expect(info.paymentRequired == nil)
        #expect(info.redactionFields.contains("X-Payment"))
        #expect(info.redactionFields.contains("receipt"))
        #expect(!info.redactionFields.contains("synthetic-payment-proof"))
    }

    @Test("X402Detector reports malformed x402 challenge as bounded fallback")
    func reportsMalformedChallenge() throws {
        let exchange = try firstExchange(in: ProtocolFixture.x402MalformedAndMissingProofContractSmoke)
        let responseMessage = try responseMessage(in: exchange)
        let info = try detectedInfo(
            request: try request(from: exchange.request),
            response: try response(from: responseMessage)
        )

        #expect(info.stage == .paymentRequired)
        #expect(info.isX402Like)
        #expect(info.paymentRequired == true)
        #expect(info.hasChallenge)
        #expect(info.parseState == .malformed)
        #expect(info.redactionFields.contains("challenge"))
    }

    @Test("X402Detector summarizes provider error metadata safely")
    func summarizesProviderErrorMetadata() throws {
        let exchange = try firstExchange(in: ProtocolFixture.x402ProviderErrorMetadataContractSmoke)
        let responseMessage = try responseMessage(in: exchange)
        let info = try detectedInfo(
            request: try request(from: exchange.request),
            response: try response(from: responseMessage)
        )

        #expect(info.stage == .providerError)
        #expect(info.isX402Like)
        #expect(info.hasPaymentProof)
        #expect(info.hasPaymentMetadata)
        #expect(info.providerErrorPresent)
        #expect(info.redactionFields.contains("Authorization"))
        #expect(info.redactionFields.contains("X-Payment"))
        #expect(info.redactionFields.contains("paymentMetadata"))
        #expect(info.redactionFields.contains("receipt"))
    }

    @Test("X402Detector keeps ordinary 402 responses inspectable without x402 inference")
    func keepsOrdinary402Inspectable() throws {
        let request = try HTTPRequestData(
            method: "GET",
            url: try url("https://api.example.com/paywall"),
            httpVersion: "HTTP/1.1",
            headers: [],
            body: nil,
            contentType: nil
        )
        let response = HTTPResponseData(
            statusCode: 402,
            statusMessage: "Payment Required",
            headers: [],
            body: nil,
            contentType: nil
        )

        let info = try detectedInfo(request: request, response: response)

        #expect(info.stage == .ordinaryPaymentRequired)
        #expect(!info.isX402Like)
        #expect(info.paymentRequired == true)
        #expect(info.parseState == .notApplicable)
        #expect(info.redactionFields.isEmpty)
    }

    @Test("X402Detector ignores ordinary successful traffic")
    func ignoresOrdinarySuccessfulTraffic() throws {
        let request = try HTTPRequestData(
            method: "GET",
            url: try url("https://api.example.com/status"),
            httpVersion: "HTTP/1.1",
            headers: [],
            body: nil,
            contentType: nil
        )
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [],
            body: Data(#"{"ok":true}"#.utf8),
            contentType: .json
        )

        #expect(X402Detector.detect(request: request, response: response) == nil)
    }

    @Test("X402Detector keeps a spec 402 error reason as payment required")
    func specErrorReasonIsPaymentRequired() throws {
        let request = try plainRequest(headers: [])
        let response = HTTPResponseData(
            statusCode: 402,
            statusMessage: "Payment Required",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"x402Version":1,"error":"X-PAYMENT header is required","accepts":[{"scheme":"exact"}]}"#.utf8),
            contentType: .json
        )

        let info = try detectedInfo(request: request, response: response)

        #expect(info.stage == .paymentRequired)
        #expect(info.isX402Like)
        #expect(info.hasChallenge)
        #expect(!info.providerErrorPresent)
        #expect(!info.hasPaymentProof)
    }

    @Test("X402Detector does not treat ordinary Authorization as a payment proof")
    func authorizationIsNotPaymentProof() throws {
        let request = try plainRequest(headers: [HTTPHeader(name: "Authorization", value: "Bearer synthetic")])
        let response = HTTPResponseData(
            statusCode: 402,
            statusMessage: "Payment Required",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"x402Version":1,"error":"payment required","accepts":[]}"#.utf8),
            contentType: .json
        )

        let info = try detectedInfo(request: request, response: response)

        #expect(info.stage == .paymentRequired)
        #expect(!info.hasPaymentProof)
        #expect(info.redactionFields.contains("Authorization"))
    }

    @Test("X402Detector recognizes x402 v2 payment headers")
    func recognizesV2Headers() throws {
        let challenge = try plainRequest(headers: [])
        let challengeResponse = HTTPResponseData(
            statusCode: 402,
            statusMessage: "Payment Required",
            headers: [HTTPHeader(name: "PAYMENT-REQUIRED", value: "synthetic-requirements")],
            body: nil,
            contentType: nil
        )
        let required = try detectedInfo(request: challenge, response: challengeResponse)
        #expect(required.stage == .paymentRequired)
        #expect(required.hasChallenge)
        #expect(required.redactionFields.contains("Payment-Required"))

        let retry = try plainRequest(headers: [HTTPHeader(name: "PAYMENT-SIGNATURE", value: "synthetic-signature")])
        let accepted = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "PAYMENT-RESPONSE", value: "synthetic-settlement")],
            body: Data(#"{"ok":true}"#.utf8),
            contentType: .json
        )
        let settled = try detectedInfo(request: retry, response: accepted)
        #expect(settled.stage == .paymentAccepted)
        #expect(settled.hasPaymentProof)
        #expect(settled.redactionFields.contains("Payment-Signature"))
        #expect(settled.redactionFields.contains("Payment-Response"))
    }

    @Test("X402Detector still recognizes x402 fields in a non-402 body without payment headers")
    func recognizesBodyOnlyHints() throws {
        let request = try plainRequest(headers: [])
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"x402Version":1,"paymentMetadata":{"receipt":"synthetic"}}"#.utf8),
            contentType: .json
        )
        let info = try detectedInfo(request: request, response: response)
        #expect(info.isX402Like)
        #expect(info.hasPaymentMetadata)
    }

    @Test("X402Detector skips body parsing for ordinary errors without payment hints")
    func ignoresOrdinaryErrorBodies() throws {
        let request = try plainRequest(headers: [HTTPHeader(name: "Authorization", value: "Bearer synthetic")])
        let response = HTTPResponseData(
            statusCode: 401,
            statusMessage: "Unauthorized",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"error":"invalid token","challenge":"synthetic"}"#.utf8),
            contentType: .json
        )

        #expect(X402Detector.detect(request: request, response: response) == nil)
    }

    private func plainRequest(headers: [HTTPHeader]) throws -> HTTPRequestData {
        try HTTPRequestData(
            method: "GET",
            url: try url("https://api.example.com/paywall"),
            httpVersion: "HTTP/1.1",
            headers: headers,
            body: nil,
            contentType: nil
        )
    }

    private func request(from message: ProtocolFixtureMessage) throws -> HTTPRequestData {
        let headers = message.headers.map { HTTPHeader(name: $0.name, value: $0.value) }
        let body = message.body.map { Data($0.utf8) }
        return try HTTPRequestData(
            method: message.method,
            url: try url(message.url),
            httpVersion: "HTTP/1.1",
            headers: headers,
            body: body,
            contentType: ContentTypeDetector.detect(headers: headers, body: body)
        )
    }

    private func response(from message: ProtocolFixtureMessage) throws -> HTTPResponseData {
        let headers = message.headers.map { HTTPHeader(name: $0.name, value: $0.value) }
        let body = message.body.map { Data($0.utf8) }
        return HTTPResponseData(
            statusCode: try statusCode(from: message),
            statusMessage: message.statusCode == 402 ? "Payment Required" : "OK",
            headers: headers,
            body: body,
            contentType: ContentTypeDetector.detect(headers: headers, body: body)
        )
    }

    private func detectedInfo(request: HTTPRequestData, response: HTTPResponseData) throws -> X402Info {
        guard let info = X402Detector.detect(request: request, response: response) else {
            throw X402TestError.missingDetection
        }
        return info
    }

    private func firstExchange(in fixture: ProtocolFixture) throws -> ProtocolFixtureExchange {
        guard let exchange = fixture.traffic.exchanges.first else {
            throw X402TestError.missingExchange
        }
        return exchange
    }

    private func secondExchange(in fixture: ProtocolFixture) throws -> ProtocolFixtureExchange {
        let exchanges = fixture.traffic.exchanges
        guard exchanges.count > 1 else {
            throw X402TestError.missingExchange
        }
        return exchanges[1]
    }

    private func responseMessage(in exchange: ProtocolFixtureExchange) throws -> ProtocolFixtureMessage {
        guard let response = exchange.response else {
            throw X402TestError.missingResponse
        }
        return response
    }

    private func statusCode(from message: ProtocolFixtureMessage) throws -> Int {
        guard let statusCode = message.statusCode else {
            throw X402TestError.missingStatusCode
        }
        return statusCode
    }

    private func url(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw X402TestError.invalidURL
        }
        return url
    }

    private enum X402TestError: Error {
        case invalidURL
        case missingDetection
        case missingExchange
        case missingResponse
        case missingStatusCode
    }
}
