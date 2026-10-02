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
    case rootUnavailable
    case systemTrustFailed(String?)

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
        case .rootUnavailable:
            String(
                localized: """
                This emulator can't run adb as root, so system trust was skipped. Google Play images can't \
                be rooted; use a Google APIs image, or install the certificate as a user certificate.
                """,
                bundle: RockxyLocalization.bundle
            )
        case let .systemTrustFailed(detail):
            detail.map {
                String(localized: "System trust was not applied: \($0)", bundle: RockxyLocalization.bundle)
            } ?? String(localized: "System trust was not applied.", bundle: RockxyLocalization.bundle)
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
    /// SDK, then Homebrew's links and SDK casks. Apps opened from Finder inherit neither
    /// a shell `PATH` nor `ANDROID_HOME`, so the cask locations are listed explicitly.
    func adbURL() -> URL? {
        var candidates: [String] = []
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key], !root.isEmpty {
                candidates.append((root as NSString).appendingPathComponent("platform-tools/adb"))
            }
        }
        candidates.append(homeDirectory.appendingPathComponent("Library/Android/sdk/platform-tools/adb").path)
        for prefix in ["/opt/homebrew", "/usr/local"] {
            candidates.append("\(prefix)/bin/adb")
            candidates.append("\(prefix)/share/android-commandlinetools/platform-tools/adb")
            candidates.append("\(prefix)/share/android-sdk/platform-tools/adb")
        }
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
                } else if certificatePEM != nil {
                    throw AndroidEmulatorError.commandFailed(
                        status: -1,
                        message: String(
                            localized: "The proxy was set, but the certificate file could not be prepared.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
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

    /// Roots each emulator's adb daemon and makes the certificate a system CA until the
    /// emulator restarts. Emulators that cannot be rooted report `.rootUnavailable`.
    func trustSystemWide(
        _ emulators: [AndroidEmulator],
        certificatePEM: String
    )
        async -> [AndroidEmulator: Result<Void, AndroidEmulatorError>]
    {
        var results: [AndroidEmulator: Result<Void, AndroidEmulatorError>] = [:]
        let targets = emulators.filter { Self.isEmulatorSerial($0.serial) }
        guard let fileName = try? AndroidSystemTrust.certificateFileName(certificatePEM: certificatePEM),
              let staging = writeTemporaryFiles([
                  fileName: certificatePEM,
                  AndroidSystemTrust.installScriptName: AndroidSystemTrust.installScript,
              ]) else
        {
            for emulator in targets {
                results[emulator] = .failure(.systemTrustFailed(nil))
            }
            return results
        }
        defer { try? FileManager.default.removeItem(at: staging) }
        let work = AndroidSystemTrust.workDirectory
        for emulator in targets {
            do {
                try await becomeRoot(emulator)
                _ = try await adb(["-s", emulator.serial, "shell", "mkdir", "-p", work])
                for name in [fileName, AndroidSystemTrust.installScriptName] {
                    _ = try await adb([
                        "-s",
                        emulator.serial,
                        "push",
                        staging.appendingPathComponent(name).path,
                        "\(work)/\(name)"
                    ])
                }
                let output = try await run([
                    "-s", emulator.serial, "shell", "sh", "\(work)/\(AndroidSystemTrust.installScriptName)", fileName,
                ])
                try Self.requireMarker(AndroidSystemTrust.installedMarker, in: output)
                Self.logger.info("Trusted the root certificate system-wide on an emulator")
                results[emulator] = .success(())
            } catch {
                results[emulator] = .failure(error as? AndroidEmulatorError ?? .systemTrustFailed(nil))
            }
        }
        return results
    }

    /// Removes system trust that `trustSystemWide` added. Emulators without Rockxy's
    /// work directory were never changed and succeed without being rooted.
    func removeSystemTrust(_ emulators: [AndroidEmulator]) async -> [AndroidEmulator: Result<
        Void,
        AndroidEmulatorError
    >] {
        var results: [AndroidEmulator: Result<Void, AndroidEmulatorError>] = [:]
        let staging = writeTemporaryFiles([AndroidSystemTrust.removeScriptName: AndroidSystemTrust.removeScript])
        defer {
            if let staging {
                try? FileManager.default.removeItem(at: staging)
            }
        }
        let work = AndroidSystemTrust.workDirectory
        for emulator in emulators where Self.isEmulatorSerial(emulator.serial) {
            do {
                let probe = try await run(["-s", emulator.serial, "shell", "test", "-d", work])
                guard probe.status == 0 else {
                    results[emulator] = .success(())
                    continue
                }
                guard let staging else {
                    throw AndroidEmulatorError.systemTrustFailed(nil)
                }
                try await becomeRoot(emulator)
                _ = try await adb([
                    "-s", emulator.serial, "push",
                    staging.appendingPathComponent(AndroidSystemTrust.removeScriptName).path,
                    "/data/local/tmp/\(AndroidSystemTrust.removeScriptName)",
                ])
                let output = try await run([
                    "-s", emulator.serial, "shell", "sh", "/data/local/tmp/\(AndroidSystemTrust.removeScriptName)",
                ])
                _ = try? await run([
                    "-s",
                    emulator.serial,
                    "shell",
                    "rm",
                    "-f",
                    "/data/local/tmp/\(AndroidSystemTrust.removeScriptName)"
                ])
                try Self.requireMarker(AndroidSystemTrust.removedMarker, in: output)
                results[emulator] = .success(())
            } catch {
                results[emulator] = .failure(error as? AndroidEmulatorError ?? .systemTrustFailed(nil))
            }
        }
        return results
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "AndroidEmulator")

    private let environment: [String: String]
    private let homeDirectory: URL
    private let isExecutable: @Sendable (String) -> Bool

    /// Fails with the script's own error line when its success marker is missing.
    private static func requireMarker(_ marker: String, in output: SimulatorCommandOutput) throws {
        let text = String(data: output.standardOutput.prefix(4_096), encoding: .utf8) ?? ""
        guard !text.contains(marker) else {
            return
        }
        let detail = text.split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix(AndroidSystemTrust.errorMarker) }
            .map { $0.dropFirst(AndroidSystemTrust.errorMarker.count).trimmingCharacters(in: .whitespaces) }
        throw AndroidEmulatorError.systemTrustFailed(detail)
    }

    /// Restarts the emulator's adb daemon as root and confirms it, since `adb root`
    /// reports a refusal on standard output with a zero exit status.
    private func becomeRoot(_ emulator: AndroidEmulator) async throws {
        if try await isRoot(emulator) {
            return
        }
        _ = try await run(["-s", emulator.serial, "root"])
        _ = try await run(["-s", emulator.serial, "wait-for-device"])
        guard try await isRoot(emulator) else {
            throw AndroidEmulatorError.rootUnavailable
        }
    }

    private func isRoot(_ emulator: AndroidEmulator) async throws -> Bool {
        let output = try await run(["-s", emulator.serial, "shell", "id", "-u"])
        return String(data: output.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "0"
    }

    /// Runs adb and returns its output whatever the exit status.
    private func run(_ arguments: [String]) async throws -> SimulatorCommandOutput {
        guard let adb = adbURL() else {
            throw AndroidEmulatorError.adbUnavailable
        }
        do {
            return try await runner.run(executable: adb, arguments: arguments)
        } catch {
            throw AndroidEmulatorError.commandFailed(status: -1, message: error.localizedDescription)
        }
    }

    private func adb(_ arguments: [String]) async throws -> Data {
        let output = try await run(arguments)
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

    /// Writes each `name: contents` pair into one private temporary directory.
    private func writeTemporaryFiles(_ files: [String: String]) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-android-trust-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            for (name, contents) in files {
                guard FileManager.default.createFile(
                    atPath: directory.appendingPathComponent(name).path,
                    contents: Data(contents.utf8),
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    try? FileManager.default.removeItem(at: directory)
                    return nil
                }
            }
            return directory
        } catch {
            return nil
        }
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
