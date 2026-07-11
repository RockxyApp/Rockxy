import Foundation
@testable import Rockxy
import Testing

struct AITrafficDetectorTests {
    @Test("OpenAI-compatible streaming traffic exposes model, usage, stream events, and tools")
    func openAIStreamingTrafficExposesInspectionSignals() throws {
        let requestBody = Data(#"{"model":"gpt-4.1-mini","input":"fixture prompt","stream":true,"tools":[{"name":"lookup_order"}]}"#.utf8)
        let responseBody = Data("""
        event: response.created
        data: {"id":"resp_fixture","model":"gpt-4.1-mini"}

        event: response.output_text.delta
        data: {"delta":"hello"}

        event: response.tool_call.delta
        data: {"name":"lookup_order","arguments":"{\\\"order_id\\\":\\\"fixture-order\\\"}"}

        event: response.completed
        data: {"usage":{"input_tokens":920,"output_tokens":568,"total_tokens":1488}}

        """.utf8)
        let transaction = makeTransaction(
            url: "https://api.openai.com/v1/responses",
            requestBody: requestBody,
            responseHeaders: [HTTPHeader(name: "Content-Type", value: "text/event-stream")],
            responseBody: responseBody
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.provider == .openAICompatible)
        #expect(inspection.kind == .api)
        #expect(inspection.model == "gpt-4.1-mini")
        #expect(inspection.isStreaming)
        #expect(inspection.usage?.inputTokens == 920)
        #expect(inspection.usage?.outputTokens == 568)
        #expect(inspection.events.contains { $0.title == "response.tool_call.delta" })
        #expect(inspection.toolCalls.contains { $0.name == "lookup_order" })
        #expect(inspection.warnings.contains { $0.message.contains("Prompt content") })
    }

    @Test("Anthropic message traffic is detected without inventing missing usage")
    func anthropicTrafficKeepsMissingUsageUnavailable() throws {
        let requestBody = Data(#"{"model":"claude-sonnet-fixture","messages":[{"role":"user","content":"fixture"}]}"#.utf8)
        let transaction = makeTransaction(
            url: "https://api.anthropic.com/v1/messages",
            requestHeaders: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "anthropic-version", value: "2023-06-01"),
            ],
            requestBody: requestBody,
            responseBody: Data(#"{"type":"message","model":"claude-sonnet-fixture","content":[]}"#.utf8)
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.provider == .anthropic)
        #expect(inspection.model == "claude-sonnet-fixture")
        #expect(inspection.usage == nil)
        #expect(inspection.unavailableFields.contains("usage"))
    }

    @Test("Known AI app session is detected without visible body metadata")
    func nativeAISessionIsDetectedFromHostEvidence() throws {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://chatgpt.com/",
            statusCode: nil
        )
        transaction.clientApp = "ChatGPT"

        let signal = AITrafficDetector.signal(transaction: transaction)
        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(signal.tableLabel == "AI Session")
        #expect(signal.evidence.contains("body hidden"))
        #expect(inspection.provider == .chatGPT)
        #expect(inspection.kind == .session)
        #expect(inspection.model == nil)
        #expect(inspection.usage == nil)
    }

    @Test("Ordinary HTTP traffic does not expose AI inspection")
    func ordinaryHTTPTrafficDoesNotExposeAIInspection() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/orders",
            statusCode: 200
        )

        #expect(!AITrafficDetector.isLikelyAI(transaction: transaction))
        #expect(AITrafficDetector.detect(transaction: transaction) == nil)
        #expect(!ResponseInspectorTab.availableTabs(hasAIInspection: false).contains(.ai))
    }

    @Test("AI tab is available only when AI metadata is likely")
    func aiTabAvailabilityFollowsDetection() {
        let requestBody = Data(#"{"model":"gpt-4.1-mini","input":"fixture"}"#.utf8)
        let transaction = makeTransaction(
            url: "https://localhost:11434/v1/responses",
            requestBody: requestBody
        )

        #expect(AITrafficDetector.isLikelyAI(transaction: transaction))
        #expect(!ResponseInspectorTab.availableTabs(hasAIInspection: true).contains(.ai))
        #expect(ProtocolTabKind.availableTabs(for: transaction).contains(.ai))
        #expect(ProtocolTabKind.defaultFor(transaction) == .ai)
    }

    private func makeTransaction(
        url: String,
        requestHeaders: [HTTPHeader] = [
            HTTPHeader(name: "Content-Type", value: "application/json"),
            HTTPHeader(name: "Authorization", value: "Bearer synthetic-token"),
        ],
        requestBody: Data? = nil,
        responseHeaders: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")],
        responseBody: Data? = nil
    )
        -> HTTPTransaction
    {
        guard let requestURL = URL(string: url) else {
            preconditionFailure("Expected valid fixture URL")
        }
        let request = HTTPRequestData(
            method: "POST",
            url: requestURL,
            httpVersion: "HTTP/1.1",
            headers: requestHeaders,
            body: requestBody,
            contentType: .json
        )
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: responseHeaders,
            body: responseBody,
            contentType: .json
        )
        let transaction = HTTPTransaction(request: request, response: response, state: .completed)
        transaction.timingInfo = TimingInfo(
            dnsLookup: 0.001,
            tcpConnection: 0.002,
            tlsHandshake: 0.003,
            timeToFirstByte: 0.642,
            contentTransfer: 3.192
        )
        return transaction
    }
}
