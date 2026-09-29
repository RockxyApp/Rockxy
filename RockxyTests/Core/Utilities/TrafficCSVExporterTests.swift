import Foundation
@testable import Rockxy
import Testing

// MARK: - TrafficCSVExporterTests

struct TrafficCSVExporterTests {
    @Test("Cells with commas, quotes, or newlines are quoted per RFC 4180")
    func quotesSpecialCharacters() {
        #expect(TrafficCSVExporter.escape("plain") == "plain")
        #expect(TrafficCSVExporter.escape("a,b") == "\"a,b\"")
        #expect(TrafficCSVExporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(TrafficCSVExporter.escape("line1\nline2") == "\"line1\nline2\"")
    }

    @Test("Formula-looking cells are neutralized")
    func neutralizesFormulas() {
        #expect(TrafficCSVExporter.escape("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(TrafficCSVExporter.escape("+1") == "'+1")
        #expect(TrafficCSVExporter.escape("@cmd") == "'@cmd")
    }

    @Test("One header row plus one row per transaction, without headers or bodies")
    func writesRows() throws {
        let failing = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.example.com/login?next=/home",
            statusCode: 401,
            comment: "token, expired"
        )
        failing.request.headers.append(HTTPHeader(name: "Authorization", value: "Bearer secret"))
        let pending = TestFixtures.makeTransaction(statusCode: nil)

        let text = try #require(String(data: TrafficCSVExporter.export(transactions: [failing, pending]), encoding: .utf8))
        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("#,Start Time,Method,URL"))
        #expect(lines[1].contains(",POST,https://api.example.com/login?next=/home,api.example.com,/login,401,"))
        #expect(lines[1].hasSuffix(",\"token, expired\""))
        #expect(!text.contains("Bearer secret"))
        #expect(lines[2].contains(",GET,"))
    }

    @Test("CSV is offered for every scope and every transaction")
    func csvFormatIsGeneric() {
        let transaction = TestFixtures.makeTransaction(method: "CONNECT")
        #expect(TrafficExportFormat.csv.isEligible(transaction))
        #expect(!TrafficExportFormat.csv.isOpenAPI)
        #expect(TrafficExportFormat.csv.defaultFileName == "rockxy-export.csv")
    }
}
