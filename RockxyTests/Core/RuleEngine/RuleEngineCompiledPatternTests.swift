import Foundation
@testable import Rockxy
import Testing

// The exclusive network-condition path appended a rule without compiling its URL pattern, so
// `RuleMatchCondition.matches` received `nil` and fell back to re-interpreting the pattern
// through `range(of:options:.regularExpression)` on every request until the next `replaceAll`
// or relaunch.

// MARK: - RuleEngineCompiledPatternTests

@Suite("Rule engine compiled patterns")
struct RuleEngineCompiledPatternTests {
    // MARK: Internal

    @Test("An exclusively enabled network condition compiles its URL pattern")
    func exclusiveNetworkConditionCompilesPattern() async throws {
        let engine = RuleEngine()
        await engine.addNetworkConditionExclusive(Self.throttleRule(pattern: ".*example\\.com/api.*"))

        #expect(await engine.compiledPatternCount == 1)

        let url = try #require(URL(string: "https://example.com/api/users"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        #expect(result != nil)
    }

    @Test("Each exclusive switch leaves exactly one compiled pattern per rule")
    func repeatedExclusiveAddsKeepPatternsCompiled() async {
        let engine = RuleEngine()
        await engine.addNetworkConditionExclusive(Self.throttleRule(pattern: ".*first\\.example\\.com.*"))
        await engine.addNetworkConditionExclusive(Self.throttleRule(pattern: ".*second\\.example\\.com.*"))

        #expect(await engine.compiledPatternCount == 2)
    }

    @Test("A rule with no URL pattern adds no compiled entry")
    func patternlessRuleCompilesNothing() async {
        let engine = RuleEngine()
        await engine.addNetworkConditionExclusive(Self.throttleRule(pattern: nil))

        #expect(await engine.compiledPatternCount == 0)
    }

    // MARK: Private

    private static func throttleRule(pattern: String?) -> ProxyRule {
        ProxyRule(
            name: "Slow network",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: pattern),
            action: .networkCondition(preset: .threeG, delayMs: 100)
        )
    }
}
