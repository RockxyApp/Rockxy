import Foundation

// MARK: - AssistantLocalRuntimeDescriptor

/// Distribution identity for a local inference runtime managed from Rockxy.
/// Model families stay separate because one runtime can host many independent model catalogs.
struct AssistantLocalRuntimeDescriptor: Equatable, Sendable {
    static let ollama = AssistantLocalRuntimeDescriptor(
        id: "ollama",
        displayName: "Ollama",
        applicationName: "Ollama.app",
        bundleIdentifier: "com.electron.ollama",
        expectedTeamIdentifier: "3MU9H2V9Y9",
        downloadURL: URL(string: "https://ollama.com/download/Ollama-darwin.zip")!,
        approximateDownloadBytes: 185_000_000,
        approximateInstalledBytes: 600_000_000,
        minimumFreeBytes: 2_000_000_000,
        modelFamilies: ["Llama", "Qwen", "DeepSeek", "Gemma", "Mistral", "Phi"]
    )

    let id: String
    let displayName: String
    let applicationName: String
    let bundleIdentifier: String
    let expectedTeamIdentifier: String
    let downloadURL: URL
    let approximateDownloadBytes: Int64
    let approximateInstalledBytes: Int64
    let minimumFreeBytes: Int64
    let modelFamilies: [String]
}

// MARK: - AssistantRuntimeInstallation

struct AssistantRuntimeInstallation: Equatable, Sendable {
    let applicationURL: URL
    let version: String
}

// MARK: - AssistantRuntimeInstallEvent

enum AssistantRuntimeInstallEvent: Equatable, Sendable {
    case downloading(receivedBytes: Int64, totalBytes: Int64?)
    case verifying
    case installing
    case completed(AssistantRuntimeInstallation)
}

// MARK: - AssistantLocalRuntimeInstalling

protocol AssistantLocalRuntimeInstalling: Sendable {
    func install(
        runtime: AssistantLocalRuntimeDescriptor,
        destinationDirectory: URL
    ) -> AsyncThrowingStream<AssistantRuntimeInstallEvent, Error>
}

// MARK: - AssistantRuntimeArtifactDownloadEvent

enum AssistantRuntimeArtifactDownloadEvent: Sendable {
    case progress(receivedBytes: Int64, totalBytes: Int64?)
    case completed(fileURL: URL)
}

protocol AssistantRuntimeArtifactDownloading: Sendable {
    func download(
        from url: URL,
        to fileURL: URL,
        maximumBytes: Int64
    ) -> AsyncThrowingStream<AssistantRuntimeArtifactDownloadEvent, Error>
}

// MARK: - AssistantProcessRunning

protocol AssistantProcessRunning: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> String
}

// MARK: - OllamaRuntimeInstaller

struct OllamaRuntimeInstaller: AssistantLocalRuntimeInstalling {
    // MARK: Lifecycle

    init(
        downloader: any AssistantRuntimeArtifactDownloading,
        processRunner: any AssistantProcessRunning
    ) {
        self.downloader = downloader
        self.processRunner = processRunner
    }

    // MARK: Internal

    static let shared = OllamaRuntimeInstaller(
        downloader: URLSessionAssistantRuntimeArtifactDownloader(),
        processRunner: SystemAssistantProcessRunner()
    )

    func install(
        runtime: AssistantLocalRuntimeDescriptor,
        destinationDirectory: URL
    ) -> AsyncThrowingStream<AssistantRuntimeInstallEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let destinationDirectory = try validatedDestination(
                        destinationDirectory,
                        runtime: runtime
                    )
                    let stagingDirectory = destinationDirectory.appendingPathComponent(
                        ".rockxy-runtime-\(UUID().uuidString)",
                        isDirectory: true
                    )
                    try FileManager.default.createDirectory(
                        at: stagingDirectory,
                        withIntermediateDirectories: false
                    )
                    defer {
                        try? FileManager.default.removeItem(at: stagingDirectory)
                    }

                    let archiveURL = stagingDirectory.appendingPathComponent("runtime.zip")
                    let maximumDownloadBytes = max(
                        runtime.approximateDownloadBytes * 4,
                        750_000_000
                    )
                    let download = downloader.download(
                        from: runtime.downloadURL,
                        to: archiveURL,
                        maximumBytes: maximumDownloadBytes
                    )
                    var downloadedArtifact: URL?
                    for try await event in download {
                        try Task.checkCancellation()
                        switch event {
                        case let .progress(receivedBytes, totalBytes):
                            continuation.yield(.downloading(
                                receivedBytes: receivedBytes,
                                totalBytes: totalBytes
                            ))
                        case let .completed(fileURL):
                            downloadedArtifact = fileURL
                        }
                    }
                    let artifactURL = try downloadedArtifact.orThrow(
                        AssistantRuntimeInstallError.incompleteDownload
                    )

                    continuation.yield(.verifying)
                    try await validateArchive(artifactURL, runtime: runtime)
                    let extractedDirectory = stagingDirectory.appendingPathComponent(
                        "extracted",
                        isDirectory: true
                    )
                    try FileManager.default.createDirectory(
                        at: extractedDirectory,
                        withIntermediateDirectories: false
                    )
                    _ = try await processRunner.run(
                        executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                        arguments: ["-x", "-k", artifactURL.path, extractedDirectory.path]
                    )
                    let extractedApplication = extractedDirectory.appendingPathComponent(
                        runtime.applicationName,
                        isDirectory: true
                    )
                    let version = try await validateApplication(
                        extractedApplication,
                        runtime: runtime
                    )

                    continuation.yield(.installing)
                    let installedApplication = destinationDirectory.appendingPathComponent(
                        runtime.applicationName,
                        isDirectory: true
                    )
                    guard !FileManager.default.fileExists(atPath: installedApplication.path) else {
                        throw AssistantRuntimeInstallError.applicationAlreadyExists(installedApplication)
                    }
                    _ = try await processRunner.run(
                        executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                        arguments: [extractedApplication.path, installedApplication.path]
                    )
                    do {
                        _ = try await validateApplication(installedApplication, runtime: runtime)
                    } catch {
                        try? FileManager.default.removeItem(at: installedApplication)
                        throw error
                    }
                    continuation.yield(.completed(AssistantRuntimeInstallation(
                        applicationURL: installedApplication,
                        version: version
                    )))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: Private

    private static let maximumArchiveEntries = 10_000
    private static let maximumExpandedBytes: Int64 = 1_500_000_000

    private let downloader: any AssistantRuntimeArtifactDownloading
    private let processRunner: any AssistantProcessRunning

    private func validatedDestination(
        _ destinationDirectory: URL,
        runtime: AssistantLocalRuntimeDescriptor
    ) throws -> URL {
        guard destinationDirectory.isFileURL else {
            throw AssistantRuntimeInstallError.invalidDestination
        }
        let destinationDirectory = destinationDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let values = try destinationDirectory.resourceValues(forKeys: [
            .isDirectoryKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        guard values.isDirectory == true,
              FileManager.default.isWritableFile(atPath: destinationDirectory.path) else
        {
            throw AssistantRuntimeInstallError.destinationNotWritable(destinationDirectory)
        }
        if let capacity = values.volumeAvailableCapacityForImportantUsage,
           capacity < runtime.minimumFreeBytes
        {
            throw AssistantRuntimeInstallError.insufficientSpace(
                requiredBytes: runtime.minimumFreeBytes,
                availableBytes: capacity
            )
        }
        return destinationDirectory
    }

    private func validateArchive(
        _ archiveURL: URL,
        runtime: AssistantLocalRuntimeDescriptor
    ) async throws {
        let entriesOutput = try await processRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z", "-1", archiveURL.path]
        )
        let entries = entriesOutput.split(whereSeparator: \.isNewline).map(String.init)
        guard !entries.isEmpty, entries.count <= Self.maximumArchiveEntries else {
            throw AssistantRuntimeInstallError.unsafeArchive
        }
        let expectedPrefix = "\(runtime.applicationName)/"
        guard entries.allSatisfy({ entry in
            entry.hasPrefix(expectedPrefix)
                && !entry.hasPrefix("/")
                && !entry.split(separator: "/").contains("..")
        }) else {
            throw AssistantRuntimeInstallError.unsafeArchive
        }

        let summary = try await processRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z", "-l", archiveURL.path]
        )
        guard let expandedBytes = archiveExpandedBytes(from: summary),
              expandedBytes > 0,
              expandedBytes <= Self.maximumExpandedBytes else
        {
            throw AssistantRuntimeInstallError.unsafeArchive
        }
    }

    private func archiveExpandedBytes(from summary: String) -> Int64? {
        let pattern = #"\d+ files?,\s+(\d+) bytes uncompressed"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: summary,
                  range: NSRange(summary.startIndex..., in: summary)
              ),
              let range = Range(match.range(at: 1), in: summary) else
        {
            return nil
        }
        return Int64(summary[range])
    }

    private func validateApplication(
        _ applicationURL: URL,
        runtime: AssistantLocalRuntimeDescriptor
    ) async throws -> String {
        let resourceValues = try applicationURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard resourceValues.isDirectory == true,
              resourceValues.isSymbolicLink != true,
              let bundle = Bundle(url: applicationURL),
              bundle.bundleIdentifier == runtime.bundleIdentifier else
        {
            throw AssistantRuntimeInstallError.unexpectedApplication
        }

        _ = try await processRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--deep", "--strict", "--verbose=2", applicationURL.path]
        )
        _ = try await processRunner.run(
            executable: URL(fileURLWithPath: "/usr/sbin/spctl"),
            arguments: ["--assess", "--type", "execute", "--verbose=4", applicationURL.path]
        )
        let signature = try await processRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["-dvvv", applicationURL.path]
        )
        guard signature.split(whereSeparator: \.isNewline).contains(where: {
            $0 == "TeamIdentifier=\(runtime.expectedTeamIdentifier)"
        }) else {
            throw AssistantRuntimeInstallError.unexpectedSigner
        }
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else
        {
            throw AssistantRuntimeInstallError.unexpectedApplication
        }
        return version
    }
}

// MARK: - URLSessionAssistantRuntimeArtifactDownloader

final class URLSessionAssistantRuntimeArtifactDownloader: AssistantRuntimeArtifactDownloading, @unchecked Sendable {
    func download(
        from url: URL,
        to fileURL: URL,
        maximumBytes: Int64
    ) -> AsyncThrowingStream<AssistantRuntimeArtifactDownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            let operation = AssistantRuntimeArtifactDownloadOperation(
                sourceURL: url,
                destinationURL: fileURL,
                maximumBytes: maximumBytes,
                continuation: continuation
            )
            continuation.onTermination = { _ in
                operation.cancel()
            }
            operation.start()
        }
    }
}

// MARK: - AssistantRuntimeArtifactDownloadOperation

private final class AssistantRuntimeArtifactDownloadOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        sourceURL: URL,
        destinationURL: URL,
        maximumBytes: Int64,
        continuation: AsyncThrowingStream<AssistantRuntimeArtifactDownloadEvent, Error>.Continuation
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.maximumBytes = maximumBytes
        self.continuation = continuation
    }

    // MARK: Internal

    func start() {
        delegateQueue.addOperation { [weak self] in
            self?.startOnDelegateQueue()
        }
    }

    func cancel() {
        delegateQueue.addOperation { [weak self] in
            self?.cancelOnDelegateQueue()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https" else {
            completionHandler(nil)
            finish(throwing: AssistantRuntimeInstallError.insecureDownload)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard response.url?.scheme?.lowercased() == "https",
              let response = response as? HTTPURLResponse,
              (200 ... 299).contains(response.statusCode) else
        {
            completionHandler(.cancel)
            finish(throwing: AssistantRuntimeInstallError.downloadRejected)
            return
        }
        if response.expectedContentLength > maximumBytes {
            completionHandler(.cancel)
            finish(throwing: AssistantRuntimeInstallError.downloadTooLarge)
            return
        }
        expectedBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isFinished else {
            return
        }
        receivedBytes += Int64(data.count)
        guard receivedBytes <= maximumBytes else {
            dataTask.cancel()
            finish(throwing: AssistantRuntimeInstallError.downloadTooLarge)
            return
        }
        do {
            try fileHandle?.write(contentsOf: data)
            continuation.yield(.progress(
                receivedBytes: receivedBytes,
                totalBytes: expectedBytes
            ))
        } catch {
            dataTask.cancel()
            finish(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard !isFinished else {
            return
        }
        if let error {
            finish(throwing: error)
            return
        }
        guard receivedBytes > 0 else {
            finish(throwing: AssistantRuntimeInstallError.incompleteDownload)
            return
        }
        try? fileHandle?.close()
        fileHandle = nil
        didDeliverArtifact = true
        continuation.yield(.completed(fileURL: destinationURL))
        isFinished = true
        continuation.finish()
        session.finishTasksAndInvalidate()
    }

    // MARK: Private

    private let sourceURL: URL
    private let destinationURL: URL
    private let maximumBytes: Int64
    private let continuation: AsyncThrowingStream<AssistantRuntimeArtifactDownloadEvent, Error>.Continuation
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.amunx.rockxy.assistant-runtime-download"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var receivedBytes: Int64 = 0
    private var expectedBytes: Int64?
    private var isFinished = false
    private var didDeliverArtifact = false

    private func startOnDelegateQueue() {
        guard sourceURL.scheme?.lowercased() == "https" else {
            finish(throwing: AssistantRuntimeInstallError.insecureDownload)
            return
        }
        guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            finish(throwing: AssistantRuntimeInstallError.destinationNotWritable(destinationURL))
            return
        }
        do {
            fileHandle = try FileHandle(forWritingTo: destinationURL)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 60 * 30
            let session = URLSession(
                configuration: configuration,
                delegate: self,
                delegateQueue: delegateQueue
            )
            self.session = session
            let task = session.dataTask(with: sourceURL)
            dataTask = task
            task.resume()
        } catch {
            finish(throwing: error)
        }
    }

    private func cancelOnDelegateQueue() {
        guard !didDeliverArtifact else {
            return
        }
        dataTask?.cancel()
        finish(throwing: CancellationError())
    }

    private func finish(throwing error: Error) {
        guard !isFinished else {
            return
        }
        isFinished = true
        try? fileHandle?.close()
        fileHandle = nil
        session?.invalidateAndCancel()
        try? FileManager.default.removeItem(at: destinationURL)
        continuation.finish(throwing: error)
    }
}

// MARK: - SystemAssistantProcessRunner

struct SystemAssistantProcessRunner: AssistantProcessRunning {
    func run(executable: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()

            var data = Data()
            while let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1_024),
                  !chunk.isEmpty
            {
                data.append(chunk)
                guard data.count <= 4 * 1_024 * 1_024 else {
                    process.terminate()
                    throw AssistantRuntimeInstallError.processOutputTooLarge
                }
            }
            process.waitUntilExit()
            try Task.checkCancellation()
            let text = String(data: data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw AssistantRuntimeInstallError.commandFailed(
                    executable.lastPathComponent,
                    String(text.prefix(2_048))
                )
            }
            return text
        }.value
    }
}

// MARK: - AssistantRuntimeInstallError

enum AssistantRuntimeInstallError: LocalizedError, Equatable {
    case insecureDownload
    case downloadRejected
    case downloadTooLarge
    case incompleteDownload
    case invalidDestination
    case destinationNotWritable(URL)
    case insufficientSpace(requiredBytes: Int64, availableBytes: Int64)
    case applicationAlreadyExists(URL)
    case unsafeArchive
    case unexpectedApplication
    case unexpectedSigner
    case processOutputTooLarge
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .insecureDownload:
            String(localized: "Rockxy only installs local runtimes from an encrypted HTTPS source.")
        case .downloadRejected:
            String(localized: "The runtime download server rejected the request.")
        case .downloadTooLarge:
            String(localized: "The runtime download exceeded Rockxy's safety limit.")
        case .incompleteDownload:
            String(localized: "The runtime download ended before the artifact was complete.")
        case .invalidDestination:
            String(localized: "Choose a local folder where the runtime application can be installed.")
        case let .destinationNotWritable(url):
            String(localized: "Rockxy cannot write to \(url.path). Choose another install folder.")
        case let .insufficientSpace(requiredBytes, availableBytes):
            String(
                localized: "The selected volume needs at least \(Self.formatted(requiredBytes)) free; \(Self.formatted(availableBytes)) is available."
            )
        case let .applicationAlreadyExists(url):
            String(localized: "An application already exists at \(url.path). Open it or choose another folder.")
        case .unsafeArchive:
            String(localized: "The downloaded runtime archive failed Rockxy's structure and size checks.")
        case .unexpectedApplication:
            String(localized: "The downloaded application does not match the expected runtime identity.")
        case .unexpectedSigner:
            String(localized: "The downloaded application was not signed by the expected developer.")
        case .processOutputTooLarge:
            String(localized: "Runtime verification produced more output than Rockxy allows.")
        case let .commandFailed(command, detail):
            String(localized: "Runtime setup failed while running \(command): \(detail)")
        }
    }

    private static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private extension Optional {
    func orThrow(_ error: @autoclosure () -> Error) throws -> Wrapped {
        guard let self else {
            throw error()
        }
        return self
    }
}
