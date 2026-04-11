import Foundation
@testable import Rockxy
import Testing

struct RuleMatchTypeTests {
    @Test("All cases are defined")
    func allCases() {
        #expect(RuleMatchType.allCases.count == 2)
    }

    @Test("Display names match spec")
    func displayNames() {
        #expect(RuleMatchType.wildcard.rawValue == "Use Wildcard")
        #expect(RuleMatchType.regex.rawValue == "Use Regex")
    }

    @Test("BlockMatchType typealias resolves to RuleMatchType")
    func typealiasResolvesToRuleMatchType() {
        let blockMatch: BlockMatchType = .wildcard
        let ruleMatch: RuleMatchType = blockMatch
        #expect(ruleMatch == .wildcard)
    }
}
