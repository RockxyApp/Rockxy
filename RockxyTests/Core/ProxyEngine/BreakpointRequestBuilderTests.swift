import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

/// BreakpointRequestBuilder is the extracted testable seam for breakpoint relay behavior.
/// Direct NIO channel handler testing requires a full pipeline setup (EventLoopGroup, Bootstrap,
/// Channel) which is impractical for unit tests. The builder tests prove the request reconstruction
/// logic that both HTTPProxyHandler.executeBreakpointDecision and
/// HTTPSProxyRelayHandler.executeBreakpointDecision delegate to. Regressions in body forwarding,
/// port preservation, scheme normalization, Content-Length reconciliation, and HTTPS host pinning
/// would be caught at this seam.
struct BreakpointRequestBuilderTests {
    @Test("Origin-form URL preserves original host")
    func originFormPreservesHost() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/api/users")
        let originalData = TestFixtures.makeRequest(url: "http://api.example.com/api/users")

        let modified = BreakpointRequestData(
            method: "GET",
            url: "/api/users?page=2",
            headers: [],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.requestData.host == "api.example.com")
        #expect(result.requestData.url.absoluteString.contains("api.example.com"))
        #expect(result.head.uri == "/api/users?page=2")
    }

    @Test("Edited body is forwarded")
    func editedBodyIncluded() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/data")
        let originalData = TestFixtures.makeRequest(method: "POST", url: "http://api.example.com/data")

        let modified = BreakpointRequestData(
            method: "POST",
            url: "http://api.example.com/data",
            headers: [EditableHeader(name: "Content-Type", value: "application/json")],
            body: "{\"edited\":true}",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        let bodyString = result.requestData.body.flatMap { String(data: $0, encoding: .utf8) }
        #expect(bodyString == "{\"edited\":true}")
    }

    @Test("HTTPS forces original host in headers and URL")
    func httpsForceHost() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/path")
        let originalData = TestFixtures.makeRequest(url: "https://secure.example.com/path")

        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://evil.com/path",
            headers: [EditableHeader(name: "Host", value: "evil.com")],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData,
            isHTTPS: true,
            originalHost: "secure.example.com"
        )

        #expect(result.requestData.headers.first { $0.name == "Host" }?.value == "secure.example.com")
        #expect(result.head.headers["Host"].first == "secure.example.com")
        #expect(result.requestData.url.host() == "secure.example.com")
    }

    @Test("Header edits are preserved")
    func headerEditsPreserved() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/")
        let originalData = TestFixtures.makeRequest()

        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://api.example.com/test",
            headers: [
                EditableHeader(name: "Authorization", value: "Bearer new-token"),
                EditableHeader(name: "X-Custom", value: "test"),
            ],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.requestData.headers.contains { $0.name == "Authorization" && $0.value == "Bearer new-token" })
        #expect(result.requestData.headers.contains { $0.name == "X-Custom" && $0.value == "test" })
    }

    @Test("Full URL edit redirects for HTTP")
    func fullURLEditHTTP() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "http://old.com/path")
        let originalData = TestFixtures.makeRequest(url: "http://old.com/path")

        let modified = BreakpointRequestData(
            method: "GET",
            url: "http://new.com/other?q=1",
            headers: [],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.requestData.host == "new.com")
        #expect(result.head.uri == "/other?q=1")
    }

    @Test("Empty body produces nil data")
    func emptyBodyProducesNil() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/")
        let originalData = TestFixtures.makeRequest()

        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://api.example.com/test",
            headers: [],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.requestData.body == nil)
    }

    @Test("Method change is reflected in head and request data")
    func methodChangeReflected() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/resource")
        let originalData = TestFixtures.makeRequest(url: "http://api.example.com/resource")

        let modified = BreakpointRequestData(
            method: "DELETE",
            url: "http://api.example.com/resource",
            headers: [],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.head.method == .DELETE)
        #expect(result.requestData.method == "DELETE")
    }

    @Test("Non-default port preserved in rebuilt request")
    func nonDefaultPortPreserved() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "http://example.com:8080/api")
        let originalData = TestFixtures.makeRequest(url: "http://example.com:8080/api")

        let modified = BreakpointRequestData(
            method: "GET",
            url: "http://example.com:8080/api/v2",
            headers: [],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.requestData.url.port == 8_080)
    }

    @Test("Content-Length recomputed after body edit")
    func contentLengthRecomputed() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/data")
        let originalData = TestFixtures.makeRequest(method: "POST", url: "http://api.example.com/data")

        let modified = BreakpointRequestData(
            method: "POST",
            url: "http://api.example.com/data",
            headers: [
                EditableHeader(name: "Content-Type", value: "application/json"),
                EditableHeader(name: "Content-Length", value: "10"),
            ],
            body: "{\"new\":\"longer body content\"}",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        let bodySize = result.requestData.body?.count ?? 0
        let contentLength = result.requestData.headers.first { $0.name == "Content-Length" }?.value
        #expect(contentLength == "\(bodySize)")
    }

    @Test("Content-Length removed when body cleared")
    func contentLengthRemovedWhenBodyCleared() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/data")
        let originalData = TestFixtures.makeRequest(method: "POST", url: "http://api.example.com/data")

        let modified = BreakpointRequestData(
            method: "POST",
            url: "http://api.example.com/data",
            headers: [
                EditableHeader(name: "Content-Length", value: "42"),
            ],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        let hasContentLength = result.requestData.headers.contains { $0.name == "Content-Length" }
        #expect(!hasContentLength)
    }

    @Test("Transfer-Encoding removed after body edit")
    func transferEncodingRemovedAfterBodyEdit() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/data")
        let originalData = TestFixtures.makeRequest(method: "POST", url: "http://api.example.com/data")

        let modified = BreakpointRequestData(
            method: "POST",
            url: "http://api.example.com/data",
            headers: [
                EditableHeader(name: "Transfer-Encoding", value: "chunked"),
            ],
            body: "fixed body",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        let hasTransferEncoding = result.requestData.headers.contains {
            $0.name.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame
        }
        #expect(!hasTransferEncoding)

        let contentLength = result.requestData.headers.first { $0.name == "Content-Length" }?.value
        #expect(contentLength == "\(result.requestData.body?.count ?? 0)")
    }

    @Test("HTTP scheme change to HTTPS is reverted")
    func httpSchemeChangeReverted() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "http://example.com/api")
        let originalData = TestFixtures.makeRequest(url: "http://example.com/api")

        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://example.com/api",
            headers: [],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData,
            isHTTPS: false
        )

        #expect(result.requestData.url.scheme == "http")
        #expect(result.requestData.url.host() == "example.com")
    }

    @Test("HTTPS origin-form edit preserves tunnel host")
    func httpsOriginFormPreservesTunnelHost() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/api/v1")
        let originalData = TestFixtures.makeRequest(url: "https://secure.example.com/api/v1")

        let modified = BreakpointRequestData(
            method: "GET",
            url: "/api/v2?limit=10",
            headers: [EditableHeader(name: "Host", value: "secure.example.com")],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData,
            isHTTPS: true,
            originalHost: "secure.example.com"
        )

        #expect(result.requestData.host == "secure.example.com")
        #expect(result.head.uri == "/api/v2?limit=10")
        #expect(result.requestData.url.path() == "/api/v2")
        #expect(result.requestData.url.query() == "limit=10")
    }
}
