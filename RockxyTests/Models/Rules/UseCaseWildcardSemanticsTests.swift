import Foundation
@testable import Rockxy
import Testing

// MARK: - UseCaseWildcardSemanticsTests

/// Wildcard behavior users rely on when mocking with Map Local: `?` is exactly one
/// character, `*` is any run, a bare host matches both schemes, and include-subpaths
/// widens a path to everything below it.
struct UseCaseWildcardSemanticsTests {
    // MARK: Internal

    @Test("? matches exactly one character")
    func questionMarkIsSingleCharacter() {
        let condition = wildcard("https://api.example.com/v?/login")

        #expect(matches(condition, "https://api.example.com/v1/login"))
        #expect(matches(condition, "https://api.example.com/v2/login"))
        #expect(!matches(condition, "https://api.example.com/v10/login"))
    }

    @Test("* matches any suffix")
    func starMatchesAnySuffix() {
        let condition = wildcard("https://api.example.com/v1/*")

        #expect(matches(condition, "https://api.example.com/v1/users"))
        #expect(matches(condition, "https://api.example.com/v1/users/42?expand=true"))
        #expect(!matches(condition, "https://api.example.com/v2/users"))
    }

    @Test("A scheme-less host pattern matches http and https; a scheme restricts it")
    func schemeHandling() {
        let schemeless = wildcard("*://api.example.com/login")
        let httpsOnly = wildcard("https://api.example.com/login")

        #expect(matches(schemeless, "http://api.example.com/login"))
        #expect(matches(schemeless, "https://api.example.com/login"))
        #expect(matches(httpsOnly, "https://api.example.com/login"))
        #expect(!matches(httpsOnly, "http://api.example.com/login"))
    }

    @Test("Include subpaths widens a path without matching sibling prefixes")
    func includeSubpaths() {
        let condition = wildcard("https://api.example.com/v1", includeSubpaths: true)

        #expect(matches(condition, "https://api.example.com/v1"))
        #expect(matches(condition, "https://api.example.com/v1/users?page=2"))
        #expect(!matches(condition, "https://api.example.com/v10/users"))
    }

    // MARK: Private

    private func wildcard(_ pattern: String, includeSubpaths: Bool = false) -> RuleMatchCondition {
        RuleMatchCondition(
            urlPattern: RulePatternBuilder.regexSource(
                rawPattern: pattern,
                matchType: .wildcard,
                includeSubpaths: includeSubpaths
            ),
            sourceURLPattern: pattern,
            matchType: .wildcard,
            includeSubpaths: includeSubpaths
        )
    }

    private func matches(_ condition: RuleMatchCondition, _ url: String) -> Bool {
        guard let url = URL(string: url) else {
            return false
        }
        return condition.matches(method: "GET", url: url, headers: [])
    }
}
