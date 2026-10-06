import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

/// BreakpointRequestBuilder is the extracted testable seam for breakpoint relay behavior.
/// Direct NIO channel handler testing requires a full pipeline setup (EventLoopGroup, Bootstrap,
/// Channel) which is impractical for unit tests. The builder tests prove the request reconstruction
/// logic that both HTTPProxyHandler.executeBreakpointDecision and
/// HTTPSProxyRelayHandler.executeBreakpointDecision delegate to. Regressions in body forwarding,
/// port preservation, scheme normalization, Content-Length reconciliation, and HTTPS authority redirects
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

    @Test("HTTPS edit to another host is sent to that server")
    func httpsHostEditRedirects() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/path")
        let originalData = TestFixtures.makeRequest(url: "https://secure.example.com/path")

        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://staging.example.com/path?debug=1",
            headers: [],
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

        #expect(result.upstreamRedirect == .init(scheme: "https", host: "staging.example.com", port: nil))
        #expect(result.requestData.url.absoluteString == "https://staging.example.com/path?debug=1")
        #expect(result.head.headers["Host"].first == "staging.example.com")
        #expect(result.head.uri == "/path?debug=1")
    }

    @Test("HTTPS edit to another scheme or port is sent to that server")
    func httpsSchemeAndPortEditsRedirect() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/path")
        let originalData = TestFixtures.makeRequest(url: "https://secure.example.com/path")

        func build(_ url: String) -> BreakpointRequestBuilder.Result {
            BreakpointRequestBuilder.build(
                from: BreakpointRequestData(method: "GET", url: url, headers: [], body: "", statusCode: 200),
                originalHead: originalHead,
                originalRequestData: originalData,
                isHTTPS: true,
                originalHost: "secure.example.com"
            )
        }

        let cleartext = build("http://localhost:3000/path")
        #expect(cleartext.upstreamRedirect == .init(scheme: "http", host: "localhost", port: 3_000))
        #expect(cleartext.head.headers["Host"].first == "localhost:3000")

        let otherPort = build("https://secure.example.com:8443/path")
        #expect(otherPort.upstreamRedirect == .init(scheme: "https", host: "secure.example.com", port: 8_443))

        let samePortSpelledOut = build("https://SECURE.example.com:443/v2")
        #expect(samePortSpelledOut.upstreamRedirect == nil)
        #expect(samePortSpelledOut.head.headers["Host"].first == "secure.example.com")
    }

    @Test("HTTPS edit on the same server keeps the tunnel's non-default port")
    func httpsFixedAuthorityPreservesPort() throws {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/path")
        let originalData = TestFixtures.makeRequest(url: "https://secure.example.com:8443/path")
        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://secure.example.com:8443/other",
            headers: [EditableHeader(name: "Host", value: "other.example")],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData,
            isHTTPS: true,
            originalHost: "secure.example.com",
            originalPort: 8_443
        )

        #expect(result.upstreamRedirect == nil)
        #expect(result.requestData.url.absoluteString == "https://secure.example.com:8443/other")
        #expect(result.head.headers["Host"].first == "secure.example.com:8443")
    }

    @Test("HTTPS fixed IPv6 authority is bracketed and preserves its port")
    func httpsIPv6AuthorityIsBracketed() throws {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/path")
        let originalData = TestFixtures.makeRequest(url: "https://[2001:db8::1]:8443/path")
        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://[2001:db8::1]:8443/path",
            headers: [],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData,
            isHTTPS: true,
            originalHost: "2001:db8::1",
            originalPort: 8_443
        )

        #expect(result.upstreamRedirect == nil)
        #expect(result.requestData.url.absoluteString == "https://[2001:db8::1]:8443/path")
        #expect(result.head.headers["Host"].first == "[2001:db8::1]:8443")
    }

    @Test("Edited request content type follows edited headers and body")
    func editedContentTypeIsRecomputed() {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/submit")
        let originalData = TestFixtures.makeRequest(method: "POST", url: "http://api.example.com/submit")
        let modified = BreakpointRequestData(
            method: "POST",
            url: "http://api.example.com/submit",
            headers: [EditableHeader(name: "Content-Type", value: "application/json")],
            body: #"{"edited":true}"#,
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.requestData.contentType == .json)
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

    @Test("Untouched original Host follows an HTTP URL redirect to the new authority")
    func hostFollowsHTTPRedirect() throws {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "http://old.com/path")
        let originalData = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "http://old.com/path")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Host", value: "old.com")],
            body: nil
        )

        let modified = BreakpointRequestData(
            method: "GET",
            url: "http://new.com/other",
            headers: [EditableHeader(name: "Host", value: "old.com")],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.requestData.headers.first { $0.name.caseInsensitiveCompare("Host") == .orderedSame }?
            .value == "new.com")
        #expect(result.head.headers["Host"].first == "new.com")
        #expect(result.requestData.host == "new.com")
    }

    @Test("Host follows an HTTP redirect carrying a non-default explicit port")
    func hostFollowsHTTPRedirectWithExplicitPort() throws {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "http://old.com/path")
        let originalData = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "http://old.com/path")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Host", value: "old.com")],
            body: nil
        )

        let modified = BreakpointRequestData(
            method: "GET",
            url: "http://new.com:8443/other",
            headers: [EditableHeader(name: "Host", value: "old.com")],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.requestData.headers.first { $0.name.caseInsensitiveCompare("Host") == .orderedSame }?
            .value == "new.com:8443")
        #expect(result.head.headers["Host"].first == "new.com:8443")
        #expect(result.requestData.url.port == 8_443)
    }

    @Test("HTTP request editing emits one canonical Host and Content-Length")
    func singletonRoutingAndFramingHeadersAreCanonicalized() throws {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .POST, uri: "http://old.com/path")
        let originalData = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "http://old.com/path")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Host", value: "old.com")],
            body: Data("old".utf8)
        )
        let modified = BreakpointRequestData(
            method: "POST",
            url: "http://new.com/upload",
            headers: [
                EditableHeader(name: "Host", value: "old.com"),
                EditableHeader(name: "host", value: "conflicting.example"),
                EditableHeader(name: "Content-Length", value: "1"),
                EditableHeader(name: "content-length", value: "999"),
                EditableHeader(name: "", value: "ignored"),
            ],
            body: "updated",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        let hosts = result.requestData.headers.filter {
            $0.name.caseInsensitiveCompare("Host") == .orderedSame
        }
        let lengths = result.requestData.headers.filter {
            $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame
        }
        #expect(hosts.map(\.value) == ["new.com"])
        #expect(lengths.map(\.value) == ["7"])
        #expect(!result.requestData.headers.contains { $0.name.isEmpty })
    }

    @Test("Percent-encoded path delimiters survive request rebuilding")
    func percentEncodedPathSurvives() throws {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "http://example.com/original")
        let originalData = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "http://example.com/original")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Host", value: "example.com")],
            body: nil
        )
        let modified = BreakpointRequestData(
            method: "GET",
            url: "http://example.com/files/a%2Fb?q=hello%20world&literal=%2B",
            headers: [EditableHeader(name: "Host", value: "example.com")],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.head.uri == "/files/a%2Fb?q=hello%20world&literal=%2B")
    }

    @Test("IPv6 HTTP authority is bracketed in Host")
    func ipv6AuthorityIsBracketed() throws {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "http://old.com/path")
        let originalData = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "http://old.com/path")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Host", value: "old.com")],
            body: nil
        )
        let modified = BreakpointRequestData(
            method: "GET",
            url: "http://[::1]:18080/path",
            headers: [EditableHeader(name: "Host", value: "old.com")],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.head.headers["Host"].first == "[::1]:18080")
    }

    @Test("Explicit custom Host override is preserved across an HTTP redirect")
    func explicitCustomHostPreserved() throws {
        let originalHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "http://old.com/path")
        let originalData = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "http://old.com/path")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Host", value: "old.com")],
            body: nil
        )

        let modified = BreakpointRequestData(
            method: "GET",
            url: "http://new.com/other",
            headers: [EditableHeader(name: "Host", value: "virtual.internal")],
            body: "",
            statusCode: 200
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.requestData.headers.first { $0.name.caseInsensitiveCompare("Host") == .orderedSame }?
            .value == "virtual.internal")
        #expect(result.head.headers["Host"].first == "virtual.internal")
        #expect(result.requestData.host == "new.com")
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

    @Test("Non-editable request body is preserved while headers can change")
    func nonEditableBodyPreserved() throws {
        let binary = Data([0x1F, 0x8B, 0x08, 0x00])
        let originalHead = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/upload")
        let originalData = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "http://api.example.com/upload")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Encoding", value: "gzip")],
            body: binary
        )
        let modified = BreakpointRequestData(
            method: "POST",
            url: "http://api.example.com/upload",
            headers: [
                EditableHeader(name: "Content-Encoding", value: "gzip"),
                EditableHeader(name: "X-Debug", value: "true"),
            ],
            body: "",
            statusCode: 200,
            isBodyEditable: false
        )

        let result = BreakpointRequestBuilder.build(
            from: modified,
            originalHead: originalHead,
            originalRequestData: originalData
        )

        #expect(result.requestData.body == binary)
        #expect(result.requestData.headers.contains { $0.name == "X-Debug" && $0.value == "true" })
        #expect(result.requestData.headers.first { $0.name == "Content-Length" }?.value == "4")
    }

    @Test("HTTP scheme change to HTTPS is honored")
    func httpSchemeChangeHonored() {
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

        #expect(result.requestData.url.scheme == "https")
        #expect(result.requestData.url.host() == "example.com")
        #expect(result.upstreamRedirect == nil)
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
