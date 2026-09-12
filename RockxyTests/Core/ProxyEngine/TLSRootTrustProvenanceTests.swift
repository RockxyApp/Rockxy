import Foundation
import NIOCore
import NIOEmbedded
import NIOSSL
import NIOTLS
@testable import Rockxy
import Testing

@MainActor
@Suite(.serialized)
struct TLSRootTrustProvenanceTests {
    @Test("custom server identity success does not clear Root CA rejection state")
    func customIdentitySuccessDoesNotProveRootCATrust() throws {
        let host = "custom-identity-\(UUID().uuidString).example"
        let staleHost = "stale-root-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeManager()
        let tracker = RecentFailureTracker()
        let notificationCount = LockedEventCount()
        manager.markHostForPassthrough(staleHost, clientIdentifier: clientIdentifier)
        _ = tracker.recordFailure(host: staleHost, clientIdentifier: clientIdentifier)
        let observer = NotificationCenter.default.addObserver(
            forName: .tlsMitmAccepted,
            object: nil,
            queue: nil
        ) { notification in
            if notification.userInfo?[TLSMITMNotificationUserInfoKey.host] as? String == host {
                notificationCount.record()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let channel = EmbeddedChannel()
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            clientIdentifier: clientIdentifier,
            provesRootCATrust: false,
            recentFailureTracker: tracker,
            onTransactionComplete: { _ in }
        )
        try channel.pipeline.syncOperations.addHandler(handler)

        channel.pipeline.fireUserInboundEventTriggered(
            TLSUserEvent.handshakeCompleted(negotiatedProtocol: nil)
        )
        channel.embeddedEventLoop.run()

        #expect(manager.isAutoPassthrough(staleHost, clientIdentifier: clientIdentifier))
        #expect(tracker.trackedEntryCount == 1)
        #expect(notificationCount.value == 0)
        _ = try? channel.finish()
    }

    @Test("custom server identity rejection does not create Root CA rejection evidence")
    func customIdentityRejectionDoesNotBlameRootCA() throws {
        let host = "custom-rejection-\(UUID().uuidString).example"
        let clientIdentifier = "client-\(UUID().uuidString)"
        let manager = makeManager()
        let tracker = RecentFailureTracker()
        let notificationCount = LockedEventCount()
        let observer = NotificationCenter.default.addObserver(
            forName: .tlsMitmRejected,
            object: nil,
            queue: nil
        ) { notification in
            if notification.userInfo?[TLSMITMNotificationUserInfoKey.host] as? String == host {
                notificationCount.record()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let channel = EmbeddedChannel()
        let handler = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: manager,
            clientIdentifier: clientIdentifier,
            provesRootCATrust: false,
            recentFailureTracker: tracker,
            onTransactionComplete: { _ in }
        )
        try channel.pipeline.syncOperations.addHandler(handler)

        channel.pipeline.fireErrorCaught(CustomIdentityTLSError())
        channel.embeddedEventLoop.run()

        #expect(manager.isAutoPassthrough(host, clientIdentifier: clientIdentifier))
        #expect(tracker.trackedEntryCount == 0)
        #expect(notificationCount.value == 0)
        _ = try? channel.finish()
    }

    private func makeManager() -> SSLProxyingManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTLSRootTrust-\(UUID().uuidString)", isDirectory: true)
        return SSLProxyingManager(
            storageURL: directory.appendingPathComponent("settings.json"),
            passthroughStorageURL: directory.appendingPathComponent("passthrough.json")
        )
    }
}

private struct CustomIdentityTLSError: Error, CustomStringConvertible {
    let description = "tls alert unknown_ca"
}

private final class LockedEventCount: @unchecked Sendable {
    var value: Int {
        lock.withLock { count }
    }

    func record() {
        lock.withLock { count += 1 }
    }

    private let lock = NSLock()
    private var count = 0
}
