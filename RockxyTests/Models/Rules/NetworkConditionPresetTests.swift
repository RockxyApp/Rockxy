import Foundation
@testable import Rockxy
import Testing

// Regression tests for `NetworkConditionPreset` in the models rules layer.

struct NetworkConditionPresetTests {
    @Test("each preset returns correct latency")
    func presetLatencies() {
        #expect(NetworkConditionPreset.threeG.defaultLatencyMs == 400)
        #expect(NetworkConditionPreset.edge.defaultLatencyMs == 850)
        #expect(NetworkConditionPreset.lte.defaultLatencyMs == 50)
        #expect(NetworkConditionPreset.veryBadNetwork.defaultLatencyMs == 2_000)
        #expect(NetworkConditionPreset.wifi.defaultLatencyMs == 2)
        #expect(NetworkConditionPreset.custom.defaultLatencyMs == 0)
    }

    @Test("each preset returns correct display name")
    func presetDisplayNames() {
        #expect(NetworkConditionPreset.threeG.displayName == "3G")
        #expect(NetworkConditionPreset.edge.displayName == "EDGE")
        #expect(NetworkConditionPreset.lte.displayName == "LTE")
        #expect(NetworkConditionPreset.veryBadNetwork.displayName == "Very Bad Network")
        #expect(NetworkConditionPreset.wifi.displayName == "WiFi")
        #expect(NetworkConditionPreset.custom.displayName == "Custom")
    }

    @Test("makeRule creates ProxyRule with networkCondition action")
    func makeRuleCreatesCorrectAction() {
        let condition = RuleMatchCondition(urlPattern: ".*example\\.com.*")
        let rule = NetworkConditionPreset.makeRule(
            preset: .threeG,
            latencyMs: 400,
            name: "Slow 3G",
            matchCondition: condition
        )

        #expect(rule.name == "Slow 3G")
        #expect(rule.isEnabled == true)
        if case let .networkCondition(preset, delayMs) = rule.action {
            #expect(preset == .threeG)
            #expect(delayMs == 400)
        } else {
            Issue.record("Expected .networkCondition action, got \(rule.action)")
        }
    }

    @Test("custom preset uses explicit ms")
    func customPresetExplicitMs() {
        let condition = RuleMatchCondition(urlPattern: ".*")
        let rule = NetworkConditionPreset.makeRule(
            preset: .custom,
            latencyMs: 1_234,
            name: "Custom Delay",
            matchCondition: condition
        )

        if case let .networkCondition(preset, delayMs) = rule.action {
            #expect(preset == .custom)
            #expect(delayMs == 1_234)
        } else {
            Issue.record("Expected .networkCondition action")
        }
    }

    @Test("from(delayMs:) reverse-maps known presets")
    func fromDelayMsKnownPresets() {
        #expect(NetworkConditionPreset.from(delayMs: 400) == .threeG)
        #expect(NetworkConditionPreset.from(delayMs: 850) == .edge)
        #expect(NetworkConditionPreset.from(delayMs: 50) == .lte)
        #expect(NetworkConditionPreset.from(delayMs: 2_000) == .veryBadNetwork)
        #expect(NetworkConditionPreset.from(delayMs: 2) == .wifi)
    }

    @Test("from(delayMs:) returns custom for unknown values")
    func fromDelayMsUnknownValues() {
        #expect(NetworkConditionPreset.from(delayMs: 0) == .custom)
        #expect(NetworkConditionPreset.from(delayMs: 999) == .custom)
        #expect(NetworkConditionPreset.from(delayMs: 1) == .custom)
        #expect(NetworkConditionPreset.from(delayMs: -1) == .custom)
    }
}
