import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
@testable import Rockxy
import Testing

// MARK: - StreamingResponseRelayTests

/// Network-level regression tests for relaying a response that is still open.
///
/// The relay writes response parts without flushing so the writes of one upstream read
/// coalesce. When nothing flushed until the response ended, a `text/event-stream` body that
/// never ends never reached the client at all: the client waited for the status line until
/// the origin closed. These tests boot a real `ProxyServer` and an origin that deliberately
/// leaves its response open, then assert the client sees the head and the first event while
/// the origin is still holding the stream.
@Suite(.serialized)
struct StreamingResponseRelayTests {
    @Test("An event stream reaches the client while the origin still holds it open")
    func eventStreamReachesClientWhileOpen() async throws {
        try await StreamingRelayHarness.run { harness in
            let client = try RawStreamClient.connect(port: harness.proxyPort)
            defer { client.close() }

            try client.send(harness.absoluteFormGET(path: "/stream"))

            // The origin has sent only the head and one event; it has NOT ended the response.
            let received = client.read(until: "open", deadline: 5)
            #expect(harness.openStreamCount() == 1)
            #expect(received.contains("200"))
            #expect(received.contains("data:"))

            // Only now let the origin finish, proving the bytes above arrived beforehand.
            harness.releaseStreams()
        }
    }

    @Test("A response with a known length still relays head and body")
    func completeResponseStillRelays() async throws {
        try await StreamingRelayHarness.run { harness in
            let client = try RawStreamClient.connect(port: harness.proxyPort)
            defer { client.close() }

            try client.send(harness.absoluteFormGET(path: "/complete"))
            let received = client.read(until: StreamingRelayHarness.completeBody, deadline: 5)

            #expect(received.contains("200"))
            #expect(received.contains(StreamingRelayHarness.completeBody))
        }
    }
}

// MARK: - StreamingRelayHarness

/// Boots an origin that can hold a response open plus a real `ProxyServer`, both on
/// ephemeral loopback ports. Owns its own `RuleEngine`, so there is no global rule state to
/// restore; teardown stops both servers.
private actor StreamingRelayHarness {
    // MARK: Lifecycle

    private init(proxyServer: ProxyServer, proxyPort: Int, origin: StreamingOriginServer) {
        self.proxyServer = proxyServer
        self.proxyPort = proxyPort
        self.origin = origin
    }

    // MARK: Internal

    static let completeBody = "{\"complete\":true}"

    nonisolated let proxyPort: Int

    static func run(_ body: (StreamingRelayHarness) async throws -> Void) async throws {
        let harness = try await start()
        do {
            try await body(harness)
        } catch {
            await harness.stop()
            throw error
        }
        await harness.stop()
    }

    /// An absolute-form request line, which is what a client sends to an explicit proxy.
    nonisolated func absoluteFormGET(path: String) -> String {
        "GET http://127.0.0.1:\(origin.port)\(path) HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
    }

    nonisolated func openStreamCount() -> Int {
        origin.openStreamCount()
    }

    nonisolated func releaseStreams() {
        origin.releaseStreams()
    }

    func stop() async {
        origin.releaseStreams()
        await proxyServer.stop()
        await origin.stop()
    }

    // MARK: Private

    private let proxyServer: ProxyServer
    private let origin: StreamingOriginServer

    private static func start() async throws -> StreamingRelayHarness {
        let origin = try await StreamingOriginServer.start()
        let proxyPort = try reserveLoopbackPort()
        let proxyServer = ProxyServer(
            configuration: ProxyConfiguration(port: proxyPort, listenAddress: "127.0.0.1", listenIPv6: false),
            ruleEngine: RuleEngine(),
            onTransactionComplete: { _ in }
        )
        do {
            try await proxyServer.start()
        } catch {
            await origin.stop()
            throw error
        }
        return StreamingRelayHarness(proxyServer: proxyServer, proxyPort: proxyPort, origin: origin)
    }

    /// Binds port 0, reads the assigned port and releases it. The window between release and
    /// the proxy binding is why these tests are serialized.
    private static func reserveLoopbackPort() throws -> Int {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let channel = try ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(host: "127.0.0.1", port: 0)
            .wait()
        guard let port = channel.localAddress?.port else {
            try? channel.close().wait()
            throw StreamingRelayError.noPort
        }
        try channel.close().wait()
        return port
    }
}

// MARK: - StreamingRelayError

private enum StreamingRelayError: Error {
    case noPort
    case socket(String)
}

// MARK: - StreamingOriginServer

/// Serves two fixtures: `/stream` sends a head plus one event and then deliberately keeps the
/// response open until released, and `/complete` sends an ordinary length-delimited body.
private actor StreamingOriginServer {
    // MARK: Internal

    nonisolated var port: Int {
        portBox.value
    }

    static func start() async throws -> StreamingOriginServer {
        let server = StreamingOriginServer()
        try await server.startListening()
        return server
    }

    nonisolated func openStreamCount() -> Int {
        registry.count()
    }

    nonisolated func releaseStreams() {
        registry.releaseAll()
    }

    func stop() async {
        registry.releaseAll()
        if let serverChannel {
            self.serverChannel = nil
            try? await serverChannel.close().get()
        }
        if let group {
            self.group = nil
            try? await group.shutdownGracefully()
        }
    }

    // MARK: Private

    private let registry = OpenStreamRegistry()
    private let portBox = StreamingPortBox()
    private var group: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    private func startListening() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let registry = registry
        do {
            let channel = try await ServerBootstrap(group: group)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline.addHandler(StreamingOriginHandler(registry: registry))
                    }
                }
                .bind(host: "127.0.0.1", port: 0)
                .get()
            guard let boundPort = channel.localAddress?.port else {
                try await channel.close().get()
                throw StreamingRelayError.socket("Streaming origin bound no port.")
            }
            serverChannel = channel
            portBox.value = boundPort
        } catch {
            self.group = nil
            try? await group.shutdownGracefully()
            throw error
        }
    }
}

// MARK: - OpenStreamRegistry

/// Holds the channels whose responses are deliberately unfinished, so a test can assert that
/// the stream is still open and then end it on purpose.
private final class OpenStreamRegistry: @unchecked Sendable {
    // MARK: Internal

    func register(_ channel: Channel) {
        lock.lock()
        channels.append(channel)
        lock.unlock()
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return channels.count
    }

    func releaseAll() {
        lock.lock()
        let open = channels
        channels.removeAll()
        lock.unlock()
        for channel in open {
            channel.eventLoop.execute {
                channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                channel.close(promise: nil)
            }
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var channels: [Channel] = []
}

// MARK: - StreamingPortBox

private final class StreamingPortBox: @unchecked Sendable {
    // MARK: Internal

    var value: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return port
        }
        set {
            lock.lock()
            port = newValue
            lock.unlock()
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var port = 0
}

// MARK: - StreamingOriginHandler

private final class StreamingOriginHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(registry: OpenStreamRegistry) {
        self.registry = registry
    }

    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            uri = head.uri
        case .body:
            break
        case .end:
            if uri.hasSuffix("/stream") {
                beginOpenStream(context: context)
            } else {
                respondComplete(context: context)
            }
        }
    }

    // MARK: Private

    private let registry: OpenStreamRegistry
    private var uri = ""

    /// Sends the head and one event, then leaves the response unfinished on purpose.
    private func beginOpenStream(context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/event-stream")
        headers.add(name: "Transfer-Encoding", value: "chunked")
        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: 32)
        buffer.writeString("data: {\"open\":true}\n\n")
        context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        registry.register(context.channel)
    }

    private func respondComplete(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: 32)
        buffer.writeString(StreamingRelayHarness.completeBody)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: "\(buffer.readableBytes)")
        headers.add(name: "Connection", value: "close")
        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

// MARK: - RawStreamClient

/// A raw socket client. `URLSession` would hide the moment bytes arrive behind its own
/// buffering, and these tests are about exactly that moment.
private struct RawStreamClient {
    // MARK: Internal

    static func connect(port: Int) throws -> RawStreamClient {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw StreamingRelayError.socket("Unable to open a client socket.")
        }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            Darwin.close(descriptor)
            throw StreamingRelayError.socket("Unable to reach the proxy on port \(port).")
        }
        return RawStreamClient(descriptor: descriptor)
    }

    func send(_ request: String) throws {
        let bytes = Array(request.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else {
                    return -1
                }
                return Darwin.send(descriptor, base.advanced(by: offset), bytes.count - offset, 0)
            }
            guard written > 0 else {
                throw StreamingRelayError.socket("Unable to write the proxy request.")
            }
            offset += written
        }
    }

    /// Reads until `marker` appears or the deadline passes, returning whatever arrived.
    func read(until marker: String, deadline seconds: TimeInterval) -> String {
        // Accumulated as bytes and decoded whole, so a multi-byte character split across two
        // reads cannot turn into replacement characters.
        var received: [UInt8] = []
        let end = Date().addingTimeInterval(seconds)
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while Date() < end {
            var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let count = buffer.withUnsafeMutableBytes { raw in
                Darwin.recv(descriptor, raw.baseAddress, raw.count, 0)
            }
            if count > 0 {
                received.append(contentsOf: buffer[0 ..< count])
                if let text = String(bytes: received, encoding: .utf8), text.contains(marker) {
                    return text
                }
            } else if count == 0 {
                break
            }
        }
        return String(bytes: received, encoding: .utf8) ?? ""
    }

    func close() {
        Darwin.close(descriptor)
    }

    // MARK: Private

    private let descriptor: Int32
}
