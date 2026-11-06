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
    // MARK: Internal

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
              components.path == session.path else
        {
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

    // MARK: Private

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
    // MARK: Lifecycle

    init(afterBind: @escaping @Sendable () async -> Void = {}) {
        self.afterBind = afterBind
    }

    // MARK: Internal

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
            await afterBind()

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
        lifecycleGeneration += 1
        activeSession = nil
        let channel = serverChannel
        let group = eventLoopGroup
        serverChannel = nil
        eventLoopGroup = nil
        await close(channel: channel, group: group)
    }

    // MARK: Private

    /// Upper bound on closing the probe's own listener channel.
    private static let channelCloseTimeout: Duration = .seconds(2)

    /// Upper bound on the probe's event-loop group shutdown.
    private static let groupShutdownTimeout: Duration = .seconds(5)

    private let afterBind: @Sendable () async -> Void
    private var lifecycleGeneration = 0
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    /// Runs `operation`, giving up after `timeout`, and reports whether it finished.
    ///
    /// Not a task group: a group awaits every child before returning, so racing a sleeper
    /// against an operation that never completes would still never return. The operation runs
    /// in an unstructured task that is simply abandoned at the deadline, with a resume-once
    /// guard so the continuation resumes exactly once. `ProxyServer` bounds its own stop the
    /// same way; that helper is private to it, so the shape is repeated rather than exposed.
    @discardableResult
    private static func awaitBounded(
        _ label: String,
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async -> Void
    )
        async -> Bool
    {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let completed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let claim: @Sendable (Bool) -> Void = { didComplete in
                let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                    if alreadyResumed {
                        return false
                    }
                    alreadyResumed = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: didComplete)
                }
            }
            Task {
                await operation()
                claim(true)
            }
            Task {
                try? await Task.sleep(for: timeout)
                claim(false)
            }
        }
        if !completed {
            developerSetupProbeLogger
                .warning("Developer Setup probe teardown proceeded: \(label) did not finish within its deadline")
        }
        return completed
    }

    private func close(
        channel: Channel?,
        group: MultiThreadedEventLoopGroup?
    )
        async
    {
        // Both waits are bounded because this teardown sits in the middle of the proxy Stop
        // sequence, which awaits it. `close()` and `shutdownGracefully()` have no deadline of
        // their own — one channel that never finishes closing would hang Stop indefinitely.
        // Giving up on the group leaks its threads until the straggler closes, which is the
        // same trade the proxy's own stop already makes: the listener is gone by then, so no
        // new work can arrive.
        if let channel {
            await Self.awaitBounded("probe channel close", Self.channelCloseTimeout) {
                do {
                    try await channel.close().get()
                } catch {
                    developerSetupProbeLogger
                        .error("Failed to close Developer Setup probe channel: \(error.localizedDescription)")
                }
            }
        }

        if let group {
            let completed = await Self.awaitBounded(
                "probe event loop group shutdown",
                Self.groupShutdownTimeout
            ) {
                do {
                    try await group.shutdownGracefully()
                } catch {
                    developerSetupProbeLogger
                        .error("Failed to shut down Developer Setup probe event loop: \(error.localizedDescription)")
                }
            }
            if !completed {
                developerSetupProbeLogger
                    .warning("Developer Setup probe abandoned its event loop shutdown; its threads outlive teardown")
            }
        }
    }
}

// MARK: - DeveloperSetupProbeHandler

private final class DeveloperSetupProbeHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(session: DeveloperSetupProbeSession) {
        self.session = session
    }

    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

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

    // MARK: Private

    private let session: DeveloperSetupProbeSession
    private var currentRequestHead: HTTPRequestHead?

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
}

// MARK: - DeveloperSetupProbeError

enum DeveloperSetupProbeError: LocalizedError {
    case portUnavailable

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .portUnavailable:
            "Developer Setup could not resolve the local validation probe port."
        }
    }
}
