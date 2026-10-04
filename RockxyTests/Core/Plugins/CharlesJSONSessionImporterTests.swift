import Foundation
@testable import Rockxy
import Testing

struct CharlesJSONSessionImporterTests {
    private static let session = #"""
    [
      {
        "status": "COMPLETE", "method": "POST", "protocolVersion": "HTTP/1.1", "scheme": "https",
        "host": "api.example.com", "actualPort": 8443, "path": "/v1/items", "query": "page=2",
        "tunnel": false, "remoteAddress": "api.example.com/93.184.216.34",
        "times": {"start": "2026-09-01T10:00:00.250+07:00"},
        "durations": {"total": 120, "dns": 5, "connect": 10, "ssl": 20, "latency": 60, "response": 25},
        "ssl": {"protocol": "TLSv1.3"}, "alpn": {"protocol": "h2"},
        "request": {
          "header": {"firstLine": "POST /v1/items?page=2 HTTP/1.1",
                     "headers": [{"name": "Content-Type", "value": "application/json"}]},
          "body": {"text": "{\"a\":1}"}
        },
        "response": {
          "status": 404,
          "header": {"firstLine": "HTTP/1.1 404 Not Here", "headers": [{"name": "X-Id", "value": "7"}]},
          "body": {"encoded": "AAEC"}
        }
      },
      {
        "status": "COMPLETE", "method": "CONNECT", "scheme": "https", "host": "secure.example.com",
        "actualPort": 443, "tunnel": true, "request": {}, "response": {"status": 200}
      }
    ]
    """#

    @Test("A Charles entry names its client from the User-Agent")
    func namesClientFromUserAgent() throws {
        let session = Self.session.replacingOccurrences(
            of: #"{"name": "Content-Type", "value": "application/json"}"#,
            with: #"{"name": "Content-Type", "value": "application/json"}, {"name": "User-Agent", "value": "MyApp/3.2 CFNetwork/1.0"}"#
        )
        let transactions = try HARImporter().importData(Data(session.utf8))

        #expect(transactions.first?.clientApp == "MyApp")
    }

    @Test("A Charles JSON session imports with URL, headers, bodies, timing, and TLS details")
    func importsEntries() throws {
        let transactions = try HARImporter().importData(Data(Self.session.utf8))
        #expect(transactions.count == 2)

        let post = try #require(transactions.first)
        #expect(post.request.method == "POST")
        #expect(post.request.url.absoluteString == "https://api.example.com:8443/v1/items?page=2")
        #expect(post.request.headers.first?.value == "application/json")
        #expect(post.request.body == Data(#"{"a":1}"#.utf8))
        #expect(post.response?.statusCode == 404)
        #expect(post.response?.statusMessage == "Not Here")
        #expect(post.response?.body == Data([0, 1, 2]))
        #expect(post.timingInfo?.tlsHandshake == 0.02)
        #expect(post.measuredDuration == 0.12)
        #expect(post.connectionLog?.remoteAddress == "93.184.216.34")
        #expect(post.connectionLog?.tls?.version == "TLSv1.3")
        #expect(post.connectionLog?.tls?.negotiatedProtocol == "h2")
        #expect(post.timestamp == ISO8601DateFormatter().date(from: "2026-09-01T03:00:00Z")?.addingTimeInterval(0.25))

        let tunnel = transactions[1]
        #expect(tunnel.request.method == "CONNECT")
        #expect(tunnel.request.url.absoluteString == "https://secure.example.com:443")
        #expect(tunnel.sslCapture == .tunneled)
    }

    @Test("HAR files still import, and .chlsj files are opened as capture documents")
    func harUnaffected() throws {
        let har = #"{"log":{"version":"1.2","entries":[]}}"#
        #expect(try HARImporter().importData(Data(har.utf8)).isEmpty)
        #expect(ExternalCaptureDocumentKind(url: URL(fileURLWithPath: "/tmp/a.chlsj")) == .har)
        #expect(MainContentCoordinator.isCharlesJSONSession(Data(Self.session.utf8)))
        #expect(!MainContentCoordinator.isCharlesJSONSession(Data(har.utf8)))
        #expect(throws: HARImportError.self) { try HARImporter().importData(Data("[1,2]".utf8)) }
    }
}
