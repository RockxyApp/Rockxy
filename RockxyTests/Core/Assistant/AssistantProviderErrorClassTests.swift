import Foundation
@testable import Rockxy
import Testing

// Provider failures that need different advice get their own error class instead of a generic
// "HTTP 200" or validation message.

struct AssistantProviderErrorClassTests {
    @Test("Anthropic 529 and an overloaded 503 are reported as overloaded, with Retry-After")
    func overloadedStatus() throws {
        let url = try #require(URL(string: "https://api.anthropic.com/v1/messages"))
        let overloaded = try #require(HTTPURLResponse(
            url: url,
            statusCode: 529,
            httpVersion: "HTTP/2",
            headerFields: ["Retry-After": "12"]
        ))
        #expect(AssistantHTTPErrorMapper.error(
            response: overloaded,
            body: Data(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8),
            model: "fixture"
        ) == .overloaded(retryAfterSeconds: 12))

        let unavailable = try #require(HTTPURLResponse(
            url: url,
            statusCode: 503,
            httpVersion: "HTTP/2",
            headerFields: nil
        ))
        #expect(AssistantHTTPErrorMapper.error(
            response: unavailable,
            body: Data(#"{"error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8),
            model: "fixture"
        ) == .overloaded(retryAfterSeconds: nil))
        #expect(AssistantHTTPErrorMapper.error(
            response: unavailable,
            body: Data(#"{"error":{"message":"maintenance"}}"#.utf8),
            model: "fixture"
        ) == .server(statusCode: 503, message: "maintenance"))
    }

    @Test("An Anthropic overloaded_error stream event is overloaded, not a validation error")
    func anthropicOverloadedEvent() {
        var decoder = AnthropicStreamDecoder()
        #expect(throws: AssistantProviderError.overloaded(retryAfterSeconds: nil)) {
            _ = try decoder
                .decode(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        }
    }

    @Test("An OpenAI response.failed event is a failed response, not HTTP 200")
    func openAIResponseFailed() {
        var decoder = OpenAIResponsesStreamDecoder()
        #expect(throws: AssistantProviderError.responseFailed("Server had an error")) {
            _ = try decoder.decode(
                line: #"data: {"type":"response.failed","response":{"id":"resp_1","error":{"code":"server_error","message":"Server had an error"}}}"#
            )
        }
    }

    @Test("An incomplete OpenAI response names its reason")
    func openAIIncompleteReason() {
        var decoder = OpenAIResponsesStreamDecoder()
        #expect(throws: AssistantProviderError.responseFailed("The response is incomplete (max_output_tokens)")) {
            _ = try decoder.decode(
                line: #"data: {"type":"response.incomplete","response":{"id":"r","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}}"#
            )
        }
    }

    @Test("Gemini prompt blocks and safety stops are reported as content blocked")
    func geminiSafety() {
        #expect(throws: AssistantProviderError.contentBlocked("SAFETY")) {
            _ = try GeminiStreamDecoder.decode(line: #"data: {"promptFeedback":{"blockReason":"SAFETY"}}"#)
        }
        #expect(throws: AssistantProviderError.contentBlocked("PROHIBITED_CONTENT")) {
            _ = try GeminiStreamDecoder.decode(
                line: #"data: {"candidates":[{"content":{"parts":[]},"finishReason":"PROHIBITED_CONTENT"}]}"#
            )
        }
        let normal = try? GeminiStreamDecoder.decode(
            line: #"data: {"candidates":[{"content":{"parts":[{"text":"hi"}]},"finishReason":"STOP"}]}"#
        )
        #expect(normal?.finished == true)
    }

    @Test("New error classes explain themselves")
    func descriptions() {
        #expect(AssistantProviderError.overloaded(retryAfterSeconds: nil).localizedDescription.contains("overloaded"))
        #expect(AssistantProviderError.contentBlocked("SAFETY").localizedDescription.contains("SAFETY"))
        #expect(AssistantProviderError.responseFailed("boom").localizedDescription.contains("boom"))
    }
}
