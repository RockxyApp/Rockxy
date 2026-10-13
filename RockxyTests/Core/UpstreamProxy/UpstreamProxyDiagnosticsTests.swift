import Foundation
import NIOCore
import NIOPosix
@testable import Rockxy
import Testing

@Suite("Upstream proxy diagnostics", .serialized)
struct UpstreamProxyDiagnosticsTests {
    // MARK: Internal

    @Test("An external proxy that is not listening is reported as unreachable, not as a site failure")
    func unreachableProxyIsDistinct() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let port = try closedLocalPort(group: group)
        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(isEnabled: true, type: .http, host: "127.0.0.1", port: port),
            credentials: nil
        )

        let error = #expect(throws: UpstreamProxyError.self) {
            try UpstreamProxyConnector.connect(
                eventLoop: group.next(),
                targetHost: "api.example.com",
                targetPort: 443,
                configuration: configuration
            ) { channel in
                channel.eventLoop.makeSucceededVoidFuture()
            }.wait()
        }

        guard case let .proxyUnreachable(host, reportedPort, reason) = error else {
            Issue.record("Expected proxyUnreachable, got \(String(describing: error))")
            return
        }
        #expect(host == "127.0.0.1")
        #expect(reportedPort == port)
        #expect(reason == "connection refused")
        let failure = try ConnectionLogCapture.failure(for: #require(error))
        #expect(failure.stage == .proxy)
        #expect(failure.message.contains("external proxy 127.0.0.1"))
    }

    @Test("Credentials embedded in URLs are removed from PAC error text")
    func pacErrorsRedactCredentials() {
        let error = UpstreamProxyError.pacEvaluationFailed(
            "Could not load https://alice:s3cret@config.example.com/proxy.pac (404)"
        )
        let message = error.localizedDescription
        #expect(!message.contains("alice"))
        #expect(!message.contains("s3cret"))
        #expect(message.contains("https://[REDACTED]@config.example.com/proxy.pac"))
        #expect(UpstreamProxyError.redactingURLCredentials(in: "http://token@host/x") == "http://[REDACTED]@host/x")
        #expect(UpstreamProxyError.redactingURLCredentials(in: "mailto bob@example.com") == "mailto bob@example.com")
    }

    @Test("The Tools menu names the route new traffic takes")
    @MainActor
    func menuModeSummary() {
        #expect(ExternalProxyMenuState.modeSummary(for: UpstreamProxyConfiguration()) == nil)
        #expect(ExternalProxyMenuState.modeSummary(for: UpstreamProxyConfiguration(
            isEnabled: true,
            type: .http,
            host: "127.0.0.1",
            port: 7_890
        )) == "HTTP 127.0.0.1:7890")
        let pac = ExternalProxyMenuState.modeSummary(for: UpstreamProxyConfiguration(
            isEnabled: true,
            type: .automatic,
            pacURL: "https://user:pass@config.example.com/proxy.pac"
        ))
        #expect(pac == "Automatic (PAC from config.example.com)")
    }

    // MARK: Private

    private func closedLocalPort(group: EventLoopGroup) throws -> Int {
        let channel = try ServerBootstrap(group: group)
            .bind(host: "127.0.0.1", port: 0)
            .wait()
        let port = try #require(channel.localAddress?.port)
        try channel.close().wait()
        return port
    }
}
