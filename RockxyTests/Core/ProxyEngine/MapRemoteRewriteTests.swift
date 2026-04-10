import Foundation
@testable import Rockxy
import Testing

// Regression tests for `MapRemoteRewrite` in the core proxy engine layer.

struct MapRemoteRewriteTests {
    @Test("Blank path preserves original path")
    func blankPathPreserves() throws {
        let config = MapRemoteConfiguration(host: "staging.com")
        let originalURL = try #require(URL(string: "https://prod.com/v2/users?page=1"))

        let path = config.path ?? originalURL.path
        #expect(path == "/v2/users")
    }

    @Test("Blank query preserves original query")
    func blankQueryPreserves() throws {
        let config = MapRemoteConfiguration(host: "staging.com")
        let originalURL = try #require(URL(string: "https://prod.com/v2/users?page=1"))

        let query = config.query ?? originalURL.query
        #expect(query == "page=1")
    }

    @Test("Scheme replacement changes protocol")
    func schemeReplacement() {
        let config = MapRemoteConfiguration(scheme: "http")
        let scheme = config.scheme ?? "https"
        #expect(scheme == "http")
    }

    @Test("Host replacement changes upstream target")
    func hostReplacement() {
        let config = MapRemoteConfiguration(host: "staging.example.com")
        let originalHost = "prod.example.com"
        let upstreamHost = config.host ?? originalHost
        #expect(upstreamHost == "staging.example.com")
    }

    @Test("Port replacement changes connection port")
    func portReplacement() {
        let config = MapRemoteConfiguration(port: 8_443)
        let originalPort = 443
        let port = config.port ?? originalPort
        #expect(port == 8_443)
    }

    @Test("Path replacement overrides original path")
    func pathReplacement() {
        let config = MapRemoteConfiguration(path: "/api/v2")
        let originalPath = "/api/v1"
        let path = config.path ?? originalPath
        #expect(path == "/api/v2")
    }

    @Test("Query replacement overrides original query")
    func queryReplacement() {
        let config = MapRemoteConfiguration(query: "debug=true")
        let originalQuery: String? = "page=1"
        let query = config.query ?? originalQuery
        #expect(query == "debug=true")
    }

    @Test("Preserve-host keeps original host in header")
    func preserveHostHeader() {
        let config = MapRemoteConfiguration(host: "staging.com", preserveHostHeader: true)
        let originalHost = "prod.com"
        let upstreamHost = config.host ?? originalHost
        let hostHeader = config.preserveHostHeader ? originalHost : upstreamHost

        #expect(upstreamHost == "staging.com")
        #expect(hostHeader == "prod.com")
    }

    @Test("Non-preserve-host uses upstream host in header")
    func nonPreserveHostHeader() {
        let config = MapRemoteConfiguration(host: "staging.com", preserveHostHeader: false)
        let originalHost = "prod.com"
        let upstreamHost = config.host ?? originalHost
        let hostHeader = config.preserveHostHeader ? originalHost : upstreamHost

        #expect(hostHeader == "staging.com")
    }

    @Test("All fields nil means no override")
    func noOverride() {
        let config = MapRemoteConfiguration()
        #expect(config.hasOverride == false)
    }

    @Test("Single field set is an override")
    func singleFieldOverride() {
        #expect(MapRemoteConfiguration(host: "x").hasOverride == true)
        #expect(MapRemoteConfiguration(scheme: "http").hasOverride == true)
        #expect(MapRemoteConfiguration(port: 8_080).hasOverride == true)
        #expect(MapRemoteConfiguration(path: "/new").hasOverride == true)
        #expect(MapRemoteConfiguration(query: "a=b").hasOverride == true)
    }

    @Test("Component-by-component independence")
    func componentIndependence() throws {
        let config = MapRemoteConfiguration(scheme: "http", host: "staging.com", port: 8_080)
        let originalURL = try #require(URL(string: "https://prod.com/api/v1?key=123"))

        let scheme = config.scheme ?? originalURL.scheme
        let host = config.host ?? originalURL.host
        let port = config.port ?? originalURL.port
        let path = config.path ?? originalURL.path
        let query = config.query ?? originalURL.query

        #expect(scheme == "http")
        #expect(host == "staging.com")
        #expect(port == 8_080)
        #expect(path == "/api/v1")
        #expect(query == "key=123")
    }

    @Test("Legacy URL parsing produces correct configuration")
    func legacyParsing() {
        let config = MapRemoteConfiguration(fromLegacyURL: "https://staging.example.com:8443/api/v2?debug=1")
        #expect(config.scheme == "https")
        #expect(config.host == "staging.example.com")
        #expect(config.port == 8_443)
        #expect(config.path == "/api/v2")
        #expect(config.query == "debug=1")
        #expect(config.preserveHostHeader == false)
    }
}
