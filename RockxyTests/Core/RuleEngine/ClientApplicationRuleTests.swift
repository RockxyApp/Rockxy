import Foundation
@testable import Rockxy
import Testing

struct ClientApplicationRuleTests {
    // MARK: Internal

    @Test("An application rule matches by display name or bundle identifier, ignoring case")
    func matchesNameOrBundleIdentifier() {
        let byName = RuleMatchCondition(clientApplication: "safari")
        let byBundle = RuleMatchCondition(clientApplication: "COM.APPLE.SAFARI")

        #expect(matches(byName, application: Self.safari))
        #expect(matches(byBundle, application: Self.safari))
        #expect(!matches(byName, application: Self.curl))
    }

    @Test("An unidentified caller never matches an application rule; unscoped rules ignore the caller")
    func unresolvedCallerFailsOpen() {
        #expect(!matches(RuleMatchCondition(clientApplication: "Safari"), application: nil))
        #expect(matches(RuleMatchCondition(), application: nil))
        #expect(matches(RuleMatchCondition(clientApplication: "  "), application: nil))
    }

    @Test("Rules saved before application scoping decode unscoped, and the field round-trips")
    func codableCompatibility() throws {
        let legacy = try JSONEncoder().encode(RuleMatchCondition(urlPattern: ".*"))
        #expect(try JSONDecoder().decode(RuleMatchCondition.self, from: legacy).clientApplication == nil)

        let scoped = RuleMatchCondition(urlPattern: ".*", clientApplication: "Safari")
        let decoded = try JSONDecoder().decode(RuleMatchCondition.self, from: JSONEncoder().encode(scoped))
        #expect(decoded.clientApplication == "Safari")
    }

    @Test("The engine blocks only the named application and reports when identity is needed")
    func engineEvaluation() async {
        let engine = RuleEngine()
        let url = URL(string: "https://api.example.com/v1")!
        #expect(await !engine.hasApplicationScopedRules)

        await engine.addRule(ProxyRule(
            name: "Block Safari",
            matchCondition: RuleMatchCondition(urlPattern: ".*", clientApplication: "Safari"),
            action: .block(statusCode: 403)
        ))
        #expect(await engine.hasApplicationScopedRules)

        let fromSafari = await engine.evaluateRule(method: "GET", url: url, headers: [], clientApplication: Self.safari)
        let fromCurl = await engine.evaluateRule(method: "GET", url: url, headers: [], clientApplication: Self.curl)
        let unknown = await engine.evaluateRule(method: "GET", url: url, headers: [], clientApplication: nil)
        #expect(fromSafari?.name == "Block Safari")
        #expect(fromCurl == nil)
        #expect(unknown == nil)
    }

    @Test("Identity is resolved only while an application-scoped rule exists")
    func identityResolvedOnDemand() async {
        let engine = RuleEngine()
        let resolutions = ResolutionCounter()
        let request = TestFixtures.makeRequest(url: "https://api.example.com/v1")

        _ = await ProxyHandlerShared.evaluateRules(
            engine,
            request: request,
            graphQLOperationName: nil,
            clientApplication: { resolutions.increment(); return Self.safari }
        )
        #expect(resolutions.value == 0)

        await engine.addRule(ProxyRule(
            name: "Block Safari",
            matchCondition: RuleMatchCondition(urlPattern: ".*", clientApplication: "Safari"),
            action: .block(statusCode: 403)
        ))
        let result = await ProxyHandlerShared.evaluateRules(
            engine,
            request: request,
            graphQLOperationName: nil,
            clientApplication: { resolutions.increment(); return Self.safari }
        )
        #expect(resolutions.value == 1)
        #expect(result.matched?.name == "Block Safari")
    }

    // MARK: Private

    private static let safari = ClientApplicationIdentity.bundle(identifier: "com.apple.Safari", displayName: "Safari")
    private static let curl = ClientApplicationIdentity.executable(normalizedPath: "/usr/bin/curl", displayName: "curl")

    private func matches(_ condition: RuleMatchCondition, application: ClientApplicationIdentity?) -> Bool {
        condition.matches(
            method: "GET",
            url: URL(string: "https://example.com/")!,
            headers: [],
            clientApplication: application
        )
    }
}

private final class ResolutionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
