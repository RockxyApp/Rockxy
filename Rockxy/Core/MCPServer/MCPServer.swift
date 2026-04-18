import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import os

/// Logger must be nonisolated(unsafe) because it may be referenced from
/// NIO event loop threads outside Swift's structured concurrency.
nonisolated(unsafe) private let mcpServerLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "MCPServer"
)

// MARK: - MCPServer

/// Entry point for the MCP Streamable HTTP server. Manages the SwiftNIO server
/// lifecycle — binds to a local port, accepts inbound connections, and installs
/// the MCP HTTP channel pipeline on each child channel.
///
/// Actor isolation ensures start/stop state transitions are data-race-free,
/// while the NIO event loop group handles actual I/O concurrency.
actor MCPServer {
    // MARK: Lifecycle

    init(
        configuration: MCPServerConfiguration = .default,
        toolRegistry: MCPToolRegistry,
        sessionManager: MCPSessionManager = MCPSessionManager()
    ) {
        self.configuration = configuration
        self.toolRegistry = toolRegistry
        self.sessionManager = sessionManager
    }

    // MARK: Internal

    private(set) var activePort: Int?

    var isRunning: Bool {
        serverChannel != nil
    }

    func start() async throws {
        guard serverChannel == nil else {
            mcpServerLogger.warning("MCP server is already running")
            return
        }

        guard let token = MCPHandshakeStore.generateToken() else {
            throw MCPServerError.tokenGenerationFailed
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = group

        let config = configuration
        let sessMgr = sessionManager
        let registry = toolRegistry
        let storedToken = token

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 64)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    let handler = MCPServerHandler(
                        configuration: config,
                        sessionManager: sessMgr,
                        toolRegistry: registry,
                        storedToken: storedToken
                    )
                    return channel.pipeline.addHandler(handler)
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 16)

        do {
            let channel = try await bootstrap.bind(
                host: configuration.listenAddress,
                port: configuration.port
            ).get()
            self.serverChannel = channel
            activePort = configuration.port
        } catch {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            if let ioError = error as? IOError, ioError.errnoCode == EADDRINUSE {
                throw MCPServerError.portInUse(configuration.port)
            }
            throw error
        }

        do {
            try MCPHandshakeStore.write(token: token, port: configuration.port)
        } catch {
            mcpServerLogger.error("Failed to write MCP handshake file: \(error.localizedDescription)")
            await stop(notifyObservers: false)
            throw error
        }

        mcpServerLogger.info(
            "MCP server started on \(self.configuration.listenAddress):\(self.configuration.port)"
        )

        NotificationCenter.default.post(name: .mcpServerDidStart, object: nil)
    }

    func stop() async {
        await stop(notifyObservers: true)
    }

    // MARK: Private

    private let configuration: MCPServerConfiguration
    private let toolRegistry: MCPToolRegistry
    private let sessionManager: MCPSessionManager

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    private func stop(notifyObservers: Bool) async {
        let hadRuntime = serverChannel != nil || eventLoopGroup != nil || activePort != nil
        guard hadRuntime else {
            return
        }
        let channel = serverChannel
        serverChannel = nil
        activePort = nil

        if let channel {
            do {
                try await channel.close().get()
            } catch {
                mcpServerLogger.error("Error closing MCP server channel: \(error.localizedDescription)")
            }
        }

        if let group = eventLoopGroup {
            do {
                try await group.shutdownGracefully()
            } catch {
                mcpServerLogger.error("Error shutting down MCP event loop group: \(error.localizedDescription)")
            }
            eventLoopGroup = nil
        }

        MCPHandshakeStore.delete()
        mcpServerLogger.info("MCP server stopped")

        if notifyObservers {
            NotificationCenter.default.post(name: .mcpServerDidStop, object: nil)
        }
    }
}

// MARK: - MCPServerError

enum MCPServerError: LocalizedError {
    case portInUse(Int)
    case tokenGenerationFailed

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .portInUse(port):
            "MCP server port \(port) is already in use by another process."
        case .tokenGenerationFailed:
            "Failed to generate a secure MCP authentication token."
        }
    }
}
