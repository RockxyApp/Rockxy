import Foundation
@testable import Rockxy
import Testing

@MainActor
struct ComposeRawRequestParserTests {
    @Test("A path request line joins the Host header and keeps headers and body")
    func parsesPathTarget() throws {
        let raw = "POST /v1/items?page=2 HTTP/1.1\r\nHost: api.example.com:8443\r\nContent-Type: application/json\r\nX-A:  b \r\n\r\n{\"a\":1}\r\nsecond"
        let parsed = try ComposeRawRequestParser.parse(raw, defaultScheme: "https")
        #expect(parsed.method == "POST")
        #expect(parsed.url == "https://api.example.com:8443/v1/items?page=2")
        #expect(parsed.headers.map(\.name) == ["Content-Type", "X-A"])
        #expect(parsed.headers.last?.value == "b")
        #expect(parsed.body == "{\"a\":1}\nsecond")
    }

    @Test("Absolute targets win over Host, and mistakes are reported")
    func absoluteAndErrors() throws {
        let absolute = try ComposeRawRequestParser.parse("get http://other.test/x HTTP/1.1\nHost: ignored\n", defaultScheme: "https")
        #expect(absolute.method == "GET")
        #expect(absolute.url == "http://other.test/x")

        #expect(throws: ComposeRawRequestError.missingHost) {
            try ComposeRawRequestParser.parse("GET /x HTTP/1.1\n\n", defaultScheme: "https")
        }
        #expect(throws: ComposeRawRequestError.missingRequestLine) {
            try ComposeRawRequestParser.parse("\n\n", defaultScheme: "https")
        }
        #expect(throws: ComposeRawRequestError.malformedHeader("Broken")) {
            try ComposeRawRequestParser.parse("GET /x HTTP/1.1\nHost: a.test\nBroken\n\n", defaultScheme: "https")
        }
    }

    @Test("Applying the raw text round-trips Compose's own raw view, including the port")
    func roundTripsThroughViewModel() throws {
        let model = ComposeViewModel()
        model.method = "PUT"
        model.url = "http://localhost:3000/api/users/1?x=1"
        model.headers = [EditableReplayHeader(name: "Accept", value: "*/*")]
        model.body = "hello"
        let raw = model.rawRequestText
        #expect(raw.contains("Host: localhost:3000"))

        try model.applyRawRequest(raw.replacingOccurrences(of: "PUT", with: "PATCH"))
        #expect(model.method == "PATCH")
        #expect(model.url == "http://localhost:3000/api/users/1?x=1")
        #expect(model.headers.map(\.name) == ["Accept"])
        #expect(model.body == "hello")
        #expect(model.queryItems.map(\.name) == ["x"])
    }
}
