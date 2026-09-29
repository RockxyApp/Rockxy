import Foundation
@testable import Rockxy
import Testing

// MARK: - AndroidEmulatorProxyControllerTests

struct AndroidEmulatorProxyControllerTests {
    // MARK: Internal

    @Test("Only online emulators are listed; devices and unauthorized entries are skipped")
    func parsesEmulators() {
        let output = """
        List of devices attached
        emulator-5554\tdevice
        emulator-5556\toffline
        R58M123ABC\tdevice
        emulator-5558\tunauthorized
        emulator-5560 device product:sdk_gphone64_arm64

        """

        #expect(AndroidEmulatorProxyController.parseEmulators(output).map(\.serial) == ["emulator-5554", "emulator-5560"])
        #expect(!AndroidEmulatorProxyController.isEmulatorSerial("emulator-55x4"))
    }

    @Test("adb is found in ANDROID_HOME before Android Studio's default SDK")
    func locatesADB() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let controller = AndroidEmulatorProxyController(
            environment: ["ANDROID_HOME": "/opt/sdk"],
            homeDirectory: home,
            isExecutable: { $0 == "/opt/sdk/platform-tools/adb" || $0.hasPrefix("/Users/tester") }
        )
        #expect(controller.adbURL()?.path == "/opt/sdk/platform-tools/adb")

        let studioOnly = AndroidEmulatorProxyController(
            environment: [:],
            homeDirectory: home,
            isExecutable: { $0.hasPrefix("/Users/tester") }
        )
        #expect(studioOnly.adbURL()?.path == "/Users/tester/Library/Android/sdk/platform-tools/adb")

        let none = AndroidEmulatorProxyController(environment: [:], homeDirectory: home, isExecutable: { _ in false })
        #expect(none.adbURL() == nil)
    }

    @Test("Routing sets the host alias proxy and pushes the certificate; revert clears the proxy")
    func routeAndRevertCommands() async {
        let runner = RecordingADBRunner()
        let controller = AndroidEmulatorProxyController(
            runner: runner,
            environment: ["ANDROID_HOME": "/opt/sdk"],
            isExecutable: { _ in true }
        )
        let emulator = AndroidEmulator(serial: "emulator-5554")
        let device = AndroidEmulator(serial: "R58M123ABC")

        let routed = await controller.routeThroughRockxy([emulator, device], proxyPort: 9_090, certificatePEM: "PEM")
        let reverted = await controller.revertProxy([emulator])

        let commands = runner.commands
        #expect(commands.count == 3)
        #expect(commands[0] == ["-s", "emulator-5554", "shell", "settings", "put", "global", "http_proxy", "10.0.2.2:9090"])
        #expect(Array(commands[1].prefix(3)) == ["-s", "emulator-5554", "push"])
        #expect(commands[1].last == "/sdcard/Download/rockxy-root-ca.pem")
        #expect(commands[2] == ["-s", "emulator-5554", "shell", "settings", "put", "global", "http_proxy", ":0"])
        #expect(routed[device] == nil)
        if case .success = routed[emulator] {} else {
            Issue.record("route should succeed")
        }
        if case .success = reverted[emulator] {} else {
            Issue.record("revert should succeed")
        }
    }

    @Test("A missing adb reports a clear error for every emulator")
    func missingADB() async {
        let controller = AndroidEmulatorProxyController(environment: [:], isExecutable: { _ in false })
        let emulator = AndroidEmulator(serial: "emulator-5554")

        let results = await controller.revertProxy([emulator])
        let failures = await AndroidEmulatorSetupFlow.summarize([emulator], results)

        #expect(results[emulator].map { if case .failure(.adbUnavailable) = $0 { true } else { false } } == true)
        #expect(failures.count == 1)
    }
}

// MARK: - RecordingADBRunner

private final class RecordingADBRunner: SimulatorCommandRunning, @unchecked Sendable {
    var commands: [[String]] {
        lock.withLock { recorded }
    }

    func run(executable _: URL, arguments: [String]) async throws -> SimulatorCommandOutput {
        lock.withLock { recorded.append(arguments) }
        return SimulatorCommandOutput(status: 0, standardOutput: Data(), standardError: Data())
    }

    private let lock = NSLock()
    private var recorded: [[String]] = []
}
