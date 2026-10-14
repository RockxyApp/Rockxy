import Foundation
import Network
@testable import Rockxy
import Testing

// MARK: - FixturePairingStorage

private struct FixturePairingStorage: BabylonPairingCredentialStorage, Sendable {
    let value: String

    func load() throws -> String? {
        value
    }

    func save(_: String) throws {}
}

// MARK: - BabylonCaptureTCPCompatibilityTests

@Suite("Babylon production TCP compatibility", .serialized)
@MainActor
struct BabylonCaptureTCPCompatibilityTests {
    // MARK: Internal

    @Test("Receiver authenticates fragmented and coalesced SDK fixtures and re-ACKs duplicates")
    func loopbackFramingAndDuplicateDelivery() async throws {
        let token = String(repeating: "a", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let portProbe = try await Self.boundListener()
        let port = try #require(portProbe.port?.rawValue)
        portProbe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let catalog = ProjectCatalog.makeDefault(now: Date(timeIntervalSince1970: 1_725_000_000))
        let repository = TCPFixtureProjectRepository(catalog: catalog)
        let coordinator = MainContentCoordinator(projectCatalogRepository: repository)
        let receiver = BabylonCaptureReceiver(preferredPort: port)
        defer { receiver.stop() }
        receiver.start(coordinator: coordinator, pairingStore: pairingStore)
        try await Self.waitUntilReady(receiver)

        let connection = try Data(contentsOf: Self.fixtureURL("connection.json"))
        let traffic = try Data(contentsOf: Self.fixtureURL("traffic-success.json"))
        let sessionID = "compatibility-session"
        let clientID = "com.example.fixture"
        let encodedConnection = try Self.encoded(
            type: .connection, content: connection, messageID: "connection-1", sequence: 1,
            sessionID: sessionID, clientID: clientID, token: token
        )
        let encodedTraffic = try Self.encoded(
            type: .traffic, content: traffic, messageID: "traffic-success", sequence: 2,
            sessionID: sessionID, clientID: clientID, token: token
        )
        let connectionFrame = try BabylonFrameAccumulator.frame(encodedConnection)
        let trafficFrame = try BabylonFrameAccumulator.frame(encodedTraffic)
        let client = try await Self.connect(port: port)
        let ackReader = BabylonAckReader(token: token)
        try await Self.send(Data(connectionFrame.prefix(3)), on: client)
        try await Task.sleep(for: .milliseconds(20))
        try await Self.send(Data(connectionFrame.dropFirst(3)) + trafficFrame, on: client)
        let firstAck = try await ackReader.next(on: client)
        #expect(firstAck == "connection-1")
        #expect(try await ackReader.next(on: client) == "traffic-success")

        let rejection = try Data(contentsOf: Self.fixtureURL("rejection.json"))
        let rejectionFrame = try Self.encoded(
            type: .error, content: rejection, messageID: "rejection-1", sequence: 3,
            sessionID: sessionID, clientID: clientID, token: token
        )
        let recoveryHeartbeat = try Self.encoded(
            type: .heartbeat, content: Data("{}".utf8), messageID: "after-rejection", sequence: 4,
            sessionID: sessionID, clientID: clientID, token: token
        )
        try await Self.send(
            BabylonFrameAccumulator.frame(rejectionFrame) + BabylonFrameAccumulator.frame(recoveryHeartbeat),
            on: client
        )
        #expect(try await ackReader.next(on: client) == "rejection-1")
        #expect(try await ackReader.next(on: client) == "after-rejection")

        try await Self.send(trafficFrame, on: client)
        let duplicateAck = try await ackReader.next(on: client)
        #expect(duplicateAck == "traffic-success")
        try await Self.send(trafficFrame, on: client)
        client.cancel() // Simulate losing the duplicate acknowledgement during disconnect.
        try await Task.sleep(for: .milliseconds(50))
        receiver.retryListener()
        try await Task.sleep(for: .milliseconds(150))
        try await Self.waitUntilReady(receiver)
        let listenerProbe = try await Self.connect(port: port)
        listenerProbe.cancel()
        let captured = coordinator.transactions.filter {
            $0.request.url.absoluteString == "https://example.test/success"
        }
        #expect(captured.count == 1)

        let reconnect = try await Self.connect(port: port)
        defer { reconnect.cancel() }
        let reconnectAckReader = BabylonAckReader(token: token)
        try await Self.send(trafficFrame, on: reconnect)
        let reconnectAck = try await reconnectAckReader.next(on: reconnect)
        #expect(reconnectAck == "traffic-success")
        let heartbeatFrame = try Self.encoded(
            type: .heartbeat, content: Data("{}".utf8), messageID: "post-restart-heartbeat", sequence: 5,
            sessionID: sessionID, clientID: clientID, token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(heartbeatFrame), on: reconnect)
        #expect(try await reconnectAckReader.next(on: reconnect) == "post-restart-heartbeat")
        try await Task.sleep(for: .milliseconds(100))
        #expect(coordinator.transactions.filter {
            $0.request.url.absoluteString == "https://example.test/success"
        }.count == 1)
    }

    @Test("Incomplete maximum-size frame peer is isolated from a healthy client")
    func incompleteMaximumFramePeerIsolation() async throws {
        let token = String(repeating: "c", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let receiver = BabylonCaptureReceiver(preferredPort: port)
        defer { receiver.stop() }
        receiver.start(coordinator: MainContentCoordinator(), pairingStore: pairingStore)
        try await Self.waitUntilReady(receiver)

        let slowPeer = try await Self.connect(port: port)
        let healthyPeer = try await Self.connect(port: port)
        defer {
            slowPeer.cancel()
            healthyPeer.cancel()
        }
        try await Self.waitForConnectionCount(receiver, expected: 2)

        var declaredLength = UInt64(BabylonCaptureProtocol.maximumFrameSize).bigEndian
        let oversizedPrefix = Data(bytes: &declaredLength, count: MemoryLayout<UInt64>.size)
            + Data(repeating: 0x7F, count: 56 * 1_024)
        let slowPeerClosed = Task { await Self.waitUntilDisconnected(slowPeer) }
        try await Self.send(oversizedPrefix, on: slowPeer)
        await slowPeerClosed.value

        let heartbeat = try Self.encoded(
            type: .heartbeat, content: Data("{}".utf8), messageID: "healthy-after-budget", sequence: 1,
            sessionID: "budget-session", clientID: "budget-client", token: token
        )
        let ackReader = BabylonAckReader(token: token)
        try await Self.send(BabylonFrameAccumulator.frame(heartbeat), on: healthyPeer)
        #expect(try await ackReader.next(on: healthyPeer) == "healthy-after-budget")
    }

    @Test("Concurrent incomplete frames cannot exceed the aggregate buffer budget")
    func aggregateBufferedByteLimitUnderLoad() async throws {
        let token = String(repeating: "f", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let receiver = BabylonCaptureReceiver(preferredPort: port)
        defer { receiver.stop() }
        receiver.start(coordinator: MainContentCoordinator(), pairingStore: pairingStore)
        try await Self.waitUntilReady(receiver)

        let firstPartialPeer = try await Self.connect(port: port)
        let secondPartialPeer = try await Self.connect(port: port)
        defer {
            firstPartialPeer.cancel()
            secondPartialPeer.cancel()
        }
        try await Self.waitForConnectionCount(receiver, expected: 2)

        var declaredLength = UInt64(BabylonCaptureProtocol.maximumFrameSize).bigEndian
        let lengthPrefix = Data(bytes: &declaredLength, count: MemoryLayout<UInt64>.size)
        let partialPayloadSize = BabylonCaptureProtocol.maximumFrameSize / 2 + 40 * 1_024
        let incompleteFrame = lengthPrefix + Data(repeating: 0x7F, count: partialPayloadSize)
        try await Self.send(incompleteFrame, on: firstPartialPeer)
        try await Task.sleep(for: .milliseconds(300))

        do {
            try await Self.send(incompleteFrame, on: secondPartialPeer)
        } catch {
            // The receiver may reject the peer before Network finishes buffering the send.
        }
        try await Self.waitForConnectionCount(receiver, expected: 1)

        let healthyPeer = try await Self.connect(port: port)
        defer { healthyPeer.cancel() }
        let heartbeat = try Self.encoded(
            type: .heartbeat, content: Data("{}".utf8), messageID: "healthy-after-aggregate-limit", sequence: 1,
            sessionID: "aggregate-budget-session", clientID: "aggregate-budget-client", token: token
        )
        let ackReader = BabylonAckReader(token: token)
        try await Self.send(BabylonFrameAccumulator.frame(heartbeat), on: healthyPeer)
        #expect(try await ackReader.next(on: healthyPeer) == "healthy-after-aggregate-limit")
    }

    @Test("gRPC shared fixture is captured as HTTP/2 with protobuf frame and status trailers")
    func grpcFixtureThroughProductionReceiver() async throws {
        let token = String(repeating: "d", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let coordinator = MainContentCoordinator()
        let receiver = BabylonCaptureReceiver(preferredPort: port)
        defer { receiver.stop() }
        receiver.start(coordinator: coordinator, pairingStore: pairingStore)
        try await Self.waitUntilReady(receiver)

        let connection = try await Self.connect(port: port)
        defer { connection.cancel() }
        let ackReader = BabylonAckReader(token: token)
        let sessionID = "grpc-fixture-session"
        let clientID = "com.example.fixture"
        let connectionPayload = try Data(contentsOf: Self.fixtureURL("connection.json"))
        let grpcPayload = try Data(contentsOf: Self.fixtureURL("grpc.json"))
        for (type, payload, id, sequence) in [
            (BabylonCaptureMessageType.connection, connectionPayload, "grpc-connection", UInt64(1)),
            (BabylonCaptureMessageType.traffic, grpcPayload, "traffic-grpc", UInt64(2)),
        ] {
            let frame = try Self.encoded(
                type: type, content: payload, messageID: id, sequence: sequence,
                sessionID: sessionID, clientID: clientID, token: token
            )
            try await Self.send(BabylonFrameAccumulator.frame(frame), on: connection)
            #expect(try await ackReader.next(on: connection) == id)
        }

        try await Self.waitForTransactions(coordinator, expected: 1)
        let transaction = try #require(coordinator.transactions.first {
            $0.request.url.path == "/example.Greeter/SayHello"
        })
        #expect(transaction.request.method == "POST")
        #expect(transaction.request.httpVersion == "HTTP/2")
        #expect(transaction.request.body == Data([0, 0, 0, 0, 2, 8, 1]))
        #expect(transaction.response?.body == Data([0, 0, 0, 0, 2, 8, 2]))
        #expect(transaction.response?.trailers?.contains { $0.name == "grpc-status" && $0.value == "0" } == true)
    }

    @Test("Receiver stop and restart accepts a fresh SDK session")
    func receiverRestartAcceptsFreshSession() async throws {
        let token = String(repeating: "e", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let coordinator = MainContentCoordinator()
        let receiver = BabylonCaptureReceiver(preferredPort: port)
        let sessionID = "receiver-restart-session"
        let clientID = "com.example.fixture"
        let connection = try Data(contentsOf: Self.fixtureURL("connection.json"))
        let traffic = try Data(contentsOf: Self.fixtureURL("traffic-success.json"))
        receiver.start(coordinator: coordinator, pairingStore: pairingStore)
        try await Self.waitUntilReady(receiver)

        let firstClient = try await Self.connect(port: port)
        let firstReader = BabylonAckReader(token: token)
        for (type, content, messageID, sequence) in [
            (BabylonCaptureMessageType.connection, connection, "restart-connection", UInt64(1)),
            (BabylonCaptureMessageType.traffic, traffic, "restart-traffic", UInt64(2)),
        ] {
            let frame = try Self.encoded(
                type: type, content: content, messageID: messageID, sequence: sequence,
                sessionID: sessionID, clientID: clientID, token: token
            )
            try await Self.send(BabylonFrameAccumulator.frame(frame), on: firstClient)
            #expect(try await firstReader.next(on: firstClient) == messageID)
        }
        firstClient.cancel()
        try await Self.waitForTransactions(coordinator, expected: 1)
        receiver.stop()
        try await Self.waitUntilStopped(receiver)

        receiver.start(coordinator: coordinator, pairingStore: pairingStore)
        try await Self.waitUntilReady(receiver)
        let replayClient = try await Self.connect(port: port)
        defer {
            replayClient.cancel()
            receiver.stop()
        }
        let replayReader = BabylonAckReader(token: token)
        let replayFrame = try Self.encoded(
            type: .connection, content: connection, messageID: "restart-new-connection", sequence: 1,
            sessionID: "receiver-restarted-session", clientID: clientID, token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(replayFrame), on: replayClient)
        #expect(try await replayReader.next(on: replayClient) == "restart-new-connection")
        let secondTraffic = try Self.encoded(
            type: .traffic, content: traffic, messageID: "restart-new-traffic", sequence: 2,
            sessionID: "receiver-restarted-session", clientID: clientID, token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(secondTraffic), on: replayClient)
        #expect(try await replayReader.next(on: replayClient) == "restart-new-traffic")
        try await Self.waitForTransactions(coordinator, expected: 2)
        #expect(coordinator.transactions.filter {
            $0.request.url.absoluteString == "https://example.test/success"
        }.count == 2)
    }

    @Test("Malformed peer does not interrupt a second valid client")
    func malformedPeerIsolation() async throws {
        let token = String(repeating: "b", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let receiver = BabylonCaptureReceiver(preferredPort: port)
        defer { receiver.stop() }
        receiver.start(coordinator: MainContentCoordinator(), pairingStore: pairingStore)
        try await Self.waitUntilReady(receiver)
        BabylonRuntimeEventStore.shared.clear()

        let invalidPeer = try await Self.connect(port: port)
        let validPeer = try await Self.connect(port: port)
        var loadPeers: [NWConnection] = []
        for _ in 0 ..< 6 {
            try await loadPeers.append(Self.connect(port: port))
        }
        defer {
            invalidPeer.cancel()
            validPeer.cancel()
            loadPeers.forEach { $0.cancel() }
        }
        try await Self.waitForConnectionCount(receiver, expected: 8)
        let overflowPeer = try await Self.connect(port: port)
        defer { overflowPeer.cancel() }
        let overflowPeerClosed = Task { await Self.waitUntilDisconnected(overflowPeer) }
        await overflowPeerClosed.value

        var oversizedLength = UInt64(BabylonCaptureProtocol.maximumFrameSize + 1).bigEndian
        let invalidHeader = Data(bytes: &oversizedLength, count: MemoryLayout<UInt64>.size)
        let malformedPeerClosed = Task { await Self.waitUntilDisconnected(invalidPeer) }
        try await Self.send(invalidHeader, on: invalidPeer)
        await malformedPeerClosed.value

        let oldCredentialAckReader = BabylonAckReader(token: token)
        let heartbeatFrame = try Self.encoded(
            type: .heartbeat, content: Data("{}".utf8), messageID: "isolated-heartbeat", sequence: 1,
            sessionID: "isolation-session", clientID: "isolation-client", token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(heartbeatFrame), on: validPeer)
        #expect(try await oldCredentialAckReader.next(on: validPeer) == "isolated-heartbeat")

        let establishedPeerClosed = Task { await Self.waitUntilDisconnected(validPeer) }
        pairingStore.regenerate()
        let rotatedToken = pairingStore.currentToken()
        #expect(rotatedToken != token)
        await establishedPeerClosed.value

        let stalePeer = try await Self.connect(port: port)
        defer { stalePeer.cancel() }
        let stalePeerClosed = Task { await Self.waitUntilDisconnected(stalePeer) }
        let staleFrame = try Self.encoded(
            type: .heartbeat, content: Data("{}".utf8), messageID: "stale-token-heartbeat", sequence: 1,
            sessionID: "rotated-session", clientID: "rotated-client", token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(staleFrame), on: stalePeer)
        await stalePeerClosed.value

        let rotatedPeer = try await Self.connect(port: port)
        defer { rotatedPeer.cancel() }
        let rotatedAckReader = BabylonAckReader(token: rotatedToken)
        let connectionFixture = try Data(contentsOf: Self.fixtureURL("connection.json"))
        let runtimeFixture = try Data(contentsOf: Self.fixtureURL("runtime.json"))
        let connectionFrame = try Self.encoded(
            type: .connection, content: connectionFixture, messageID: "rotated-connection", sequence: 1,
            sessionID: "rotated-session", clientID: "com.example.fixture", token: rotatedToken
        )
        let runtimeFrame = try Self.encoded(
            type: .runtime, content: runtimeFixture, messageID: "runtime-event-1", sequence: 2,
            sessionID: "rotated-session", clientID: "com.example.fixture", token: rotatedToken
        )
        try await Self.send(BabylonFrameAccumulator.frame(connectionFrame), on: rotatedPeer)
        #expect(try await rotatedAckReader.next(on: rotatedPeer) == "rotated-connection")
        try await Self.send(BabylonFrameAccumulator.frame(runtimeFrame), on: rotatedPeer)
        #expect(try await rotatedAckReader.next(on: rotatedPeer) == "runtime-event-1")

        receiver.stop()
        try await Self.waitUntilStopped(receiver)
        #expect(BabylonRuntimeEventStore.shared.events.contains { $0.packageID == "runtime-event-1" })
    }

    // MARK: Private

    private static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/BabylonProtocol/v1")
            .appendingPathComponent(name)
    }

    private static func waitForConnectionCount(
        _ receiver: BabylonCaptureReceiver,
        expected: Int
    )
        async throws
    {
        for _ in 0 ..< 100 {
            if receiver.openConnectionCount == expected {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Babylon receiver did not reach the expected connection count")
    }

    private static func waitForTransactions(
        _ coordinator: MainContentCoordinator,
        expected: Int
    )
        async throws
    {
        for _ in 0 ..< 100 {
            if coordinator.transactions.count >= expected {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Babylon receiver did not publish the expected transactions")
    }

    private static func waitUntilDisconnected(_ connection: NWConnection) async {
        let disconnected = AsyncStream<Void> { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .cancelled,
                     .failed:
                    continuation.yield()
                    continuation.finish()
                default:
                    break
                }
            }
            switch connection.state {
            case .cancelled,
                 .failed:
                continuation.yield()
                continuation.finish()
            default:
                break
            }
        }
        for await _ in disconnected {
            return
        }
    }

    private static func waitUntilStopped(_ receiver: BabylonCaptureReceiver) async throws {
        for _ in 0 ..< 100 {
            if receiver.listenerStatus == .stopped, receiver.listeningPort == nil {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Babylon TCP receiver did not stop")
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

    private static func connect(port: UInt16) async throws -> NWConnection {
        let connection = try NWConnection(
            host: "127.0.0.1",
            port: #require(NWEndpoint.Port(rawValue: port)),
            using: .tcp
        )
        let ready = AsyncStream<Void> { continuation in
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    continuation.yield()
                    continuation.finish()
                } else if case .failed = state {
                    continuation.finish()
                }
            }
        }
        connection.start(queue: .global())
        for await _ in ready {
            return connection
        }
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

    private static func waitUntilReady(_ receiver: BabylonCaptureReceiver) async throws {
        for _ in 0 ..< 100 {
            if receiver.listenerStatus == .ready, receiver.listeningPort != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Babylon TCP receiver did not become ready")
    }
}

// MARK: - TCPFixtureProjectRepository

private actor TCPFixtureProjectRepository: ProjectCatalogPersisting {
    // MARK: Lifecycle

    init(catalog: ProjectCatalog) {
        self.catalog = catalog
    }

    // MARK: Internal

    let catalog: ProjectCatalog

    func load() async throws -> ProjectCatalog {
        catalog
    }

    func save(_: ProjectCatalog) async throws {}
    func reset() async throws -> ProjectCatalog {
        catalog
    }
}

// MARK: - BabylonAckReader

@MainActor
private final class BabylonAckReader {
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
