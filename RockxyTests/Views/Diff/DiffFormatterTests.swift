import Foundation
@testable import Rockxy
import Testing

// Regression tests for `DiffFormatter` in the views diff layer.

struct DiffFormatterTests {
    @Test("Request formatting produces structured sections")
    func requestFormatting() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/v2/users?page=1",
            statusCode: 200
        )
        let sections = DiffFormatter.format(transaction: transaction, target: .request)

        #expect(sections.count >= 4)
        #expect(sections[0].0 == "Request Line")
        #expect(sections[0].1.contains("GET"))
        #expect(sections[1].0 == "Host")
        #expect(sections[1].1 == "api.example.com")
        #expect(sections[2].0 == "Query")
        #expect(sections[3].0 == "Headers")
    }

    @Test("Response formatting produces structured sections")
    func responseFormatting() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/test",
            statusCode: 200
        )
        let sections = DiffFormatter.format(transaction: transaction, target: .response)

        #expect(sections.count >= 2)
        #expect(sections[0].0 == "Status Line")
        #expect(sections[0].1.contains("200"))
    }

    @Test("Response formatting decodes a compressed body into diffable text")
    func responseFormattingDecodesCompressedBody() throws {
        let plain = #"{"users":[{"id":1}]}"#
        let compressed = try (Data(plain.utf8) as NSData).compressed(using: .zlib) as Data
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/users",
            statusCode: 200
        )
        transaction.response = TestFixtures.makeResponse(
            statusCode: 200,
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Content-Encoding", value: "deflate"),
            ],
            body: compressed
        )

        let sections = DiffFormatter.format(transaction: transaction, target: .response)
        let body = try #require(sections.first { $0.0 == "Body" }?.1)

        // Pretty-printed JSON, not a binary summary of the compressed bytes.
        #expect(body.contains("\"users\""))
        #expect(body.contains("\"id\""))
        // The captured headers stay as they were on the wire.
        let headers = try #require(sections.first { $0.0 == "Headers" }?.1)
        #expect(headers.contains("Content-Encoding: deflate"))
    }

    @Test("Timing formatting produces timing section")
    func timingFormatting() {
        let transaction = TestFixtures.makeTransactionWithTiming()
        let sections = DiffFormatter.format(transaction: transaction, target: .timing)

        #expect(sections.count == 1)
        #expect(sections[0].0 == "Timing")
        #expect(sections[0].1.contains("DNS"))
        #expect(sections[0].1.contains("Total"))
    }

    @Test("No timing data shows fallback")
    func noTimingFallback() {
        let transaction = TestFixtures.makeTransaction()
        transaction.timingInfo = nil
        let sections = DiffFormatter.format(transaction: transaction, target: .timing)

        #expect(sections[0].1.contains("No timing data"))
    }

    @Test("Measured duration is used when phase timing is unavailable")
    func measuredDurationFallback() {
        let transaction = TestFixtures.makeTransaction()
        transaction.timingInfo = nil
        transaction.measuredDuration = 0.125

        let sections = DiffFormatter.format(transaction: transaction, target: .timing)

        // The decimal separator follows Rockxy's formatting locale ("125,0ms" on a Vietnam Mac).
        #expect(sections[0].1.contains("\(DecimalFormatter.format(125, fractionDigits: 1))ms"))
        #expect(sections[0].1.contains("Detailed phase timing unavailable"))
    }

    @Test("No response shows fallback")
    func noResponseFallback() {
        let transaction = TestFixtures.makeTransaction(statusCode: nil)
        let sections = DiffFormatter.format(transaction: transaction, target: .response)

        #expect(sections[0].1.contains("No response"))
    }

    @Test("Empty body shows fallback text")
    func emptyBodyFallback() {
        let transaction = TestFixtures.makeTransaction()
        let sections = DiffFormatter.format(transaction: transaction, target: .request)
        let bodySection = sections.first { $0.0 == "Body" }
        #expect(bodySection != nil)
        #expect(bodySection?.1.contains("No request body") == true)
    }

    @Test("JSON body is pretty-printed")
    func jsonPrettyPrint() {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            statusCode: 200,
            body: Data("{\"name\":\"Alice\",\"age\":30}".utf8)
        )
        let sections = DiffFormatter.format(transaction: transaction, target: .response)
        let bodySection = sections.first { $0.0 == "Body" }
        #expect(bodySection?.1.contains("\"name\"") == true)
        #expect(bodySection?.1.contains("\n") == true)
    }

    @Test("Equal-size binary bodies compare by captured content")
    func equalSizeBinaryBodiesRemainDistinct() {
        let left = TestFixtures.makeTransaction()
        left.response = TestFixtures.makeResponse(
            statusCode: 200,
            body: Data([0xFF, 0x00, 0x01])
        )
        let right = TestFixtures.makeTransaction()
        right.response = TestFixtures.makeResponse(
            statusCode: 200,
            body: Data([0xFF, 0x00, 0x02])
        )

        let result = DiffFormatter.diff(left: left, right: right, target: .response)

        #expect(result.differenceCount > 0)
    }

    @Test("Truncated response body is explicit in comparison")
    func truncatedResponseIsExplicit() {
        let transaction = TestFixtures.makeTransaction()
        var response = TestFixtures.makeResponse(
            statusCode: 200,
            body: Data("partial".utf8)
        )
        response.bodyTruncated = true
        transaction.response = response

        let sections = DiffFormatter.format(transaction: transaction, target: .response)
        let bodySection = sections.first { $0.0 == "Body" }

        #expect(bodySection?.1.contains("Capture truncated") == true)
    }

    @Test("Truncated response with no retained body remains explicit")
    func truncatedEmptyResponseIsExplicit() {
        let transaction = TestFixtures.makeTransaction()
        var response = TestFixtures.makeResponse(statusCode: 200, body: nil)
        response.bodyTruncated = true
        transaction.response = response

        let sections = DiffFormatter.format(transaction: transaction, target: .response)
        let bodySection = sections.first { $0.0 == "Body" }

        #expect(bodySection?.1.contains("No response body") == true)
        #expect(bodySection?.1.contains("Capture truncated") == true)
    }

    @Test("Binary content type is hashed even when its bytes form valid text")
    func binaryContentTypeUsesDigest() {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "application/octet-stream")],
            body: Data("abc".utf8)
        )

        let sections = DiffFormatter.format(transaction: transaction, target: .response)
        let body = sections.first { $0.0 == "Body" }?.1

        #expect(body?.contains("Binary body") == true)
        #expect(body?.contains("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == true)
    }

    @Test("Control bytes are classified as binary without relying on UTF-8 failure")
    func controlBytesUseDigest() {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain")],
            body: Data([0x61, 0x00, 0x62])
        )

        let sections = DiffFormatter.format(transaction: transaction, target: .response)
        let body = sections.first { $0.0 == "Body" }?.1

        #expect(body?.contains("Binary body") == true)
        #expect(body?.contains("SHA-256") == true)
    }

    @Test("Control bytes beyond the first four KiB are still classified as binary")
    func laterControlBytesUseDigest() {
        let transaction = TestFixtures.makeTransaction()
        var bytes = Array(repeating: UInt8(ascii: "a"), count: 5_000)
        bytes[4_500] = 0
        transaction.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain")],
            body: Data(bytes)
        )

        let sections = DiffFormatter.format(transaction: transaction, target: .response)
        let body = sections.first { $0.0 == "Body" }?.1

        #expect(body?.contains("Binary body") == true)
    }

    @Test("Large textual bodies use a bounded preview and captured-body digest")
    func largeBodyPreviewIsBounded() {
        let body = Data(
            String(repeating: "a", count: DiffFormatter.maximumBodyPreviewBytes + 128).utf8
        )
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain; charset=utf-8")],
            body: body
        )

        let sections = DiffFormatter.format(transaction: transaction, target: .response)
        let bodyText = sections.first { $0.0 == "Body" }?.1

        #expect(bodyText?.contains("Body preview limited") == true)
        #expect(bodyText?.contains("SHA-256 (all captured bytes)") == true)
        #expect((bodyText?.count ?? 0) < DiffFormatter.maximumBodyPreviewBytes + 512)
    }

    @Test("Large bodies with equal previews and different tails remain distinct")
    func largeBodyTailDifference() {
        let shared = Data(repeating: UInt8(ascii: "a"), count: DiffFormatter.maximumBodyPreviewBytes)
        let left = TestFixtures.makeTransaction()
        left.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain")],
            body: shared + Data("left".utf8)
        )
        let right = TestFixtures.makeTransaction()
        right.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain")],
            body: shared + Data("right".utf8)
        )

        let result = DiffFormatter.diff(left: left, right: right, target: .response)

        #expect(result.differenceCount > 0)
        #expect(result.allLines.contains { $0.content.contains("SHA-256") })
    }

    @Test("Text previews stay textual when the byte limit cuts a multibyte scalar")
    func textPreviewTrimsPartialUTF8Scalar() {
        let text = String(repeating: "a", count: DiffFormatter.maximumBodyPreviewBytes - 1)
            + "é"
            + "tail"
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain; charset=utf-8")],
            body: Data(text.utf8)
        )

        let sections = DiffFormatter.format(transaction: transaction, target: .response)
        let body = sections.first { $0.0 == "Body" }?.1

        #expect(body?.contains("Body preview limited") == true)
        #expect(body?.contains("Binary body") == false)
    }

    @Test("Diff between two transactions produces structured result")
    func diffBetweenTransactions() {
        let left = TestFixtures.makeTransaction(url: "https://api.example.com/v1/users", statusCode: 200)
        let right = TestFixtures.makeTransaction(url: "https://api.example.com/v2/users", statusCode: 200)

        let result = DiffFormatter.diff(left: left, right: right, target: .request)

        #expect(result.sections.count >= 4)
        #expect(result.differenceCount > 0)
    }

    // MARK: - Regression tests

    @Test("Response diff with no-response vs full-response produces aligned sections")
    func noResponseVsFullResponse() {
        let noResp = TestFixtures.makeTransaction(statusCode: nil)
        let fullResp = TestFixtures.makeTransaction(statusCode: 200)

        let result = DiffFormatter.diff(left: noResp, right: fullResp, target: .response)

        // Both sides should have Status Line, Headers, Body sections
        #expect(result.sections.count == 3)
        #expect(result.sections[0].title == "Status Line")
        #expect(result.sections[1].title == "Headers")
        #expect(result.sections[2].title == "Body")
    }

    @Test("HTTP version normalization renders correctly for HTTP/1.1 input")
    func httpVersionWithPrefix() {
        let transaction = TestFixtures.makeTransaction()
        let sections = DiffFormatter.format(transaction: transaction, target: .request)
        let requestLine = sections.first { $0.0 == "Request Line" }
        #expect(requestLine?.1.contains("HTTP/1.1") == true)
        #expect(requestLine?.1.contains("HTTP/HTTP/") == false)
    }

    @Test("Export formatter preserves section order and diff markers")
    func exportFormatter() {
        let result = DiffResult(sections: [
            DiffSection(title: "Body", lines: [
                DiffLine(lineNumber: 1, content: "same", type: .unchanged),
                DiffLine(lineNumber: 2, content: "before", type: .removed),
                DiffLine(lineNumber: 3, content: "after", type: .added),
            ]),
        ])

        let output = DiffExportFormatter.text(for: result)

        #expect(output.contains("--- Body ---"))
        #expect(output.contains("  same"))
        #expect(output.contains("- before"))
        #expect(output.contains("+ after"))
    }

    @Test("Unified patch uses standard headers, hunk ranges, and context")
    func unifiedPatchFormat() {
        let result = DiffResult(sections: [
            DiffSection(title: "Response Headers", lines: [
                DiffLine(lineNumber: 1, content: "A: 1", type: .unchanged, oldLineNumber: 1, newLineNumber: 1),
                DiffLine(lineNumber: 2, content: "ETag: \"old\"", type: .removed, oldLineNumber: 2),
                DiffLine(lineNumber: 3, content: "ETag: \"new\"", type: .added, newLineNumber: 2),
                DiffLine(lineNumber: 4, content: "B: 2", type: .unchanged, oldLineNumber: 3, newLineNumber: 3),
            ]),
            DiffSection(title: "Body", lines: [
                DiffLine(lineNumber: 1, content: "same", type: .unchanged),
            ]),
        ])

        let patch = DiffExportFormatter.unifiedPatch(for: result)

        #expect(patch == """
        --- a/response-headers
        +++ b/response-headers
        @@ -1,3 +1,3 @@
         A: 1
        -ETag: "old"
        +ETag: "new"
         B: 2

        """)
    }

    @Test("Distant changes become separate hunks with correct ranges")
    func unifiedPatchSplitsHunks() {
        var lines = [DiffLine(lineNumber: 1, content: "top", type: .added, newLineNumber: 1)]
        for number in 1 ... 10 {
            lines.append(DiffLine(
                lineNumber: number + 1,
                content: "l\(number)",
                type: .unchanged,
                oldLineNumber: number,
                newLineNumber: number + 1
            ))
        }
        lines.append(DiffLine(lineNumber: 12, content: "l11", type: .removed, oldLineNumber: 11))

        let patch = DiffExportFormatter.unifiedPatch(
            for: DiffResult(sections: [DiffSection(title: "Body", lines: lines)]),
            context: 1
        )

        #expect(patch == """
        --- a/body
        +++ b/body
        @@ -1,1 +1,2 @@
        +top
         l1
        @@ -10,2 +11,1 @@
         l10
        -l11

        """)
    }

    @Test("FileMerge gets a left and right document rebuilt from the comparison")
    func fileMergeDocuments() {
        let result = DiffResult(sections: [
            DiffSection(title: "Headers", lines: [
                DiffLine(lineNumber: 1, content: "Accept: */*", type: .unchanged),
                DiffLine(lineNumber: 2, content: "X-Old: 1", type: .removed),
                DiffLine(lineNumber: 3, content: "X-New: 2", type: .added),
            ]),
        ])
        let documents = DiffFileMerge.documents(for: result)
        #expect(documents.left == "--- Headers ---\nAccept: */*\nX-Old: 1\n\n")
        #expect(documents.right == "--- Headers ---\nAccept: */*\nX-New: 2\n\n")
    }
}
