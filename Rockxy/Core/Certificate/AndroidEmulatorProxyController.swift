import Foundation
import os

// Points running Android emulators at Rockxy through adb, copies the public root
// certificate onto them, and reverts the proxy when testing is done.

// MARK: - AndroidEmulator

struct AndroidEmulator: Equatable, Hashable, Sendable, Identifiable {
    /// adb serial, for example `emulator-5554`.
    let serial: String

    var id: String {
        serial
    }
}

// MARK: - AndroidEmulatorError

enum AndroidEmulatorError: LocalizedError, Equatable {
    case adbUnavailable
    case commandFailed(status: Int32, message: String?)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .adbUnavailable:
            String(
                localized: "adb was not found. Install Android Studio or the Android SDK platform tools.",
                bundle: RockxyLocalization.bundle
            )
        case let .commandFailed(status, message):
            message.map { "adb: \($0)" }
                ?? String(localized: "adb exited with status \(status).", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - AndroidEmulatorProxyController

/// Drives `adb` for emulators only (serials `emulator-NNNN`). Inside the stock
/// emulator the Mac's loopback is reachable at 10.0.2.2, so the emulator-wide
/// HTTP proxy points there. The certificate is copied to the emulator's Download
/// folder for installation from Settings; system-store trust is not changed.
struct AndroidEmulatorProxyController: Sendable {
    // MARK: Lifecycle

    init(
        runner: SimulatorCommandRunning = SimulatorProcessRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.runner = runner
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.isExecutable = isExecutable
    }

    // MARK: Internal

    static let hostLoopbackAlias = "10.0.2.2"
    static let deviceCertificatePath = "/sdcard/Download/rockxy-root-ca.pem"

    let runner: SimulatorCommandRunning

    /// Serials of running emulators from `adb devices` output; physical devices and
    /// offline or unauthorized entries are skipped.
    static func parseEmulators(_ output: String) -> [AndroidEmulator] {
        output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line -> AndroidEmulator? in
                let columns = line.split(whereSeparator: \.isWhitespace)
                guard columns.count >= 2, columns[1] == "device" else {
                    return nil
                }
                let serial = String(columns[0])
                return isEmulatorSerial(serial) ? AndroidEmulator(serial: serial) : nil
            }
    }

    static func isEmulatorSerial(_ serial: String) -> Bool {
        guard serial.hasPrefix("emulator-") else {
            return false
        }
        return serial.dropFirst("emulator-".count).allSatisfy(\.isNumber)
    }

    /// Candidate adb locations: the SDK from the environment, Android Studio's default
    /// SDK, then Homebrew. GUI apps do not inherit a shell `PATH`, so it is not searched.
    func adbURL() -> URL? {
        var candidates: [String] = []
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key], !root.isEmpty {
                candidates.append((root as NSString).appendingPathComponent("platform-tools/adb"))
            }
        }
        candidates.append(homeDirectory.appendingPathComponent("Library/Android/sdk/platform-tools/adb").path)
        candidates.append(contentsOf: ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"])
        return candidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    func runningEmulators() async throws -> [AndroidEmulator] {
        let output = try await adb(["devices"])
        return Self.parseEmulators(String(bytes: output, encoding: .utf8) ?? "")
    }

    /// Sets each emulator's global HTTP proxy to Rockxy and copies the root certificate.
    func routeThroughRockxy(
        _ emulators: [AndroidEmulator],
        proxyPort: Int,
        certificatePEM: String?
    )
        async -> [AndroidEmulator: Result<Void, AndroidEmulatorError>]
    {
        var results: [AndroidEmulator: Result<Void, AndroidEmulatorError>] = [:]
        let certificateFile = certificatePEM.flatMap(writeTemporaryCertificate)
        defer {
            if let certificateFile {
                try? FileManager.default.removeItem(at: certificateFile.deletingLastPathComponent())
            }
        }
        for emulator in emulators where Self.isEmulatorSerial(emulator.serial) {
            do {
                _ = try await adb([
                    "-s", emulator.serial, "shell", "settings", "put", "global", "http_proxy",
                    "\(Self.hostLoopbackAlias):\(proxyPort)",
                ])
                if let certificateFile {
                    _ = try await adb(["-s", emulator.serial, "push", certificateFile.path, Self.deviceCertificatePath])
                }
                results[emulator] = .success(())
            } catch {
                results[emulator] = .failure(error as? AndroidEmulatorError ?? .commandFailed(status: -1, message: nil))
            }
        }
        return results
    }

    /// Clears the global HTTP proxy so emulators reach the network directly again.
    func revertProxy(_ emulators: [AndroidEmulator]) async -> [AndroidEmulator: Result<Void, AndroidEmulatorError>] {
        var results: [AndroidEmulator: Result<Void, AndroidEmulatorError>] = [:]
        for emulator in emulators where Self.isEmulatorSerial(emulator.serial) {
            do {
                _ = try await adb(["-s", emulator.serial, "shell", "settings", "put", "global", "http_proxy", ":0"])
                results[emulator] = .success(())
            } catch {
                results[emulator] = .failure(error as? AndroidEmulatorError ?? .commandFailed(status: -1, message: nil))
            }
        }
        return results
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "AndroidEmulator")

    private let environment: [String: String]
    private let homeDirectory: URL
    private let isExecutable: @Sendable (String) -> Bool

    private func adb(_ arguments: [String]) async throws -> Data {
        guard let adb = adbURL() else {
            throw AndroidEmulatorError.adbUnavailable
        }
        let output: SimulatorCommandOutput
        do {
            output = try await runner.run(executable: adb, arguments: arguments)
        } catch {
            throw AndroidEmulatorError.commandFailed(status: -1, message: error.localizedDescription)
        }
        guard output.status == 0 else {
            let message = String(data: output.standardError.prefix(2_048), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Self.logger.error("adb exited with status \(output.status)")
            throw AndroidEmulatorError.commandFailed(
                status: output.status,
                message: message?.isEmpty == false ? message : nil
            )
        }
        return output.standardOutput
    }

    private func writeTemporaryCertificate(_ pem: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-android-ca-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("rockxy-root-ca.pem")
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            guard FileManager.default.createFile(
                atPath: file.path,
                contents: Data(pem.utf8),
                attributes: [.posixPermissions: 0o600]
            ) else {
                return nil
            }
            return file
        } catch {
            return nil
        }
    }
}
