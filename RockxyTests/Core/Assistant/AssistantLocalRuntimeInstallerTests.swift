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

    @Test("Runtime installer refuses to overwrite an existing application")
    func existingApplication() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }
        let existing = destination.appendingPathComponent("Ollama.app", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        let marker = existing.appendingPathComponent("user-file")
        try Data("keep".utf8).write(to: marker)

        let error = await installError(OllamaRuntimeInstaller(
            downloader: RuntimeArtifactFixtureDownloader(),
            processRunner: RuntimeInstallFixtureProcessRunner()
        ), destination: destination)

        #expect(error == .applicationAlreadyExists(existing))
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(stagingDirectories(in: destination).isEmpty)
    }

    @Test("Runtime installer rejects an application with the wrong bundle identifier")
    func wrongBundleIdentifier() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }

        let error = await installError(OllamaRuntimeInstaller(
            downloader: RuntimeArtifactFixtureDownloader(),
            processRunner: RuntimeInstallFixtureProcessRunner(bundleIdentifier: "com.example.impostor")
        ), destination: destination)

        #expect(error == .unexpectedApplication)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Ollama.app").path))
    }

    @Test(
        "Runtime installer rejects archives that escape, overflow, or expand too far",
        arguments: [
            RuntimeArchiveShape.absolutePath,
            RuntimeArchiveShape.foreignTopLevel,
            RuntimeArchiveShape.empty,
            RuntimeArchiveShape.oversizedExpansion,
            RuntimeArchiveShape.unreadableSummary,
        ]
    )
    func unsafeArchiveShapes(shape: RuntimeArchiveShape) async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }

        let error = await installError(OllamaRuntimeInstaller(
            downloader: RuntimeArtifactFixtureDownloader(),
            processRunner: RuntimeInstallFixtureProcessRunner(archiveShape: shape)
        ), destination: destination)

        #expect(error == .unsafeArchive)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Ollama.app").path))
        #expect(stagingDirectories(in: destination).isEmpty)
    }

    @Test("Runtime installer stops before downloading when the volume lacks free space")
    func insufficientSpace() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }
        let downloader = RuntimeArtifactFixtureDownloader()
        let base = AssistantLocalRuntimeDescriptor.ollama
        let demanding = AssistantLocalRuntimeDescriptor(
            id: base.id,
            displayName: base.displayName,
            applicationName: base.applicationName,
            bundleIdentifier: base.bundleIdentifier,
            expectedTeamIdentifier: base.expectedTeamIdentifier,
            downloadURL: base.downloadURL,
            approximateDownloadBytes: base.approximateDownloadBytes,
            approximateInstalledBytes: base.approximateInstalledBytes,
            minimumFreeBytes: Int64.max,
            modelFamilies: base.modelFamilies
        )

        let error = await installError(
            OllamaRuntimeInstaller(downloader: downloader, processRunner: RuntimeInstallFixtureProcessRunner()),
            destination: destination,
            runtime: demanding
        )

        guard case let .insufficientSpace(requiredBytes, _) = error else {
            Issue.record("Expected insufficient space, got \(String(describing: error))")
            return
        }
        #expect(requiredBytes == Int64.max)
        #expect(stagingDirectories(in: destination).isEmpty)
    }

    @Test("Runtime installer rejects a destination that is not a local folder")
    func invalidDestination() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }
        let installer = OllamaRuntimeInstaller(
            downloader: RuntimeArtifactFixtureDownloader(),
            processRunner: RuntimeInstallFixtureProcessRunner()
        )

        let remote = await installError(installer, destination: try #require(URL(string: "https://example.com/apps")))
        #expect(remote == .invalidDestination)

        let file = destination.appendingPathComponent("not-a-folder")
        try Data().write(to: file)
        let fileError = await installError(installer, destination: file)
        #expect(fileError == .destinationNotWritable(file.standardizedFileURL.resolvingSymlinksInPath()))
    }

    @Test("A download that ends without an artifact is reported as incomplete")
    func incompleteDownload() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }

        let error = await installError(OllamaRuntimeInstaller(
            downloader: RuntimeArtifactFixtureDownloader(completes: false),
            processRunner: RuntimeInstallFixtureProcessRunner()
        ), destination: destination)

        #expect(error == .incompleteDownload)
        #expect(stagingDirectories(in: destination).isEmpty)
    }

    @Test("An installed copy that fails its post-install check is removed")
    func postInstallVerificationFailure() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }

        let error = await installError(OllamaRuntimeInstaller(
            downloader: RuntimeArtifactFixtureDownloader(),
            processRunner: RuntimeInstallFixtureProcessRunner(failingSignatureCheck: 2)
        ), destination: destination)

        #expect(error == .unexpectedSigner)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Ollama.app").path))
    }

    @Test("Cancelling an install mid-download leaves nothing behind")
    func cancellationCleansUp() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }
        let installer = OllamaRuntimeInstaller(
            downloader: RuntimeArtifactFixtureDownloader(completes: false, staysOpen: true),
            processRunner: RuntimeInstallFixtureProcessRunner()
        )

        let consumer = Task {
            for try await event in installer.install(runtime: .ollama, destinationDirectory: destination) {
                if case .downloading = event {
                    return
                }
            }
        }
        try await consumer.value

        var remaining = stagingDirectories(in: destination)
        for _ in 0 ..< 100 where !remaining.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
            remaining = stagingDirectories(in: destination)
        }
        #expect(remaining.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Ollama.app").path))
    }

    @Test("The production downloader refuses plain HTTP sources")
    func insecureDownloadSource() async throws {
        let destination = try makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }
        let downloader = URLSessionAssistantRuntimeArtifactDownloader()

        do {
            for try await _ in downloader.download(
                from: try #require(URL(string: "http://example.invalid/Ollama-darwin.zip")),
                to: destination.appendingPathComponent("runtime.zip"),
                maximumBytes: 1_024
            ) {}
            Issue.record("Expected the HTTP source to be rejected")
        } catch let error as AssistantRuntimeInstallError {
            #expect(error == .insecureDownload)
        }
    }

    private func installError(
        _ installer: OllamaRuntimeInstaller,
        destination: URL,
        runtime: AssistantLocalRuntimeDescriptor = .ollama
    ) async -> AssistantRuntimeInstallError? {
        do {
            for try await _ in installer.install(runtime: runtime, destinationDirectory: destination) {}
            return nil
        } catch let error as AssistantRuntimeInstallError {
            return error
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }

    private func stagingDirectories(in destination: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
        return names.filter { $0.hasPrefix(".rockxy-runtime-") }
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
    var completes = true
    /// Keeps the stream open after the first progress event, like a slow network download.
    var staysOpen = false

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
                if staysOpen {
                    return
                }
                if completes {
                    continuation.yield(.completed(fileURL: fileURL))
                }
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
        archiveShape: RuntimeArchiveShape? = nil,
        teamIdentifier: String = AssistantLocalRuntimeDescriptor.ollama.expectedTeamIdentifier,
        bundleIdentifier: String = AssistantLocalRuntimeDescriptor.ollama.bundleIdentifier,
        failingSignatureCheck: Int? = nil
    ) {
        self.archiveIsSafe = archiveIsSafe
        self.archiveShape = archiveShape
        self.teamIdentifier = teamIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.failingSignatureCheck = failingSignatureCheck
    }

    func run(executable: URL, arguments: [String]) async throws -> String {
        switch (executable.path, arguments) {
        case ("/usr/bin/unzip", let arguments) where arguments.starts(with: ["-Z", "-1"]):
            switch archiveShape {
            case .absolutePath:
                return "Ollama.app/\n/Ollama.app/Contents/Info.plist\n"
            case .foreignTopLevel:
                return "Ollama.app/\nOther.app/Contents/Info.plist\n"
            case .empty:
                return ""
            case .oversizedExpansion,
                 .unreadableSummary,
                 nil:
                break
            }
            if archiveIsSafe {
                return "Ollama.app/\nOllama.app/Contents/\nOllama.app/Contents/Info.plist\n"
            }
            return "Ollama.app/\nOllama.app/Contents/../../escaped\n"
        case ("/usr/bin/unzip", let arguments) where arguments.starts(with: ["-Z", "-l"]):
            switch archiveShape {
            case .oversizedExpansion:
                return "3 files, 9000000000 bytes uncompressed, 512 bytes compressed: 99.9%"
            case .unreadableSummary:
                return "garbled"
            default:
                return "3 files, 1024 bytes uncompressed, 512 bytes compressed: 50.0%"
            }
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
            signatureChecks += 1
            if signatureChecks == failingSignatureCheck {
                return "Identifier=com.electron.ollama\nTeamIdentifier=UNTRUSTED\n"
            }
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
    private let archiveShape: RuntimeArchiveShape?
    private let teamIdentifier: String
    private let bundleIdentifier: String
    private let failingSignatureCheck: Int?
    private var signatureChecks = 0

    private func makeFixtureApplication(in directory: URL) throws {
        let contents = directory
            .appendingPathComponent("Ollama.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
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

// MARK: - RuntimeArchiveShape

enum RuntimeArchiveShape: Sendable, CustomTestStringConvertible {
    case absolutePath
    case foreignTopLevel
    case empty
    case oversizedExpansion
    case unreadableSummary

    var testDescription: String {
        switch self {
        case .absolutePath: "absolute path entry"
        case .foreignTopLevel: "entry outside the app bundle"
        case .empty: "no entries"
        case .oversizedExpansion: "expands past the size limit"
        case .unreadableSummary: "unreadable size summary"
        }
    }
}
