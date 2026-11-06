import Foundation
@testable import Rockxy
import Testing

@MainActor
struct BodyCompletenessTests {
    // MARK: Internal

    @Test("Unreadable-evidence omission is unknown; ordinary truncation stays known-truncated")
    func classification() {
        #expect(BodyCompleteness(truncated: false, omission: nil) == .complete)
        #expect(BodyCompleteness(truncated: true, omission: nil) == .knownTruncated)
        let ordinary = BodyOmissionMetadata(reason: "maxBodySize", observedBytes: 10, originalBytes: 99)
        #expect(BodyCompleteness(truncated: true, omission: ordinary) == .knownTruncated)
        #expect(BodyCompleteness(truncated: true, omission: unreadable) == .unknown)
    }

    @Test("Reason wording is human for unreadable evidence and untouched otherwise")
    func reasonWording() {
        let human = BodyCompleteness.reasonDescription(SessionStore.unreadableEvidenceOmissionReason)
        #expect(!human.contains("captureEvidenceUnreadable"))
        #expect(BodyCompleteness.reasonDescription("maxBodySize") == "maxBodySize")
    }

    @Test("Log notes distinguish the two states")
    func logNotes() {
        #expect(BodyCompleteness.complete.logNote.isEmpty)
        #expect(BodyCompleteness.knownTruncated.logNote == " (only the first part was kept)")
        #expect(BodyCompleteness.unknown.logNote.contains("may be incomplete"))
        #expect(!BodyCompleteness.unknown.logNote.contains("only the first part"))
    }

    @Test("cURL, raw and snippet copies carry a note only when completeness is unknown")
    func copyNotes() {
        let flagged = transaction(truncated: true, omission: unreadable)
        let plain = transaction(truncated: true, omission: nil)

        #expect(RequestCopyFormatter.curl(for: flagged).hasPrefix("# Rockxy: the request body may be incomplete"))
        #expect(RequestCopyFormatter.rawRequest(for: flagged).hasPrefix("# Rockxy: the request body"))
        #expect(RequestCopyFormatter.rawResponse(for: flagged)?.hasPrefix("# Rockxy: the response body") == true)
        #expect(RequestCopyFormatter.json(for: flagged)?.contains("\"bodyCompleteness\" : \"unknown\"") == true)
        #expect(CodeSnippetGenerator.snippet(for: flagged.request, language: .pythonRequests).hasPrefix("# Rockxy"))
        #expect(CodeSnippetGenerator.snippet(for: flagged.request, language: .goNetHTTP).hasPrefix("// Rockxy"))

        #expect(!RequestCopyFormatter.curl(for: plain).contains("Rockxy:"))
        #expect(!RequestCopyFormatter.rawRequest(for: plain).contains("Rockxy:"))
        #expect(RequestCopyFormatter.json(for: plain)?.contains("bodyCompleteness") == false)
    }

    @Test("The note names exactly the bodies that are affected")
    func noteNamesAffectedBodies() {
        let both = BodyCompleteness.exportNote(request: .unknown, response: .unknown)
        let requestOnly = BodyCompleteness.exportNote(request: .unknown, response: .complete)
        let responseOnly = BodyCompleteness.exportNote(request: .complete, response: .unknown)
        #expect(both?.hasPrefix("Rockxy: the request and response bodies may be incomplete") == true)
        #expect(requestOnly?.hasPrefix("Rockxy: the request body may be incomplete") == true)
        #expect(responseOnly?.hasPrefix("Rockxy: the response body may be incomplete") == true)
        #expect(BodyCompleteness.exportNote(request: .knownTruncated, response: .complete) == nil)
        #expect(BodyCompleteness.exportNote(request: .complete, response: nil) == nil)
    }

    @Test("Each copy names only the body it actually carries")
    func copiesNameTheirOwnBody() {
        let requestOnly = transaction(truncated: true, omission: unreadable)
        requestOnly.response?.bodyTruncated = false
        requestOnly.response?.bodyOmission = nil
        let responseOnly = transaction(truncated: true, omission: unreadable)
        responseOnly.request.bodyTruncated = false
        responseOnly.request.bodyOmission = nil

        #expect(RequestCopyFormatter.rawResponse(for: requestOnly)?.hasPrefix("HTTP/1.1") == true)
        #expect(RequestCopyFormatter.rawRequest(for: requestOnly).hasPrefix("# Rockxy: the request body"))
        #expect(!RequestCopyFormatter.rawRequest(for: responseOnly).contains("Rockxy:"))
        #expect(RequestCopyFormatter.rawResponse(for: responseOnly)?.hasPrefix("# Rockxy: the response body") == true)
        #expect(!RequestCopyFormatter.curl(for: responseOnly).contains("Rockxy:"))
        #expect(RequestCopyFormatter.json(for: requestOnly)?.contains("\"bodyCompleteness\"") == true)
        #expect(RequestCopyFormatter.json(for: responseOnly)?.components(separatedBy: "bodyCompleteness").count == 2)
    }

    @Test("Connection log tells unknown apart from truncated")
    func connectionLog() {
        let flagged = transaction(truncated: true, omission: unreadable)
        let plain = transaction(truncated: true, omission: nil)
        let flaggedText = ConnectionLogFormatter.plainText(for: input(flagged))
        let plainText = ConnectionLogFormatter.plainText(for: input(plain))
        #expect(flaggedText.contains("Response body: ") && flaggedText.contains("may be incomplete"))
        #expect(!flaggedText.contains("only the first part"))
        #expect(plainText.contains("only the first part was kept"))
    }

    // MARK: Private

    private var unreadable: BodyOmissionMetadata {
        BodyOmissionMetadata(
            reason: SessionStore.unreadableEvidenceOmissionReason,
            observedBytes: 4,
            originalBytes: nil
        )
    }

    private func transaction(truncated: Bool, omission: BodyOmissionMetadata?) -> HTTPTransaction {
        let request = HTTPRequestData(
            method: "POST",
            url: URL(string: "https://example.com/a")!,
            httpVersion: "HTTP/1.1",
            headers: [],
            body: Data("abcd".utf8),
            bodyTruncated: truncated,
            bodyOmission: omission
        )
        let transaction = HTTPTransaction(request: request)
        transaction.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [],
            body: Data("wxyz".utf8),
            bodyTruncated: truncated,
            bodyOmission: omission
        )
        return transaction
    }

    private func input(_ transaction: HTTPTransaction) -> ConnectionLogFormatter.Input {
        ConnectionLogFormatter.Input(
            log: nil,
            request: transaction.request,
            response: transaction.response,
            serverHTTPVersion: nil
        )
    }
}
