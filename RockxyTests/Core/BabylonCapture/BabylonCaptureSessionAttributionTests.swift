import Foundation
import Network
@testable import Rockxy
import Testing

// MARK: - AttributionPairingStorage

private struct AttributionPairingStorage: BabylonPairingCredentialStorage, Sendable {
    let value: String

    func load() throws -> String? {
        value
    }

    func save(_: String) throws {}
}

// MARK: - BabylonCaptureSessionAttributionTests

/// Nothing in the frame format ties a TCP connection to a single session ID, so a connection
/// can carry frames for more than one. The receiver used to keep only the last key it saw on
/// the connection, which made a disconnect finish the last session's open rows and leave every
/// earlier session's rows active for the rest of the run.
@Suite("Babylon session attribution", .serialized)
@MainActor
struct BabylonCaptureSessionAttributionTests {
    // MARK: Internal

    @Test("One connection carrying two session IDs finishes each session's own open rows")
    func twoSessionsOnOneConnectionFinishTheirOwnRows() async throws {
        let token = String(repeating: "e", count: 64)
        let pairingStore = BabylonPairingStore(storage: AttributionPairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let coordinator = MainContentCoordinator()
        coordinator.configureBabylonCaptureIntake()
        let suiteName = "BabylonSessionAttribution-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let receiver = BabylonCaptureReceiver(preferredPort: port, defaults: defaults)
        defer {
            receiver.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
        receiver.start(coordinator: coordinator, pairingStore: pairingStore)
        receiver.setEnabled(true)
        try await Self.waitUntilReady(receiver)

        let client = try await Self.connect(receiver: receiver)
        let ackReader = AttributionAckReader(token: token)
        let clientID = "com.example.twosession"
        let connectionPayload = try Data(contentsOf: Self.connectionFixtureURL())
        // Both sessions travel over the SAME TCP connection. The replay guard is per session,
        // so each one starts its own sequence at 1.
        for (sessionID, label) in [("session-first", "first"), ("session-second", "second")] {
            let handshake = try Self.encoded(
                type: .connection, content: connectionPayload, messageID: "\(label)-connection", sequence: 1,
                sessionID: sessionID, clientID: clientID, token: token
            )
            try await Self.send(BabylonFrameAccumulator.frame(handshake), on: client)
            #expect(try await ackReader.next(on: client) == "\(label)-connection")

            let openFrame = try Self.encoded(
                type: .websocket, content: Self.openWebSocketPayload(label: label),
                messageID: "\(label)-websocket", sequence: 2,
                sessionID: sessionID, clientID: clientID, token: token
            )
            try await Self.send(BabylonFrameAccumulator.frame(openFrame), on: client)
            #expect(try await ackReader.next(on: client) == "\(label)-websocket")
        }
        try await Self.waitForTransactions(coordinator, expected: 2)
        #expect(coordinator.transactions.allSatisfy { $0.state == .active })

        client.cancel()
        for _ in 0 ..< 100 where coordinator.transactions.contains(where: { $0.state == .active }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        for label in ["first", "second"] {
            let row = try #require(coordinator.transactions.first {
                $0.request.url.absoluteString == "wss://example.test/\(label)"
            })
            #expect(row.state == .failed)
            #expect(row.connectionLog?.failure?.message == "The app disconnected before the WebSocket closed")
        }
        receiver.stop()
    }

    // MARK: Private

    /// A WebSocket package with a frame but no response or end time, so the row it creates
    /// stays active until something finishes it.
    private static func openWebSocketPayload(label: String) throws -> Data {
        let request = BabylonTrafficPackageDTO.Request(
            url: "wss://example.test/\(label)",
            method: "GET",
            headers: [],
            body: nil
        )
        let message = BabylonTrafficPackageDTO.WebSocketMessage(
            id: "\(label)-ping",
            createdAt: 1.5,
            messageType: .ping,
            stringValue: nil,
            dataValue: Data("ping".utf8)
        )
        let package = BabylonTrafficPackageDTO(
            id: "\(label)-parent",
            startAt: 1,
            request: request,
            response: nil,
            error: nil,
            responseBodyData: Data(),
            endAt: nil,
            packageType: .websocket,
            correlationContext: nil,
            urlSessionTiming: nil,
            websocketMessagePackage: message,
            grpcCapture: nil
        )
        return try BabylonCaptureProtocol.encoder.encode(package)
    }

    private static func connectionFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/BabylonProtocol/v1/connection.json")
    }

    private static func encoded(
        type: BabylonCaptureMessageType,
        content: Data,
        messageID: String,
        sequence: UInt64,
        sessionID: String,
        clientID: String,
        token: String
    )
        throws -> Data
    {
        let payload = BabylonPayloadEnvelope(messageType: type, sentAt: 1_725_000_000, content: content)
        return try BabylonSecureFrameCodec.encodeFrame(
            payload: payload,
            messageID: messageID,
            sessionID: sessionID,
            clientID: clientID,
            sequence: sequence,
            pairingToken: token,
            nonceData: Data(repeating: UInt8(truncatingIfNeeded: sequence), count: 12)
        )
    }

    private static func waitForTransactions(_ coordinator: MainContentCoordinator, expected: Int) async throws {
        for _ in 0 ..< 100 {
            if coordinator.transactions.count >= expected {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Babylon receiver did not publish the expected transactions")
    }

    private static func waitUntilReady(_ receiver: BabylonCaptureReceiver) async throws {
        for _ in 0 ..< 100 {
            if receiver.listenerStatus == .ready, receiver.listeningPort != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Babylon receiver never became ready")
    }

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
            return listener
        }
        throw BabylonCaptureProtocolError.invalidFrame
    }

    private static func connect(receiver: BabylonCaptureReceiver) async throws -> NWConnection {
        // Hoisted into two steps: a `#require` nested inside another `#require` expands
        // recursively and does not compile. `NWConnection.init` does not throw -- the `try`
        // belongs to the requirements, not to it.
        let listeningPort = try #require(receiver.listeningPort)
        let port = try #require(NWEndpoint.Port(rawValue: listeningPort))
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let ready = AsyncThrowingStream<Void, Error> { continuation in
            let timeout = DispatchWorkItem {
                continuation.finish(throwing: BabylonCaptureProtocolError.invalidFrame)
                connection.cancel()
            }
            continuation.onTermination = { _ in timeout.cancel() }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.yield()
                    continuation.finish()
                case let .failed(error),
                     let .waiting(error):
                    continuation.finish(throwing: error)
                case .cancelled:
                    continuation.finish(throwing: CancellationError())
                default:
                    break
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(5), execute: timeout)
        }
        connection.start(queue: .global())
        do {
            for try await _ in ready {
                return connection
            }
        } catch {
            connection.cancel()
            throw error
        }
        connection.cancel()
        throw BabylonCaptureProtocolError.invalidFrame
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

// MARK: - AttributionAckReader

@MainActor
private final class AttributionAckReader {
    // MARK: Lifecycle

    init(token: String) {
        self.token = token
    }

    // MARK: Internal

    func next(on connection: NWConnection) async throws -> String {
        while frames.isEmpty {
            let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { data, _, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: BabylonCaptureProtocolError.invalidFrame)
                    }
                }
            }
            frames += try accumulator.append(data)
        }
        let frameData = frames.removeFirst()
        let (_, payload) = try BabylonSecureFrameCodec.decodeFrame(frameData, pairingToken: token)
        #expect(payload.messageType == .ack)
        return try BabylonCaptureProtocol.decoder.decode(BabylonAcknowledgement.self, from: payload.content).messageID
    }

    // MARK: Private

    private let token: String
    private var accumulator = BabylonFrameAccumulator()
    private var frames: [Data] = []
}
