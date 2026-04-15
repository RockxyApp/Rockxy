import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

// MARK: - BuildForwardHeadTests

// Tests for `ProxyHandlerShared.buildForwardHead(from:originalHead:)` — the
// helper that rebuilds the outbound HTTPRequestHead from a (possibly script-
// mutated) HTTPRequestData.

struct BuildForwardHeadTests {
    // MARK: Internal

    @Test("Mutated method appears on forwarded head")
    func mutatedMethod() {
        let req = makeRequest(method: "POST")
        let originalHead = makeOriginalHead(method: .GET, uri: "/api")
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.method == .POST)
    }

    @Test("Mutated path + query appear on forwarded URI in origin form")
    func mutatedPathQuery() {
        let req = makeRequest(url: "https://example.com/v2/users?id=42")
        let originalHead = makeOriginalHead(uri: "/v1/users")
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.uri == "/v2/users?id=42")
    }

    @Test("Path-only mutation produces uri without query suffix")
    func pathOnly() {
        let req = makeRequest(url: "https://example.com/v2/users")
        let originalHead = makeOriginalHead(uri: "/v1/users")
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.uri == "/v2/users")
    }

    @Test("Mutated headers appear on forwarded headers")
    func mutatedHeaders() {
        let req = makeRequest(
            headers: [HTTPHeader(name: "X-Test", value: "ok"), HTTPHeader(name: "Accept", value: "application/json")]
        )
        let originalHead = makeOriginalHead(headers: [])
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.headers.containsHeader(name: "X-Test", value: "ok"))
        #expect(forward.headers.containsHeader(name: "Accept", value: "application/json"))
    }

    @Test("Content-Length recomputes when original head carried Content-Length")
    func contentLengthRecomputes() {
        let body = Data("hello world".utf8)
        let req = makeRequest(
            method: "POST",
            headers: [HTTPHeader(name: "Content-Length", value: "5")],
            body: body
        )
        let originalHead = makeOriginalHead(method: .POST, headers: [("Content-Length", "5")])
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.headers.first(name: "Content-Length") == "\(body.count)")
    }

    @Test("Chunked uploads do NOT have Content-Length added")
    func chunkedUploadsLeaveContentLengthAlone() {
        let req = makeRequest(
            method: "POST",
            headers: [HTTPHeader(name: "Transfer-Encoding", value: "chunked")],
            body: Data("ignored".utf8)
        )
        let originalHead = makeOriginalHead(method: .POST, headers: [("Transfer-Encoding", "chunked")])
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(!forward.headers.containsHeader(named: "Content-Length"))
    }

    @Test("Empty path defaults to /")
    func emptyPathDefaultsToSlash() {
        let req = makeRequest(url: "https://example.com")
        let originalHead = makeOriginalHead(uri: "/")
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.uri == "/")
    }

    @Test("Invalid method falls back to original head's method")
    func invalidMethodFallback() {
        let req = makeRequest(method: "BOGUS")
        let originalHead = makeOriginalHead(method: .DELETE, uri: "/api")
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.method == .DELETE)
    }

    @Test("HTTP version is preserved from original head")
    func versionPreserved() {
        let req = makeRequest()
        var originalHead = makeOriginalHead()
        originalHead = HTTPRequestHead(version: .http1_0, method: originalHead.method, uri: originalHead.uri)
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.version == .http1_0)
    }

    @Test("Host header is NOT rewritten by buildForwardHead")
    func hostHeaderNotRewritten() {
        let req = makeRequest(
            url: "https://example.com/path",
            headers: [HTTPHeader(name: "Host", value: "example.com")]
        )
        let originalHead = makeOriginalHead(headers: [("Host", "example.com")])
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.headers.first(name: "Host") == "example.com")
    }

    @Test("Mutated response head recomputes Content-Length from body bytes")
    func relayResponseHeadRecomputesContentLength() {
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Content-Length", value: "3")
            ],
            body: Data("{\"hello\":true}".utf8)
        )
        let originalHead = HTTPResponseHead(version: .http1_1, status: .ok)

        let head = ProxyHandlerShared.buildRelayResponseHead(from: response, originalHead: originalHead)

        #expect(head.headers.first(name: "Content-Length") == "\(response.body?.count ?? 0)")
        #expect(head.headers.containsHeader(name: "Content-Type", value: "application/json"))
    }

    @Test("Mutated response head drops stale Transfer-Encoding")
    func relayResponseHeadDropsTransferEncoding() {
        let response = HTTPResponseData(
            statusCode: 201,
            statusMessage: "Created",
            headers: [
                HTTPHeader(name: "Transfer-Encoding", value: "chunked"),
                HTTPHeader(name: "Content-Type", value: "text/plain")
            ],
            body: Data("payload".utf8)
        )
        let originalHead = HTTPResponseHead(version: .http1_0, status: .created)

        let head = ProxyHandlerShared.buildRelayResponseHead(from: response, originalHead: originalHead)

        #expect(head.version == .http1_0)
        #expect(head.status.code == 201)
        #expect(!head.headers.containsHeader(named: "Transfer-Encoding"))
        #expect(head.headers.first(name: "Content-Length") == "7")
    }

    // MARK: Private

    private func makeRequest(
        method: String = "GET",
        url: String = "https://example.com/api",
        headers: [HTTPHeader] = [],
        body: Data? = nil
    )
        -> HTTPRequestData
    {
        HTTPRequestData(
            method: method,
            // swiftlint:disable:next force_unwrapping
            url: URL(string: url)!,
            httpVersion: "HTTP/1.1",
            headers: headers,
            body: body
        )
    }

    private func makeOriginalHead(
        method: HTTPMethod = .GET,
        uri: String = "/api",
        headers: [(String, String)] = []
    )
        -> HTTPRequestHead
    {
        var head = HTTPRequestHead(version: .http1_1, method: method, uri: uri)
        for (name, value) in headers {
            head.headers.add(name: name, value: value)
        }
        return head
    }
}

private extension HTTPHeaders {
    func containsHeader(named name: String) -> Bool {
        contains(name: name)
    }

    func containsHeader(name: String, value: String) -> Bool {
        self[name].contains(value)
    }
}
