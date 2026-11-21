import Darwin
import Foundation

// MARK: - RuntimeProbeProcessResult

struct RuntimeProbeProcessResult: Sendable {
    let terminationStatus: Int32
    let stdout: String
    let stderr: String
}

// MARK: - RuntimeProbeProcessError

enum RuntimeProbeProcessError: Error {
    case timedOut
}

// MARK: - RuntimeProbeProcessRunner

/// Keeps process launch and pipe I/O off the cooperative executor. The deadline covers
/// launch as well as execution; inherited pipe writers cannot keep a finished probe alive.
final class RuntimeProbeProcessRunner: @unchecked Sendable {
    // MARK: Lifecycle

    private init(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        timeout: Duration
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
    }

    // MARK: Internal

    static func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: Duration = .seconds(20)
    )
        async throws -> RuntimeProbeProcessResult
    {
        let runner = RuntimeProbeProcessRunner(
            executableURL: executableURL, arguments: arguments,
            workingDirectory: workingDirectory, environment: environment, timeout: timeout
        )
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { runner.start($0) }
        } onCancel: {
            runner.finish(.failure(CancellationError()))
        }
    }

    // MARK: Private

    private let executableURL: URL
    private let arguments: [String]
    private let workingDirectory: URL?
    private let environment: [String: String]?
    private let timeout: Duration
    private let lock = NSLock()
    private var result: Result<RuntimeProbeProcessResult, Error>?
    private var continuation: CheckedContinuation<RuntimeProbeProcessResult, Error>?
    private var deadline: DispatchWorkItem?

    private var isFinished: Bool {
        lock.withLock { result != nil }
    }

    private func start(_ continuation: CheckedContinuation<RuntimeProbeProcessResult, Error>) {
        let deadline = DispatchWorkItem { [weak self] in
            self?.finish(.failure(RuntimeProbeProcessError.timedOut))
        }
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        self.deadline = deadline
        lock.unlock()
        let components = timeout.components
        let seconds = max(0.001, Double(components.seconds) + Double(components.attoseconds) / 1e18)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: deadline)
        DispatchQueue.global(qos: .utility).async { self.collect() }
    }

    private func finish(_ result: Result<RuntimeProbeProcessResult, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let deadline = deadline
        self.deadline = nil
        lock.unlock()
        deadline?.cancel()
        // The collector normally delivers after cleanup. Keep launch itself bounded
        // if an OS spawn call does not return promptly enough to reach that cleanup.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.deliver()
        }
    }

    private func deliver() {
        lock.lock()
        guard let result, let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }

    private func collect() {
        defer { deliver() }
        guard !isFinished else {
            return
        }
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        defer {
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForReading.close()
            try? errors.fileHandleForWriting.close()
        }
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        if let environment {
            process.environment = environment
        }
        process.standardOutput = output
        process.standardError = errors
        do {
            let outputFD = output.fileHandleForReading.fileDescriptor
            let errorFD = errors.fileHandleForReading.fileDescriptor
            try makeNonblocking(outputFD)
            try makeNonblocking(errorFD)
            try process.run()
            let pid = process.processIdentifier
            let ownsGroup = pid > 0 && getpgid(pid) == pid
            defer { terminateOwnedProcess(process, ownsGroup: ownsGroup) }
            var stdout = Data()
            var stderr = Data()
            while !isFinished {
                try drain(outputFD, into: &stdout)
                try drain(errorFD, into: &stderr)
                if !process.isRunning {
                    // Drain buffered bytes once more, without awaiting EOF from descendants.
                    try drain(outputFD, into: &stdout)
                    try drain(errorFD, into: &stderr)
                    finish(.success(RuntimeProbeProcessResult(
                        terminationStatus: process.terminationStatus,
                        stdout: String(bytes: stdout, encoding: .utf8) ?? "",
                        stderr: String(bytes: stderr, encoding: .utf8) ?? ""
                    )))
                    return
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        } catch {
            finish(.failure(error))
        }
    }

    private func makeNonblocking(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func drain(_ fd: Int32, into data: inout Data) throws {
        var bytes = [UInt8](repeating: 0, count: 8_192)
        // Bound work per poll as well as retained diagnostics; always drain both streams.
        for _ in 0 ..< 32 {
            guard !isFinished else {
                return
            }
            let count = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                data.append(contentsOf: bytes.prefix(min(count, max(0, 1_048_576 - data.count))))
            } else if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else if errno != EINTR {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }
    }

    private func terminateOwnedProcess(_ process: Process, ownsGroup: Bool) {
        let pid = process.processIdentifier
        guard pid > 0 else {
            return
        }
        func groupExists() -> Bool {
            ownsGroup && kill(-pid, 0) == 0
        }
        if groupExists() {
            kill(-pid, SIGTERM)
        } else if process.isRunning {
            process.terminate()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while process.isRunning || groupExists(), ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if groupExists() {
            kill(-pid, SIGKILL)
        } else if process.isRunning {
            kill(pid, SIGKILL)
        }
    }
}
