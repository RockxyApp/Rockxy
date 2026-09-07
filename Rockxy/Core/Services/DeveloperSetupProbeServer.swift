import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import os

private let developerSetupProbeLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "DeveloperSetupProbeServer"
)

// MARK: - DeveloperSetupProbeSession

struct DeveloperSetupProbeSession: Equatable, Sendable {
    static let host = "127.0.0.1"
    static let method = "GET"
    static let basePath = "/.well-known/rockxy/dev-setup"

    let port: Int
    let token: String
    let targetID: SetupTarget.ID

    var host: String {
        Self.host
    }

    var method: String {
        Self.method
    }

    var path: String {
        "\(Self.basePath)/\(targetID.rawValue)/\(token)"
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path

        guard let url = components.url else {
            preconditionFailure("Developer Setup probe session produced an invalid URL.")
        }
        return url
    }

    static func make(port: Int, targetID: SetupTarget.ID, token: String = UUID().uuidString.lowercased()) -> Self {
        DeveloperSetupProbeSession(port: port, token: token, targetID: targetID)
    }
}

// MARK: - DeveloperSetupProbeResponse

struct DeveloperSetupProbeResponse {
    let status: HTTPResponseStatus
    let headers: [(String, String)]
    let body: Data
}

// MARK: - DeveloperSetupProbeResponder

enum DeveloperSetupProbeResponder {
    static func response(
        method: HTTPMethod,
        uri: String,
        session: DeveloperSetupProbeSession
    )
        -> DeveloperSetupProbeResponse
    {
        guard method == .GET else {
            return plainResponse(status: .methodNotAllowed, message: "Method not allowed")
        }

        guard let components = URLComponents(string: uri),
              components.path == session.path
        else {
            return plainResponse(status: .notFound, message: "Not found")
        }

        return DeveloperSetupProbeResponse(
            status: .ok,
            headers: [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Cache-Control", "no-store"),
                ("X-Content-Type-Options", "nosniff"),
            ],
            body: Data("{\"ok\":true}\n".utf8)
        )
    }

    private static func plainResponse(status: HTTPResponseStatus, message: String) -> DeveloperSetupProbeResponse {
        DeveloperSetupProbeResponse(
            status: status,
            headers: [
                ("Content-Type", "text/plain; charset=utf-8"),
                ("Cache-Control", "no-store"),
                ("X-Content-Type-Options", "nosniff"),
            ],
            body: Data(message.utf8)
        )
    }
}

// MARK: - DeveloperSetupProbeServer

actor DeveloperSetupProbeServer {
    private(set) var activeSession: DeveloperSetupProbeSession?

    var isRunning: Bool {
        serverChannel != nil
    }

    func start(targetID: SetupTarget.ID) async throws -> DeveloperSetupProbeSession {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        let previousChannel = serverChannel
        let previousGroup = eventLoopGroup
        serverChannel = nil
        eventLoopGroup = nil
        activeSession = nil
        await close(channel: previousChannel, group: previousGroup)

        guard lifecycleGeneration == generation else {
            throw CancellationError()
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let placeholderSession = DeveloperSetupProbeSession.make(port: 0, targetID: targetID)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 16)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(DeveloperSetupProbeHandler(session: placeholderSession))
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 8)

        do {
            let channel = try await bootstrap.bind(host: DeveloperSetupProbeSession.host, port: 0).get()
            guard let localAddress = channel.localAddress, let port = localAddress.port else {
                try await channel.close().get()
                throw DeveloperSetupProbeError.portUnavailable
            }

            let session = DeveloperSetupProbeSession.make(
                port: port,
                targetID: targetID,
                token: placeholderSession.token
            )

            guard lifecycleGeneration == generation else {
                try? await channel.close().get()
                throw CancellationError()
            }

            eventLoopGroup = group
            serverChannel = channel
            activeSession = session
            developerSetupProbeLogger.info("Developer Setup probe server started on 127.0.0.1:\(port)")
            return session
        } catch {
            await close(channel: nil, group: group)
            if lifecycleGeneration == generation {
                eventLoopGroup = nil
                serverChannel = nil
                activeSession = nil
            }
            throw error
        }
    }

    func stop() async {
        lifecycleGeneration += 1
        activeSession = nil
        let channel = serverChannel
        let group = eventLoopGroup
        serverChannel = nil
        eventLoopGroup = nil
        await close(channel: channel, group: group)
    }

    /// Stops only when `session` still owns the server. A superseded health check must
    /// not tear down the newer check that replaced it.
    func stop(ifCurrent session: DeveloperSetupProbeSession) async {
        guard activeSession == session else {
            return
        }
        await stop()
    }

    private func close(
        channel: Channel?,
        group: MultiThreadedEventLoopGroup?
    ) async {
        if let channel {
            do {
                try await channel.close().get()
            } catch {
                developerSetupProbeLogger.error("Failed to close Developer Setup probe channel: \(error.localizedDescription)")
            }
        }

        if let group {
            do {
                try await group.shutdownGracefully()
            } catch {
                developerSetupProbeLogger.error("Failed to shut down Developer Setup probe event loop: \(error.localizedDescription)")
            }
        }
    }

    private var lifecycleGeneration = 0
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?
}

// MARK: - DeveloperSetupProbeHandler

private final class DeveloperSetupProbeHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    init(session: DeveloperSetupProbeSession) {
        self.session = session
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            currentRequestHead = head
        case .body:
            break
        case .end:
            respond(context: context)
            currentRequestHead = nil
        }
    }

    private func respond(context: ChannelHandlerContext) {
        let response = DeveloperSetupProbeResponder.response(
            method: currentRequestHead?.method ?? .GET,
            uri: currentRequestHead?.uri ?? "/",
            session: session
        )

        var buffer = context.channel.allocator.buffer(capacity: response.body.count)
        buffer.writeBytes(response.body)

        var headers = HTTPHeaders()
        for (name, value) in response.headers {
            headers.add(name: name, value: value)
        }
        headers.add(name: "Content-Length", value: "\(response.body.count)")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: response.status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private let session: DeveloperSetupProbeSession
    private var currentRequestHead: HTTPRequestHead?
}

// MARK: - DeveloperSetupProbeError

enum DeveloperSetupProbeError: LocalizedError {
    case portUnavailable

    var errorDescription: String? {
        switch self {
        case .portUnavailable:
            "Developer Setup could not resolve the local validation probe port."
        }
    }
}
