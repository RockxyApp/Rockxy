import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import os

/// Logger must be nonisolated(unsafe) because NIO channel handlers are called
/// from event loop threads outside Swift's structured concurrency.
private nonisolated(unsafe) let proxyServerLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "ProxyServer"
)

// MARK: - ConnectionLogger

/// Logs when a new client TCP connection is accepted or closed. Added as the first
/// handler in each child channel so connection lifecycle is visible even when
/// subsequent handlers fail or swallow errors.
private final class ConnectionLogger: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = NIOAny

    func channelActive(context: ChannelHandlerContext) {
        let remote = context.remoteAddress?.description ?? "unknown"
        proxyServerLogger.info("New TCP connection from \(remote)")
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        proxyServerLogger.debug("TCP connection closed")
        context.fireChannelInactive()
    }
}

// MARK: - ConnectionTimeoutHandler

/// Enforces an idle timeout on client connections. If no data is read within
/// the configured timeout, the channel is closed to prevent resource leaks.
private final class ConnectionTimeoutHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(timeout: TimeAmount) {
        self.timeout = timeout
    }

    // MARK: Internal

    typealias InboundIn = NIOAny

    func handlerAdded(context: ChannelHandlerContext) {
        rescheduleTimeout(context: context)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        rescheduleTimeout(context: context)
        context.fireChannelRead(data)
    }

    // MARK: Private

    private let timeout: TimeAmount
    private var timeoutTask: Scheduled<Void>?

    private func rescheduleTimeout(context: ChannelHandlerContext) {
        timeoutTask?.cancel()
        timeoutTask = context.eventLoop.scheduleTask(in: timeout) {
            proxyServerLogger.debug("Connection idle timeout exceeded, closing channel")
            context.close(promise: nil)
        }
    }
}

// MARK: - ProxyServer

/// Entry point for the proxy engine. Manages the SwiftNIO server lifecycle —
/// binds to a local port, accepts inbound connections, and installs the HTTP
/// proxy channel pipeline on each child channel. All proxy traffic flows
/// through channel handlers created here.
///
/// Actor isolation ensures start/stop state transitions are data-race-free,
/// while the NIO event loop group handles actual I/O concurrency.
actor ProxyServer {
    // MARK: Lifecycle

    init(
        configuration: ProxyConfiguration = .default,
        certificateManager: CertificateManager = .shared,
        ruleEngine: RuleEngine = RuleEngine(),
        scriptPluginManager: ScriptPluginManager? = nil,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void = { _ in },
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? = nil
    ) {
        self.configuration = configuration
        self.certificateManager = certificateManager
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.onTransactionComplete = onTransactionComplete
        self.onBreakpointHit = onBreakpointHit
    }

    // MARK: Internal

    var isRunning: Bool {
        serverChannel != nil
    }

    func start() async throws {
        guard serverChannel == nil else {
            Self.logger.warning("Proxy server is already running")
            return
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.eventLoopGroup = group

        let certManager = certificateManager
        let ruleEng = ruleEngine
        let scriptMgr = scriptPluginManager
        let limiter = connectionLimiter
        let callback = onTransactionComplete
        let breakpointHit = onBreakpointHit

        let bootstrap = ServerBootstrap(group: group)
            // Backlog of 256 pending connections before the OS starts rejecting
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ConnectionTimeoutHandler(timeout: .seconds(300))).flatMap {
                    channel.pipeline.addHandler(ConnectionLogger())
                }.flatMap {
                    channel.pipeline.configureHTTPServerPipeline()
                }.flatMap {
                    let handler = HTTPProxyHandler(
                        certificateManager: certManager,
                        ruleEngine: ruleEng,
                        scriptPluginManager: scriptMgr,
                        connectionLimiter: limiter,
                        onTransactionComplete: callback,
                        onBreakpointHit: breakpointHit
                    )
                    return channel.pipeline.addHandler(handler)
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            // Cap messages per read to bound per-channel memory usage under high throughput
            .childChannelOption(.maxMessagesPerRead, value: 16)

        do {
            let channel = try await bootstrap.bind(
                host: configuration.listenAddress,
                port: configuration.port
            ).get()
            self.serverChannel = channel
        } catch {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            if let ioError = error as? IOError, ioError.errnoCode == EADDRINUSE {
                throw ProxyServerError.portInUse(configuration.port)
            }
            throw error
        }

        Self.logger.info(
            "Proxy server started on \(self.configuration.listenAddress):\(self.configuration.port)"
        )
    }

    func stop() async {
        guard let channel = serverChannel else {
            return
        }
        serverChannel = nil

        do {
            try await channel.close().get()
        } catch {
            Self.logger.error("Error closing server channel: \(error.localizedDescription)")
        }

        if let group = eventLoopGroup {
            do {
                try await group.shutdownGracefully()
            } catch {
                Self.logger.error("Error shutting down event loop group: \(error.localizedDescription)")
            }
            eventLoopGroup = nil
        }

        Self.logger.info("Proxy server stopped")
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProxyServer")

    private let configuration: ProxyConfiguration
    private let certificateManager: CertificateManager
    private let ruleEngine: RuleEngine
    private let scriptPluginManager: ScriptPluginManager?
    private let connectionLimiter = ConnectionLimiter()
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?
}

// MARK: - ProxyServerError

nonisolated enum ProxyServerError: LocalizedError {
    case portInUse(Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .portInUse(port):
            "Port \(port) is already in use by another process. Check if another proxy (e.g. Proxyman) is running."
        }
    }
}
