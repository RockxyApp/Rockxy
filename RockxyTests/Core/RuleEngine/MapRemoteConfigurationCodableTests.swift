import Foundation
@testable import Rockxy
import Testing

// Regression tests for `MapRemoteConfigurationCodable` in the core rule engine layer.

struct MapRemoteConfigurationCodableTests {
    @Test("Legacy URL string decodes into structured configuration")
    func legacyDecode() throws {
        let json = """
        {"type":"mapRemote","url":"https://staging.example.com:8443/api/v2?debug=true"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuleAction.self, from: json)

        if case let .mapRemote(config) = decoded {
            #expect(config.scheme == "https")
            #expect(config.host == "staging.example.com")
            #expect(config.port == 8_443)
            #expect(config.path == "/api/v2")
            #expect(config.query == "debug=true")
            #expect(config.preserveHostHeader == false)
        } else {
            Issue.record("Expected .mapRemote")
        }
    }

    @Test("Structured configuration roundtrips correctly")
    func structuredRoundtrip() throws {
        let config = MapRemoteConfiguration(
            scheme: "https",
            host: "staging.example.com",
            port: 8_443,
            path: "/api/v2",
            query: "debug=true",
            preserveHostHeader: true
        )
        let action = RuleAction.mapRemote(configuration: config)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RuleAction.self, from: data)

        if case let .mapRemote(decodedConfig) = decoded {
            #expect(decodedConfig.scheme == "https")
            #expect(decodedConfig.host == "staging.example.com")
            #expect(decodedConfig.port == 8_443)
            #expect(decodedConfig.path == "/api/v2")
            #expect(decodedConfig.query == "debug=true")
            #expect(decodedConfig.preserveHostHeader == true)
        } else {
            Issue.record("Expected .mapRemote")
        }
    }

    @Test("Partial configuration preserves nil fields")
    func partialConfig() throws {
        let config = MapRemoteConfiguration(host: "new-host.com")
        let action = RuleAction.mapRemote(configuration: config)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RuleAction.self, from: data)

        if case let .mapRemote(decodedConfig) = decoded {
            #expect(decodedConfig.scheme == nil)
            #expect(decodedConfig.host == "new-host.com")
            #expect(decodedConfig.port == nil)
            #expect(decodedConfig.path == nil)
            #expect(decodedConfig.query == nil)
            #expect(decodedConfig.preserveHostHeader == false)
        } else {
            Issue.record("Expected .mapRemote")
        }
    }

    @Test("Empty configuration decodes without error")
    func emptyConfig() throws {
        let json = """
        {"type":"mapRemote","configuration":{}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuleAction.self, from: json)

        if case let .mapRemote(config) = decoded {
            #expect(config.host == nil)
            #expect(config.hasOverride == false)
        } else {
            Issue.record("Expected .mapRemote")
        }
    }

    @Test("hasOverride returns true when any field is set")
    func hasOverride() {
        #expect(MapRemoteConfiguration(host: "x").hasOverride == true)
        #expect(MapRemoteConfiguration(path: "/y").hasOverride == true)
        #expect(MapRemoteConfiguration(scheme: "https").hasOverride == true)
        #expect(MapRemoteConfiguration().hasOverride == false)
    }

    @Test("destinationSummary shows host:port when both set")
    func summaryHostPort() {
        let config = MapRemoteConfiguration(host: "staging.com", port: 8_443)
        #expect(config.destinationSummary == "staging.com:8443")
    }

    @Test("destinationSummary shows host alone when no port")
    func summaryHostOnly() {
        let config = MapRemoteConfiguration(host: "staging.com")
        #expect(config.destinationSummary == "staging.com")
    }

    @Test("destinationSummary shows path when only path set")
    func summaryPathOnly() {
        let config = MapRemoteConfiguration(path: "/api/v2")
        #expect(config.destinationSummary == "/api/v2")
    }

    @Test("destinationSummary shows dash when nothing set")
    func summaryEmpty() {
        let config = MapRemoteConfiguration()
        #expect(config.destinationSummary == "—")
    }
}
