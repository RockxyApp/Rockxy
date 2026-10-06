import NIOCore
import os

private let rawTunnelLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "TLSInterceptHandler"
)

// MARK: - RawTunnelHandler

/// Bidirectional byte-level relay between two channels. Used as a fallback when TLS
/// interception cannot be performed (cert generation failure, SSL pinning). Each side
/// of the tunnel gets its own RawTunnelHandler pointing at the peer channel.
final class RawTunnelHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    /// - Parameters:
    ///   - bytesPerSecond: caps this direction's rate; `nil` relays as fast as the link allows.
    ///   - latencyMs: fixed delay added before each forwarded read in this direction.
    ///   - packetLoss: simulated loss, expressed as retransmission stalls.
    init(
        peerChannel: Channel,
        bytesPerSecond: Int? = nil,
        latencyMs: Int = 0,
        packetLoss: NetworkPacketLoss? = nil
    ) {
        self.peerChannel = peerChannel
        self.bytesPerSecond = bytesPerSecond
        self.latencyMs = max(0, latencyMs)
        self.packetLoss = packetLoss
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    nonisolated func handlerAdded(context: ChannelHandlerContext) {
        resetIdleTimeout(context: context)
    }

    nonisolated func handlerRemoved(context: ChannelHandlerContext) {
        idleTimeout?.cancel()
        idleTimeout = nil
    }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        resetIdleTimeout(context: context)
        let buffer = unwrapInboundIn(data)
        guard isShaped else {
            peerChannel.writeAndFlush(NIOAny(buffer), promise: nil)
            return
        }
        relayShaped(buffer, context: context)
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        idleTimeout?.cancel()
        peerChannel.close(promise: nil)
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        idleTimeout?.cancel()
        peerChannel.close(promise: nil)
        context.close(promise: nil)
    }

    // MARK: Private

    private static let idleTimeoutDuration: TimeAmount = .seconds(60)

    /// How far ahead of real time the shaped queue may run before reading from the sender
    /// pauses, so a fast sender cannot pile an unbounded backlog into memory.
    private static let maxBacklogNanos: UInt64 = 500_000_000

    private let peerChannel: Channel
    private let bytesPerSecond: Int?
    private let latencyMs: Int
    private let packetLoss: NetworkPacketLoss?
    private var idleTimeout: Scheduled<Void>?
    private var shapedReadyAtNanos: UInt64?
    private var lastDeadline: NIODeadline?

    private var isShaped: Bool {
        bytesPerSecond != nil || latencyMs > 0 || packetLoss != nil
    }

    /// Forwards a read through the network-condition profile. Chunk deadlines are strictly
    /// increasing, so a byte stream (often TLS records) is never reordered.
    nonisolated private func relayShaped(_ buffer: ByteBuffer, context: ChannelHandlerContext) {
        let now = DispatchTime.now().uptimeNanoseconds
        let plan = NetworkThrottlePlanner.makePlan(
            byteCount: buffer.readableBytes,
            bytesPerSecond: bytesPerSecond,
            nowNanos: now,
            earliestReadyAtNanos: shapedReadyAtNanos,
            packetLoss: packetLoss
        )
        let chunks = plan?.chunks ?? [NetworkThrottleChunkPlan(offset: 0, length: buffer.readableBytes, delayMs: 0)]
        if let plan {
            shapedReadyAtNanos = plan.readyAtNanos
        }
        let peer = peerChannel
        for chunk in chunks {
            var deadline = context.eventLoop.now + .milliseconds(chunk.delayMs + Int64(latencyMs))
            if let lastDeadline, deadline <= lastDeadline {
                deadline = lastDeadline + .nanoseconds(1)
            }
            lastDeadline = deadline
            context.eventLoop.scheduleTask(deadline: deadline) {
                var slice = buffer
                slice.moveReaderIndex(forwardBy: chunk.offset)
                let part = slice.readSlice(length: chunk.length) ?? slice
                peer.writeAndFlush(NIOAny(part), promise: nil)
            }
        }
        // Pause reading while the shaped backlog is long, then resume when it has drained.
        if let ready = shapedReadyAtNanos, ready > now + Self.maxBacklogNanos {
            let channel = context.channel
            channel.setOption(ChannelOptions.autoRead, value: false).whenSuccess {
                let resumeAfter = Int64((ready - now - Self.maxBacklogNanos) / 1_000_000)
                context.eventLoop.scheduleTask(in: .milliseconds(resumeAfter)) {
                    channel.setOption(ChannelOptions.autoRead, value: true).whenSuccess {
                        channel.read()
                    }
                }
            }
        }
    }

    nonisolated private func resetIdleTimeout(context: ChannelHandlerContext) {
        idleTimeout?.cancel()
        idleTimeout = context.eventLoop.scheduleTask(in: Self.idleTimeoutDuration) {
            rawTunnelLogger.debug("Raw tunnel idle timeout, closing")
            context.close(promise: nil)
        }
    }
}
