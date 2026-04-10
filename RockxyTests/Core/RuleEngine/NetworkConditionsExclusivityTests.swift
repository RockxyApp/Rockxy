import Foundation
@testable import Rockxy
import Testing

// Regression tests for `NetworkConditionsExclusivity` in the core rule engine layer.

@Suite(.serialized)
struct NetworkConditionsExclusivityTests {
    @Test("enableExclusive enables target and disables other networkCondition rules")
    func enableExclusiveTargetOnly() async {
        let engine = RuleEngine()
        let nc1 = ProxyRule(
            name: "3G Sim",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .networkCondition(preset: .threeG, delayMs: 400)
        )
        let nc2 = ProxyRule(
            name: "Edge Sim",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .networkCondition(preset: .edge, delayMs: 850)
        )
        let nc3 = ProxyRule(
            name: "LTE Sim",
            isEnabled: false,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .networkCondition(preset: .lte, delayMs: 50)
        )
        await engine.addRule(nc1)
        await engine.addRule(nc2)
        await engine.addRule(nc3)

        await engine.enableExclusiveNetworkCondition(id: nc2.id)

        let rules = await engine.allRules
        let rule1 = rules.first(where: { $0.id == nc1.id })
        let rule2 = rules.first(where: { $0.id == nc2.id })
        let rule3 = rules.first(where: { $0.id == nc3.id })

        #expect(rule1?.isEnabled == false)
        #expect(rule2?.isEnabled == true)
        #expect(rule3?.isEnabled == false)
    }

    @Test("enableExclusive leaves throttle and block rules untouched")
    func enableExclusiveLeavesOtherRules() async {
        let engine = RuleEngine()
        let nc = ProxyRule(
            name: "3G Sim",
            isEnabled: false,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .networkCondition(preset: .threeG, delayMs: 400)
        )
        let block = ProxyRule(
            name: "Block Rule",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*blocked.*"),
            action: .block(statusCode: 403)
        )
        let throttle = ProxyRule(
            name: "Throttle Rule",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*slow.*"),
            action: .throttle(delayMs: 1_000)
        )
        await engine.addRule(nc)
        await engine.addRule(block)
        await engine.addRule(throttle)

        await engine.enableExclusiveNetworkCondition(id: nc.id)

        let rules = await engine.allRules
        let blockRule = rules.first(where: { $0.id == block.id })
        let throttleRule = rules.first(where: { $0.id == throttle.id })
        let ncRule = rules.first(where: { $0.id == nc.id })

        #expect(blockRule?.isEnabled == true)
        #expect(throttleRule?.isEnabled == true)
        #expect(ncRule?.isEnabled == true)
    }

    @Test("disableAll disables all networkCondition rules")
    func disableAllNetworkConditions() async {
        let engine = RuleEngine()
        let nc1 = ProxyRule(
            name: "3G Sim",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .networkCondition(preset: .threeG, delayMs: 400)
        )
        let nc2 = ProxyRule(
            name: "Edge Sim",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .networkCondition(preset: .edge, delayMs: 850)
        )
        await engine.addRule(nc1)
        await engine.addRule(nc2)

        await engine.disableAllNetworkConditions()

        let rules = await engine.allRules
        for rule in rules {
            #expect(rule.isEnabled == false)
        }
    }

    @Test("disableAll leaves other rule types untouched")
    func disableAllLeavesOtherTypes() async {
        let engine = RuleEngine()
        let nc = ProxyRule(
            name: "3G Sim",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .networkCondition(preset: .threeG, delayMs: 400)
        )
        let block = ProxyRule(
            name: "Block Rule",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*blocked.*"),
            action: .block(statusCode: 403)
        )
        let throttle = ProxyRule(
            name: "Throttle Rule",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*slow.*"),
            action: .throttle(delayMs: 500)
        )
        await engine.addRule(nc)
        await engine.addRule(block)
        await engine.addRule(throttle)

        await engine.disableAllNetworkConditions()

        let rules = await engine.allRules
        let ncRule = rules.first(where: { $0.id == nc.id })
        let blockRule = rules.first(where: { $0.id == block.id })
        let throttleRule = rules.first(where: { $0.id == throttle.id })

        #expect(ncRule?.isEnabled == false)
        #expect(blockRule?.isEnabled == true)
        #expect(throttleRule?.isEnabled == true)
    }

    @Test("enableExclusive with non-existent ID disables others but enables nothing")
    func enableExclusiveNonExistentId() async {
        let engine = RuleEngine()
        let nc = ProxyRule(
            name: "3G Sim",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .networkCondition(preset: .threeG, delayMs: 400)
        )
        await engine.addRule(nc)

        let fakeId = UUID()
        await engine.enableExclusiveNetworkCondition(id: fakeId)

        let rules = await engine.allRules
        let ncRule = rules.first(where: { $0.id == nc.id })
        #expect(ncRule?.isEnabled == false)
    }

    @Test("addNetworkConditionExclusive disables existing active network conditions")
    func addExclusiveDisablesExisting() async {
        let engine = RuleEngine()
        let nc1 = ProxyRule(
            name: "3G Sim",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .networkCondition(preset: .threeG, delayMs: 400)
        )
        await engine.addRule(nc1)

        let nc2 = ProxyRule(
            name: "Edge Sim",
            matchCondition: RuleMatchCondition(urlPattern: ".*api.*"),
            action: .networkCondition(preset: .edge, delayMs: 850)
        )
        await engine.addNetworkConditionExclusive(nc2)

        let rules = await engine.allRules
        let rule1 = rules.first(where: { $0.id == nc1.id })
        let rule2 = rules.first(where: { $0.id == nc2.id })

        #expect(rule1?.isEnabled == false)
        #expect(rule2?.isEnabled == true)
        #expect(rules.count == 2)
    }
}
