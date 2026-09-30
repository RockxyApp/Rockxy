import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
@testable import Rockxy
import Testing

// Each test blocks its thread on NIO futures; running them one at a time keeps a full-suite
// run from parking the whole cooperative pool.
@Suite("UpstreamProxyConnector", .serialized)
struct UpstreamProxyConnectorTests {
    // MARK: Internal

    @Test("disabled configuration uses direct outbound bytes")
    func disabledUsesDirectConnect() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let capture = UpstreamProxyStringCapture()
        let server = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyByteCaptureHandler(capture: capture))
        }
        defer { try? server.close().wait() }

        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetHost: "127.0.0.1",
            targetPort: serverPort(server),
            configuration: nil
        ) { channel in
            channel.eventLoop.makeSucceededVoidFuture()
        }.wait()
        defer { try? channel.close().wait() }

        var buffer = channel.allocator.buffer(capacity: 5)
        buffer.writeString("hello")
        try channel.writeAndFlush(buffer).wait()

        #expect(capture.wait() == "hello")
    }

    @Test("bypass list short-circuits an enabled upstream proxy")
    func bypassUsesDirectConnect() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let capture = UpstreamProxyStringCapture()
        let server = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyByteCaptureHandler(capture: capture))
        }
        defer { try? server.close().wait() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                host: "192.0.2.10",
                port: 65_000,
                bypassHostPatterns: ["127.0.0.1"]
            ),
            credentials: nil
        )
        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetHost: "127.0.0.1",
            targetPort: serverPort(server),
            configuration: configuration
        ) { channel in
            channel.eventLoop.makeSucceededVoidFuture()
        }.wait()
        defer { try? channel.close().wait() }

        var buffer = channel.allocator.buffer(capacity: 6)
        buffer.writeString("direct")
        try channel.writeAndFlush(buffer).wait()

        #expect(capture.wait() == "direct")
    }

    @Test("HTTP upstream proxy performs CONNECT before initializer")
    func httpConnectHandshake() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let capture = UpstreamProxyStringCapture()
        let proxy = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyHTTPConnectStubHandler(capture: capture))
        }
        defer { try? proxy.close().wait() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                type: .http,
                host: "127.0.0.1",
                port: serverPort(proxy)
            ),
            credentials: nil
        )
        let initializerCapture = UpstreamProxyStringCapture()
        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetHost: "api.example.com",
            targetPort: 443,
            configuration: configuration
        ) { channel in
            initializerCapture.fulfill("initialized")
            return channel.eventLoop.makeSucceededVoidFuture()
        }.wait()
        defer { try? channel.close().wait() }

        let request = capture.wait()
        #expect(request?.contains("CONNECT api.example.com:443 HTTP/1.1") == true)
        #expect(request?.contains("Host: api.example.com:443") == true)
        #expect(initializerCapture.wait() == "initialized")
    }

    @Test("plain-HTTP targets are relayed to an HTTP proxy in absolute form, not tunneled")
    func httpTargetUsesAbsoluteFormThroughHTTPProxy() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        // The stub only records bytes; it must never see a CONNECT for an http:// target.
        let capture = UpstreamProxyStringCapture()
        let proxy = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyByteCaptureHandler(capture: capture))
        }
        defer { try? proxy.close().wait() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                type: .http,
                host: "127.0.0.1",
                port: serverPort(proxy),
                bypassLocalhost: false
            ),
            credentials: UpstreamProxyCredentials(username: "user", password: "pa:ss")
        )
        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetScheme: "http",
            targetHost: "staging.example.com",
            targetPort: 8_080,
            configuration: configuration
        ) { channel in
            channel.pipeline.addHTTPClientHandlers()
        }.wait()
        defer { try? channel.close().wait() }

        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "staging.example.com:8080")
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/api/items?page=2", headers: headers)
        try channel.writeAndFlush(HTTPClientRequestPart.head(head)).wait()
        try channel.writeAndFlush(HTTPClientRequestPart.end(nil)).wait()

        let request = try #require(capture.wait())
        #expect(request.hasPrefix("GET http://staging.example.com:8080/api/items?page=2 HTTP/1.1\r\n"))
        #expect(!request.contains("CONNECT"))
        #expect(request.contains("Host: staging.example.com:8080"))
        #expect(request.contains("Proxy-Authorization: Basic dXNlcjpwYTpzcw=="))
    }

    @Test("absolute-form relay applies only to http targets on HTTP proxies")
    func absoluteFormRelayDecision() {
        #expect(UpstreamProxyConnector.usesAbsoluteFormRelay(proxyType: .http, targetScheme: "http"))
        #expect(UpstreamProxyConnector.usesAbsoluteFormRelay(proxyType: .https, targetScheme: "HTTP"))
        #expect(!UpstreamProxyConnector.usesAbsoluteFormRelay(proxyType: .http, targetScheme: "https"))
        #expect(!UpstreamProxyConnector.usesAbsoluteFormRelay(proxyType: .socks5, targetScheme: "http"))
        #expect(!UpstreamProxyConnector.usesAbsoluteFormRelay(proxyType: .automatic, targetScheme: "http"))

        #expect(AbsoluteFormRequestHandler.absoluteURI(
            scheme: "http", host: "example.com", port: 80, originFormURI: "/"
        ) == "http://example.com/")
        #expect(AbsoluteFormRequestHandler.absoluteURI(
            scheme: "http", host: "example.com", port: 8_080, originFormURI: "/a?b=1"
        ) == "http://example.com:8080/a?b=1")
        #expect(AbsoluteFormRequestHandler.absoluteURI(
            scheme: "http", host: "::1", port: 8_080, originFormURI: "/x"
        ) == "http://[::1]:8080/x")
        #expect(AbsoluteFormRequestHandler.absoluteURI(
            scheme: "http", host: "example.com", port: 80, originFormURI: "http://other.example/y"
        ) == "http://other.example/y")
    }

    @Test("automatic PAC direct route connects to target without upstream proxy")
    func automaticPACDirectRoute() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let capture = UpstreamProxyStringCapture()
        let server = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyByteCaptureHandler(capture: capture))
        }
        defer { try? server.close().wait() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                type: .automatic,
                pacURL: "https://proxy.example.com/proxy.pac"
            ),
            credentials: nil
        )
        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetScheme: "http",
            targetHost: "127.0.0.1",
            targetPort: serverPort(server),
            configuration: configuration,
            pacResolver: { eventLoop, pacURL, targetScheme, targetHost, targetPort in
                #expect(pacURL.absoluteString == "https://proxy.example.com/proxy.pac")
                #expect(targetScheme == "http")
                #expect(targetHost == "127.0.0.1")
                #expect(targetPort == serverPort(server))
                return eventLoop.makeSucceededFuture(.direct)
            }
        ) { channel in
            channel.eventLoop.makeSucceededVoidFuture()
        }.wait()
        defer { try? channel.close().wait() }

        var buffer = channel.allocator.buffer(capacity: 6)
        buffer.writeString("direct")
        try channel.writeAndFlush(buffer).wait()

        #expect(capture.wait() == "direct")
    }

    @Test("automatic PAC HTTP route reuses CONNECT handshake")
    func automaticPACHTTPRoute() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let capture = UpstreamProxyStringCapture()
        let proxy = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyHTTPConnectStubHandler(capture: capture))
        }
        defer { try? proxy.close().wait() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                type: .automatic,
                pacURL: "https://proxy.example.com/proxy.pac"
            ),
            credentials: nil
        )
        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetScheme: "https",
            targetHost: "api.example.com",
            targetPort: 443,
            configuration: configuration,
            pacResolver: { eventLoop, _, _, _, _ in
                eventLoop.makeSucceededFuture(.proxy(type: .http, host: "127.0.0.1", port: serverPort(proxy)))
            }
        ) { channel in
            channel.eventLoop.makeSucceededVoidFuture()
        }.wait()
        defer { try? channel.close().wait() }

        let request = capture.wait()
        #expect(request?.contains("CONNECT api.example.com:443 HTTP/1.1") == true)
        #expect(request?.contains("Host: api.example.com:443") == true)
    }

    @Test("automatic PAC SOCKS route respects policy snapshot")
    func automaticPACSOCKSRouteRequiresPolicy() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                type: .automatic,
                pacURL: "https://proxy.example.com/proxy.pac"
            ),
            credentials: nil,
            allowsSOCKS5: false
        )

        #expect(throws: UpstreamProxyError.pacSOCKS5Unavailable) {
            try UpstreamProxyConnector.connect(
                eventLoop: group.next(),
                targetScheme: "https",
                targetHost: "api.example.com",
                targetPort: 443,
                configuration: configuration,
                pacResolver: { eventLoop, _, _, _, _ in
                    eventLoop.makeSucceededFuture(.proxy(type: .socks5, host: "127.0.0.1", port: 1_080))
                }
            ) { channel in
                channel.eventLoop.makeSucceededVoidFuture()
            }.wait()
        }
    }

    // MARK: Private

    private func serverPort(_ channel: Channel) -> Int {
        channel.localAddress?.port ?? 0
    }
}
