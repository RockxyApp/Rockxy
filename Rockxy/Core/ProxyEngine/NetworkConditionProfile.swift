import Foundation
import NIOCore
import NIOHTTP1

// MARK: - NetworkConditionProfile

/// Runtime profile derived from the persisted `RuleAction.networkCondition`
/// payload. The rule action remains latency-compatible on disk; preset bandwidth
/// metadata is resolved here when the action is enforced.
struct NetworkConditionProfile: Equatable, Sendable {
    // MARK: Lifecycle

    init(preset: NetworkConditionPreset, latencyMs: Int) {
        self.preset = preset
        self.latencyMs = max(0, latencyMs)
        downloadBytesPerSecond = preset.downloadBytesPerSecond
        uploadBytesPerSecond = preset.uploadBytesPerSecond
        packetLossRate = preset.packetLossRate
    }

    // MARK: Internal

    let preset: NetworkConditionPreset
    let latencyMs: Int
    let downloadBytesPerSecond: Int?
    let uploadBytesPerSecond: Int?
    let packetLossRate: Double

    var latencyDelay: TimeAmount {
        .milliseconds(Int64(latencyMs))
    }

    /// Loss applied to throttled body chunks, or nil when the profile drops nothing.
    var packetLoss: NetworkPacketLoss? {
        guard packetLossRate > 0, packetLossRate < 1 else {
            return nil
        }
        return NetworkPacketLoss(rate: packetLossRate, latencyMs: latencyMs)
    }
}

// MARK: - NetworkPacketLoss

/// Simulated packet loss. A proxy relays over TCP, which never hands a gap to the app: a lost
/// segment is retransmitted after a timeout. So each lost chunk arrives late by one
/// retransmission timeout (at least 200 ms, or twice the profile latency), and everything
/// after it waits too — the stall-and-recover pattern a lossy link produces.
struct NetworkPacketLoss: Equatable {
    let rate: Double
    let latencyMs: Int

    var retransmissionPenaltyNanos: UInt64 {
        UInt64(max(200, latencyMs * 2)) * 1_000_000
    }
}

// MARK: - NetworkThrottleChunkPlan

struct NetworkThrottleChunkPlan: Equatable {
    let offset: Int
    let length: Int
    let delayMs: Int64
}

// MARK: - NetworkThrottlePlan

struct NetworkThrottlePlan: Equatable {
    let chunks: [NetworkThrottleChunkPlan]
    let readyAtNanos: UInt64

    var totalDelayMs: Int64 {
        chunks.last?.delayMs ?? 0
    }
}

// MARK: - NetworkThrottlePlanner

enum NetworkThrottlePlanner {
    static let targetChunkIntervalMs = 250
    static let minimumChunkSize = 4 * 1_024
    static let maximumChunkSize = 64 * 1_024

    static func chunkSize(bytesPerSecond: Int) -> Int {
        guard bytesPerSecond > 0 else {
            return 0
        }
        let intervalChunk = max(1, (bytesPerSecond * targetChunkIntervalMs) / 1_000)
        return min(max(intervalChunk, minimumChunkSize), maximumChunkSize)
    }

    static func makePlan(
        byteCount: Int,
        bytesPerSecond: Int?,
        nowNanos: UInt64 = DispatchTime.now().uptimeNanoseconds,
        earliestReadyAtNanos: UInt64? = nil,
        packetLoss: NetworkPacketLoss? = nil,
        random: () -> Double = { Double.random(in: 0 ..< 1) }
    )
        -> NetworkThrottlePlan?
    {
        guard byteCount > 0, let bytesPerSecond, bytesPerSecond > 0 else {
            return nil
        }

        let chunkSize = chunkSize(bytesPerSecond: bytesPerSecond)
        guard chunkSize > 0 else {
            return nil
        }

        let startNanos = max(nowNanos, earliestReadyAtNanos ?? nowNanos)
        var chunks: [NetworkThrottleChunkPlan] = []
        chunks.reserveCapacity(Int(ceil(Double(byteCount) / Double(chunkSize))))

        var offset = 0
        var transmittedBytes = 0
        var lossPenaltyNanos: UInt64 = 0
        while offset < byteCount {
            let length = min(chunkSize, byteCount - offset)
            transmittedBytes += length
            if let packetLoss, random() < packetLoss.rate {
                lossPenaltyNanos = lossPenaltyNanos.saturatingAdd(packetLoss.retransmissionPenaltyNanos)
            }
            let elapsedNanos = nanoseconds(forByteCount: transmittedBytes, bytesPerSecond: bytesPerSecond)
                .saturatingAdd(lossPenaltyNanos)
            let scheduledAtNanos = startNanos.saturatingAdd(elapsedNanos)
            chunks.append(NetworkThrottleChunkPlan(
                offset: offset,
                length: length,
                delayMs: millisecondsCeiling(from: nowNanos, to: scheduledAtNanos)
            ))
            offset += length
        }

        return NetworkThrottlePlan(
            chunks: chunks,
            readyAtNanos: startNanos
                .saturatingAdd(nanoseconds(forByteCount: byteCount, bytesPerSecond: bytesPerSecond))
                .saturatingAdd(lossPenaltyNanos)
        )
    }

    static func millisecondsUntil(
        nowNanos: UInt64 = DispatchTime.now().uptimeNanoseconds,
        readyAtNanos: UInt64?
    )
        -> Int64
    {
        guard let readyAtNanos else {
            return 0
        }
        return millisecondsCeiling(from: nowNanos, to: readyAtNanos)
    }

    private static func nanoseconds(forByteCount byteCount: Int, bytesPerSecond: Int) -> UInt64 {
        let seconds = Double(byteCount) / Double(bytesPerSecond)
        return UInt64((seconds * 1_000_000_000).rounded(.up))
    }

    private static func millisecondsCeiling(from nowNanos: UInt64, to scheduledAtNanos: UInt64) -> Int64 {
        guard scheduledAtNanos > nowNanos else {
            return 0
        }
        let nanos = scheduledAtNanos - nowNanos
        return Int64((nanos + 999_999) / 1_000_000)
    }
}

// MARK: - NetworkConditionIOThrottle

enum NetworkConditionIOThrottle {
    static func writeClientRequestBodyAndEnd(
        bodyData: Data?,
        to channel: Channel,
        uploadBytesPerSecond: Int?,
        packetLoss: NetworkPacketLoss? = nil
    ) {
        guard let bodyData, !bodyData.isEmpty else {
            writeClientRequestEnd(to: channel)
            return
        }

        guard let plan = NetworkThrottlePlanner.makePlan(
            byteCount: bodyData.count,
            bytesPerSecond: uploadBytesPerSecond,
            packetLoss: packetLoss
        ) else {
            var bodyBuffer = channel.allocator.buffer(capacity: bodyData.count)
            bodyBuffer.writeBytes(bodyData)
            channel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(bodyBuffer))), promise: nil)
            writeClientRequestEnd(to: channel)
            return
        }

        for chunk in plan.chunks {
            let isLastChunk = chunk == plan.chunks.last
            channel.eventLoop.scheduleTask(in: .milliseconds(chunk.delayMs)) {
                guard channel.isActive else {
                    return
                }
                var bodyBuffer = channel.allocator.buffer(capacity: chunk.length)
                let startIndex = bodyData.index(bodyData.startIndex, offsetBy: chunk.offset)
                let endIndex = bodyData.index(startIndex, offsetBy: chunk.length)
                bodyBuffer.writeBytes(bodyData[startIndex ..< endIndex])
                let bodyPromise = channel.eventLoop.makePromise(of: Void.self)
                channel.writeAndFlush(
                    NIOAny(HTTPClientRequestPart.body(.byteBuffer(bodyBuffer))),
                    promise: bodyPromise
                )
                if isLastChunk {
                    bodyPromise.futureResult.whenComplete { _ in
                        guard channel.isActive else {
                            return
                        }
                        writeClientRequestEnd(to: channel)
                    }
                }
            }
        }
    }

    private static func writeClientRequestEnd(to channel: Channel) {
        let endPromise = channel.eventLoop.makePromise(of: Void.self)
        endPromise.futureResult.whenFailure { _ in
            channel.close(promise: nil)
        }
        channel.writeAndFlush(
            NIOAny(HTTPClientRequestPart.end(nil)),
            promise: endPromise
        )
    }
}

private extension UInt64 {
    func saturatingAdd(_ value: UInt64) -> UInt64 {
        let (result, overflow) = addingReportingOverflow(value)
        return overflow ? UInt64.max : result
    }
}
