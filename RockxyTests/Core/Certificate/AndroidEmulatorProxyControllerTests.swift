import Foundation
@testable import Rockxy
import Testing

// MARK: - AndroidEmulatorProxyControllerTests

struct AndroidEmulatorProxyControllerTests {
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

        #expect(AndroidEmulatorProxyController.parseEmulators(output).map(\.serial) == [
            "emulator-5554",
            "emulator-5560"
        ])
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

    @Test("adb from Homebrew's Android command-line tools is found without ANDROID_HOME")
    func locatesHomebrewCommandLineToolsADB() {
        let path = "/opt/homebrew/share/android-commandlinetools/platform-tools/adb"
        let controller = AndroidEmulatorProxyController(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/tester"),
            isExecutable: { $0 == path }
        )
        #expect(controller.adbURL()?.path == path)
    }

    @Test("The system CA file name matches OpenSSL's legacy subject hash")
    func systemCertificateFileName() throws {
        #expect(try AndroidSystemTrust.certificateFileName(certificatePEM: Self.testCAPEM) == "5e7ceb16.0")
        #expect(throws: (any Error).self) {
            try AndroidSystemTrust.certificateFileName(certificatePEM: "not a certificate")
        }
    }

    @Test("Chrome gets a user CA copy, and revert removes only a byte-identical copy")
    func chromeUserStoreCopyIsAddedAndRemovedSafely() {
        let store = AndroidSystemTrust.userStoreDirectory
        #expect(store == "/data/misc/user/0/cacerts-added")
        let install = AndroidSystemTrust.installScript
        #expect(install.contains("if [ ! -f \"$USER_CA/$NAME\" ]; then"))
        #expect(install.contains("chown system:system \"$USER_CA\" \"$USER_CA/$NAME\""))
        #expect(install.contains("misc_user_data_file"))
        let remove = AndroidSystemTrust.removeScript
        #expect(remove.contains("ADDED=\(store)/${CERT##*/}"))
        #expect(remove.contains("cmp -s \"$CERT\" \"$ADDED\"; then rm -f \"$ADDED\""))
        // The user copy is removed before the work directory that holds the reference copy.
        let removal = remove.range(of: "rm -f \"$ADDED\"")?.lowerBound
        let cleanup = remove.range(of: "rm -rf \"$WORK\"")?.lowerBound
        #expect(removal.flatMap { first in cleanup.map { first < $0 } } == true)
    }

    @Test("System trust roots the emulator, pushes the certificate and script, and needs the success marker")
    func systemTrustCommands() async {
        let runner = ScriptedADBRunner { arguments in
            if arguments.suffix(2) == ["id", "-u"] {
                return "0\n"
            }
            if arguments.contains("sh") {
                return "ROCKXY_SYSTEM_CA_OK\n"
            }
            return ""
        }
        let controller = AndroidEmulatorProxyController(
            runner: runner,
            environment: ["ANDROID_HOME": "/opt/sdk"],
            isExecutable: { _ in true }
        )
        let emulator = AndroidEmulator(serial: "emulator-5554")
        let device = AndroidEmulator(serial: "R58M123ABC")

        let results = await controller.trustSystemWide([emulator, device], certificatePEM: Self.testCAPEM)

        let commands = runner.commands
        #expect(results[device] == nil)
        #expect(results[emulator].map {
            if case .success = $0 {
                true
            } else {
                false
            }
        } == true)
        #expect(!commands.contains { $0.contains("root") })
        #expect(commands.contains { $0.contains("push") && $0.last == "/data/local/tmp/rockxy-ca/5e7ceb16.0" })
        #expect(commands.last == [
            "-s",
            "emulator-5554",
            "shell",
            "sh",
            "/data/local/tmp/rockxy-ca/rockxy-trust.sh",
            "5e7ceb16.0"
        ])
    }

    @Test("An emulator that refuses root reports it, and a script error is surfaced")
    func systemTrustFailures() async {
        let unrootable = ScriptedADBRunner { arguments in
            arguments.suffix(2) == ["id", "-u"] ? "2000\n" : "adbd cannot run as root in production builds\n"
        }
        let emulator = AndroidEmulator(serial: "emulator-5554")
        let refused = await AndroidEmulatorProxyController(
            runner: unrootable,
            environment: ["ANDROID_HOME": "/opt/sdk"],
            isExecutable: { _ in true }
        ).trustSystemWide([emulator], certificatePEM: Self.testCAPEM)
        #expect(refused[emulator].map {
            if case .failure(.rootUnavailable) = $0 {
                true
            } else {
                false
            }
        } == true)

        let broken = ScriptedADBRunner { arguments in
            if arguments.suffix(2) == ["id", "-u"] {
                return "0\n"
            }
            return arguments.contains("sh") ? "ROCKXY_ERROR mount failed\n" : ""
        }
        let failed = await AndroidEmulatorProxyController(
            runner: broken,
            environment: ["ANDROID_HOME": "/opt/sdk"],
            isExecutable: { _ in true }
        ).trustSystemWide([emulator], certificatePEM: Self.testCAPEM)
        #expect(failed[emulator]
            .map {
                if case .failure(.systemTrustFailed("mount failed")) = $0 {
                    true
                } else {
                    false
                }
            } == true)
    }

    @Test("Removing system trust leaves untouched emulators alone and unmounts changed ones")
    func removeSystemTrust() async {
        let untouched = ScriptedADBRunner(status: { $0.contains("test") ? 1 : 0 }) { _ in "" }
        let emulator = AndroidEmulator(serial: "emulator-5554")
        let skipped = await AndroidEmulatorProxyController(
            runner: untouched,
            environment: ["ANDROID_HOME": "/opt/sdk"],
            isExecutable: { _ in true }
        ).removeSystemTrust([emulator])
        #expect(skipped[emulator].map {
            if case .success = $0 {
                true
            } else {
                false
            }
        } == true)
        #expect(untouched.commands == [["-s", "emulator-5554", "shell", "test", "-d", "/data/local/tmp/rockxy-ca"]])

        let changed = ScriptedADBRunner { arguments in
            if arguments.suffix(2) == ["id", "-u"] {
                return "0\n"
            }
            return arguments.contains("sh") ? "ROCKXY_SYSTEM_CA_REMOVED\n" : ""
        }
        let removed = await AndroidEmulatorProxyController(
            runner: changed,
            environment: ["ANDROID_HOME": "/opt/sdk"],
            isExecutable: { _ in true }
        ).removeSystemTrust([emulator])
        #expect(removed[emulator].map {
            if case .success = $0 {
                true
            } else {
                false
            }
        } == true)
        #expect(changed.commands.contains(["-s", "emulator-5554", "shell", "sh", "/data/local/tmp/rockxy-untrust.sh"]))
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
        #expect(commands[0] == [
            "-s",
            "emulator-5554",
            "shell",
            "settings",
            "put",
            "global",
            "http_proxy",
            "10.0.2.2:9090"
        ])
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

        #expect(results[emulator].map {
            if case .failure(.adbUnavailable) = $0 {
                true
            } else {
                false
            }
        } == true)
        #expect(failures.count == 1)
    }
}

extension AndroidEmulatorProxyControllerTests {
    /// A throwaway public CA whose `openssl x509 -subject_hash_old` is 5e7ceb16.
    static let testCAPEM = """
    -----BEGIN CERTIFICATE-----
    MIIDWTCCAkGgAwIBAgIUR99dRFXTaSijpanetcNoYZdE4sAwDQYJKoZIhvcNAQEL
    BQAwNDEeMBwGA1UEAwwVUm9ja3h5IEFjY2VwdCBUZXN0IENBMRIwEAYDVQQKDAlS
    b2NreHkgUUEwHhcNMjYxMDAyMDIyNjQ2WhcNMjYxMTAxMDIyNjQ2WjA0MR4wHAYD
    VQQDDBVSb2NreHkgQWNjZXB0IFRlc3QgQ0ExEjAQBgNVBAoMCVJvY2t4eSBRQTCC
    ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAL7Onn0K92u7U11nnK5LPW1r
    gsCCersoZ+nWRJN0eD3qACQb3ZicMq++qFmFJJyXQD+B0QKUTonmHK+Dnnhtx0Qp
    xS5FzSSaroFC4bJYxG7NasDr5/+cmk+sbttygzxEYSsPqbixAMwOnXO9/UqBO0Sn
    EMzghIpgFeJR1klj0FO9w6xJ6rtPyNeN9zv3TGtrH1fRLLlINaYmcaPssdRlitFl
    3klTMqMae1941y3Ew5/tcv49BoW6neeqKfZXt3s2KK3AJii1GXEMfgfnyX5MZojj
    Apj86JIR7UiQ2k03Xj+tcjXdb4ZYv/xCH7jKwR0JETcKBcGiK+QnNCPi/iDAQNMC
    AwEAAaNjMGEwHQYDVR0OBBYEFB0OmSjzt/5pgsZxLprtru6dYa5dMB8GA1UdIwQY
    MBaAFB0OmSjzt/5pgsZxLprtru6dYa5dMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0P
    AQH/BAQDAgEGMA0GCSqGSIb3DQEBCwUAA4IBAQA5E++87bNypuvj8fmEriiGPkrB
    Aaa85AR4drUY1uhi3XjCwDlyih3+vWT0Qpr2dCF7t05nIUvqySmBo/RsgQEi+zao
    Ni2eaRNVmorl/0wODMzyNbO+gXREiH8an19dh7HbuDaLB401II8Fj+OKsjweJulb
    vYqdO2arZWU7VjJnYyN2/JiA8YeEk7OrxFbgJITsCDdDDuqlzFeogs71yxVV87Z6
    c87mF0HVzHAUxVqEJIR4Jot2pe/zvwopeAsNyVeEOqAdeYE0oAA2Btz3XBtEGHNF
    bB1fNDznlguuU5IV7B0OaB9b2xylyxO5f7er3F/w5J5UNeLN20dTu3MNOTQa
    -----END CERTIFICATE-----
    """
}

// MARK: - ScriptedADBRunner

private final class ScriptedADBRunner: SimulatorCommandRunning, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        status: @escaping @Sendable ([String]) -> Int32 = { _ in 0 },
        output: @escaping @Sendable ([String]) -> String
    ) {
        self.status = status
        self.output = output
    }

    // MARK: Internal

    var commands: [[String]] {
        lock.withLock { recorded }
    }

    func run(executable _: URL, arguments: [String]) async throws -> SimulatorCommandOutput {
        lock.withLock { recorded.append(arguments) }
        return SimulatorCommandOutput(
            status: status(arguments),
            standardOutput: Data(output(arguments).utf8),
            standardError: Data()
        )
    }

    // MARK: Private

    private let status: @Sendable ([String]) -> Int32
    private let output: @Sendable ([String]) -> String
    private let lock = NSLock()
    private var recorded: [[String]] = []
}

// MARK: - RecordingADBRunner

private final class RecordingADBRunner: SimulatorCommandRunning, @unchecked Sendable {
    // MARK: Internal

    var commands: [[String]] {
        lock.withLock { recorded }
    }

    func run(executable _: URL, arguments: [String]) async throws -> SimulatorCommandOutput {
        lock.withLock { recorded.append(arguments) }
        return SimulatorCommandOutput(status: 0, standardOutput: Data(), standardError: Data())
    }

    // MARK: Private

    private let lock = NSLock()
    private var recorded: [[String]] = []
}
