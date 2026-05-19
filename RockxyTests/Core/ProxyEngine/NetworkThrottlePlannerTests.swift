@testable import Rockxy
import NIOCore
import Testing

struct NetworkThrottlePlannerTests {
    @Test("planner returns nil when bandwidth is unlimited")
    func unlimitedBandwidthReturnsNil() {
        #expect(NetworkThrottlePlanner.makePlan(byteCount: 1_024, bytesPerSecond: nil) == nil)
        #expect(NetworkThrottlePlanner.makePlan(byteCount: 1_024, bytesPerSecond: 0) == nil)
    }

    @Test("planner preserves total bandwidth duration")
    func totalBandwidthDuration() throws {
        let plan = try #require(NetworkThrottlePlanner.makePlan(
            byteCount: 1_000,
            bytesPerSecond: 500,
            nowNanos: 1_000
        ))

        #expect(plan.chunks.count == 1)
        #expect(plan.chunks[0].length == 1_000)
        #expect(plan.totalDelayMs == 2_000)
    }

    @Test("planner chains behind existing response backlog")
    func chainsBehindBacklog() throws {
        let plan = try #require(NetworkThrottlePlanner.makePlan(
            byteCount: 500,
            bytesPerSecond: 500,
            nowNanos: 1_000,
            earliestReadyAtNanos: 1_000_001_000
        ))

        #expect(plan.totalDelayMs == 2_000)
        #expect(NetworkThrottlePlanner.millisecondsUntil(nowNanos: 1_000, readyAtNanos: plan.readyAtNanos) == 2_000)
    }

    @Test("planner splits large payload into bounded chunks")
    func splitsLargePayloadIntoBoundedChunks() throws {
        let plan = try #require(NetworkThrottlePlanner.makePlan(
            byteCount: 200_000,
            bytesPerSecond: 1_000_000,
            nowNanos: 0
        ))

        #expect(plan.chunks.count == 4)
        #expect(plan.chunks.map(\.offset) == [0, 65_536, 131_072, 196_608])
        #expect(plan.chunks.map(\.length) == [65_536, 65_536, 65_536, 3_392])
        #expect(plan.chunks.map(\.delayMs) == [66, 132, 197, 200])
        #expect(plan.readyAtNanos == 200_000_000)
    }

    @Test("profile exposes upload and download caps for preset")
    func profileExposesPresetCaps() {
        let profile = NetworkConditionProfile(preset: .threeG, latencyMs: 400)
        let expectedLatency = TimeAmount.milliseconds(400)

        #expect(profile.preset == .threeG)
        #expect(profile.latencyMs == 400)
        #expect(profile.downloadBytesPerSecond == 97_500)
        #expect(profile.uploadBytesPerSecond == 41_250)
        #expect(profile.packetLossRate == 0.0)
        #expect(profile.latencyDelay == expectedLatency)
    }

    @Test("custom profile leaves upload and download unlimited")
    func customProfileLeavesUploadDownloadUnlimited() {
        let profile = NetworkConditionProfile(preset: .custom, latencyMs: -10)
        let expectedLatency = TimeAmount.milliseconds(0)

        #expect(profile.preset == .custom)
        #expect(profile.latencyMs == 0)
        #expect(profile.downloadBytesPerSecond == nil)
        #expect(profile.uploadBytesPerSecond == nil)
        #expect(profile.packetLossRate == 0.0)
        #expect(profile.latencyDelay == expectedLatency)
    }
}
