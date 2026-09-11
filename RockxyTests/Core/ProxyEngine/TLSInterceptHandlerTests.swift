import Foundation
import NIOCore
import NIOEmbedded
import NIOSSL
@testable import Rockxy
import Testing

// MARK: - TunnelSetupState

private final class TunnelSetupState: @unchecked Sendable {
    // MARK: Internal

    private(set) var successCount = 0
    private(set) var receivedError: Error?

    func recordSuccess() {
        lock.lock()
        successCount += 1
        lock.unlock()
    }

    func recordError(_ error: Error) {
        lock.lock()
        receivedError = error
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
}

// MARK: - RecordedTransactionBox

private final class RecordedTransactionBox: @unchecked Sendable {
    // MARK: Internal

    private(set) var transaction: HTTPTransaction?

    func record(_ transaction: HTTPTransaction) {
        lock.lock()
        self.transaction = transaction
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
}

// MARK: - EventCountBox

private final class EventCountBox: @unchecked Sendable {
    private(set) var count = 0

    func record() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    private let lock = NSLock()
}

// MARK: - SyntheticTLSError

private struct SyntheticTLSError: Error, CustomStringConvertible {
    let description: String
}

// MARK: - TLSInterceptHandlerTests

@MainActor
@Suite(.serialized)
struct TLSInterceptHandlerTests {
    // MARK: Internal

    @Test("TLS rejection notification attributes evidence without exposing an executable path")
    func rejectionNotificationUsesStableApplicationIdentity() {
        let identity = ClientApplicationIdentity.executable(
            normalizedPath: "/Users/example/Private Tool/bin/client",
            displayName: "client"
        )

        let userInfo = PostHandshakeHandler.rejectionNotificationUserInfo(
            host: "api.example.com",
            clientIdentifier: identity.identifier
        )

        #expect(userInfo[TLSMITMNotificationUserInfoKey.host] == "api.example.com")
        #expect(userInfo[TLSMITMNotificationUserInfoKey.clientIdentifier] == identity.identifier)
        #expect(!userInfo.values.contains(where: { $0.contains("/Users/example") }))
    }

    @Test("duplicate TLS rejections suppress only repeated evidence")
    func duplicateRejectionsSuppressOnlyRepeatedEvidence() {
        let tracker = RecentFailureTracker()

        let firstShouldReport = PostHandshakeHandler.shouldReportCertificateRejection(
            host: "api.example.com",
            clientIdentifier: "app.one",
            tracker: tracker
        )
        let duplicateShouldReport = PostHandshakeHandler.shouldReportCertificateRejection(
            host: "api.example.com",
            clientIdentifier: "app.one",
            tracker: tracker
        )

        #expect(firstShouldReport)
        #expect(!duplicateShouldReport)
    }

    @Test("TLS rejection suppression is isolated by both host and client")
    func rejectionSuppressionUsesHostAndClientScope() {
        let tracker = RecentFailureTracker()

        #expect(PostHandshakeHandler.shouldReportCertificateRejection(
            host: "one.example",
            clientIdentifier: "app.one",
            tracker: tracker
        ))
        #expect(PostHandshakeHandler.shouldReportCertificateRejection(
            host: "two.example",
            clientIdentifier: "app.one",
            tracker: tracker
        ))
        #expect(PostHandshakeHandler.shouldReportCertificateRejection(
            host: "one.example",
            clientIdentifier: "app.two",
            tracker: tracker
        ))
    }

    @Test("explicit retry re-arms only the selected client's rejection evidence")
    func scopedRetryRearmsSelectedClient() {
        let tracker = RecentFailureTracker()

        for clientIdentifier in ["app.one", "app.two"] {
            #expect(PostHandshakeHandler.shouldReportCertificateRejection(
                host: "api.example.com",
                clientIdentifier: clientIdentifier,
                tracker: tracker
            ))
            #expect(!PostHandshakeHandler.shouldReportCertificateRejection(
                host: "api.example.com",
                clientIdentifier: clientIdentifier,
                tracker: tracker
            ))
        }

        tracker.reset(clientIdentifiers: ["APP.ONE"])

        #expect(PostHandshakeHandler.shouldReportCertificateRejection(
            host: "api.example.com",
            clientIdentifier: "app.one",
            tracker: tracker
        ))
        #expect(!PostHandshakeHandler.shouldReportCertificateRejection(
            host: "api.example.com",
            clientIdentifier: "app.two",
            tracker: tracker
        ))
    }

    @Test("per-host retry re-arms rejection evidence for every client scope")
    func hostRetryRearmsRejectionEvidence() {
        let host = "retry-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeSSLProxyingManager()

        #expect(PostHandshakeHandler.shouldReportCertificateRejection(
            host: host,
            clientIdentifier: clientIdentifier
        ))
        #expect(!PostHandshakeHandler.shouldReportCertificateRejection(
            host: host,
            clientIdentifier: clientIdentifier
        ))
        manager.markHostForPassthrough(host, clientIdentifier: clientIdentifier)

        #expect(manager.retryInterception(for: host))
        #expect(PostHandshakeHandler.shouldReportCertificateRejection(
            host: host,
            clientIdentifier: clientIdentifier
        ))
    }

    @Test("duplicate certificate errors still execute the real recovery control flow")
    func duplicateCertificateErrorsStillRecover() throws {
        let host = "duplicate-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let tracker = RecentFailureTracker()
        let transactionCount = EventCountBox()
        let notificationCount = EventCountBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .tlsMitmRejected,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?[TLSMITMNotificationUserInfoKey.host] as? String == host,
                  notification.userInfo?[TLSMITMNotificationUserInfoKey.clientIdentifier] as? String
                    == clientIdentifier
            else {
                return
            }
            notificationCount.record()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        for _ in 0 ..< 2 {
            let manager = makeSSLProxyingManager()
            let channel = EmbeddedChannel()
            let handler = PostHandshakeHandler(
                host: host,
                port: 443,
                ruleEngine: RuleEngine(),
                scriptPluginManager: nil,
                connectionLimiter: ConnectionLimiter(),
                sslProxyingManager: manager,
                clientIdentifier: clientIdentifier,
                recentFailureTracker: tracker,
                onTransactionComplete: { _ in transactionCount.record() }
            )
            try channel.pipeline.syncOperations.addHandler(handler)

            channel.pipeline.fireErrorCaught(SyntheticTLSError(description: "tls alert unknown_ca"))
            channel.embeddedEventLoop.run()

            #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
            _ = try? channel.finish()
        }

        #expect(transactionCount.count == 2)
        #expect(notificationCount.count == 1)
    }

    @Test("ambiguous TLS errors prime temporary scoped passthrough for the next connection")
    func ambiguousTLSErrorPrimesTemporaryBypass() throws {
        let host = "ambiguous-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeSSLProxyingManager()
        let recorded = RecordedTransactionBox()
        let channel = EmbeddedChannel()
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            clientIdentifier: clientIdentifier,
            onTransactionComplete: { recorded.record($0) }
        )
        try channel.pipeline.syncOperations.addHandler(handler)

        channel.pipeline.fireErrorCaught(SyntheticTLSError(description: "handshake timed out"))
        channel.embeddedEventLoop.run()

        #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
        #expect(recorded.transaction?.isTLSFailure == true)
        _ = try? channel.finish()
    }

    @Test("client-abandoned TLS handshakes never prime passthrough")
    func abandonedHandshakeDoesNotPrimeBypass() throws {
        let host = "abandoned-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeSSLProxyingManager()
        let recorded = RecordedTransactionBox()
        let channel = EmbeddedChannel()
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            clientIdentifier: clientIdentifier,
            recentFailureTracker: RecentFailureTracker(),
            onTransactionComplete: { recorded.record($0) }
        )
        try channel.pipeline.syncOperations.addHandler(handler)

        channel.pipeline.fireErrorCaught(
            NIOSSLError.handshakeFailed(.sslError([.eofDuringHandshake]))
        )
        channel.embeddedEventLoop.run()

        #expect(!channel.isActive)
        #expect(!manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
        #expect(recorded.transaction == nil)
        _ = try? channel.finish()
    }

    @Test("unresolved local certificate rejection gets a short-lived host fallback")
    func unresolvedCertificateRejectionGetsTransientFallback() throws {
        let host = "unresolved-rejection-\(UUID().uuidString).example"
        let manager = makeSSLProxyingManager()
        let recorded = RecordedTransactionBox()
        let channel = EmbeddedChannel()
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            recentFailureTracker: RecentFailureTracker(),
            onTransactionComplete: { recorded.record($0) }
        )
        try channel.pipeline.syncOperations.addHandler(handler)

        channel.pipeline.fireErrorCaught(SyntheticTLSError(description: "tls alert unknown_ca"))
        channel.embeddedEventLoop.run()

        #expect(manager.isAutoPassthrough(host, clientIdentifier: nil))
        #expect(recorded.transaction?.isTLSFailure == true)
        _ = try? channel.finish()
    }

    @Test("connection reset during TLS handshake retains recovery evidence")
    func connectionResetIsNotTreatedAsAbandonedHandshake() throws {
        let host = "reset-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeSSLProxyingManager()
        let recorded = RecordedTransactionBox()
        let channel = EmbeddedChannel()
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            clientIdentifier: clientIdentifier,
            recentFailureTracker: RecentFailureTracker(),
            onTransactionComplete: { recorded.record($0) }
        )
        try channel.pipeline.syncOperations.addHandler(handler)

        channel.pipeline.fireErrorCaught(SyntheticTLSError(description: "connection reset by peer"))
        channel.embeddedEventLoop.run()

        #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
        #expect(recorded.transaction?.isTLSFailure == true)
        _ = try? channel.finish()
    }

    @Test("strict client certificate alerts use scoped recovery")
    func strictCertificateAlertsUseScopedRecovery() throws {
        for alert in [
            "unsupported_certificate",
            "bad_certificate_hash_value",
        ] {
            let host = "strict-\(alert)-\(UUID().uuidString).example"
            let clientIdentifier = "client-\(UUID().uuidString)"
            let manager = makeSSLProxyingManager()
            let transactionCount = EventCountBox()
            let channel = EmbeddedChannel()
            let handler = PostHandshakeHandler(
                host: host,
                port: 443,
                ruleEngine: RuleEngine(),
                scriptPluginManager: nil,
                connectionLimiter: ConnectionLimiter(),
                sslProxyingManager: manager,
                clientIdentifier: clientIdentifier,
                recentFailureTracker: RecentFailureTracker(),
                onTransactionComplete: { _ in transactionCount.record() }
            )
            try channel.pipeline.syncOperations.addHandler(handler)

            channel.pipeline.fireErrorCaught(SyntheticTLSError(description: alert))
            channel.embeddedEventLoop.run()

            #expect(transactionCount.count == 1)
            #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
            _ = try? channel.finish()
        }
    }

    @Test("known TLS compatibility failures persist scoped passthrough with retry evidence")
    func tlsCompatibilityFailureUsesScopedPassthrough() throws {
        for failure in [
            "certificate_required",
            "sslv3_alert_handshake_failure",
            "no_application_protocol",
        ] {
            let host = "compatibility-\(UUID().uuidString).example"
            let clientIdentifier = "client-\(UUID().uuidString)"
            let manager = makeSSLProxyingManager()
            let transactionCount = EventCountBox()
            let notificationCount = EventCountBox()
            let observer = NotificationCenter.default.addObserver(
                forName: .tlsMitmRejected,
                object: nil,
                queue: nil
            ) { notification in
                if notification.userInfo?[TLSMITMNotificationUserInfoKey.host] as? String == host {
                    notificationCount.record()
                }
            }
            let channel = EmbeddedChannel()
            let handler = PostHandshakeHandler(
                host: host,
                port: 443,
                ruleEngine: RuleEngine(),
                scriptPluginManager: nil,
                connectionLimiter: ConnectionLimiter(),
                sslProxyingManager: manager,
                clientIdentifier: clientIdentifier,
                recentFailureTracker: RecentFailureTracker(),
                onTransactionComplete: { _ in transactionCount.record() }
            )
            try channel.pipeline.syncOperations.addHandler(handler)

            channel.pipeline.fireErrorCaught(SyntheticTLSError(description: failure))
            channel.embeddedEventLoop.run()

            #expect(transactionCount.count == 1)
            #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
            #expect(notificationCount.count == 1)
            NotificationCenter.default.removeObserver(observer)
            _ = try? channel.finish()
        }
    }

    @Test("certificate rejection closes the consumed handshake and primes scoped passthrough")
    func certificateRejectionPrimesNextConnectionPassthrough() throws {
        let host = "production-recovery-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeSSLProxyingManager()
        let recorded = RecordedTransactionBox()
        let clientChannel = EmbeddedChannel()
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            clientIdentifier: clientIdentifier,
            recentFailureTracker: RecentFailureTracker(),
            onTransactionComplete: { recorded.record($0) }
        )
        try clientChannel.pipeline.syncOperations.addHandler(handler)

        clientChannel.pipeline.fireErrorCaught(SyntheticTLSError(description: "tls alert unknown_ca"))
        clientChannel.embeddedEventLoop.run()

        #expect(!clientChannel.isActive)
        #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
        #expect(recorded.transaction?.response?.statusCode == 0)
        #expect(recorded.transaction?.state == .failed)
        #expect(recorded.transaction?.isTLSFailure == true)
        _ = try? clientChannel.finish()
    }

    @Test("ambiguous handshake failures also prime scoped passthrough for the next connection")
    func ambiguousFailurePrimesNextConnectionPassthrough() throws {
        let host = "ambiguous-recovery-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeSSLProxyingManager()
        let clientChannel = EmbeddedChannel()
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            clientIdentifier: clientIdentifier,
            recentFailureTracker: RecentFailureTracker(),
            onTransactionComplete: { _ in }
        )
        try clientChannel.pipeline.syncOperations.addHandler(handler)

        clientChannel.pipeline.fireErrorCaught(SyntheticTLSError(description: "handshake timed out"))
        clientChannel.embeddedEventLoop.run()

        #expect(!clientChannel.isActive)
        #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
        _ = try? clientChannel.finish()
    }

    @Test("scoped passthrough preserves a fragmented real ClientHello and registers its tunnel")
    func scopedPassthroughForwardsFragmentedRealClientHello() throws {
        let host = "registered-\(UUID().uuidString).example"
        let identity = ClientApplicationIdentity.bundle(
            identifier: "client-\(UUID().uuidString)",
            displayName: "TLS Test Client"
        )
        let manager = makeSSLProxyingManager()
        manager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        manager.markHostForPassthrough(host, clientIdentifier: identity.identifier)
        let loop = EmbeddedEventLoop()
        let clientChannel = EmbeddedChannel(handlers: [], loop: loop)
        let serverChannel = EmbeddedChannel(handlers: [], loop: loop)
        let connectorPromise = loop.makePromise(of: Channel.self)
        let registry = LiveTunnelRegistry { host, _ in
            !manager.isAutoPassthrough(host, clientIdentifier: identity.identifier)
        }
        let handler = TLSInterceptHandler(
            host: host,
            port: 443,
            certificateManager: .shared,
            ruleEngine: RuleEngine(),
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            bypassProxyManager: makeBypassProxyManager(),
            clientApplicationIdentity: identity,
            liveTunnelRegistry: registry,
            rawTunnelConnector: { _, _, _, _ in connectorPromise.futureResult },
            onTransactionComplete: { _ in }
        )
        try clientChannel.pipeline.syncOperations.addHandler(handler)

        let clientHello = try makeRealClientHello(host: host)
        let expectedBytes = try #require(
            clientHello.getBytes(at: clientHello.readerIndex, length: clientHello.readableBytes)
        )
        let splitIndex = expectedBytes.count / 2
        var firstFragment = clientChannel.allocator.buffer(capacity: splitIndex)
        firstFragment.writeBytes(expectedBytes[..<splitIndex])
        var secondFragment = clientChannel.allocator.buffer(capacity: expectedBytes.count - splitIndex)
        secondFragment.writeBytes(expectedBytes[splitIndex...])
        try clientChannel.writeInbound(firstFragment)
        try clientChannel.writeInbound(secondFragment)
        connectorPromise.succeed(serverChannel)
        loop.run()

        #expect(registry.trackedTunnelCount() == 1)
        var forwardedFirst = try #require(try serverChannel.readOutbound(as: ByteBuffer.self))
        var forwardedSecond = try #require(try serverChannel.readOutbound(as: ByteBuffer.self))
        let forwardedBytes = (forwardedFirst.readBytes(length: forwardedFirst.readableBytes) ?? [])
            + (forwardedSecond.readBytes(length: forwardedSecond.readableBytes) ?? [])
        #expect(forwardedBytes == expectedBytes)

        #expect(manager.retryInterception(clientIdentifiers: [identity.identifier]) == 1)
        registry.invalidateTunnelsNowRequiringInterception()
        loop.run()
        #expect(!clientChannel.isActive)

        _ = try? clientChannel.finish()
        _ = try? serverChannel.finish()
    }

    @Test("non-TLS raw fallback preserves all bytes received while upstream connects")
    func protocolDetectorRawFallbackPreservesPendingBytes() throws {
        let host = "raw-pending-\(UUID().uuidString).example"
        let loop = EmbeddedEventLoop()
        let clientChannel = EmbeddedChannel(handlers: [], loop: loop)
        let serverChannel = EmbeddedChannel(handlers: [], loop: loop)
        let connectorPromise = loop.makePromise(of: Channel.self)
        let recorded = RecordedTransactionBox()
        let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
        let sslHandler = NIOSSLServerHandler(context: sslContext)
        let postHandshake = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: makeSSLProxyingManager(),
            onTransactionComplete: { recorded.record($0) }
        )
        let detector = ProtocolDetectorHandler(
            sslHandler: sslHandler,
            host: host,
            port: 443,
            postHandshake: postHandshake,
            connectionLimiter: ConnectionLimiter(),
            rawTunnelConnector: { _, _, _, _ in connectorPromise.futureResult }
        )
        try clientChannel.pipeline.syncOperations.addHandlers(detector, sslHandler, postHandshake)

        var first = clientChannel.allocator.buffer(capacity: 4)
        first.writeBytes([0x47, 0x45, 0x54, 0x20])
        var second = clientChannel.allocator.buffer(capacity: 3)
        second.writeBytes([0x2f, 0x0d, 0x0a])
        try clientChannel.writeInbound(first)
        try clientChannel.writeInbound(second)

        connectorPromise.succeed(serverChannel)
        loop.run()

        var forwardedFirst = try #require(try serverChannel.readOutbound(as: ByteBuffer.self))
        var forwardedSecond = try #require(try serverChannel.readOutbound(as: ByteBuffer.self))
        #expect(forwardedFirst.readBytes(length: forwardedFirst.readableBytes) == [0x47, 0x45, 0x54, 0x20])
        #expect(forwardedSecond.readBytes(length: forwardedSecond.readableBytes) == [0x2f, 0x0d, 0x0a])
        #expect(recorded.transaction?.sslCapture == .tunneled)

        _ = try? clientChannel.finish()
        _ = try? serverChannel.finish()
    }

    @Test("scoped passthrough reports oversized buffered data once")
    func scopedPassthroughRejectsOversizedBufferedDataOnce() throws {
        let host = "oversized-scoped-\(UUID().uuidString).example"
        let identity = ClientApplicationIdentity.bundle(
            identifier: "client-\(UUID().uuidString)",
            displayName: "Oversized Test Client"
        )
        let manager = makeSSLProxyingManager()
        manager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        manager.markHostForPassthrough(host, clientIdentifier: identity.identifier)
        let loop = EmbeddedEventLoop()
        let clientChannel = EmbeddedChannel(handlers: [], loop: loop)
        let connectorPromise = loop.makePromise(of: Channel.self)
        let recorded = RecordedTransactionBox()
        let transactionCount = EventCountBox()
        let handler = TLSInterceptHandler(
            host: host,
            port: 443,
            certificateManager: .shared,
            ruleEngine: RuleEngine(),
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            bypassProxyManager: makeBypassProxyManager(),
            clientApplicationIdentity: identity,
            rawTunnelConnector: { _, _, _, _ in connectorPromise.futureResult },
            onTransactionComplete: {
                recorded.record($0)
                transactionCount.record()
            }
        )
        try clientChannel.pipeline.syncOperations.addHandler(handler)

        var oversized = clientChannel.allocator.buffer(
            capacity: TLSInterceptHandler.maximumBufferedTunnelBytes + 1
        )
        oversized.writeBytes(
            repeatElement(UInt8(0x16), count: TLSInterceptHandler.maximumBufferedTunnelBytes + 1)
        )
        try clientChannel.writeInbound(oversized)
        loop.run()

        #expect(!clientChannel.isActive)
        #expect(recorded.transaction?.response?.statusCode == 413)
        #expect(recorded.transaction?.response?.statusMessage == "Tunnel Preface Too Large")
        #expect(transactionCount.count == 1)

        connectorPromise.fail(SyntheticTLSError(description: "late connector failure"))
        loop.run()
        #expect(transactionCount.count == 1)
        _ = try? clientChannel.finish()
    }

    @Test("protocol detector reports oversized pending raw data once")
    func protocolDetectorRejectsOversizedPendingDataOnce() throws {
        let host = "oversized-detector-\(UUID().uuidString).example"
        let loop = EmbeddedEventLoop()
        let clientChannel = EmbeddedChannel(handlers: [], loop: loop)
        let connectorPromise = loop.makePromise(of: Channel.self)
        let recorded = RecordedTransactionBox()
        let transactionCount = EventCountBox()
        let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
        let sslHandler = NIOSSLServerHandler(context: sslContext)
        let postHandshake = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: makeSSLProxyingManager(),
            onTransactionComplete: {
                recorded.record($0)
                transactionCount.record()
            }
        )
        let detector = ProtocolDetectorHandler(
            sslHandler: sslHandler,
            host: host,
            port: 443,
            postHandshake: postHandshake,
            connectionLimiter: ConnectionLimiter(),
            rawTunnelConnector: { _, _, _, _ in connectorPromise.futureResult }
        )
        try clientChannel.pipeline.syncOperations.addHandlers(detector, sslHandler, postHandshake)

        var first = clientChannel.allocator.buffer(capacity: 1)
        first.writeInteger(UInt8(0x47))
        try clientChannel.writeInbound(first)
        var oversized = clientChannel.allocator.buffer(
            capacity: TLSInterceptHandler.maximumBufferedTunnelBytes
        )
        oversized.writeBytes(
            repeatElement(UInt8(0x45), count: TLSInterceptHandler.maximumBufferedTunnelBytes)
        )
        try clientChannel.writeInbound(oversized)
        loop.run()

        #expect(!clientChannel.isActive)
        #expect(recorded.transaction?.response?.statusCode == 413)
        #expect(recorded.transaction?.response?.statusMessage == "Tunnel Preface Too Large")
        #expect(transactionCount.count == 1)

        connectorPromise.fail(SyntheticTLSError(description: "late connector failure"))
        loop.run()
        #expect(transactionCount.count == 1)
        _ = try? clientChannel.finish()
    }

    @Test("empty detector reads wait for protocol bytes")
    func emptyDetectorReadDoesNotCloseTunnel() throws {
        let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
        let sslHandler = NIOSSLServerHandler(context: sslContext)
        let postHandshake = PostHandshakeHandler(
            host: "empty-read.example",
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: makeSSLProxyingManager(),
            onTransactionComplete: { _ in }
        )
        let detector = ProtocolDetectorHandler(
            sslHandler: sslHandler,
            host: "empty-read.example",
            port: 443,
            postHandshake: postHandshake,
            connectionLimiter: ConnectionLimiter()
        )
        let channel = EmbeddedChannel(handler: detector)
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 443)).wait()

        try channel.writeInbound(channel.allocator.buffer(capacity: 0))

        #expect(channel.isActive)
        #expect((try? channel.pipeline.syncOperations.handler(type: ProtocolDetectorHandler.self)) != nil)
        _ = try? channel.finish()
    }

    @Test("protocol detector errors produce a visible failed CONNECT")
    func protocolDetectorErrorProducesFailedTunnel() throws {
        let recorded = RecordedTransactionBox()
        let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
        let sslHandler = NIOSSLServerHandler(context: sslContext)
        let postHandshake = PostHandshakeHandler(
            host: "detector-error.example",
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: makeSSLProxyingManager(),
            onTransactionComplete: { recorded.record($0) }
        )
        let detector = ProtocolDetectorHandler(
            sslHandler: sslHandler,
            host: "detector-error.example",
            port: 443,
            postHandshake: postHandshake,
            connectionLimiter: ConnectionLimiter()
        )
        let channel = EmbeddedChannel(handler: detector)

        channel.pipeline.fireErrorCaught(SyntheticTLSError(description: "detector failed"))
        channel.embeddedEventLoop.run()

        #expect(!channel.isActive)
        #expect(recorded.transaction?.response?.statusCode == 500)
        #expect(recorded.transaction?.response?.statusMessage == "Protocol Detection Failed")
        _ = try? channel.finish()
    }

    @Test("unattributed TLS rejection notifications are bounded per host")
    func unattributedRejectionsAreRateLimited() {
        let tracker = RecentFailureTracker()

        #expect(PostHandshakeHandler.shouldReportCertificateRejection(
            host: "api.example.com",
            clientIdentifier: nil,
            tracker: tracker
        ))
        #expect(!PostHandshakeHandler.shouldReportCertificateRejection(
            host: "API.EXAMPLE.COM",
            clientIdentifier: nil,
            tracker: tracker
        ))
        #expect(tracker.trackedEntryCount == 1)
    }

    @Test("remote clients receive a stable privacy-preserving TLS recovery scope")
    func remoteClientScopeIsStableAndPrivate() {
        let first = ProxyConnectionDescriptor(
            acceptedAt: .now(),
            clientHost: "192.168.1.42",
            clientPort: 54_321,
            proxyHost: "192.168.1.2",
            proxyPort: 9_090
        )
        let second = ProxyConnectionDescriptor(
            acceptedAt: .now(),
            clientHost: "192.168.1.42",
            clientPort: 54_322,
            proxyHost: "192.168.1.2",
            proxyPort: 9_090
        )

        let firstScope = TLSInterceptHandler.clientScopeIdentifier(
            application: nil,
            connectionDescriptor: first
        )
        let secondScope = TLSInterceptHandler.clientScopeIdentifier(
            application: nil,
            connectionDescriptor: second
        )

        #expect(firstScope == secondScope)
        #expect(firstScope?.hasPrefix("remote:") == true)
        #expect(firstScope?.contains("192.168.1.42") == false)
    }

    @Test("local unresolved clients never share a global TLS recovery scope")
    func unresolvedLocalClientHasNoFallbackScope() {
        let descriptor = ProxyConnectionDescriptor(
            acceptedAt: .now(),
            clientHost: "127.0.0.1",
            clientPort: 54_321,
            proxyHost: "127.0.0.1",
            proxyPort: 9_090
        )

        #expect(TLSInterceptHandler.clientScopeIdentifier(
            application: nil,
            connectionDescriptor: descriptor
        ) == nil)
    }

    @Test("bypass proxy list forces raw tunnel before SSL interception")
    func bypassProxyListForcesRawTunnel() {
        let sslManager = makeSSLProxyingManager()
        sslManager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        let bypassManager = makeBypassProxyManager()
        bypassManager.addDomain("gmail.com")

        let mode = TLSInterceptHandler.initialTunnelMode(
            host: "mail.gmail.com",
            sslProxyingManager: sslManager,
            bypassProxyManager: bypassManager
        )

        #expect(mode == .rawTunnel(.bypassProxyList))
    }

    @Test("non-bypassed included host still intercepts")
    func nonBypassedIncludedHostIntercepts() {
        let sslManager = makeSSLProxyingManager()
        sslManager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        let bypassManager = makeBypassProxyManager()

        let mode = TLSInterceptHandler.initialTunnelMode(
            host: "api.example.com",
            sslProxyingManager: sslManager,
            bypassProxyManager: bypassManager
        )

        #expect(mode == .intercept)
    }

    @Test("one application's certificate fallback does not tunnel another application")
    func autoPassthroughDecisionIsApplicationScoped() {
        let sslManager = makeSSLProxyingManager()
        sslManager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        let bypassManager = makeBypassProxyManager()
        let first = ClientApplicationIdentity.bundle(identifier: "app.one", displayName: "One")
        let second = ClientApplicationIdentity.bundle(identifier: "app.two", displayName: "Two")
        sslManager.markHostForPassthrough("shared.example", application: first)

        #expect(TLSInterceptHandler.initialTunnelMode(
            host: "shared.example",
            sslProxyingManager: sslManager,
            bypassProxyManager: bypassManager,
            application: first
        ) == .rawTunnel(.autoPassthrough))
        #expect(TLSInterceptHandler.initialTunnelMode(
            host: "shared.example",
            sslProxyingManager: sslManager,
            bypassProxyManager: bypassManager,
            application: second
        ) == .intercept)
    }

    @Test("unresolved local application fails closed while any application Tunnel rule is active")
    func unresolvedLocalApplicationDoesNotBypassTunnelRules() {
        let sslManager = makeSSLProxyingManager()
        sslManager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        let bypassManager = makeBypassProxyManager()

        let mode = TLSInterceptHandler.initialTunnelMode(
            host: "api.example.com",
            sslProxyingManager: sslManager,
            bypassProxyManager: bypassManager,
            unresolvedApplicationMustTunnel: true
        )

        #expect(mode == .rawTunnel(.unresolvedApplicationIdentity))
    }

    @Test("central raw tunnel setup invokes success callback")
    func completeRawTunnelSetupInvokesSuccess() {
        let clientChannel = EmbeddedChannel()
        let serverChannel = EmbeddedChannel()
        let state = TunnelSetupState()

        TLSInterceptHandler.completeRawTunnelSetup(
            serverChannel: serverChannel,
            clientChannel: clientChannel,
            prepareClientChannel: clientChannel.eventLoop.makeSucceededVoidFuture()
        ) {
            state.recordSuccess()
        } onFailure: { error in
            state.recordError(error)
        }

        #expect(state.successCount == 1)
        #expect(state.receivedError == nil)
        #expect((try? serverChannel.pipeline.syncOperations.handler(type: RawTunnelHandler.self)) != nil)
        #expect((try? clientChannel.pipeline.syncOperations.handler(type: RawTunnelHandler.self)) != nil)

        _ = try? clientChannel.finish()
        _ = try? serverChannel.finish()
    }

    @Test("raw tunnel capture builds successful CONNECT transaction")
    func makeSuccessfulTunnelTransaction() {
        let transaction = TLSInterceptHandler.makeTunnelTransaction(
            host: "example.com",
            port: 443,
            statusCode: 200,
            statusMessage: "Connection Established",
            state: .completed,
            sourcePort: 54_321,
            measuredDuration: 0.125
        )

        #expect(transaction.request.method == "CONNECT")
        #expect(transaction.request.url.absoluteString == "https://example.com:443")
        #expect(transaction.response?.statusCode == 200)
        #expect(transaction.response?.statusMessage == "Connection Established")
        #expect(transaction.state == .completed)
        #expect(transaction.sourcePort == 54_321)
        #expect(transaction.measuredDuration == 0.125)
        #expect(transaction.isTLSFailure == false)
    }

    @Test("CONNECT transaction retains only its privacy-preserving TLS client scope")
    func tunnelTransactionRetainsTLSClientScope() {
        let transaction = TLSInterceptHandler.makeTunnelTransaction(
            host: "example.com",
            port: 443,
            statusCode: 200,
            statusMessage: "Connection Established",
            state: .completed,
            sourcePort: 54_321,
            clientIdentifier: "remote:deadbeef"
        )

        #expect(transaction.tlsClientScopeIdentifier == "remote:deadbeef")
    }

    @Test("raw tunnel capture builds IPv6 CONNECT transaction")
    func makeSuccessfulIPv6TunnelTransaction() {
        let transaction = TLSInterceptHandler.makeTunnelTransaction(
            host: "2001:db8::1",
            port: 443,
            statusCode: 200,
            statusMessage: "Connection Established",
            state: .completed,
            sourcePort: 54_321
        )

        #expect(transaction.request.method == "CONNECT")
        #expect(transaction.request.url.absoluteString == "https://[2001:db8::1]:443")
        #expect(transaction.response?.statusCode == 200)
    }

    @Test("TLS handshake failure keeps failed CONNECT metadata")
    func makeFailedTunnelTransaction() {
        let transaction = TLSInterceptHandler.makeTunnelTransaction(
            host: "bad.example.com",
            port: 443,
            statusCode: 0,
            statusMessage: "TLS Handshake Failed",
            state: .failed,
            sourcePort: 44_321,
            isTLSFailure: true
        )

        #expect(transaction.request.method == "CONNECT")
        #expect(transaction.request.url.absoluteString == "https://bad.example.com:443")
        #expect(transaction.response?.statusCode == 0)
        #expect(transaction.response?.statusMessage == "TLS Handshake Failed")
        #expect(transaction.state == .failed)
        #expect(transaction.sourcePort == 44_321)
        #expect(transaction.isTLSFailure == true)
    }

    @Test("raw tunnel capture is tagged tunneled")
    func rawTunnelCaptureModeTunneled() {
        let transaction = TLSInterceptHandler.makeTunnelTransaction(
            host: "example.com",
            port: 443,
            statusCode: 200,
            statusMessage: "Connection Established",
            state: .completed,
            sourcePort: 54_321,
            sslCapture: .tunneled
        )

        #expect(transaction.sslCapture == .tunneled)
    }

    @Test("non-TLS raw fallback records a tunneled CONNECT")
    func protocolDetectorRawFallbackIsTunneled() {
        let recorded = RecordedTransactionBox()
        let handler = PostHandshakeHandler(
            host: "api.example.com",
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: .shared,
            clientSourcePort: 60_123,
            onTransactionComplete: { transaction in
                recorded.record(transaction)
            }
        )

        handler.recordSuccessfulTunnel()

        #expect(recorded.transaction?.sslCapture == .tunneled)
    }

    @Test("post-handshake helper builds successful CONNECT transaction")
    func postHandshakeSuccessfulTunnelTransaction() {
        let handler = PostHandshakeHandler(
            host: "api.example.com",
            port: 8_443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: .shared,
            clientSourcePort: 60_123,
            onTransactionComplete: { _ in }
        )

        let transaction = handler.makeSuccessfulTunnelTransaction()

        #expect(transaction.request.method == "CONNECT")
        #expect(transaction.request.url.absoluteString == "https://api.example.com:8443")
        #expect(transaction.response?.statusCode == 200)
        #expect(transaction.state == .completed)
        #expect(transaction.sourcePort == 60_123)
    }

    @Test("post-handshake successful tunnel reports transaction downstream")
    func postHandshakeRecordSuccessfulTunnel() {
        let recorded = RecordedTransactionBox()
        let handler = PostHandshakeHandler(
            host: "api.example.com",
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: .shared,
            clientSourcePort: 60_123,
            onTransactionComplete: { transaction in
                recorded.record(transaction)
            }
        )

        handler.recordSuccessfulTunnel()

        #expect(recorded.transaction?.request.method == "CONNECT")
        #expect(recorded.transaction?.response?.statusCode == 200)
        #expect(recorded.transaction?.state == .completed)
        #expect(recorded.transaction?.isTLSFailure == false)
    }

    @Test("post-handshake tunnel failure reports a visible failed CONNECT")
    func postHandshakeRecordTunnelFailure() {
        let recorded = RecordedTransactionBox()
        let handler = PostHandshakeHandler(
            host: "api.example.com",
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: .shared,
            clientSourcePort: 60_123,
            onTransactionComplete: { transaction in
                recorded.record(transaction)
            }
        )

        handler.recordTunnelFailure(statusCode: 502, statusMessage: "Upstream Connection Failed")

        #expect(recorded.transaction?.request.method == "CONNECT")
        #expect(recorded.transaction?.response?.statusCode == 502)
        #expect(recorded.transaction?.response?.statusMessage == "Upstream Connection Failed")
        #expect(recorded.transaction?.state == .failed)
        // Not a TLS handshake failure, so the row stays visible in the request list.
        #expect(recorded.transaction?.isTLSFailure == false)
    }

    @Test("post-handshake fallback reports only its first terminal outcome")
    func postHandshakeRecordsOnlyFirstTunnelOutcome() {
        let recorded = RecordedTransactionBox()
        let transactionCount = EventCountBox()
        let handler = PostHandshakeHandler(
            host: "api.example.com",
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: .shared,
            onTransactionComplete: {
                recorded.record($0)
                transactionCount.record()
            }
        )

        handler.recordTunnelFailure(statusCode: 413, statusMessage: "Tunnel Preface Too Large")
        handler.recordTunnelFailure(statusCode: 502, statusMessage: "Upstream Connection Failed")
        handler.recordSuccessfulTunnel()

        #expect(transactionCount.count == 1)
        #expect(recorded.transaction?.response?.statusCode == 413)
    }

    @Test("rejected raw tunnel reports a visible failed CONNECT instead of closing silently")
    func tlsInterceptRecordTunnelFailure() {
        let recorded = RecordedTransactionBox()
        let handler = TLSInterceptHandler(
            host: "api.example.com",
            port: 8_443,
            certificateManager: .shared,
            ruleEngine: RuleEngine(),
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: makeSSLProxyingManager(),
            bypassProxyManager: makeBypassProxyManager(),
            clientSourcePort: 60_124,
            onTransactionComplete: { transaction in
                recorded.record(transaction)
            }
        )

        handler.recordTunnelFailure(statusCode: 503, statusMessage: "Connection Limit Reached")

        #expect(recorded.transaction?.request.method == "CONNECT")
        #expect(recorded.transaction?.request.url.absoluteString == "https://api.example.com:8443")
        #expect(recorded.transaction?.response?.statusCode == 503)
        #expect(recorded.transaction?.state == .failed)
        #expect(recorded.transaction?.isTLSFailure == false)
    }

    // MARK: Private

    private func makeSSLProxyingManager() -> SSLProxyingManager {
        SSLProxyingManager(
            storageURL: makeTempURL(prefix: "rockxy-tls-ssl-test"),
            passthroughStorageURL: makeTempURL(prefix: "rockxy-tls-passthrough-test")
        )
    }

    private func makeBypassProxyManager() -> BypassProxyManager {
        BypassProxyManager(storageURL: makeTempURL(prefix: "rockxy-tls-bypass-test"))
    }

    private func makeRealClientHello(host: String) throws -> ByteBuffer {
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.certificateVerification = .none
        let context = try NIOSSLContext(configuration: configuration)
        let tlsHandler = try NIOSSLClientHandler(context: context, serverHostname: host)
        let channel = EmbeddedChannel(handler: tlsHandler)
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 443)).wait()
        channel.embeddedEventLoop.run()
        let clientHello = try #require(try channel.readOutbound(as: ByteBuffer.self))
        _ = try? channel.finish()
        return clientHello
    }

    private func makeTempURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }
}
