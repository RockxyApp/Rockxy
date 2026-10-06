import Foundation
import Network
@testable import Rockxy
import Testing

// MARK: - BabylonCaptureReceiverPortTests

/// A second Rockxy (or any app) holding the fixed Babylon port must not leave this one without a
/// listener: devices discover the Mac over Bonjour, which carries whatever port was bound.
@Suite(.serialized)
@MainActor
struct BabylonCaptureReceiverPortTests {
    @Test("When the preferred port is taken the receiver listens on another port")
    func fallsBackWhenPortIsTaken() async throws {
        let holder = try await Self.boundListener()
        defer { holder.cancel() }
        let takenPort = try #require(holder.port?.rawValue)

        let receiver = BabylonCaptureReceiver(preferredPort: takenPort)
        defer { receiver.stop() }
        receiver.startListening()

        try await Self.waitUntilReady(receiver)
        let bound = try #require(receiver.listeningPort)
        #expect(bound != takenPort)
        #expect(receiver.isUsingFallbackPort)
    }

    @Test("A free preferred port is used as is")
    func usesFreePreferredPort() async throws {
        let probe = try await Self.boundListener()
        let freePort = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(200))

        let receiver = BabylonCaptureReceiver(preferredPort: freePort)
        defer { receiver.stop() }
        receiver.startListening()

        try await Self.waitUntilReady(receiver)
        #expect(receiver.listeningPort == freePort)
        #expect(!receiver.isUsingFallbackPort)
    }

    @Test("Only address-in-use errors trigger the fallback")
    func detectsAddressInUse() {
        #expect(BabylonCaptureReceiver.isAddressInUse(.posix(.EADDRINUSE)))
        #expect(!BabylonCaptureReceiver.isAddressInUse(.posix(.EACCES)))
        #expect(!BabylonCaptureReceiver.isAddressInUse(.dns(0)))
    }

    // MARK: Private

    private static func boundListener() async throws -> NWListener {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = AsyncStream<Void> { continuation in
            listener.stateUpdateHandler = { state in
                if case .ready = state {
                    continuation.yield()
                    continuation.finish()
                }
            }
        }
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: .global())
        for await _ in ready {
            break
        }
        return listener
    }

    private static func waitUntilReady(_ receiver: BabylonCaptureReceiver) async throws {
        for _ in 0 ..< 100 {
            if receiver.listenerStatus == .ready, receiver.listeningPort != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Listener did not become ready: \(receiver.listenerStatus)")
    }
}
