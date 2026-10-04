import Foundation
import NIOCore
import NIOHTTP1
import NIOSSL
import os

nonisolated(unsafe) private let tlsLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "TLSInterceptHandler"
)

// Defines `ProtocolDetectorHandler`, which decides how a CONNECT tunnel is relayed once the
// client's first bytes reveal TLS, plain HTTP, or an unknown protocol.

// MARK: - ProtocolDetectorHandler

/// Sits before NIOSSLServerHandler in the pipeline. Examines the first byte of
/// incoming data to determine if the client is speaking TLS. If yes, forwards
/// data naturally to the next handler (NIOSSLServerHandler) via context.fireChannelRead
/// and removes itself. If no, tears down TLS handlers and sets up a raw tunnel.
///
/// This forward-based approach avoids the broken channel.pipeline.fireChannelRead
/// replay pattern that causes WRONG_VERSION_NUMBER errors.
final class ProtocolDetectorHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        sslHandler: NIOSSLServerHandler,
        host: String,
        port: Int,
        postHandshake: PostHandshakeHandler,
        connectionLimiter: ConnectionLimiter,
        upstreamProxySnapshotProvider: @escaping @Sendable () -> UpstreamProxyResolvedConfiguration? = { nil },
        rawTunnelConnector: @escaping TLSInterceptHandler.RawTunnelConnector = TLSInterceptHandler.connectRawTunnel,
        networkProfile: NetworkConditionProfile? = nil
    ) {
        self.networkProfile = networkProfile
        self.sslHandler = sslHandler
        self.host = host
        self.port = port
        self.postHandshake = postHandshake
        self.connectionLimiter = connectionLimiter
        self.upstreamProxySnapshotProvider = upstreamProxySnapshotProvider
        self.rawTunnelConnector = rawTunnelConnector
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer

    /// `true` when the tunnel's first bytes are an HTTP/1.x request line (`GET /path HTTP/1.1`).
    /// Anything shorter or shaped differently stays a raw tunnel, which is the safe default.
    nonisolated static func looksLikePlainHTTPRequest(_ buffer: ByteBuffer) -> Bool {
        let probeLength = min(buffer.readableBytes, 512)
        guard probeLength >= 16,
              let preface = buffer.getString(at: buffer.readerIndex, length: probeLength) else
        {
            return false
        }
        guard let lineEnd = preface.range(of: "\r\n") else {
            return false
        }
        let requestLine = preface[..<lineEnd.lowerBound]
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3,
              !parts[0].isEmpty,
              parts[0].allSatisfy({ $0.isUppercase && $0.isLetter }),
              parts[1].hasPrefix("/"),
              parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0" else
        {
            return false
        }
        return true
    }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if rawTunnelPending {
            guard appendRawTunnelData(unwrapInboundIn(data)) else {
                tlsLogger.warning("Buffered raw CONNECT data exceeded the safety limit for \(self.host)")
                postHandshake.recordTunnelFailure(statusCode: 413, statusMessage: "Tunnel Preface Too Large")
                context.close(promise: nil)
                return
            }
            return
        }

        if detected {
            context.fireChannelRead(data)
            return
        }

        let buffer = unwrapInboundIn(data)
        guard let firstByte = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) else {
            return
        }

        // TLS record content types: 0x14=ChangeCipherSpec, 0x15=Alert,
        // 0x16=Handshake, 0x17=ApplicationData, 0x18=Heartbeat.
        // 0x80=SSLv2 ClientHello (legacy compatibility).
        let isTLS = (firstByte >= 0x14 && firstByte <= 0x18) || firstByte == 0x80

        if isTLS {
            detected = true
            tlsLogger.debug("TLS detected for \(self.host), forwarding to NIOSSLServerHandler")
            // Forward naturally to the next handler (NIOSSLServerHandler) in the pipeline.
            // No replay needed — data flows through the normal NIO path.
            context.fireChannelRead(data)
            // Remove ourselves so future reads go directly to NIOSSLServerHandler.
            context.pipeline.removeHandler(context: context, promise: nil)
        } else if Self.looksLikePlainHTTPRequest(buffer) {
            detected = true
            tlsLogger.info("Plain HTTP inside CONNECT tunnel for \(self.host), relaying as http://")
            installPlainHTTPRelay(context: context, firstBuffer: buffer)
        } else {
            rawTunnelPending = true
            guard appendRawTunnelData(buffer) else {
                tlsLogger.warning("Buffered raw CONNECT data exceeded the safety limit for \(self.host)")
                postHandshake.recordTunnelFailure(statusCode: 413, statusMessage: "Tunnel Preface Too Large")
                context.close(promise: nil)
                return
            }
            tlsLogger
                .info(
                    "Non-TLS data (0x\(String(firstByte, radix: 16))) in CONNECT tunnel for \(self.host), falling back to raw tunnel"
                )
            tearDownForRawTunnel(context: context)
        }
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        tlsLogger.warning("ProtocolDetector error for \(self.host): \(String(describing: error))")
        postHandshake.recordTunnelFailure(statusCode: 500, statusMessage: "Protocol Detection Failed")
        context.close(promise: nil)
    }

    // MARK: Private

    private let networkProfile: NetworkConditionProfile?
    private let sslHandler: NIOSSLServerHandler
    private let host: String
    private let port: Int
    private let postHandshake: PostHandshakeHandler
    private let connectionLimiter: ConnectionLimiter
    private let upstreamProxySnapshotProvider: @Sendable () -> UpstreamProxyResolvedConfiguration?
    private let rawTunnelConnector: TLSInterceptHandler.RawTunnelConnector
    private var detected = false, rawTunnelPending = false
    private var bufferedRawTunnelData: [ByteBuffer] = []
    private var bufferedRawTunnelByteCount = 0

    /// Replaces the TLS handlers with the HTTP server codecs and a plain-scheme relay, then
    /// replays the bytes that revealed the protocol so the first request is parsed normally.
    nonisolated private func installPlainHTTPRelay(context: ChannelHandlerContext, firstBuffer: ByteBuffer) {
        let pipeline = context.pipeline
        let sslHandler = self.sslHandler
        let postHandshake = self.postHandshake
        let relay = postHandshake.makeRelayHandler(scheme: "http")

        pipeline.removeHandler(sslHandler).flatMapError { _ in
            context.eventLoop.makeSucceededVoidFuture()
        }.flatMap {
            pipeline.removeHandler(postHandshake)
        }.flatMapError { _ in
            context.eventLoop.makeSucceededVoidFuture()
        }.flatMap {
            pipeline.configureHTTPServerPipeline()
        }.flatMap {
            pipeline.addHandler(relay)
        }.whenComplete { result in
            switch result {
            case .success:
                // The CONNECT itself succeeded; its row is the tunnel, the relayed requests
                // become their own transactions like a decrypted tunnel's would.
                postHandshake.recordSuccessfulTunnel(scheme: "http")
                context.fireChannelRead(NIOAny(firstBuffer))
                pipeline.removeHandler(context: context, promise: nil)
            case let .failure(error):
                tlsLogger.error("Plain HTTP relay setup failed for \(self.host): \(error.localizedDescription)")
                postHandshake.recordTunnelFailure(statusCode: 500, statusMessage: "Tunnel Relay Setup Failed")
                context.close(promise: nil)
            }
        }
    }

    /// Remove NIOSSLServerHandler and PostHandshakeHandler, then set up a raw TCP relay.
    nonisolated private func tearDownForRawTunnel(
        context: ChannelHandlerContext
    ) {
        let host = self.host
        let port = self.port
        let channel = context.channel
        let sslHandler = self.sslHandler
        let postHandshake = self.postHandshake
        let limiter = self.connectionLimiter

        guard limiter.acquire(host: host, port: port) else {
            tlsLogger.warning("Connection limit reached for \(host):\(port), closing")
            postHandshake.recordTunnelFailure(statusCode: 503, statusMessage: "Connection Limit Reached")
            channel.close(promise: nil)
            return
        }

        let pipeline = context.pipeline
        channel.setOption(ChannelOptions.autoRead, value: false).flatMap {
            self.rawTunnelConnector(
                context.eventLoop,
                host,
                port,
                self.upstreamProxySnapshotProvider()
            )
        }.whenComplete { result in
            switch result {
            case let .success(serverChannel):
                serverChannel.closeFuture.whenComplete { _ in
                    limiter.release(host: host, port: port)
                }
                self.postHandshake.tunnelConnectionLog = ConnectionLogCapture.log(
                    for: serverChannel,
                    host: host,
                    port: port,
                    tlsIntent: nil,
                    handshakeDuration: nil,
                    negotiatedProtocol: nil
                )
                let replayClientReads = self.bufferedRawTunnelData
                self.bufferedRawTunnelData.removeAll(keepingCapacity: false)
                self.bufferedRawTunnelByteCount = 0
                let prepareClientChannel = pipeline.removeHandler(sslHandler).flatMapError { _ in
                    context.eventLoop.makeSucceededVoidFuture()
                }.flatMap {
                    pipeline.removeHandler(postHandshake)
                }.flatMapError { _ in
                    context.eventLoop.makeSucceededVoidFuture()
                }.flatMap {
                    pipeline.removeHandler(context: context)
                }
                TLSInterceptHandler.completeRawTunnelSetup(
                    serverChannel: serverChannel,
                    clientChannel: channel,
                    prepareClientChannel: prepareClientChannel,
                    replayClientReads: replayClientReads,
                    enableClientAutoRead: true,
                    networkProfile: self.networkProfile
                ) {
                    self.postHandshake.recordSuccessfulTunnel()
                } onFailure: { error in
                    tlsLogger.error("Raw tunnel setup failed for \(host): \(error.localizedDescription)")
                    self.postHandshake.recordTunnelFailure(statusCode: 502, statusMessage: "Tunnel Setup Failed")
                    serverChannel.close(promise: nil)
                    channel.close(promise: nil)
                }
            case let .failure(error):
                limiter.release(host: host, port: port)
                tlsLogger.error("Raw tunnel connection failed to \(host):\(port): \(String(describing: error))")
                self.postHandshake.tunnelConnectionLog = ConnectionLogCapture.failedConnection(
                    host: host,
                    port: port,
                    connectHost: host,
                    error: error
                )
                self.postHandshake.recordTunnelFailure(statusCode: 502, statusMessage: "Upstream Connection Failed")
                channel.close(promise: nil)
            }
        }
    }

    nonisolated private func appendRawTunnelData(_ buffer: ByteBuffer) -> Bool {
        guard bufferedRawTunnelByteCount <= TLSInterceptHandler.maximumBufferedTunnelBytes - buffer.readableBytes else {
            return false
        }
        bufferedRawTunnelByteCount += buffer.readableBytes
        bufferedRawTunnelData.append(buffer)
        return true
    }
}
