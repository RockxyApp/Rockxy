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
        let runtime = try decoder.decode(
            BabylonRuntimePackageDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("runtime.json"))
        )

        #expect(connection.project.bundleIdentifier == "com.example.fixture")
        #expect(success.id == "traffic-success")
        #expect(success.correlationContext?.traceID == "trace-success")
        #expect(failure.error?.code == -1_001)
        #expect(websocket.packageType == .websocket)
        #expect(grpc.request.method == "GRPC")
        #expect(grpc.request.url == "/example.Greeter/SayHello")
        #expect(grpc.request.body == Data([0x08, 0x01]))
        #expect(grpc.responseBodyData == Data([0x08, 0x02]))
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
