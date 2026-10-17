import Foundation
import Network
import os
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
        coordinator.configureBabylonCaptureIntake()
        let (defaults, suiteName) = try Self.isolatedDefaults()
        let receiver = BabylonCaptureReceiver(preferredPort: port, defaults: defaults)
        defer {
            receiver.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
        receiver.start(coordinator: coordinator, pairingStore: pairingStore)
        receiver.setEnabled(true)
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
        try await Self.waitForTransactions(coordinator, expected: 1)
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
        try await Self.waitForTransactions(coordinator, expected: 1)
        #expect(coordinator.transactions.filter {
            $0.request.url.absoluteString == "https://example.test/success"
        }.count == 1)
        try await Self.stopAndWait(receiver)
    }

    @Test("Incomplete maximum-size frame peer is isolated from a healthy client")
    func incompleteMaximumFramePeerIsolation() async throws {
        let token = String(repeating: "c", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let (defaults, suiteName) = try Self.isolatedDefaults()
        let receiver = BabylonCaptureReceiver(preferredPort: port, defaults: defaults)
        defer {
            receiver.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
        receiver.start(coordinator: MainContentCoordinator(), pairingStore: pairingStore)
        receiver.setEnabled(true)
        try await Self.waitUntilReady(receiver)

        let slowPeer = try await Self.connect(port: port)
        let healthyPeer = try await Self.connect(port: port)
        defer {
            slowPeer.cancel()
            healthyPeer.cancel()
        }
        try await Self.waitForConnectionCount(receiver, expected: 2)

        var declaredLength = UInt64(BabylonCaptureProtocol.maximumFrameSize).bigEndian
        let incompletePrefix = Data(bytes: &declaredLength, count: MemoryLayout<UInt64>.size)
            + Data(repeating: 0x7F, count: 56 * 1_024)
        try await Self.send(incompletePrefix, on: slowPeer)

        let heartbeat = try Self.encoded(
            type: .heartbeat, content: Data("{}".utf8), messageID: "healthy-after-budget", sequence: 1,
            sessionID: "budget-session", clientID: "budget-client", token: token
        )
        let ackReader = BabylonAckReader(token: token)
        try await Self.send(BabylonFrameAccumulator.frame(heartbeat), on: healthyPeer)
        #expect(try await ackReader.next(on: healthyPeer) == "healthy-after-budget")
        #expect(receiver.openConnectionCount == 2)
        try await Self.stopAndWait(receiver)
    }

    @Test("Concurrent incomplete frames cannot exceed the aggregate buffer budget")
    func aggregateBufferedByteLimitUnderLoad() async throws {
        let token = String(repeating: "f", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let (defaults, suiteName) = try Self.isolatedDefaults()
        let receiver = BabylonCaptureReceiver(preferredPort: port, defaults: defaults)
        defer {
            receiver.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
        receiver.start(coordinator: MainContentCoordinator(), pairingStore: pairingStore)
        receiver.setEnabled(true)
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
        try await Self.stopAndWait(receiver)
    }

    @Test("WebSocket frames received before upgrade are kept when the parent closes")
    func websocketPreUpgradeFrameSurvivesParentUpdate() async throws {
        let token = String(repeating: "b", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let coordinator = MainContentCoordinator()
        coordinator.configureBabylonCaptureIntake()
        let (defaults, suiteName) = try Self.isolatedDefaults()
        let receiver = BabylonCaptureReceiver(preferredPort: port, defaults: defaults)
        defer {
            receiver.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
        receiver.start(coordinator: coordinator, pairingStore: pairingStore)
        receiver.setEnabled(true)
        try await Self.waitUntilReady(receiver)

        let client = try await Self.connect(port: port)
        defer { client.cancel() }
        let ackReader = BabylonAckReader(token: token)
        let sessionID = "websocket-pre-upgrade-session"
        let clientID = "com.example.websocket"
        let connectionPayload = try Data(contentsOf: Self.fixtureURL("connection.json"))
        let connectionFrame = try Self.encoded(
            type: .connection, content: connectionPayload, messageID: "websocket-connection", sequence: 1,
            sessionID: sessionID, clientID: clientID, token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(connectionFrame), on: client)
        #expect(try await ackReader.next(on: client) == "websocket-connection")

        let request = BabylonTrafficPackageDTO.Request(
            url: "wss://example.test/socket",
            method: "GET",
            headers: [],
            body: nil
        )
        let earlyMessage = BabylonTrafficPackageDTO.WebSocketMessage(
            id: "websocket-early-ping",
            createdAt: 1.5,
            messageType: .ping,
            stringValue: nil,
            dataValue: Data("ping".utf8)
        )
        let earlyPackage = BabylonTrafficPackageDTO(
            id: "websocket-parent",
            startAt: 1,
            request: request,
            response: nil,
            error: nil,
            responseBodyData: Data(),
            endAt: nil,
            packageType: .websocket,
            correlationContext: nil,
            urlSessionTiming: nil,
            websocketMessagePackage: earlyMessage,
            grpcCapture: nil
        )
        let earlyPayload = try BabylonCaptureProtocol.encoder.encode(earlyPackage)
        let earlyFrame = try Self.encoded(
            type: .websocket, content: earlyPayload, messageID: "websocket-early-frame", sequence: 2,
            sessionID: sessionID, clientID: clientID, token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(earlyFrame), on: client)
        #expect(try await ackReader.next(on: client) == "websocket-early-frame")

        let completedPackage = BabylonTrafficPackageDTO(
            id: "websocket-parent",
            startAt: 1,
            request: request,
            response: .init(statusCode: 101, headers: [.init(key: "Upgrade", value: "websocket")]),
            error: nil,
            responseBodyData: Data(),
            endAt: 2,
            packageType: .websocket,
            correlationContext: nil,
            urlSessionTiming: nil,
            websocketMessagePackage: nil,
            grpcCapture: nil
        )
        let completedPayload = try BabylonCaptureProtocol.encoder.encode(completedPackage)
        let completedFrame = try Self.encoded(
            type: .websocket, content: completedPayload, messageID: "websocket-upgrade-complete", sequence: 3,
            sessionID: sessionID, clientID: clientID, token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(completedFrame), on: client)
        #expect(try await ackReader.next(on: client) == "websocket-upgrade-complete")

        try await Self.waitForTransactions(coordinator, expected: 1)
        let transaction = try #require(coordinator.transactions.first {
            $0.request.url.absoluteString == "wss://example.test/socket"
        })
        let connection = try #require(transaction.webSocketConnection)
        #expect(transaction.state == .completed)
        #expect(transaction.response?.statusCode == 101)
        #expect(connection.frameCount == 1)
        #expect(connection.frames.first?.direction == .sent)
        #expect(connection.frames.first?.opcode == .ping)
        #expect(connection.frames.first?.payload == Data("ping".utf8))
        try await Self.stopAndWait(receiver)
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
        coordinator.configureBabylonCaptureIntake()
        let (defaults, suiteName) = try Self.isolatedDefaults()
        let receiver = BabylonCaptureReceiver(preferredPort: port, defaults: defaults)
        defer {
            receiver.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
        receiver.start(coordinator: coordinator, pairingStore: pairingStore)
        receiver.setEnabled(true)
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
        try await Self.stopAndWait(receiver)
    }

    @Test("Production receiver preserves all gRPC call types and ordered message directions")
    func allGRPCCallTypesThroughProductionReceiver() async throws {
        let token = String(repeating: "e", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let coordinator = MainContentCoordinator()
        coordinator.configureBabylonCaptureIntake()
        let (defaults, suiteName) = try Self.isolatedDefaults()
        let receiver = BabylonCaptureReceiver(preferredPort: port, defaults: defaults)
        defer {
            receiver.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
        receiver.start(coordinator: coordinator, pairingStore: pairingStore)
        receiver.setEnabled(true)
        try await Self.waitUntilReady(receiver)

        let connection = try await Self.connect(port: port)
        defer { connection.cancel() }
        let ackReader = BabylonAckReader(token: token)
        let sessionID = "grpc-call-types-session"
        let clientID = "com.example.fixture"
        let connectionPayload = try Data(contentsOf: Self.fixtureURL("connection.json"))
        let connectionFrame = try Self.encoded(
            type: .connection, content: connectionPayload, messageID: "grpc-call-types-connection", sequence: 1,
            sessionID: sessionID, clientID: clientID, token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(connectionFrame), on: connection)
        #expect(try await ackReader.next(on: connection) == "grpc-call-types-connection")

        let fixture = try Data(contentsOf: Self.fixtureURL("grpc.json"))
        let baseObject = try #require(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        let callCases: [(type: String, messages: [(direction: String, sequence: Int, value: UInt8)])] = [
            ("unary", [("request", 0, 1), ("response", 0, 9)]),
            ("clientStreaming", [("request", 0, 1), ("request", 1, 2), ("response", 0, 9)]),
            ("serverStreaming", [("request", 0, 1), ("response", 0, 9), ("response", 1, 10)]),
            (
                "bidirectionalStreaming",
                [("request", 0, 1), ("response", 0, 9), ("request", 1, 2), ("response", 1, 10)]
            ),
        ]

        for (index, call) in callCases.enumerated() {
            var payloadObject = baseObject
            var grpcCapture = try #require(payloadObject["grpcCapture"] as? [String: Any])
            let endpoint = "/example.Greeter/\(call.type)"
            grpcCapture["callType"] = call.type
            grpcCapture["endpoint"] = endpoint
            grpcCapture["messages"] = call.messages.map { message in
                [
                    "sequence": message.sequence,
                    "direction": message.direction,
                    "data": Data([8, message.value]).base64EncodedString(),
                    "observedBytes": 2,
                    "omitted": false,
                    "compressed": false,
                    "timestamp": 1_725_000_000.1 + Double(message.sequence) / 10,
                ] as [String: Any]
            }
            payloadObject["grpcCapture"] = grpcCapture
            payloadObject["id"] = "traffic-grpc-\(call.type)"
            var request = try #require(payloadObject["request"] as? [String: Any])
            request["url"] = endpoint
            payloadObject["request"] = request

            let payload = try JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys])
            let messageID = "traffic-grpc-\(call.type)"
            let frame = try Self.encoded(
                type: .traffic, content: payload, messageID: messageID, sequence: UInt64(index + 2),
                sessionID: sessionID, clientID: clientID, token: token
            )
            try await Self.send(BabylonFrameAccumulator.frame(frame), on: connection)
            #expect(try await ackReader.next(on: connection) == messageID)
        }

        try await Self.waitForTransactions(coordinator, expected: callCases.count)
        for call in callCases {
            let endpoint = "/example.Greeter/\(call.type)"
            let transaction = try #require(coordinator.transactions.first { $0.request.url.path == endpoint })
            #expect(transaction.request.httpVersion == "HTTP/2")
            #expect(transaction.babylonGRPCCallType == call.type)
            #expect(transaction.response?.trailers?.contains { $0.name == "grpc-status" && $0.value == "0" } == true)

            var expectedRequestBody = Data()
            for message in call.messages.filter({ $0.direction == "request" })
                .sorted(by: { $0.sequence < $1.sequence })
            {
                expectedRequestBody.append(contentsOf: [0, 0, 0, 0, 2, 8, message.value])
            }
            var expectedResponseBody = Data()
            for message in call.messages.filter({ $0.direction == "response" })
                .sorted(by: { $0.sequence < $1.sequence })
            {
                expectedResponseBody.append(contentsOf: [0, 0, 0, 0, 2, 8, message.value])
            }
            #expect(transaction.request.body == expectedRequestBody)
            #expect(transaction.response?.body == expectedResponseBody)

            let inspection = GRPCDetector.detect(
                request: transaction.request,
                response: transaction.response,
                timingInfo: transaction.timingInfo,
                measuredDuration: transaction.measuredDuration,
                callType: transaction.babylonGRPCCallType
            )
            #expect(inspection?.callType == call.type)
            #expect(inspection?.requestFrames.count == call.messages.count(where: { $0.direction == "request" }))
            #expect(inspection?.responseFrames.count == call.messages.count(where: { $0.direction == "response" }))
        }
        try await Self.stopAndWait(receiver)
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
        coordinator.configureBabylonCaptureIntake()
        let (defaults, suiteName) = try Self.isolatedDefaults()
        let receiver = BabylonCaptureReceiver(preferredPort: port, defaults: defaults)
        defer {
            receiver.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let sessionID = "receiver-restart-session"
        let clientID = "com.example.fixture"
        let connection = try Data(contentsOf: Self.fixtureURL("connection.json"))
        let traffic = try Data(contentsOf: Self.fixtureURL("traffic-success.json"))
        receiver.start(coordinator: coordinator, pairingStore: pairingStore)
        receiver.setEnabled(true)
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
        try await Self.stopAndWait(receiver)
    }

    @Test("Malformed peer isolation survives credential rotation and stop flushes final runtime event")
    func malformedPeerIsolation() async throws {
        let token = String(repeating: "b", count: 64)
        let pairingStore = BabylonPairingStore(storage: FixturePairingStorage(value: token))
        let probe = try await Self.boundListener()
        let port = try #require(probe.port?.rawValue)
        probe.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let (defaults, suiteName) = try Self.isolatedDefaults()
        let receiver = BabylonCaptureReceiver(
            preferredPort: port,
            defaults: defaults,
            runtimeFlushMaxLatency: .seconds(5)
        )
        defer {
            receiver.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
        receiver.start(coordinator: MainContentCoordinator(), pairingStore: pairingStore)
        receiver.setEnabled(true)
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
        try await Self.waitUntilRemoteClose(overflowPeer, label: "overflow peer")

        var oversizedLength = UInt64(BabylonCaptureProtocol.maximumFrameSize + 1).bigEndian
        let invalidHeader = Data(bytes: &oversizedLength, count: MemoryLayout<UInt64>.size)
        try await Self.send(invalidHeader, on: invalidPeer)
        try await Self.waitUntilRemoteClose(invalidPeer, label: "malformed peer")
        try await Self.waitForConnectionCount(receiver, expected: 7)

        let oldCredentialAckReader = BabylonAckReader(token: token)
        let heartbeatFrame = try Self.encoded(
            type: .heartbeat, content: Data("{}".utf8), messageID: "isolated-heartbeat", sequence: 1,
            sessionID: "isolation-session", clientID: "isolation-client", token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(heartbeatFrame), on: validPeer)
        #expect(try await oldCredentialAckReader.next(on: validPeer) == "isolated-heartbeat")

        pairingStore.regenerate()
        let rotatedToken = pairingStore.currentToken()
        #expect(rotatedToken != token)
        try await Self.waitUntilRemoteClose(validPeer, label: "peer with rotated credential")

        let stalePeer = try await Self.connect(port: port)
        defer { stalePeer.cancel() }
        let staleFrame = try Self.encoded(
            type: .heartbeat, content: Data("{}".utf8), messageID: "stale-token-heartbeat", sequence: 1,
            sessionID: "rotated-session", clientID: "rotated-client", token: token
        )
        try await Self.send(BabylonFrameAccumulator.frame(staleFrame), on: stalePeer)
        try await Self.waitUntilRemoteClose(stalePeer, label: "stale credential peer")

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

        #expect(!BabylonRuntimeEventStore.shared.events.contains { $0.packageID == "runtime-event-1" })
        receiver.stop()
        try await Self.waitUntilStopped(receiver)
        #expect(BabylonRuntimeEventStore.shared.events.contains { $0.packageID == "runtime-event-1" })
    }

    // MARK: Private

    private static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/BabylonProtocol/v1")
            .appendingPathComponent(name)
    }

    private static func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "BabylonCaptureTCP-\(UUID().uuidString)"
        return try (#require(UserDefaults(suiteName: suiteName)), suiteName)
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
        throw BabylonTCPCompatibilityTestError.connectionCount(
            expected: expected,
            actual: receiver.openConnectionCount
        )
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

    private static func waitUntilRemoteClose(_ connection: NWConnection, label: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completed = OSAllocatedUnfairLock(initialState: false)
            let timeout = DispatchWorkItem {
                let shouldResume = completed.withLock { didComplete -> Bool in
                    guard !didComplete else {
                        return false
                    }
                    didComplete = true
                    return true
                }
                guard shouldResume else {
                    return
                }
                continuation.resume(
                    throwing: BabylonTCPCompatibilityTestError.connectionStillOpen(
                        label: label,
                        state: connection.state
                    )
                )
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(5), execute: timeout)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, isComplete, error in
                let shouldResume = completed.withLock { didComplete -> Bool in
                    guard !didComplete else {
                        return false
                    }
                    didComplete = true
                    return true
                }
                guard shouldResume else {
                    return
                }
                timeout.cancel()
                if error != nil || isComplete || data == nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BabylonTCPCompatibilityTestError.unexpectedData(label: label))
                }
            }
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

    private static func stopAndWait(_ receiver: BabylonCaptureReceiver) async throws {
        receiver.stop()
        try await waitUntilStopped(receiver)
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

// MARK: - BabylonTCPCompatibilityTestError

private enum BabylonTCPCompatibilityTestError: Error, LocalizedError {
    case connectionCount(expected: Int, actual: Int)
    case connectionStillOpen(label: String, state: NWConnection.State)
    case unexpectedData(label: String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .connectionCount(expected, actual):
            "Babylon receiver connection count was \(actual), expected \(expected)."
        case let .connectionStillOpen(label, state):
            "Babylon TCP \(label) remained in state \(state) after the 5 second deadline."
        case let .unexpectedData(label):
            "Babylon TCP \(label) received data from an overloaded listener."
        }
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
