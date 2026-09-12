import Foundation
@testable import Rockxy
import Testing

// Regression tests for `RequestReplay` in the core traffic capture layer.

struct RequestReplayTests {
    @Test("proxyBypassSession disables HTTP proxy")
    func httpProxyDisabled() {
        let config = RequestReplay.proxyBypassSession.configuration
        let dict = config.connectionProxyDictionary ?? [:]
        if let httpEnable = dict[kCFNetworkProxiesHTTPEnable as String] as? Bool {
            #expect(httpEnable == false)
        } else if let httpEnable = dict[kCFNetworkProxiesHTTPEnable as String] as? Int {
            #expect(httpEnable == 0)
        }
    }

    @Test("proxyBypassSession disables HTTPS proxy")
    func httpsProxyDisabled() {
        let config = RequestReplay.proxyBypassSession.configuration
        let dict = config.connectionProxyDictionary ?? [:]
        if let httpsEnable = dict[kCFNetworkProxiesHTTPSEnable as String] as? Bool {
            #expect(httpsEnable == false)
        } else if let httpsEnable = dict[kCFNetworkProxiesHTTPSEnable as String] as? Int {
            #expect(httpsEnable == 0)
        }
    }

    @Test("proxyBypassSession is not URLSession.shared")
    func notSharedSession() {
        #expect(RequestReplay.proxyBypassSession !== URLSession.shared)
    }

    @Test("replays do not persist or synthesize cookies across sends")
    func cookiesDisabled() {
        let config = RequestReplay.proxyBypassSession.configuration
        #expect(config.httpShouldSetCookies == false)
        #expect(config.httpCookieAcceptPolicy == .never)
        #expect(config.httpCookieStorage == nil)
    }

    @Test("request builder retains repeated captured header values")
    func repeatedHeadersRetained() throws {
        let request = HTTPRequestData(
            method: "GET",
            url: try #require(URL(string: "https://api.example.com/items")),
            httpVersion: "HTTP/1.1",
            headers: [
                HTTPHeader(name: "X-Trace", value: "one"),
                HTTPHeader(name: "X-Trace", value: "two"),
            ]
        )

        let built = RequestReplay.makeURLRequest(from: request)
        let value = try #require(built.value(forHTTPHeaderField: "X-Trace"))
        #expect(value.contains("one"))
        #expect(value.contains("two"))
    }

    @Test("fast replay rejects CONNECT tunnels and WebSocket sessions")
    func unsupportedTransportsRejected() {
        let http = TestFixtures.makeTransaction(method: "GET")
        let connect = TestFixtures.makeTransaction(method: "CONNECT")
        let webSocket = TestFixtures.makeWebSocketTransaction()

        #expect(MainContentCoordinator.canReplay(http))
        #expect(!MainContentCoordinator.canReplay(connect))
        #expect(!MainContentCoordinator.canReplay(webSocket))
    }
}
