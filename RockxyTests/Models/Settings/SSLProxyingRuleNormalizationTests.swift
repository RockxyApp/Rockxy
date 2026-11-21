import Foundation
@testable import Rockxy
import Testing

// MARK: - SSLProxyingRuleNormalizationTests

/// `matches` decides whether a connection is decrypted, so the two sides of it are normalized
/// differently on purpose: the configured pattern is trimmed, the wire-supplied host is not.
struct SSLProxyingRuleNormalizationTests {
    @Test("a pattern with stray whitespace still matches its host")
    func trimsPatternFromInitializer() {
        let rule = SSLProxyingRule(domain: "  example.com\n")
        #expect(rule.domain == "example.com")
        #expect(rule.matches("example.com"))
    }

    @Test("a wildcard pattern with stray whitespace still matches its subdomains")
    func trimsWildcardPattern() {
        let rule = SSLProxyingRule(domain: " *.example.com ")
        #expect(rule.matches("api.example.com"))
        #expect(!rule.matches("example.com"))
    }

    /// The case that mattered: an untrimmed Exclude rule matched nothing, so a host the user had
    /// explicitly marked "do not decrypt" was decrypted anyway.
    @Test("an untrimmed Tunnel rule decoded from storage still excludes its host")
    func trimsPatternFromDecoder() throws {
        let json = """
        {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "domain": " bank.example.com ",
          "isEnabled": true,
          "listType": "exclude"
        }
        """
        let decoded = try JSONDecoder().decode(SSLProxyingRule.self, from: Data(json.utf8))

        #expect(decoded.domain == "bank.example.com")
        #expect(decoded.listType == .exclude)
        #expect(decoded.matches("bank.example.com"))
    }

    /// A host is wire-supplied. Normalizing it would let a malformed ` example.com` be turned into
    /// an Include (Decrypt) match on attacker-controlled input; left alone it matches neither
    /// list, which lands on the fail-closed tunnel default.
    @Test("an untrimmed host is not normalized into a match")
    func doesNotTrimHost() {
        let rule = SSLProxyingRule(domain: "example.com")
        #expect(!rule.matches(" example.com"))
        #expect(!rule.matches("example.com "))

        let wildcard = SSLProxyingRule(domain: "*.example.com")
        #expect(!wildcard.matches("api.example.com "))
    }

    @Test("a blank pattern addresses no host instead of acting as a wildcard")
    func blankPatternMatchesNothing() {
        let blank = SSLProxyingRule(domain: "   ")
        #expect(blank.domain.isEmpty)
        #expect(!blank.matches("example.com"))
        #expect(!blank.matches(""))
    }

    @Test("a mutated pattern is still matched after trimming")
    func trimsMutatedPattern() {
        var rule = SSLProxyingRule(domain: "example.com")
        rule.domain = " example.org "
        #expect(rule.matches("example.org"))
    }
}
