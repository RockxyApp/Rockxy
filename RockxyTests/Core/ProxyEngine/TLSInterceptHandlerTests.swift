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
            sourcePort: 54_321
        )

        #expect(transaction.request.method == "CONNECT")
        #expect(transaction.request.url.absoluteString == "https://example.com:443")
        #expect(transaction.response?.statusCode == 200)
        #expect(transaction.response?.statusMessage == "Connection Established")
        #expect(transaction.state == .completed)
        #expect(transaction.sourcePort == 54_321)
        #expect(transaction.isTLSFailure == false)
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
}
