import CryptoKit
import Foundation
import os
import SQLite3

// Installs the Rockxy root certificate into booted Apple simulators through simctl.

// MARK: - BootedSimulator

struct BootedSimulator: Equatable, Hashable, Sendable, Identifiable {
    let udid: String
    let name: String
    /// Readable runtime, for example "iOS 26.0" or "watchOS 26.0".
    let runtime: String

    var id: String {
        udid
    }

    var displayName: String {
        "\(name) (\(runtime))"
    }
}

// MARK: - SimulatorTrustStatus

/// Whether a simulator's trust store holds the Rockxy root, read from its
/// `TrustStore.sqlite3`. `unknown` covers stores that cannot be read.
enum SimulatorTrustStatus: Equatable, Sendable {
    case trusted
    case missing
    case unknown
}

// MARK: - SimulatorCertificateInstallerError

enum SimulatorCertificateInstallerError: LocalizedError, Equatable {
    case developerToolsUnavailable
    case commandFailed(status: Int32, message: String?)
    case timedOut
    case unreadableDeviceList

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .developerToolsUnavailable:
            String(
                localized: "Xcode is not installed or selected. Install Xcode, then choose it with xcode-select.",
                bundle: RockxyLocalization.bundle
            )
        case let .commandFailed(status, message):
            message.map { "simctl: \($0)" }
                ?? String(localized: "simctl exited with status \(status).", bundle: RockxyLocalization.bundle)
        case .timedOut:
            String(localized: "simctl did not finish in time.", bundle: RockxyLocalization.bundle)
        case .unreadableDeviceList:
            String(localized: "The simulator list could not be read.", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - SimulatorCommandRunning

protocol SimulatorCommandRunning: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> SimulatorCommandOutput
}

// MARK: - SimulatorCommandOutput

struct SimulatorCommandOutput: Sendable {
    let status: Int32
    let standardOutput: Data
    let standardError: Data
}

// MARK: - SimulatorCertificateInstaller

/// Drives `simctl` for the simulators that are booted right now. Only the public
/// root certificate is written, to a private temporary file that is removed
/// after each install. `simctl` is located through the selected developer
/// directory so a Mac without Xcode never sees the Command Line Tools prompt.
struct SimulatorCertificateInstaller: Sendable {
    // MARK: Lifecycle

    init(
        runner: SimulatorCommandRunning = SimulatorProcessRunner(),
        fileManager: @escaping @Sendable () -> FileManager = { .default },
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    // MARK: Internal

    static let xcodeSelectURL = URL(fileURLWithPath: "/usr/bin/xcode-select")

    let runner: SimulatorCommandRunning

    /// Parses `simctl list devices booted -j`.
    static func parseBootedSimulators(json: Data) throws -> [BootedSimulator] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let devices = root["devices"] as? [String: Any] else
        {
            throw SimulatorCertificateInstallerError.unreadableDeviceList
        }
        var simulators: [BootedSimulator] = []
        for (runtimeIdentifier, value) in devices {
            guard let entries = value as? [[String: Any]] else {
                continue
            }
            for entry in entries {
                guard (entry["state"] as? String) == "Booted",
                      let udid = entry["udid"] as? String, isValidUDID(udid),
                      let name = entry["name"] as? String else
                {
                    continue
                }
                simulators.append(BootedSimulator(udid: udid, name: name, runtime: runtimeName(runtimeIdentifier)))
            }
        }
        return simulators.sorted {
            ($0.runtime, $0.name) < ($1.runtime, $1.name)
        }
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-0` → `iOS 26.0`. CoreSimulator still names the
    /// Vision Pro runtime `xrOS`; people know it as visionOS.
    static func runtimeName(_ identifier: String) -> String {
        let suffix = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let parts = suffix.split(separator: "-")
        guard let platform = parts.first, parts.count > 1 else {
            return suffix
        }
        let platformName = platform == "xrOS" ? "visionOS" : String(platform)
        return "\(platformName) \(parts.dropFirst().joined(separator: "."))"
    }

    static func isValidUDID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    /// The DER bytes inside a PEM certificate.
    static func derData(fromPEM pem: String) -> Data? {
        let body = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: body)
    }

    /// Where CoreSimulator keeps a device's trust settings; `simctl keychain add-root-cert`
    /// writes the certificate's SHA-256 there and erasing the device removes it.
    static func trustStoreURL(udid: String, homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
            .appendingPathComponent(udid, isDirectory: true)
            .appendingPathComponent("data/private/var/protected/trustd/private/TrustStore.sqlite3")
    }

    /// Reads the trust store read-only; nil when it is missing or unreadable.
    static func trustStore(at url: URL, containsSHA256 digest: Data) -> Bool? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_busy_timeout(database, 500)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT 1 FROM tsettings WHERE sha256 = ? LIMIT 1", -1, &statement, nil)
            == SQLITE_OK else
        {
            return nil
        }
        let bound = digest.withUnsafeBytes { buffer in
            sqlite3_bind_blob(
                statement,
                1,
                buffer.baseAddress,
                Int32(buffer.count),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
        }
        guard bound == SQLITE_OK else {
            return nil
        }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            return nil
        }
    }

    /// Trust status of the Rockxy root in each simulator.
    func trustStatus(
        of simulators: [BootedSimulator],
        certificatePEM: String
    )
        -> [BootedSimulator: SimulatorTrustStatus]
    {
        guard let der = Self.derData(fromPEM: certificatePEM) else {
            return Dictionary(uniqueKeysWithValues: simulators.map { ($0, .unknown) })
        }
        let digest = Data(SHA256.hash(data: der))
        return Dictionary(uniqueKeysWithValues: simulators.map { simulator in
            guard Self.isValidUDID(simulator.udid) else {
                return (simulator, .unknown)
            }
            let url = Self.trustStoreURL(udid: simulator.udid, homeDirectory: homeDirectory)
            switch Self.trustStore(at: url, containsSHA256: digest) {
            case true?: return (simulator, .trusted)
            case false?: return (simulator, .missing)
            case nil: return (simulator, .unknown)
            }
        })
    }

    func bootedSimulators() async throws -> [BootedSimulator] {
        let simctl = try await simctlURL()
        let output = try await runner.run(executable: simctl, arguments: ["list", "devices", "booted", "-j"])
        guard output.status == 0 else {
            throw SimulatorCertificateInstallerError.commandFailed(
                status: output.status,
                message: Self.message(from: output.standardError)
            )
        }
        return try Self.parseBootedSimulators(json: output.standardOutput)
    }

    /// Adds `certificatePEM` as a trusted root in each simulator. Every simulator
    /// is attempted; the result reports each one's outcome.
    func installRootCertificate(
        pem certificatePEM: String,
        into simulators: [BootedSimulator]
    )
        async -> [BootedSimulator: Result<Void, SimulatorCertificateInstallerError>]
    {
        var results: [BootedSimulator: Result<Void, SimulatorCertificateInstallerError>] = [:]
        let simctl: URL
        do {
            simctl = try await simctlURL()
        } catch {
            let failure = error as? SimulatorCertificateInstallerError ?? .developerToolsUnavailable
            for simulator in simulators {
                results[simulator] = .failure(failure)
            }
            return results
        }

        for simulator in simulators {
            guard Self.isValidUDID(simulator.udid) else {
                results[simulator] = .failure(.unreadableDeviceList)
                continue
            }
            results[simulator] = await install(certificatePEM, into: simulator, simctl: simctl)
        }
        return results
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "SimulatorCertificate")

    private let fileManager: @Sendable () -> FileManager
    private let homeDirectory: URL

    private static func message(from data: Data) -> String? {
        let text = String(data: data.prefix(2_048), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private func simctlURL() async throws -> URL {
        let output: SimulatorCommandOutput
        do {
            output = try await runner.run(executable: Self.xcodeSelectURL, arguments: ["-p"])
        } catch SimulatorCertificateInstallerError.timedOut {
            // A busy Mac can stall the lookup; that is not a missing Xcode.
            throw SimulatorCertificateInstallerError.timedOut
        } catch {
            throw SimulatorCertificateInstallerError.developerToolsUnavailable
        }
        guard output.status == 0,
              let developerPath = String(data: output.standardOutput, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !developerPath.isEmpty else
        {
            throw SimulatorCertificateInstallerError.developerToolsUnavailable
        }
        let simctl = URL(fileURLWithPath: developerPath).appendingPathComponent("usr/bin/simctl")
        guard fileManager().isExecutableFile(atPath: simctl.path) else {
            throw SimulatorCertificateInstallerError.developerToolsUnavailable
        }
        return simctl
    }

    private func install(
        _ certificatePEM: String,
        into simulator: BootedSimulator,
        simctl: URL
    )
        async -> Result<Void, SimulatorCertificateInstallerError>
    {
        let fileManager = fileManager()
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("rockxy-simulator-ca-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }
        let certificateURL = directory.appendingPathComponent("rockxy-root-ca.pem")
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            guard fileManager.createFile(
                atPath: certificateURL.path,
                contents: Data(certificatePEM.utf8),
                attributes: [.posixPermissions: 0o600]
            ) else {
                return .failure(.commandFailed(status: -1, message: nil))
            }
            let output = try await runner.run(
                executable: simctl,
                arguments: ["keychain", simulator.udid, "add-root-cert", certificateURL.path]
            )
            guard output.status == 0 else {
                Self.logger.error("simctl add-root-cert failed with status \(output.status)")
                return .failure(.commandFailed(
                    status: output.status,
                    message: Self.message(from: output.standardError)
                ))
            }
            Self.logger.info("Installed root certificate in a booted simulator")
            return .success(())
        } catch let error as SimulatorCertificateInstallerError {
            return .failure(error)
        } catch {
            return .failure(.commandFailed(status: -1, message: error.localizedDescription))
        }
    }
}

// MARK: - SimulatorProcessRunner

/// Runs a developer tool with a timeout and bounded output capture. Both pipes
/// are drained while the process runs so a chatty tool can never block on a
/// full pipe.
struct SimulatorProcessRunner: SimulatorCommandRunning {
    static let maxCapturedBytes = 1_048_576

    var timeout: Duration = .seconds(30)

    func run(executable: URL, arguments: [String]) async throws -> SimulatorCommandOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
        }
        let captured = OSAllocatedUnfairLock(initialState: (output: Data(), error: Data()))
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            captured.withLock { state in
                if state.output.count < Self.maxCapturedBytes {
                    state.output.append(chunk.prefix(Self.maxCapturedBytes - state.output.count))
                }
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            captured.withLock { state in
                if state.error.count < Self.maxCapturedBytes {
                    state.error.append(chunk.prefix(Self.maxCapturedBytes - state.error.count))
                }
            }
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let finished = OSAllocatedUnfairLock(initialState: false)
            process.terminationHandler = { process in
                let shouldResume = finished.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if shouldResume {
                    continuation.resume(returning: process.terminationStatus)
                }
            }
            do {
                try process.run()
            } catch {
                finished.withLock { $0 = true }
                continuation.resume(throwing: error)
                return
            }
            let timeout = timeout
            Task.detached {
                try? await Task.sleep(for: timeout)
                let timedOut = finished.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if timedOut {
                    process.terminate()
                    continuation.resume(throwing: SimulatorCertificateInstallerError.timedOut)
                }
            }
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        let remainingOutput = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
        let remainingError = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
        let result = captured.withLock { state in
            (
                output: (state.output + remainingOutput).prefix(Self.maxCapturedBytes),
                error: (state.error + remainingError).prefix(Self.maxCapturedBytes)
            )
        }
        return SimulatorCommandOutput(
            status: status,
            standardOutput: Data(result.output),
            standardError: Data(result.error)
        )
    }
}
