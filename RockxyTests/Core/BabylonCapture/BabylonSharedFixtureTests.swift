import Foundation
@testable import Rockxy
import Testing

@Suite("Shared Babylon protocol fixtures")
struct BabylonSharedFixtureTests {
    @Test("Versioned payload fixtures decode into receiver models")
    func sharedFixturesDecode() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // BabylonCapture/
            .deletingLastPathComponent() // Core/
            .deletingLastPathComponent() // RockxyTests/
            .appendingPathComponent("Fixtures/BabylonProtocol/v1")
        let decoder = JSONDecoder()
        let connection = try decoder.decode(
            BabylonConnectionPackageDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("connection.json"))
        )
        let success = try decoder.decode(
            BabylonTrafficPackageDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("traffic-success.json"))
        )
        let failure = try decoder.decode(
            BabylonTrafficPackageDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("traffic-error.json"))
        )
        let websocket = try decoder.decode(
            BabylonTrafficPackageDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("websocket.json"))
        )
        let grpc = try decoder.decode(
            BabylonTrafficPackageDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("grpc.json"))
        )
        let timing = try decoder.decode(
            BabylonTrafficPackageDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("url-session-timing.json"))
        )
        let runtime = try decoder.decode(
            BabylonRuntimePackageDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("runtime.json"))
        )

        #expect(connection.project.bundleIdentifier == "com.example.fixture")
        #expect(connection.capabilities?.sdkVersion == "1.0.0")
        #expect(connection.capabilities?.platform == "iOS")
        #expect(connection.capabilities?.payloadSchemaVersions["grpcCapture"] == 1)
        #expect(connection.capabilities?.payloadSchemaVersions["urlSessionTiming"] == 1)
        #expect(connection.capabilities?.maximumBodyBytes == 52_428_800)
        #expect(connection.capabilities?.supportedTrafficTypes == ["http", "websocket", "grpc"])
        #expect(success.id == "traffic-success")
        #expect(success.startAt == 1_725_000_000)
        #expect(success.packageType == .http)
        #expect(success.correlationContext?.traceID == "trace-success")
        #expect(success.urlSessionTiming == nil)
        #expect(failure.error?.code == -1_001)
        #expect(failure.requestBodyOmission?.reason == "bodyLimit")
        #expect(failure.requestBodyOmission?.observedBytes == 4_096)
        #expect(failure.requestBodyOmission?.originalBytes == 8_192)
        #expect(websocket.packageType == .websocket)
        #expect(grpc.request.method == "POST")
        #expect(grpc.packageType == .grpc)
        #expect(grpc.grpcCapture?.schemaVersion == 1)
        #expect(grpc.grpcCapture?.callType == .unary)
        #expect(grpc.request.url == "/example.Greeter/SayHello")
        #expect(grpc.request.body == Data([0x08, 0x01]))
        #expect(grpc.responseBodyData == Data([0x08, 0x02]))
        #expect(timing.urlSessionTiming?.schemaVersion == 1)
        #expect(timing.urlSessionTiming?.redirectCount == 1)
        #expect(timing.urlSessionTiming?.transactions.map(\.index) == [0, 1])
        #expect(timing.urlSessionTiming?.transactions.first?.secureConnectDuration == nil)
        #expect(timing.urlSessionTiming?.transactions.last?.reusedConnection == true)
        let identity = BabylonCaptureIdentity(
            clientID: "fixture-client",
            sessionID: "fixture-session",
            projectName: "Fixture",
            bundleIdentifier: "com.example.fixture",
            deviceName: "Fixture Device",
            deviceModel: "Test"
        )
        let transaction = try BabylonCaptureMapper.makeTransaction(from: grpc, identity: identity)
        #expect(transaction.babylonGRPCCallType == "unary")
        let inspection = try #require(GRPCDetector.detect(
            request: transaction.request,
            response: transaction.response,
            timingInfo: transaction.timingInfo,
            measuredDuration: transaction.measuredDuration,
            callType: transaction.babylonGRPCCallType
        ))
        #expect(inspection.callType == "unary")
        #expect(runtime.id == "runtime-event-1")
        let acknowledgement = try decoder.decode(
            BabylonAcknowledgement.self,
            from: Data(contentsOf: directory.appendingPathComponent("ack.json"))
        )
        let rejection = try decoder.decode(
            BabylonProtocolErrorPayload.self,
            from: Data(contentsOf: directory.appendingPathComponent("rejection.json"))
        )
        #expect(acknowledgement.messageID == "traffic-success")
        #expect(rejection.code == "unsupported_version")
    }
}
