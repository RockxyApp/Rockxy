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

// MARK: - TLSInterceptHandlerTests

@MainActor
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
