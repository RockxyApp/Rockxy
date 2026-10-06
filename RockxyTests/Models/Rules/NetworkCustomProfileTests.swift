import Foundation
@testable import Rockxy
import Testing

// MARK: - NetworkCustomProfileTests

struct NetworkCustomProfileTests {
    @Test("Custom limits drive the runtime profile; presets ignore them")
    func runtimeProfileUsesCustomLimits() {
        let custom = NetworkCustomProfile(downloadKbps: 800, uploadKbps: 0, packetLossPercent: 5)
        let profile = NetworkConditionProfile(preset: .custom, latencyMs: 120, custom: custom)
        #expect(profile.downloadBytesPerSecond == 100_000)
        #expect(profile.uploadBytesPerSecond == nil)
        #expect(profile.packetLoss?.rate == 0.05)
        #expect(profile.latencyMs == 120)

        let preset = NetworkConditionProfile(preset: .threeG, latencyMs: 400, custom: custom)
        #expect(preset.downloadBytesPerSecond == NetworkConditionPreset.threeG.downloadBytesPerSecond)
        #expect(preset.packetLoss == nil)
    }

    @Test("Custom rule round-trips its limits and older custom rules stay unlimited")
    func codableRoundTrip() throws {
        let custom = NetworkCustomProfile(downloadKbps: 1_500, uploadKbps: 256, packetLossPercent: 2.5)
        let action = RuleAction.networkCondition(preset: .custom, delayMs: 300, custom: custom)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RuleAction.self, from: data)
        guard case let .networkCondition(preset, delayMs, decodedCustom) = decoded else {
            Issue.record("Expected a network condition action")
            return
        }
        #expect(preset == .custom)
        #expect(delayMs == 300)
        #expect(decodedCustom == custom)

        let legacy = Data(#"{"type":"networkCondition","preset":"custom","delayMs":500}"#.utf8)
        guard case let .networkCondition(_, _, legacyCustom) = try JSONDecoder().decode(RuleAction.self, from: legacy)
        else {
            Issue.record("Expected a network condition action")
            return
        }
        #expect(legacyCustom == nil)
    }

    @Test("Unlimited or preset profiles encode exactly as before")
    func encodingStaysCompatible() throws {
        let unlimited = RuleAction.networkCondition(preset: .custom, delayMs: 500, custom: .unlimited)
        let json = try #require(String(data: JSONEncoder().encode(unlimited), encoding: .utf8))
        #expect(!json.contains("Kbps"))
        #expect(!json.contains("packetLoss"))

        let preset = RuleAction.networkCondition(
            preset: .lte,
            delayMs: 50,
            custom: NetworkCustomProfile(downloadKbps: 10)
        )
        let presetJSON = try #require(String(data: JSONEncoder().encode(preset), encoding: .utf8))
        #expect(!presetJSON.contains("downloadKbps"))
    }

    @Test("Validation rejects negative bandwidth and out-of-range loss")
    func validation() {
        #expect(NetworkCustomProfile(downloadKbps: 500, packetLossPercent: 10).validationMessage == nil)
        #expect(NetworkCustomProfile(downloadKbps: -1).validationMessage != nil)
        #expect(NetworkCustomProfile(packetLossPercent: 100).validationMessage != nil)
        #expect(NetworkCustomProfile(packetLossPercent: -2).validationMessage != nil)
        #expect(NetworkCustomProfile(downloadKbps: 0, uploadKbps: nil).isUnlimited)
    }

    @Test("The editor stores custom limits only for the Custom preset")
    func formStoresCustomOnlyForCustomPreset() {
        let custom = NetworkCustomProfile(downloadKbps: 64, packetLossPercent: 1)
        let rule = NetworkConditionsRuleForm.makeRule(
            original: nil,
            name: "Slow API",
            isEnabled: true,
            hostText: "api.example.com",
            applySystemWide: false,
            preset: .custom,
            customLatencyMs: 200,
            customProfile: custom
        )
        guard case let .networkCondition(_, delayMs, stored) = rule.action else {
            Issue.record("Expected a network condition action")
            return
        }
        #expect(delayMs == 200)
        #expect(stored == custom)
        #expect(!NetworkConditionsRuleForm.isValid(
            name: "Slow API",
            hostText: "api.example.com",
            applySystemWide: false,
            preset: .custom,
            customLatencyMs: 200,
            customProfile: NetworkCustomProfile(packetLossPercent: 150)
        ))
        #expect(NetworkConditionsRuleForm.customAction(preset: .threeG, customProfile: custom) == nil)
    }

    @Test("Loss without a bandwidth cap still delays lost chunks")
    func lossWithoutBandwidthCap() throws {
        let plan = try #require(NetworkThrottlePlanner.makePlan(
            byteCount: 200_000,
            bytesPerSecond: nil,
            nowNanos: 0,
            packetLoss: NetworkPacketLoss(rate: 0.5, latencyMs: 100),
            random: { 0 }
        ))
        #expect(plan.totalDelayMs >= 200)
        #expect(NetworkThrottlePlanner.makePlan(byteCount: 200_000, bytesPerSecond: nil, nowNanos: 0) == nil)
    }
}
