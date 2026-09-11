import Foundation
import NIOCore
import NIOEmbedded
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

    @Test("duplicate certificate errors still execute the real recovery control flow")
    func duplicateCertificateErrorsStillRecover() throws {
        let host = "duplicate-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let tracker = RecentFailureTracker()
        let recoveryCount = EventCountBox()
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
                handshakeFailureRecovery: { recoveryCount.record() },
                onTransactionComplete: { _ in }
            )
            try channel.pipeline.syncOperations.addHandler(handler)

            channel.pipeline.fireErrorCaught(SyntheticTLSError(description: "tls alert unknown_ca"))
            channel.embeddedEventLoop.run()

            #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
            _ = try? channel.finish()
        }

        #expect(recoveryCount.count == 2)
        #expect(notificationCount.count == 1)
    }

    @Test("ambiguous TLS errors recover through one-connection passthrough")
    func ambiguousTLSErrorRecoversWithoutPersistentBypass() throws {
        let host = "ambiguous-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeSSLProxyingManager()
        let recoveryCount = EventCountBox()
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
            handshakeFailureRecovery: { recoveryCount.record() },
            onTransactionComplete: { recorded.record($0) }
        )
        try channel.pipeline.syncOperations.addHandler(handler)

        channel.pipeline.fireErrorCaught(SyntheticTLSError(description: "handshake timed out"))
        channel.embeddedEventLoop.run()

        #expect(recoveryCount.count == 1)
        #expect(!manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
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
            let recoveryCount = EventCountBox()
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
                handshakeFailureRecovery: { recoveryCount.record() },
                onTransactionComplete: { _ in }
            )
            try channel.pipeline.syncOperations.addHandler(handler)

            channel.pipeline.fireErrorCaught(SyntheticTLSError(description: alert))
            channel.embeddedEventLoop.run()

            #expect(recoveryCount.count == 1)
            #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
            _ = try? channel.finish()
        }
    }

    @Test("known TLS compatibility failures persist scoped passthrough without trust evidence")
    func tlsCompatibilityFailureUsesScopedPassthrough() throws {
        for failure in [
            "certificate_required",
            "sslv3_alert_handshake_failure",
            "no_application_protocol",
        ] {
            let host = "compatibility-\(UUID().uuidString).example"
            let clientIdentifier = "client-\(UUID().uuidString)"
            let manager = makeSSLProxyingManager()
            let recoveryCount = EventCountBox()
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
                handshakeFailureRecovery: { recoveryCount.record() },
                onTransactionComplete: { _ in }
            )
            try channel.pipeline.syncOperations.addHandler(handler)

            channel.pipeline.fireErrorCaught(SyntheticTLSError(description: failure))
            channel.embeddedEventLoop.run()

            #expect(recoveryCount.count == 1)
            #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
            #expect(notificationCount.count == 0)
            NotificationCenter.default.removeObserver(observer)
            _ = try? channel.finish()
        }
    }

    @Test("certificate rejection executes the production recovery tunnel path")
    func certificateRejectionExecutesProductionRecoveryPath() throws {
        let host = "production-recovery-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeSSLProxyingManager()
        let limiter = ConnectionLimiter(maxPerDestination: 1)
        let recorded = RecordedTransactionBox()
        let loop = EmbeddedEventLoop()
        let clientChannel = EmbeddedChannel(handlers: [], loop: loop)
        let serverChannel = EmbeddedChannel(handlers: [], loop: loop)
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 443)
        try clientChannel.connect(to: address).wait()
        try serverChannel.connect(to: address).wait()
        let registry = LiveTunnelRegistry { _, _ in false }
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: limiter,
            sslProxyingManager: manager,
            clientIdentifier: clientIdentifier,
            liveTunnelRegistry: registry,
            recentFailureTracker: RecentFailureTracker(),
            recoveryTunnelConnector: { eventLoop, _, _, _ in
                eventLoop.makeSucceededFuture(serverChannel)
            },
            onTransactionComplete: { recorded.record($0) }
        )
        try clientChannel.pipeline.syncOperations.addHandler(handler)

        clientChannel.pipeline.fireErrorCaught(SyntheticTLSError(description: "tls alert unknown_ca"))
        loop.run()

        #expect(recorded.transaction?.response?.statusCode == 200)
        #expect(recorded.transaction?.response?.statusMessage == "Tunneled — Client Rejected Certificate")
        #expect(recorded.transaction?.state == .completed)
        #expect(recorded.transaction?.sslCapture == .tunneled)
        #expect(recorded.transaction?.isTLSFailure == false)
        #expect(registry.trackedTunnelCount() == 1)
        let acquiredWhileTunnelWasOpen = limiter.acquire(host: host, port: 443)
        #expect(!acquiredWhileTunnelWasOpen)
        if acquiredWhileTunnelWasOpen {
            limiter.release(host: host, port: 443)
        }

        serverChannel.close(promise: nil)
        loop.run()
        #expect(registry.trackedTunnelCount() == 0)
        #expect(limiter.acquire(host: host, port: 443))
        limiter.release(host: host, port: 443)

        _ = try? clientChannel.finish()
        _ = try? serverChannel.finish()
    }

    @Test("production recovery reports upstream connection failure and releases its limiter slot")
    func productionRecoveryHandlesUpstreamFailure() throws {
        let host = "recovery-failure-\(UUID().uuidString).example"
        let limiter = ConnectionLimiter(maxPerDestination: 1)
        let recorded = RecordedTransactionBox()
        let loop = EmbeddedEventLoop()
        let clientChannel = EmbeddedChannel(handlers: [], loop: loop)
        try clientChannel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 443)).wait()
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: limiter,
            sslProxyingManager: makeSSLProxyingManager(),
            clientIdentifier: "client-\(UUID().uuidString)",
            recentFailureTracker: RecentFailureTracker(),
            recoveryTunnelConnector: { eventLoop, _, _, _ in
                eventLoop.makeFailedFuture(SyntheticTLSError(description: "upstream unavailable"))
            },
            onTransactionComplete: { recorded.record($0) }
        )
        try clientChannel.pipeline.syncOperations.addHandler(handler)

        clientChannel.pipeline.fireErrorCaught(SyntheticTLSError(description: "tls alert unknown_ca"))
        loop.run()

        #expect(recorded.transaction?.response?.statusCode == 502)
        #expect(recorded.transaction?.response?.statusMessage == "Upstream Connection Failed")
        #expect(recorded.transaction?.state == .failed)
        #expect(recorded.transaction?.isTLSFailure == false)
        #expect(limiter.acquire(host: host, port: 443))
        limiter.release(host: host, port: 443)

        _ = try? clientChannel.finish()
    }

    @Test("production recovery reports a visible limit refusal without opening upstream")
    func productionRecoveryHandlesConnectionLimit() throws {
        let host = "recovery-limited-\(UUID().uuidString).example"
        let limiter = ConnectionLimiter(maxPerDestination: 1)
        #expect(limiter.acquire(host: host, port: 443))
        let connectorCount = EventCountBox()
        let recorded = RecordedTransactionBox()
        let loop = EmbeddedEventLoop()
        let clientChannel = EmbeddedChannel(handlers: [], loop: loop)
        try clientChannel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 443)).wait()
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: limiter,
            sslProxyingManager: makeSSLProxyingManager(),
            clientIdentifier: "client-\(UUID().uuidString)",
            recentFailureTracker: RecentFailureTracker(),
            recoveryTunnelConnector: { eventLoop, _, _, _ in
                connectorCount.record()
                return eventLoop.makeFailedFuture(SyntheticTLSError(description: "must not connect"))
            },
            onTransactionComplete: { recorded.record($0) }
        )
        try clientChannel.pipeline.syncOperations.addHandler(handler)

        clientChannel.pipeline.fireErrorCaught(SyntheticTLSError(description: "tls alert unknown_ca"))
        loop.run()

        #expect(connectorCount.count == 0)
        #expect(recorded.transaction?.response?.statusCode == 503)
        #expect(recorded.transaction?.response?.statusMessage == "Connection Limit Reached")
        #expect(recorded.transaction?.state == .failed)
        #expect(recorded.transaction?.isTLSFailure == false)
        limiter.release(host: host, port: 443)

        _ = try? clientChannel.finish()
    }

    @Test("certificate-rejection fallback registers its live tunnel for retry invalidation")
    func certificateRejectionFallbackRegistersLiveTunnel() throws {
        let host = "registered-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeSSLProxyingManager()
        manager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        manager.markHostForPassthrough(host, clientIdentifier: clientIdentifier)
        let clientChannel = EmbeddedChannel()
        let registry = LiveTunnelRegistry { host, _ in
            !manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier)
        }
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            clientIdentifier: clientIdentifier,
            liveTunnelRegistry: registry,
            recentFailureTracker: RecentFailureTracker(),
            onTransactionComplete: { _ in }
        )
        handler.registerRecoveryTunnel(
            channel: clientChannel,
            reason: .certificateRejection,
            decisionGeneration: registry.currentGeneration()
        )

        #expect(registry.trackedTunnelCount() == 1)

        #expect(manager.retryInterception(clientIdentifiers: [clientIdentifier]) == 1)
        registry.invalidateTunnelsNowRequiringInterception()
        clientChannel.embeddedEventLoop.run()
        #expect(!clientChannel.isActive)

        _ = try? clientChannel.finish()
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

    private func makeTempURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }
}
