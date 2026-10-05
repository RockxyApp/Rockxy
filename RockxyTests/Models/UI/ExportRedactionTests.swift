import Foundation
@testable import Rockxy
import Testing

// MARK: - ExportRedactionTests

/// Sharing a capture (for example a server calling a paid API with a bearer key) should not
/// require editing the export by hand to remove the key.
struct ExportRedactionTests {
    @Test("A redacted HAR export hides secrets and leaves the captured session untouched")
    func redactedHARHidesSecrets() throws {
        let request = HTTPRequestData(
            method: "POST",
            url: try #require(URL(string: "https://api.example.com/v1/chat?api_key=sk-query-secret&page=2")),
            httpVersion: "HTTP/1.1",
            headers: [
                HTTPHeader(name: "Authorization", value: "Bearer sk-live-secret"),
                HTTPHeader(name: "Content-Type", value: "application/json"),
            ],
            body: Data(#"{"model":"gpt","password":"hunter2"}"#.utf8)
        )
        let transaction = HTTPTransaction(request: request, state: .completed)
        let plan = ExportExecutionPlan(
            format: .har,
            scope: .all,
            reviewedSource: [transaction],
            eligibleTransactions: [transaction],
            skippedCount: 0
        )

        let redacted = plan.redactingSensitiveData()
        let har = try #require(String(
            data: HARExporter().export(transactions: redacted.eligibleTransactions),
            encoding: .utf8
        ))

        #expect(!har.contains("sk-live-secret"))
        #expect(!har.contains("sk-query-secret"))
        #expect(!har.contains("hunter2"))
        #expect(har.contains("REDACTED"))
        #expect(har.contains("page=2"))
        #expect(transaction.request.headers.contains { $0.value == "Bearer sk-live-secret" })
    }

    @Test("Only formats that write headers, bodies, or URLs offer redaction")
    func redactionFormats() {
        #expect(TrafficExportFormat.har.supportsRedaction)
        #expect(TrafficExportFormat.rockxySession.supportsRedaction)
        #expect(TrafficExportFormat.postman.supportsRedaction)
        #expect(TrafficExportFormat.csv.supportsRedaction)
        #expect(!TrafficExportFormat.openAPIYAML.supportsRedaction)
        #expect(!TrafficExportFormat.openAPIHTML.supportsRedaction)
    }
}
