import Foundation
import os

/// Central coordinator for all log capture sources (OSLog, process stdout/stderr, custom).
///
/// Manages the lifecycle of individual log streams — starting, stopping, and routing
/// incoming entries through a single `onLogEntry` callback. Designed as an actor to
/// safely manage stream state from multiple callers without locks.
actor LogCaptureEngine {
    // MARK: Internal

    var onLogEntry: (@Sendable (LogEntry) -> Void)?

    var activeStreams: [LogStream] {
        Array(streams.values.filter(\.isActive))
    }

    var capturing: Bool {
        isCapturing
    }

    func setOnLogEntry(_ handler: @escaping @Sendable (LogEntry) -> Void) {
        onLogEntry = handler
    }

    func startCapture() {
        guard !isCapturing else {
            return
        }
        isCapturing = true

        for (id, stream) in streams where stream.isActive {
            startStream(id: id, stream: stream)
        }

        Self.logger.info("Log capture started with \(self.streams.count) stream(s)")
    }

    func stopCapture() {
        for (id, task) in activeTasks {
            task.cancel()
            Self.logger.debug("Cancelled task for stream \(id)")
        }
        activeTasks.removeAll()

        for (id, captured) in capturedProcesses {
            terminateProcess(captured)
            captured.monitorTask.cancel()
            Self.logger.debug("Terminated process for stream \(id)")
        }
        capturedProcesses.removeAll()

        isCapturing = false
        Self.logger.info("Log capture stopped")
    }

    func addStream(_ stream: LogStream) {
        streams[stream.id] = stream

        if isCapturing, stream.isActive {
            startStream(id: stream.id, stream: stream)
        }
    }

    func removeStream(id: UUID) {
        streams.removeValue(forKey: id)

        if let task = activeTasks.removeValue(forKey: id) {
            task.cancel()
        }

        if let captured = capturedProcesses.removeValue(forKey: id) {
            terminateProcess(captured)
            captured.monitorTask.cancel()
        }
    }

    // MARK: - Process Capture

    func addProcessStream(
        executablePath: String,
        arguments: [String] = [],
        name: String? = nil
    )
        async -> UUID?
    {
        let streamName = name ?? URL(fileURLWithPath: executablePath).lastPathComponent
        let handler = makeEntryHandler()

        guard let captured = await MainActor.run(body: {
            ProcessLogSource.captureProcess(
                executablePath: executablePath,
                arguments: arguments,
                handler: handler
            )
        }) else {
            Self.logger.error("Failed to start process capture for \(executablePath)")
            return nil
        }

        let pid = await MainActor.run { captured.process.processIdentifier }

        let streamId = UUID()
        let stream = LogStream(
            id: streamId,
            name: streamName,
            source: .processStdout(pid: pid),
            isActive: true
        )

        streams[streamId] = stream
        capturedProcesses[streamId] = captured

        Self.logger.info("Added process stream '\(streamName)' (PID \(pid))")
        return streamId
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "LogCaptureEngine")

    private var isCapturing = false
    private var streams: [UUID: LogStream] = [:]
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var capturedProcesses: [UUID: ProcessLogSource.CapturedProcess] = [:]

    private func startStream(id: UUID, stream: LogStream) {
        let handler = makeEntryHandler()

        switch stream.source {
        case let .oslog(subsystem):
            let task = OSLogSource.startStreaming(
                subsystem: subsystem,
                since: Date(),
                handler: handler
            )
            activeTasks[id] = task

        case let .processStdout(pid),
             let .processStderr(pid):
            Self.logger.warning(
                "Cannot start process stream from LogSource with PID \(pid). Use addProcessStream instead."
            )

        case .custom:
            Self.logger.debug("Custom log source for stream \(id) — no built-in handler")
        }
    }

    /// nonisolated so the closure can be passed to non-actor log sources
    private nonisolated func makeEntryHandler() -> @Sendable (LogEntry) -> Void {
        { [weak self] entry in
            guard let self else {
                return
            }
            Task {
                await self.handleEntry(entry)
            }
        }
    }

    private func handleEntry(_ entry: LogEntry) {
        onLogEntry?(entry)
    }

    private nonisolated func terminateProcess(_ captured: ProcessLogSource.CapturedProcess) {
        Task { @MainActor in
            if captured.process.isRunning {
                captured.process.terminate()
            }
        }
    }
}
