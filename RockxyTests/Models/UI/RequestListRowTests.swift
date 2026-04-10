import Foundation
@testable import Rockxy
import Testing

@MainActor
struct RequestListRowTests {
    // MARK: Internal

    // MARK: - Basic Extraction

    @Test("Extracts all fields from completed HTTP transaction")
    func extractsAllFields() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.example.com/users/1",
            statusCode: 201
        )
        transaction.sequenceNumber = 42
        transaction.clientApp = "Safari"
        transaction.sourcePort = 54_321
        transaction.isPinned = true
        transaction.isSaved = false
        transaction.comment = "Test comment"
        transaction.highlightColor = .blue

        let row = RequestListRow(from: transaction)

        #expect(row.id == transaction.id)
        #expect(row.timestamp == transaction.timestamp)
        #expect(row.method == "POST")
        #expect(row.scheme == "https")
        #expect(row.host == "api.example.com")
        #expect(row.path == "/users/1")
        #expect(row.statusCode == 201)
        #expect(row.state == .completed)
        #expect(row.clientApp == "Safari")
        #expect(row.sourcePort == 54_321)
        #expect(row.isPinned == true)
        #expect(row.isSaved == false)
        #expect(row.comment == "Test comment")
        #expect(row.highlightColor == .blue)
        #expect(row.sequenceNumber == 42)
        #expect(row.isTLSFailure == false)
    }

    @Test("Nil response produces nil status and response fields")
    func nilResponse() {
        let transaction = TestFixtures.makeTransaction(statusCode: nil)
        let row = RequestListRow(from: transaction)

        #expect(row.statusCode == nil)
        #expect(row.statusMessage == nil)
        #expect(row.responseBodySize == nil)
        #expect(row.responseContentType == nil)
        #expect(row.responseHeaders == nil)
    }

    @Test("Extracts GraphQL fields correctly")
    func graphQLFields() {
        let transaction = TestFixtures.makeGraphQLTransaction(
            operationName: "GetUsers",
            operationType: .query
        )
        let row = RequestListRow(from: transaction)

        #expect(row.graphQLOpName == "GetUsers")
        #expect(row.graphQLOpType == "query")
        #expect(row.isWebSocket == false)
        #expect(row.webSocketFrameCount == 0)
    }

    @Test("Extracts WebSocket fields correctly")
    func webSocketFields() {
        let transaction = TestFixtures.makeWebSocketTransaction()
        let row = RequestListRow(from: transaction)

        #expect(row.isWebSocket == true)
        #expect(row.webSocketFrameCount == 5)
        #expect(row.graphQLOpName == nil)
    }

    @Test("Extracts headers for custom column resolution")
    func headersExtracted() {
        let transaction = TestFixtures.makeTransaction()
        let row = RequestListRow(from: transaction)

        #expect(!row.requestHeaders.isEmpty)
        #expect(row.requestHeaders.contains { $0.name == "Content-Type" })
        #expect(row.responseHeaders != nil)
        #expect(row.responseHeaders?.contains { $0.name == "Content-Type" } == true)
    }

    @Test("TLS failure field extracted")
    func tlsFailure() {
        let transaction = TestFixtures.makeTransaction()
        transaction.isTLSFailure = true
        let row = RequestListRow(from: transaction)

        #expect(row.isTLSFailure == true)
    }

    @Test("Body sizes extracted from request and response")
    func bodySizes() {
        let transaction = TestFixtures.makeTransactionWithBody(
            responseJSON: ["key": "value"]
        )
        let row = RequestListRow(from: transaction)

        #expect(row.responseBodySize != nil)
        #expect(row.responseBodySize ?? 0 > 0)
    }

    // MARK: - Sorting

    @Test("Sort by URL ascending")
    func sortByURL() {
        let a = makeRow(host: "alpha.com", path: "/test")
        let b = makeRow(host: "beta.com", path: "/test")
        let descriptors = [NSSortDescriptor(key: "url", ascending: true)]

        #expect(RequestListRow.compare(a, b, using: descriptors) == true)
        #expect(RequestListRow.compare(b, a, using: descriptors) == false)
    }

    @Test("Sort by status code with nil sorting last")
    func sortByStatusCode() {
        let ok = makeRow(statusCode: 200)
        let error = makeRow(statusCode: 500)
        let pending = makeRow(statusCode: nil)
        let descriptors = [NSSortDescriptor(key: "code", ascending: true)]

        #expect(RequestListRow.compare(ok, error, using: descriptors) == true)
        #expect(RequestListRow.compare(ok, pending, using: descriptors) == true)
        #expect(RequestListRow.compare(pending, ok, using: descriptors) == false)
    }

    @Test("Sort by sequence number (row column)")
    func sortBySequenceNumber() {
        let first = makeRow(sequenceNumber: 1)
        let second = makeRow(sequenceNumber: 2)
        let descriptors = [NSSortDescriptor(key: "row", ascending: true)]

        #expect(RequestListRow.compare(first, second, using: descriptors) == true)
        #expect(RequestListRow.compare(second, first, using: descriptors) == false)
    }

    @Test("Sort descending reverses order")
    func sortDescending() {
        let a = makeRow(host: "alpha.com", path: "/test")
        let b = makeRow(host: "beta.com", path: "/test")
        let descriptors = [NSSortDescriptor(key: "url", ascending: false)]

        #expect(RequestListRow.compare(a, b, using: descriptors) == false)
        #expect(RequestListRow.compare(b, a, using: descriptors) == true)
    }

    @Test("Unknown sort key preserves order")
    func unknownSortKey() {
        let a = makeRow(host: "alpha.com", path: "/test")
        let b = makeRow(host: "beta.com", path: "/test")
        let descriptors = [NSSortDescriptor(key: "nonexistent", ascending: true)]

        #expect(RequestListRow.compare(a, b, using: descriptors) == false)
        #expect(RequestListRow.compare(b, a, using: descriptors) == false)
    }

    @Test("Custom header column sort resolved from row headers")
    func customHeaderSort() {
        let a = makeRow(requestHeaders: [HTTPHeader(name: "X-Request-ID", value: "aaa")])
        let b = makeRow(requestHeaders: [HTTPHeader(name: "X-Request-ID", value: "zzz")])
        let descriptors = [NSSortDescriptor(key: "reqHeader.X-Request-ID", ascending: true)]

        #expect(RequestListRow.compare(a, b, using: descriptors) == true)
    }

    // MARK: - Header Value Resolution

    @Test("Resolve request header value")
    func resolveRequestHeader() {
        let row = makeRow(requestHeaders: [HTTPHeader(name: "Authorization", value: "Bearer token")])
        let value = RequestListRow.resolveHeaderValue(for: "reqHeader.Authorization", row: row)
        #expect(value == "Bearer token")
    }

    @Test("Resolve response header value")
    func resolveResponseHeader() {
        let row = makeRow(responseHeaders: [HTTPHeader(name: "Cache-Control", value: "no-cache")])
        let value = RequestListRow.resolveHeaderValue(for: "resHeader.Cache-Control", row: row)
        #expect(value == "no-cache")
    }

    @Test("Missing header returns empty string")
    func missingHeader() {
        let row = makeRow()
        let value = RequestListRow.resolveHeaderValue(for: "reqHeader.X-Nonexistent", row: row)
        #expect(value == "")
    }

    // MARK: - WebSocket Numeric Sort

    @Test("WebSocket frame count sorts numerically not lexicographically")
    func webSocketNumericSort() {
        let ws2 = makeWebSocketRow(frameCount: 2)
        let ws10 = makeWebSocketRow(frameCount: 10)
        let descriptors = [NSSortDescriptor(key: "queryName", ascending: true)]

        // Numeric: 2 < 10 (lexicographic would put "10" before "2")
        #expect(RequestListRow.compare(ws2, ws10, using: descriptors) == true)
        #expect(RequestListRow.compare(ws10, ws2, using: descriptors) == false)
    }

    // MARK: - Sequence Number Display

    @Test("sequenceNumber is correctly set from transaction")
    func sequenceNumberFromTransaction() {
        let transaction = TestFixtures.makeTransaction()
        transaction.sequenceNumber = 42
        let row = RequestListRow(from: transaction)
        #expect(row.sequenceNumber == 42)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeRow(
        host: String = "example.com",
        path: String = "/test",
        statusCode: Int? = 200,
        sequenceNumber: Int = 0,
        requestHeaders: [HTTPHeader] = [],
        responseHeaders: [HTTPHeader]? = nil
    )
        -> RequestListRow
    {
        let url = "https://\(host)\(path)"
        let transaction = TestFixtures.makeTransaction(
            url: url,
            statusCode: statusCode
        )
        transaction.sequenceNumber = sequenceNumber
        if !requestHeaders.isEmpty {
            transaction.request = HTTPRequestData(
                method: "GET",
                url: URL(string: url)!,
                httpVersion: "HTTP/1.1",
                headers: requestHeaders,
                body: nil,
                contentType: nil
            )
        }
        if let resHeaders = responseHeaders, let response = transaction.response {
            transaction.response = HTTPResponseData(
                statusCode: response.statusCode,
                statusMessage: response.statusMessage,
                headers: resHeaders,
                body: response.body,
                contentType: response.contentType
            )
        }
        return RequestListRow(from: transaction)
    }

    private func makeWebSocketRow(frameCount: Int) -> RequestListRow {
        let request = TestFixtures.makeRequest(url: "wss://ws.example.com/stream")
        let frames = (0 ..< frameCount).map { i in
            WebSocketFrameData(
                direction: i % 2 == 0 ? .sent : .received,
                opcode: .text,
                payload: Data("Frame \(i)".utf8)
            )
        }
        let connection = WebSocketConnection(upgradeRequest: request, frames: frames)
        let transaction = HTTPTransaction(
            request: request, state: .completed, webSocketConnection: connection
        )
        transaction.response = HTTPResponseData(
            statusCode: 101, statusMessage: "Switching Protocols",
            headers: [], body: nil, contentType: nil
        )
        return RequestListRow(from: transaction)
    }
}
