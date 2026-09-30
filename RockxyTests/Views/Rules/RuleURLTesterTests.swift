@testable import Rockxy
import Testing

struct RuleURLTesterTests {
    private func condition(_ pattern: String, method: String? = nil, subpaths: Bool = true) -> RuleMatchCondition {
        RuleMatchCondition(
            urlPattern: RulePatternBuilder.regexSource(rawPattern: pattern, matchType: .wildcard, includeSubpaths: subpaths),
            sourceURLPattern: pattern,
            method: method,
            matchType: .wildcard,
            includeSubpaths: subpaths
        )
    }

    @Test("The tester agrees with the rule engine on wildcard, subpath and method matching")
    func matchesLikeTheEngine() {
        let rule = condition("https://api.example.com/v1/*", method: "POST")
        #expect(RuleURLTester.evaluate(condition: rule, method: "POST", urlText: "https://api.example.com/v1/users") == .matched)
        #expect(RuleURLTester.evaluate(condition: rule, method: "GET", urlText: "https://api.example.com/v1/users") == .notMatched)
        #expect(RuleURLTester.evaluate(condition: rule, method: "POST", urlText: "https://api.example.com/v2/users") == .notMatched)
    }

    @Test("Incomplete URLs and broken regular expressions are reported, not matched")
    func reportsInvalidInput() {
        let rule = condition("https://api.example.com/*")
        #expect(RuleURLTester.evaluate(condition: rule, method: "GET", urlText: "api.example.com/x") == .invalidURL)
        let broken = RuleMatchCondition(urlPattern: "(", sourceURLPattern: "(", matchType: .regex)
        if case .invalidPattern = RuleURLTester.evaluate(condition: broken, method: "GET", urlText: "https://a.test/") {
        } else {
            Issue.record("a broken regex must be reported")
        }
    }

    @Test("A GraphQL operation filter does not make the URL test fail")
    func ignoresOperationFilter() {
        var rule = condition("https://api.example.com/graphql")
        rule.graphQLOperationName = "GetUser"
        #expect(RuleURLTester.evaluate(condition: rule, method: "POST", urlText: "https://api.example.com/graphql") == .matched)
    }
}
