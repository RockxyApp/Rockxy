import Foundation
@testable import Rockxy
import Testing

// Regression tests for `RequestCopyFormatter` in the core utilities layer.

struct RequestCopyFormatterTests {
    // MARK: - URL

    @Test("url returns absolute URL string")
    func urlFormat() {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/users?page=1")
        #expect(RequestCopyFormatter.url(for: transaction) == "https://api.example.com/users?page=1")
    }

    // MARK: - cURL

    @Test("curl includes method, URL, and headers")
    func curlBasic() {
        let transaction = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/data")
        let result = RequestCopyFormatter.curl(for: transaction)
        #expect(result.contains("curl"))
        #expect(result.contains("'https://api.example.com/data'"))
        #expect(result.contains("-X POST"))
        #expect(result.contains("-H 'Content-Type: application/json'"))
    }

    @Test("curl escapes single quotes in header values")
    func curlEscapesSingleQuotes() {
        let headers = [HTTPHeader(name: "X-Custom", value: "it's a test")]
        let request = TestFixtures.makeRequest(headers: headers)
        let transaction = HTTPTransaction(request: request, state: .completed)
        let result = RequestCopyFormatter.curl(for: transaction)
        #expect(result.contains("-H 'X-Custom: it'\\''s a test'"))
    }

    @Test("curl includes body with -d flag")
    func curlWithBody() throws {
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://api.example.com/data")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data("{\"key\":\"value\"}".utf8)
        )
        let transaction = HTTPTransaction(request: request, state: .completed)
        let result = RequestCopyFormatter.curl(for: transaction)
        #expect(result.contains("-d '{\"key\":\"value\"}'"))
    }

    @Test("curl handles binary body with --data-binary flag")
    func curlBinaryBody() throws {
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://api.example.com/upload")),
            httpVersion: "HTTP/1.1",
            headers: [],
            body: Data([0x00, 0xFF, 0xFE, 0xFD])
        )
        let transaction = HTTPTransaction(request: request, state: .completed)
        let result = RequestCopyFormatter.curl(for: transaction)
        #expect(result.contains("--data-binary"))
        #expect(result.contains("binary data"))
    }

    @Test("curl omits body flag when no body")
    func curlNoBody() {
        let transaction = TestFixtures.makeTransaction(method: "GET")
        let result = RequestCopyFormatter.curl(for: transaction)
        #expect(!result.contains("-d"))
        #expect(!result.contains("--data-binary"))
    }

    // MARK: - Cell Value

    @Test("cellValue returns host+path for url column")
    func cellValueURL() {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/users/123")
        let result = RequestCopyFormatter.cellValue(for: transaction, column: "url")
        #expect(result == "api.example.com/users/123")
    }

    @Test("cellValue returns method for method column")
    func cellValueMethod() {
        let transaction = TestFixtures.makeTransaction(method: "DELETE")
        let result = RequestCopyFormatter.cellValue(for: transaction, column: "method")
        #expect(result == "DELETE")
    }

    @Test("cellValue returns status code for code column")
    func cellValueCode() {
        let transaction = TestFixtures.makeTransaction(statusCode: 404)
        let result = RequestCopyFormatter.cellValue(for: transaction, column: "code")
        #expect(result == "404")
    }

    @Test("cellValue returns empty for code column when no response")
    func cellValueCodeNoResponse() {
        let transaction = TestFixtures.makeTransaction(statusCode: nil)
        let result = RequestCopyFormatter.cellValue(for: transaction, column: "code")
        #expect(result == "")
    }

    @Test("cellValue returns client app for client column")
    func cellValueClient() {
        let transaction = TestFixtures.makeTransaction()
        transaction.clientApp = "Safari"
        let result = RequestCopyFormatter.cellValue(for: transaction, column: "client")
        #expect(result == "Safari")
    }

    @Test("cellValue returns empty client when nil")
    func cellValueClientNil() {
        let transaction = TestFixtures.makeTransaction()
        let result = RequestCopyFormatter.cellValue(for: transaction, column: "client")
        #expect(result == "")
    }

    @Test("cellValue returns full URL for unknown column")
    func cellValueUnknownColumn() {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/test")
        let result = RequestCopyFormatter.cellValue(for: transaction, column: "unknown")
        #expect(result == "https://api.example.com/test")
    }

    @Test("cellValue returns GraphQL operation name for queryName column")
    func cellValueGraphQLName() {
        let transaction = TestFixtures.makeGraphQLTransaction(operationName: "FetchUsers")
        let result = RequestCopyFormatter.cellValue(for: transaction, column: "queryName")
        #expect(result == "FetchUsers")
    }

    @Test("cellValue returns Web3 RPC method for queryName column")
    func cellValueWeb3RPCMethod() {
        let transaction = TestFixtures.makeWeb3RPCTransaction(method: "eth_getLogs")
        let result = RequestCopyFormatter.cellValue(for: transaction, column: "queryName")
        #expect(result == "eth_getLogs")
    }

    // MARK: - Headers

    @Test("requestHeaders formats all headers")
    func requestHeadersFormat() {
        let headers = [
            HTTPHeader(name: "Content-Type", value: "application/json"),
            HTTPHeader(name: "Authorization", value: "Bearer token123"),
        ]
        let request = TestFixtures.makeRequest(headers: headers)
        let transaction = HTTPTransaction(request: request, state: .completed)
        let result = RequestCopyFormatter.requestHeaders(for: transaction)
        #expect(result == "Content-Type: application/json\nAuthorization: Bearer token123")
    }

    @Test("requestHeaders returns empty string for no headers")
    func requestHeadersEmpty() {
        let request = TestFixtures.makeRequest(headers: [])
        let transaction = HTTPTransaction(request: request, state: .completed)
        let result = RequestCopyFormatter.requestHeaders(for: transaction)
        #expect(result == "")
    }

    @Test("responseHeaders returns nil when no response")
    func responseHeadersNoResponse() {
        let transaction = TestFixtures.makeTransaction(statusCode: nil)
        #expect(RequestCopyFormatter.responseHeaders(for: transaction) == nil)
    }

    @Test("responseHeaders formats response headers")
    func responseHeadersFormat() throws {
        let transaction = TestFixtures.makeTransaction()
        let result = try #require(RequestCopyFormatter.responseHeaders(for: transaction))
        #expect(result.contains("Content-Type: application/json"))
    }

    // MARK: - Body

    @Test("requestBody returns nil when no body")
    func requestBodyNil() {
        let transaction = TestFixtures.makeTransaction()
        #expect(RequestCopyFormatter.requestBody(for: transaction) == nil)
    }

    @Test("requestBody returns text for UTF-8 body")
    func requestBodyText() throws {
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://api.example.com/data")),
            httpVersion: "HTTP/1.1",
            headers: [],
            body: Data("{\"hello\":\"world\"}".utf8)
        )
        let transaction = HTTPTransaction(request: request, state: .completed)
        #expect(RequestCopyFormatter.requestBody(for: transaction) == "{\"hello\":\"world\"}")
    }

    @Test("requestBody returns binary placeholder for non-UTF-8")
    func requestBodyBinary() throws {
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://api.example.com/upload")),
            httpVersion: "HTTP/1.1",
            headers: [],
            body: Data([0x00, 0xFF, 0xFE, 0xFD])
        )
        let transaction = HTTPTransaction(request: request, state: .completed)
        let result = try #require(RequestCopyFormatter.requestBody(for: transaction))
        #expect(result.contains("binary data"))
    }

    @Test("responseBody returns nil when no response")
    func responseBodyNoResponse() {
        let transaction = TestFixtures.makeTransaction(statusCode: nil)
        #expect(RequestCopyFormatter.responseBody(for: transaction) == nil)
    }

    @Test("responseBody returns nil when response has no body")
    func responseBodyNilBody() {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(body: nil)
        #expect(RequestCopyFormatter.responseBody(for: transaction) == nil)
    }

    @Test("responseBody returns text for JSON response")
    func responseBodyJSON() {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(body: Data("{\"ok\":true}".utf8))
        let result = RequestCopyFormatter.responseBody(for: transaction)
        #expect(result == "{\"ok\":true}")
    }

    @Test("responseBody returns binary placeholder for non-UTF-8")
    func responseBodyBinary() throws {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(body: Data([0x00, 0xFF, 0xFE, 0xFD]))
        let result = try #require(RequestCopyFormatter.responseBody(for: transaction))
        #expect(result.contains("binary data"))
    }

    // MARK: - Cookies

    @Test("requestCookies returns empty for no cookies")
    func requestCookiesEmpty() {
        let transaction = TestFixtures.makeTransaction()
        #expect(RequestCopyFormatter.requestCookies(for: transaction) == "")
    }

    @Test("requestCookies formats cookie header value")
    func requestCookiesFormat() {
        let headers = [
            HTTPHeader(name: "Cookie", value: "session=abc123; theme=dark"),
            HTTPHeader(name: "Accept", value: "*/*"),
        ]
        let request = TestFixtures.makeRequest(url: "https://example.com/api", headers: headers)
        let transaction = HTTPTransaction(request: request, state: .completed)
        let result = RequestCopyFormatter.requestCookies(for: transaction)
        #expect(result.contains("session"))
    }

    @Test("responseCookies returns empty for no Set-Cookie headers")
    func responseCookiesEmpty() {
        let transaction = TestFixtures.makeTransaction()
        #expect(RequestCopyFormatter.responseCookies(for: transaction) == "")
    }

    @Test("responseCookies returns Set-Cookie header values")
    func responseCookiesFormat() {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            headers: [
                HTTPHeader(name: "Set-Cookie", value: "session=abc123; Path=/; HttpOnly"),
                HTTPHeader(name: "Set-Cookie", value: "theme=dark; Path=/"),
            ]
        )
        let result = RequestCopyFormatter.responseCookies(for: transaction)
        #expect(result.contains("session=abc123"))
        #expect(result.contains("theme=dark"))
    }

    @Test("responseCookies returns empty when no response")
    func responseCookiesNoResponse() {
        let transaction = TestFixtures.makeTransaction(statusCode: nil)
        #expect(RequestCopyFormatter.responseCookies(for: transaction) == "")
    }

    // MARK: - Raw Request

    @Test("rawRequest includes request line with method, path, and HTTP version")
    func rawRequestLine() {
        let transaction = TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/users")
        let result = RequestCopyFormatter.rawRequest(for: transaction)
        #expect(result.contains("GET /users HTTP/1.1"))
    }

    @Test("rawRequest includes Host header")
    func rawRequestHost() {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/users")
        let result = RequestCopyFormatter.rawRequest(for: transaction)
        #expect(result.contains("Host: api.example.com"))
    }

    @Test("rawRequest includes headers and body")
    func rawRequestFull() throws {
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://api.example.com/users")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data("{\"name\":\"test\"}".utf8)
        )
        let transaction = HTTPTransaction(request: request, state: .completed)
        let result = RequestCopyFormatter.rawRequest(for: transaction)
        #expect(result.contains("POST /users HTTP/1.1"))
        #expect(result.contains("Host: api.example.com"))
        #expect(result.contains("Content-Type: application/json"))
        #expect(result.contains("{\"name\":\"test\"}"))
    }

    @Test("rawRequest uses CRLF line endings")
    func rawRequestCRLF() {
        let transaction = TestFixtures.makeTransaction()
        let result = RequestCopyFormatter.rawRequest(for: transaction)
        #expect(result.contains("\r\n"))
    }

    // MARK: - Raw Response

    @Test("rawResponse returns nil when no response")
    func rawResponseNil() {
        let transaction = TestFixtures.makeTransaction(statusCode: nil)
        #expect(RequestCopyFormatter.rawResponse(for: transaction) == nil)
    }

    @Test("rawResponse includes status line")
    func rawResponseStatusLine() throws {
        let transaction = TestFixtures.makeTransaction(statusCode: 200)
        let result = try #require(RequestCopyFormatter.rawResponse(for: transaction))
        #expect(result.contains("HTTP/1.1 200 OK"))
    }

    @Test("rawResponse includes headers")
    func rawResponseHeaders() throws {
        let transaction = TestFixtures.makeTransaction(statusCode: 200)
        let result = try #require(RequestCopyFormatter.rawResponse(for: transaction))
        #expect(result.contains("Content-Type: application/json"))
    }

    @Test("rawResponse includes body when present")
    func rawResponseWithBody() throws {
        let transaction = TestFixtures.makeTransaction(statusCode: 200)
        transaction.response = TestFixtures.makeResponse(
            statusCode: 200,
            body: Data("{\"ok\":true}".utf8)
        )
        let result = try #require(RequestCopyFormatter.rawResponse(for: transaction))
        #expect(result.contains("{\"ok\":true}"))
    }

    @Test("rawResponse uses CRLF line endings")
    func rawResponseCRLF() throws {
        let transaction = TestFixtures.makeTransaction(statusCode: 200)
        let result = try #require(RequestCopyFormatter.rawResponse(for: transaction))
        #expect(result.contains("\r\n"))
    }

    // MARK: - JSON

    @Test("json returns formatted JSON with request fields")
    func jsonRequestFields() throws {
        let request = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "https://api.example.com/test")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Accept", value: "*/*")],
            body: nil
        )
        let transaction = HTTPTransaction(request: request, state: .completed)
        transaction.response = TestFixtures.makeResponse(statusCode: 200)
        let result = RequestCopyFormatter.json(for: transaction)
        #expect(result != nil)
        if let result {
            #expect(result.contains("GET"))
            #expect(result.contains("api.example.com"))
        }
    }

    @Test("json includes response when present")
    func jsonWithResponse() throws {
        let transaction = TestFixtures.makeTransaction(method: "GET", statusCode: 200)
        let result = try #require(RequestCopyFormatter.json(for: transaction))
        #expect(result.contains("statusCode"))
        #expect(result.contains("200"))
        #expect(result.contains("response"))
    }

    @Test("json omits response key when no response")
    func jsonNoResponse() throws {
        let transaction = TestFixtures.makeTransaction(statusCode: nil)
        let result = try #require(RequestCopyFormatter.json(for: transaction))
        #expect(!result.contains("\"response\""))
    }

    @Test("json includes timestamp in ISO 8601 format")
    func jsonTimestamp() throws {
        let transaction = TestFixtures.makeTransaction()
        let result = try #require(RequestCopyFormatter.json(for: transaction))
        #expect(result.contains("\"timestamp\""))
    }

    @Test("json includes request headers")
    func jsonHeaders() throws {
        let transaction = TestFixtures.makeTransaction()
        let result = try #require(RequestCopyFormatter.json(for: transaction))
        #expect(result.contains("\"headers\""))
        #expect(result.contains("Content-Type"))
    }

    // MARK: - HAR Entry

    @Test("harEntry returns valid HAR JSON with log and entries")
    func harEntryFormat() throws {
        let transaction = TestFixtures.makeTransaction()
        let result = try #require(RequestCopyFormatter.harEntry(for: transaction))
        #expect(result.contains("\"log\""))
        #expect(result.contains("\"entries\""))
    }

    @Test("harEntry contains request host")
    func harEntryContainsHost() throws {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/test")
        let result = try #require(RequestCopyFormatter.harEntry(for: transaction))
        #expect(result.contains("api.example.com"))
    }
}
