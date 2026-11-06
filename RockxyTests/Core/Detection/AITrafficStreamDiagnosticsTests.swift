import Foundation
@testable import Rockxy
import Testing

struct AITrafficStreamDiagnosticsTests {
    // MARK: Internal

    @Test("Live stream diagnostics drive first stream event, gap, and completion")
    func liveDiagnosticsSurfaceInInspection() throws {
        let transaction = makeStreamingTransaction(responseBody: sseBody)
        transaction.streamDiagnostics = StreamDiagnostics(
            events: [
                SSEEventMetadata(index: 0, eventName: "response.created", relativeTime: 0.12, byteCount: 24),
                SSEEventMetadata(index: 1, eventName: nil, relativeTime: 1.80, byteCount: 12),
            ],
            eventCount: 3,
            firstEventTime: 0.12,
            lastEventTime: 1.80,
            terminalEventTime: 1.80,
            maxInterEventGap: 1.68,
            terminalMarker: .done,
            outcome: .completedWithTerminalMarker,
            didReachMetadataLimit: false,
            didObserveMalformedFrame: false,
            hasUnterminatedPartialFrame: false
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.isStreaming)
        let diagnostics = try #require(transaction.streamDiagnostics)
        #expect(diagnostics.firstEventTime == 0.12)
        #expect(diagnostics.maxInterEventGap == 1.68)
        #expect(diagnostics.terminalEventTime == 1.80)
        #expect(diagnostics.outcome == .completedWithTerminalMarker)
    }

    @Test("A stream ending without a terminal marker is not reported as completed")
    func incompleteStreamPreservesOutcome() throws {
        let transaction = makeStreamingTransaction(responseBody: sseBody)
        transaction.streamDiagnostics = StreamDiagnostics(
            events: [],
            eventCount: 2,
            firstEventTime: 0.05,
            lastEventTime: 0.90,
            terminalEventTime: nil,
            maxInterEventGap: 0.85,
            terminalMarker: nil,
            outcome: .transportInterrupted,
            didReachMetadataLimit: false,
            didObserveMalformedFrame: false,
            hasUnterminatedPartialFrame: true
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))
        let diagnostics = try #require(transaction.streamDiagnostics)

        #expect(diagnostics.terminalMarker == nil)
        #expect(diagnostics.outcome == .transportInterrupted)
    }

    @Test("OpenAI-style choices finish_reason is extracted")
    func openAIFinishReasonExtracted() throws {
        let responseBody = Data(#"""
        {"model":"gpt-4.1-mini","choices":[{"finish_reason":"stop","message":{"content":"hi"}}]}
        """#.utf8)
        let transaction = makeTransaction(
            url: "https://api.openai.com/v1/chat/completions",
            requestBody: Data(#"{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"hey"}]}"#.utf8),
            responseBody: responseBody
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))
        #expect(inspection.finishReason == "stop")
    }

    @Test("Top-level stop_reason is extracted for message-style responses")
    func stopReasonExtracted() throws {
        let transaction = makeTransaction(
            url: "https://api.anthropic.com/v1/messages",
            requestHeaders: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "anthropic-version", value: "2023-06-01"),
            ],
            requestBody: Data(#"{"model":"claude-fixture","messages":[{"role":"user","content":"hi"}]}"#.utf8),
            responseBody: Data(#"{"model":"claude-fixture","stop_reason":"end_turn","content":[]}"#.utf8)
        )

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))
        #expect(inspection.finishReason == "end_turn")
    }

    @Test("Body-only SSE traffic has no live diagnostics and no inferred timing")
    func bodyOnlyStreamHasNoLiveDiagnostics() throws {
        let transaction = makeStreamingTransaction(responseBody: sseBody)
        // No `streamDiagnostics` assigned: this mirrors imported HAR traffic.

        let inspection = try #require(AITrafficDetector.detect(transaction: transaction))

        #expect(inspection.isStreaming)
        #expect(transaction.streamDiagnostics == nil)
    }

    // MARK: Private

    private let sseBody = Data("""
    event: response.created
    data: {"id":"resp_fixture","model":"gpt-4.1-mini"}

    event: response.output_text.delta
    data: {"delta":"hi"}

    data: [DONE]

    """.utf8)

    private func makeStreamingTransaction(responseBody: Data) -> HTTPTransaction {
        makeTransaction(
            url: "https://api.openai.com/v1/responses",
            requestBody: Data(#"{"model":"gpt-4.1-mini","input":"fixture","stream":true}"#.utf8),
            responseHeaders: [HTTPHeader(name: "Content-Type", value: "text/event-stream")],
            responseBody: responseBody
        )
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
        return HTTPTransaction(request: request, response: response, state: .completed)
    }
}
