import Foundation
@testable import Rockxy
import Testing

// MARK: - SSLProxyingRuleTests

@MainActor
struct SSLProxyingRuleTests {
    // MARK: - Initialization

    @Test("init defaults listType to include")
    func initDefaultsToInclude() {
        let rule = SSLProxyingRule(domain: "example.com")
        #expect(rule.listType == .include)
        #expect(rule.isEnabled == true)
    }

    @Test("init accepts explicit listType")
    func initWithExplicitListType() {
        let rule = SSLProxyingRule(domain: "example.com", listType: .exclude)
        #expect(rule.listType == .exclude)
    }

    // MARK: - Pattern Matching

    @Test("matches exact domain")
    func matchesExact() {
        let rule = SSLProxyingRule(domain: "example.com")
        #expect(rule.matches("example.com"))
        #expect(!rule.matches("other.com"))
    }

    @Test("matches exact domain case-insensitively")
    func matchesExactCaseInsensitive() {
        let rule = SSLProxyingRule(domain: "Example.COM")
        #expect(rule.matches("example.com"))
        #expect(rule.matches("EXAMPLE.COM"))
    }

    @Test("matches wildcard prefix")
    func matchesWildcard() {
        let rule = SSLProxyingRule(domain: "*.example.com")
        #expect(rule.matches("foo.example.com"))
        #expect(rule.matches("bar.baz.example.com"))
        #expect(!rule.matches("example.com"))
        #expect(!rule.matches("notexample.com"))
    }

    @Test("wildcard does not match bare domain")
    func wildcardDoesNotMatchBare() {
        let rule = SSLProxyingRule(domain: "*.example.com")
        #expect(!rule.matches("example.com"))
    }

    @Test("global wildcard * matches any host")
    func matchesGlobalWildcard() {
        let rule = SSLProxyingRule(domain: "*")
        #expect(rule.matches("example.com"))
        #expect(rule.matches("sub.example.com"))
        #expect(rule.matches("foo.bar"))
    }

    // MARK: - Codable

    @Test("encodes and decodes with listType")
    func codableRoundTrip() throws {
        let original = SSLProxyingRule(domain: "test.com", listType: .exclude)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SSLProxyingRule.self, from: data)

        #expect(decoded.domain == "test.com")
        #expect(decoded.listType == .exclude)
        #expect(decoded.isEnabled == true)
        #expect(decoded.id == original.id)
    }

    @Test("decodes legacy format without listType as include")
    func decodesLegacyAsInclude() throws {
        let json = """
        {"id":"550e8400-e29b-41d4-a716-446655440000","domain":"legacy.com","isEnabled":true}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(SSLProxyingRule.self, from: data)

        #expect(decoded.domain == "legacy.com")
        #expect(decoded.listType == .include)
    }

    // MARK: - SSLProxyingListType

    @Test("SSLProxyingListType has expected raw values")
    func listTypeRawValues() {
        #expect(SSLProxyingListType.include.rawValue == "include")
        #expect(SSLProxyingListType.exclude.rawValue == "exclude")
    }

    @Test("SSLProxyingListType is CaseIterable with 2 cases")
    func listTypeCaseIterable() {
        #expect(SSLProxyingListType.allCases.count == 2)
    }
}
