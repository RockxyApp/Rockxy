import Foundation
@testable import Rockxy
import Testing

// MARK: - ReverseProxyRuleTests

@MainActor
struct ReverseProxyRuleTests {
    // MARK: Internal

    @Test("Validation rejects unusable ports, hosts with a scheme or path, and self-forwarding")
    func validation() {
        let valid = rule(localPort: 10_000, host: "api.example.com", remotePort: 443)
        #expect(ReverseProxyRuleValidator.problem(with: valid, among: [valid], proxyPort: 9_090) == nil)

        let lowPort = rule(localPort: 80, host: "api.example.com", remotePort: 443)
        let proxyPort = rule(localPort: 9_090, host: "api.example.com", remotePort: 443)
        let withScheme = rule(localPort: 10_001, host: "https://api.example.com", remotePort: 443)
        let withPath = rule(localPort: 10_001, host: "api.example.com/v1", remotePort: 443)
        let selfLoop = rule(localPort: 10_002, host: "127.0.0.1", remotePort: 10_002)
        let proxyLoop = rule(localPort: 10_003, host: "localhost", remotePort: 9_090)
        let localDevServer = rule(localPort: 10_004, host: "localhost", remotePort: 3_000)

        for broken in [lowPort, proxyPort, withScheme, withPath, selfLoop, proxyLoop] {
            #expect(ReverseProxyRuleValidator.problem(with: broken, among: [], proxyPort: 9_090) != nil)
        }
        #expect(ReverseProxyRuleValidator.problem(with: localDevServer, among: [], proxyPort: 9_090) == nil)
    }

    @Test("A new rule's empty remote host keeps Save disabled without an error message")
    func emptyHostIsQuiet() {
        let draft = rule(localPort: 10_000, host: "", remotePort: 443)
        #expect(ReverseProxyRuleValidator.problem(with: draft, among: [], proxyPort: 9_090) != nil)
        #expect(ReverseProxyRuleValidator.problem(
            with: draft,
            among: [],
            proxyPort: 9_090,
            reportsMissingFields: false
        ) == nil)
        let lowPort = rule(localPort: 80, host: "", remotePort: 443)
        #expect(ReverseProxyRuleValidator.problem(
            with: lowPort,
            among: [],
            proxyPort: 9_090,
            reportsMissingFields: false
        ) != nil)
    }

    @Test("Two rules cannot share a local port")
    func duplicateLocalPort() {
        let first = rule(localPort: 10_000, host: "a.example.com", remotePort: 443)
        let second = rule(localPort: 10_000, host: "b.example.com", remotePort: 443)

        #expect(ReverseProxyRuleValidator.problem(with: second, among: [first, second], proxyPort: 9_090) != nil)
    }

    @Test("Rules persist, and only enabled rules become listener targets")
    func storePersistenceAndTargets() throws {
        let suite = "ReverseProxyRuleTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ReverseProxyStore(defaults: defaults)
        var enabled = rule(localPort: 10_000, host: "api.example.com", remotePort: 443)
        var disabled = rule(localPort: 10_001, host: "staging.example.com", remotePort: 8_443)
        disabled.isEnabled = false
        store.upsert(enabled)
        store.upsert(disabled)

        #expect(store.enabledTargets.map(\.localPort) == [10_000])
        #expect(store.status(for: disabled) == .disabled)
        #expect(store.status(for: enabled) == .proxyStopped)

        store.applyListenerResult(targets: store.enabledTargets, failures: [:])
        #expect(store.status(for: enabled) == .listening)
        store.applyListenerResult(targets: store.enabledTargets, failures: [enabled.id: .portInUse])
        #expect(store.status(for: enabled) == .portInUse)

        enabled.name = "Production API"
        store.upsert(enabled)
        let reloaded = ReverseProxyStore(defaults: defaults)
        #expect(reloaded.rules.map(\.name) == ["Production API", "Staging"])
        #expect(reloaded.rules.first?.remoteURLString == "https://api.example.com")
        #expect(reloaded.rules.last?.remoteURLString == "https://staging.example.com:8443")
    }

    // MARK: Private

    private func rule(localPort: Int, host: String, remotePort: Int) -> ReverseProxyRule {
        ReverseProxyRule(
            name: host.hasPrefix("staging") ? "Staging" : "API",
            localPort: localPort,
            remoteHost: host,
            remotePort: remotePort
        )
    }
}
