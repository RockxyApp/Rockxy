import CryptoKit
import Foundation
@testable import Rockxy
import Testing

// MARK: - SimulatorCertificateInstallerTests

struct SimulatorCertificateInstallerTests {
    // MARK: Internal

    @Test("Booted devices are parsed across runtimes with readable runtime names")
    func parsesBootedDevices() throws {
        let json = Data("""
        {"devices":{
          "com.apple.CoreSimulator.SimRuntime.iOS-26-0":[
            {"udid":"6F1B2C3D-0000-4000-8000-000000000001","name":"iPhone 17 Pro","state":"Booted"},
            {"udid":"6F1B2C3D-0000-4000-8000-000000000002","name":"iPad Air","state":"Shutdown"}
          ],
          "com.apple.CoreSimulator.SimRuntime.watchOS-26-0":[
            {"udid":"6F1B2C3D-0000-4000-8000-000000000003","name":"Apple Watch Ultra 3","state":"Booted"}
          ],
          "com.apple.CoreSimulator.SimRuntime.xrOS-26-0":[
            {"udid":"not-a-uuid;echo injected","name":"Bad","state":"Booted"}
          ]
        }}
        """.utf8)

        let simulators = try SimulatorCertificateInstaller.parseBootedSimulators(json: json)

        #expect(simulators.map(\.displayName) == ["iPhone 17 Pro (iOS 26.0)", "Apple Watch Ultra 3 (watchOS 26.0)"])
        #expect(throws: SimulatorCertificateInstallerError.unreadableDeviceList) {
            try SimulatorCertificateInstaller.parseBootedSimulators(json: Data("[]".utf8))
        }
    }

    @Test("Vision Pro runtimes read as visionOS, not CoreSimulator's xrOS")
    func visionRuntimeName() {
        #expect(SimulatorCertificateInstaller.runtimeName("com.apple.CoreSimulator.SimRuntime.xrOS-27-0") == "visionOS 27.0")
        #expect(SimulatorCertificateInstaller.runtimeName("com.apple.CoreSimulator.SimRuntime.watchOS-27-0") == "watchOS 27.0")
    }

    @Test("Without a selected developer directory, nothing else is run")
    func missingDeveloperToolsFailsClosed() async {
        let runner = RecordingRunner { executable, _ in
            #expect(executable == SimulatorCertificateInstaller.xcodeSelectURL)
            return SimulatorCommandOutput(status: 2, standardOutput: Data(), standardError: Data())
        }
        let installer = SimulatorCertificateInstaller(runner: runner)

        await #expect(throws: SimulatorCertificateInstallerError.developerToolsUnavailable) {
            try await installer.bootedSimulators()
        }
        #expect(runner.invocations.count == 1)
    }

    @Test("A stalled developer-directory lookup reports a timeout, not a missing Xcode")
    func stalledLookupIsATimeout() async {
        let runner = RecordingRunner { _, _ in
            throw SimulatorCertificateInstallerError.timedOut
        }
        let installer = SimulatorCertificateInstaller(runner: runner)
        let simulator = BootedSimulator(udid: UUID().uuidString, name: "iPhone", runtime: "iOS 27.0")

        await #expect(throws: SimulatorCertificateInstallerError.timedOut) {
            try await installer.bootedSimulators()
        }
        let results = await installer.installRootCertificate(pem: "PEM", into: [simulator])
        #expect(results[simulator].map { if case .failure(.timedOut) = $0 { true } else { false } } == true)
    }

    @Test("Install passes the UDID and a private PEM file to simctl, then removes the file")
    func installInvokesSimctl() async throws {
        let developerDirectory = try makeFakeDeveloperDirectory()
        defer { try? FileManager.default.removeItem(at: developerDirectory) }
        let seenPEM = LockedBox<String?>(nil)
        let runner = RecordingRunner { executable, arguments in
            if executable == SimulatorCertificateInstaller.xcodeSelectURL {
                return SimulatorCommandOutput(
                    status: 0,
                    standardOutput: Data((developerDirectory.path + "\n").utf8),
                    standardError: Data()
                )
            }
            #expect(executable.lastPathComponent == "simctl")
            #expect(Array(arguments.prefix(3)) == ["keychain", "6F1B2C3D-0000-4000-8000-000000000001", "add-root-cert"])
            let path = try #require(arguments.last)
            seenPEM.value = try String(contentsOfFile: path, encoding: .utf8)
            let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
            #expect(permissions == 0o600)
            return SimulatorCommandOutput(status: 0, standardOutput: Data(), standardError: Data())
        }
        let simulator = BootedSimulator(
            udid: "6F1B2C3D-0000-4000-8000-000000000001",
            name: "iPhone 17 Pro",
            runtime: "iOS 26.0"
        )

        let results = await SimulatorCertificateInstaller(runner: runner).installRootCertificate(
            pem: "-----BEGIN CERTIFICATE-----\nAA==\n-----END CERTIFICATE-----\n",
            into: [simulator]
        )

        #expect(seenPEM.value?.hasPrefix("-----BEGIN CERTIFICATE-----") == true)
        if case .success = results[simulator] {} else {
            Issue.record("Expected success, got \(String(describing: results[simulator]))")
        }
        let installArguments = try #require(runner.invocations.last?.arguments)
        let pemPath = try #require(installArguments.last)
        #expect(!FileManager.default.fileExists(atPath: pemPath))
    }

    @Test("A failing simulator is reported with simctl's message")
    func installFailureIsReported() async throws {
        let developerDirectory = try makeFakeDeveloperDirectory()
        defer { try? FileManager.default.removeItem(at: developerDirectory) }
        let runner = RecordingRunner { executable, _ in
            if executable == SimulatorCertificateInstaller.xcodeSelectURL {
                return SimulatorCommandOutput(
                    status: 0,
                    standardOutput: Data(developerDirectory.path.utf8),
                    standardError: Data()
                )
            }
            return SimulatorCommandOutput(
                status: 148,
                standardOutput: Data(),
                standardError: Data("Unable to lookup in current state: Shutdown".utf8)
            )
        }
        let simulator = BootedSimulator(
            udid: "6F1B2C3D-0000-4000-8000-000000000009",
            name: "iPhone",
            runtime: "iOS 26.0"
        )

        let results = await SimulatorCertificateInstaller(runner: runner)
            .installRootCertificate(pem: "pem", into: [simulator])
        let summary = await SimulatorCertificateInstallFlow.summary(simulators: [simulator], results: results)

        #expect(summary.installed.isEmpty)
        #expect(summary.failed.first?.1.contains("Shutdown") == true)
    }

    @Test("The real runner lists booted simulators read-only or reports missing Xcode")
    func liveListingIsReadOnlyAndBounded() async {
        do {
            let simulators = try await SimulatorCertificateInstaller().bootedSimulators()
            #expect(simulators.allSatisfy { SimulatorCertificateInstaller.isValidUDID($0.udid) })
        } catch let error as SimulatorCertificateInstallerError {
            #expect(error == .developerToolsUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Trust status reads the simulator's trust store: present, missing after erase, or unreadable")
    func trustStatusFromTrustStore() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let trusted = BootedSimulator(udid: UUID().uuidString, name: "iPhone", runtime: "iOS 27.0")
        let erased = BootedSimulator(udid: UUID().uuidString, name: "iPad", runtime: "iOS 27.0")
        let unreadable = BootedSimulator(udid: UUID().uuidString, name: "Watch", runtime: "watchOS 26.0")
        let pem = AndroidEmulatorProxyControllerTests.testCAPEM
        let der = try #require(SimulatorCertificateInstaller.derData(fromPEM: pem))
        try makeTrustStore(home: home, udid: trusted.udid, sha256: Data(SHA256.hash(data: der)))
        try makeTrustStore(home: home, udid: erased.udid, sha256: nil)

        let statuses = SimulatorCertificateInstaller(homeDirectory: home)
            .trustStatus(of: [trusted, erased, unreadable], certificatePEM: pem)

        #expect(statuses[trusted] == .trusted)
        #expect(statuses[erased] == .missing)
        #expect(statuses[unreadable] == .unknown)
    }

    @Test("The confirmation and live line state each simulator's trust and the empty state")
    @MainActor
    func trustSummaries() {
        let simulator = BootedSimulator(udid: UUID().uuidString, name: "iPhone 18 Pro", runtime: "iOS 27.0")
        let other = BootedSimulator(udid: UUID().uuidString, name: "iPad Air", runtime: "iOS 27.0")
        let lines = SimulatorCertificateInstallFlow.statusLines(
            [simulator, other],
            statuses: [simulator: .trusted, other: .missing]
        )
        #expect(lines.contains("iPhone 18 Pro (iOS 27.0) — already trusts Rockxy"))
        #expect(lines.contains("iPad Air (iOS 27.0) — certificate not installed"))
        #expect(SimulatorTrustStatusLine.summary(booted: 0, trusted: 0, trustKnown: true)
            .hasPrefix("No simulators are booted"))
        #expect(SimulatorTrustStatusLine
            .summary(booted: 2, trusted: 1, trustKnown: true) == "2 booted simulators · 1 with the Rockxy certificate")
        #expect(SimulatorTrustStatusLine.summary(booted: 1, trusted: 0, trustKnown: false) == "1 booted simulator")
    }

    // MARK: Private

    private func makeTrustStore(home: URL, udid: String, sha256: Data?) throws {
        let url = SimulatorCertificateInstaller.trustStoreURL(udid: udid, homeDirectory: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        var sql = "CREATE TABLE tsettings(sha256 BLOB NOT NULL DEFAULT '',subj BLOB NOT NULL DEFAULT '',tset BLOB,data BLOB,uuid BLOB NOT NULL DEFAULT '',UNIQUE(sha256,uuid));"
        if let sha256 {
            sql += "INSERT INTO tsettings(sha256) VALUES (x'\(sha256.map { String(format: "%02x", $0) }.joined())');"
        }
        process.arguments = [url.path, sql]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    private func makeFakeDeveloperDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bin = root.appendingPathComponent("usr/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let simctl = bin.appendingPathComponent("simctl")
        FileManager.default.createFile(
            atPath: simctl.path,
            contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
        return root
    }
}

// MARK: - RecordingRunner

private final class RecordingRunner: SimulatorCommandRunning, @unchecked Sendable {
    // MARK: Lifecycle

    init(handler: @escaping @Sendable (URL, [String]) throws -> SimulatorCommandOutput) {
        self.handler = handler
    }

    // MARK: Internal

    var invocations: [(executable: URL, arguments: [String])] {
        lock.withLock { recorded }
    }

    func run(executable: URL, arguments: [String]) async throws -> SimulatorCommandOutput {
        lock.withLock { recorded.append((executable, arguments)) }
        return try handler(executable, arguments)
    }

    // MARK: Private

    private let handler: @Sendable (URL, [String]) throws -> SimulatorCommandOutput
    private let lock = NSLock()
    private var recorded: [(executable: URL, arguments: [String])] = []
}

// MARK: - LockedBox

private final class LockedBox<Value>: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ value: Value) {
        storage = value
    }

    // MARK: Internal

    var value: Value {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    // MARK: Private

    private let lock = NSLock()
    private var storage: Value
}
