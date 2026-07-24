import Foundation
@testable import Rockxy
import Testing

// MARK: - AssistantLocalRuntimeInstallerTests

struct AssistantLocalRuntimeInstallerTests {
    @Test("Verified runtime is installed only after archive and signing checks")
    func verifiedInstall() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }
        let installer = OllamaRuntimeInstaller(
            downloader: RuntimeArtifactFixtureDownloader(),
            processRunner: RuntimeInstallFixtureProcessRunner()
        )

        var events: [AssistantRuntimeInstallEvent] = []
        for try await event in installer.install(
            runtime: .ollama,
            destinationDirectory: destination
        ) {
            events.append(event)
        }

        let installedApplication = destination.appendingPathComponent("Ollama.app", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: installedApplication.path))
        #expect(events == [
            .downloading(receivedBytes: 7, totalBytes: 7),
            .verifying,
            .installing,
            .completed(AssistantRuntimeInstallation(
                applicationURL: installedApplication,
                version: "1.2.3"
            )),
        ])
    }

    @Test("Runtime installer rejects path traversal before extraction")
    func unsafeArchive() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }
        let installer = OllamaRuntimeInstaller(
            downloader: RuntimeArtifactFixtureDownloader(),
            processRunner: RuntimeInstallFixtureProcessRunner(archiveIsSafe: false)
        )

        do {
            for try await _ in installer.install(
                runtime: .ollama,
                destinationDirectory: destination
            ) {}
            Issue.record("Expected the unsafe archive to be rejected")
        } catch let error as AssistantRuntimeInstallError {
            #expect(error == .unsafeArchive)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("Ollama.app").path
        ))
    }

    @Test("Runtime installer rejects an unexpected developer identity")
    func unexpectedSigner() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }
        let installer = OllamaRuntimeInstaller(
            downloader: RuntimeArtifactFixtureDownloader(),
            processRunner: RuntimeInstallFixtureProcessRunner(teamIdentifier: "UNTRUSTED")
        )

        do {
            for try await _ in installer.install(
                runtime: .ollama,
                destinationDirectory: destination
            ) {}
            Issue.record("Expected the unexpected signer to be rejected")
        } catch let error as AssistantRuntimeInstallError {
            #expect(error == .unexpectedSigner)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("Ollama.app").path
        ))
    }

    private func makeDestination() throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
            "rockxy-runtime-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination
    }
}

// MARK: - RuntimeArtifactFixtureDownloader

private struct RuntimeArtifactFixtureDownloader: AssistantRuntimeArtifactDownloading {
    func download(
        from _: URL,
        to fileURL: URL,
        maximumBytes _: Int64
    ) -> AsyncThrowingStream<AssistantRuntimeArtifactDownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                let data = Data("fixture".utf8)
                try data.write(to: fileURL)
                continuation.yield(.progress(
                    receivedBytes: Int64(data.count),
                    totalBytes: Int64(data.count)
                ))
                continuation.yield(.completed(fileURL: fileURL))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

// MARK: - RuntimeInstallFixtureProcessRunner

private actor RuntimeInstallFixtureProcessRunner: AssistantProcessRunning {
    init(
        archiveIsSafe: Bool = true,
        teamIdentifier: String = AssistantLocalRuntimeDescriptor.ollama.expectedTeamIdentifier
    ) {
        self.archiveIsSafe = archiveIsSafe
        self.teamIdentifier = teamIdentifier
    }

    func run(executable: URL, arguments: [String]) async throws -> String {
        switch (executable.path, arguments) {
        case ("/usr/bin/unzip", let arguments) where arguments.starts(with: ["-Z", "-1"]):
            if archiveIsSafe {
                return "Ollama.app/\nOllama.app/Contents/\nOllama.app/Contents/Info.plist\n"
            }
            return "Ollama.app/\nOllama.app/Contents/../../escaped\n"
        case ("/usr/bin/unzip", let arguments) where arguments.starts(with: ["-Z", "-l"]):
            return "3 files, 1024 bytes uncompressed, 512 bytes compressed: 50.0%"
        case ("/usr/bin/ditto", let arguments) where arguments.starts(with: ["-x", "-k"]):
            let extractedDirectory = URL(fileURLWithPath: arguments[3], isDirectory: true)
            try makeFixtureApplication(in: extractedDirectory)
            return ""
        case ("/usr/bin/ditto", let arguments) where arguments.count == 2:
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: arguments[0], isDirectory: true),
                to: URL(fileURLWithPath: arguments[1], isDirectory: true)
            )
            return ""
        case ("/usr/bin/codesign", let arguments) where arguments.first == "-dvvv":
            return "Identifier=com.electron.ollama\nTeamIdentifier=\(teamIdentifier)\n"
        case ("/usr/bin/codesign", _),
             ("/usr/sbin/spctl", _):
            return ""
        default:
            throw AssistantRuntimeInstallError.commandFailed(
                executable.lastPathComponent,
                arguments.joined(separator: " ")
            )
        }
    }

    private let archiveIsSafe: Bool
    private let teamIdentifier: String

    private func makeFixtureApplication(in directory: URL) throws {
        let contents = directory
            .appendingPathComponent("Ollama.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": AssistantLocalRuntimeDescriptor.ollama.bundleIdentifier,
            "CFBundleName": "Ollama",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.2.3",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
