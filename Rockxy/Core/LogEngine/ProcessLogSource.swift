import Foundation
import os

/// Captures stdout and stderr from a child process by attaching `Pipe` handles.
/// Each line of output is emitted as a `LogEntry` — stdout at `.info`, stderr at `.warning`.
enum ProcessLogSource {
    // MARK: Internal

    /// Holds a reference to the spawned `Process` and its monitor task for cleanup.
    final class CapturedProcess: @unchecked Sendable {
        // MARK: Lifecycle

        init(process: Process, monitorTask: Task<Void, Never>) {
            self.process = process
            self.monitorTask = monitorTask
        }

        // MARK: Internal

        let process: Process
        let monitorTask: Task<Void, Never>
    }

    @MainActor
    static func captureProcess(
        executablePath: String,
        arguments: [String],
        handler: @Sendable @escaping (LogEntry) -> Void
    )
        -> CapturedProcess?
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            Self.logger.error("Failed to launch process at \(executablePath): \(error.localizedDescription)")
            return nil
        }

        let pid = process.processIdentifier
        let processName = URL(fileURLWithPath: executablePath).lastPathComponent

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }

            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for line in lines {
                let entry = LogEntry(
                    id: UUID(),
                    timestamp: Date(),
                    level: .info,
                    message: Self.redactCredentials(line),
                    source: .processStdout(pid: pid),
                    processName: processName,
                    subsystem: nil,
                    category: nil,
                    metadata: [:],
                    correlatedTransactionId: nil
                )
                handler(entry)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }

            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for line in lines {
                let entry = LogEntry(
                    id: UUID(),
                    timestamp: Date(),
                    level: .warning,
                    message: Self.redactCredentials(line),
                    source: .processStderr(pid: pid),
                    processName: processName,
                    subsystem: nil,
                    category: nil,
                    metadata: [:],
                    correlatedTransactionId: nil
                )
                handler(entry)
            }
        }

        let monitorTask = Task {
            process.waitUntilExit()

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            Self.logger.info("Process \(executablePath) (PID \(pid)) exited with code \(process.terminationStatus)")
        }

        Self.logger.info("Started capturing process \(executablePath) (PID \(pid))")
        return CapturedProcess(process: process, monitorTask: monitorTask)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProcessLogSource")

    private static let bearerRegex = try? NSRegularExpression(pattern: #"(?i)Bearer\s+\S+"#)
    private static let passwordRegex = try? NSRegularExpression(pattern: #"(?i)password\s*(?:=|:)\s*\S+"#)

    private static func redactCredentials(_ line: String) -> String {
        var result = line
        let fullRange = NSRange(result.startIndex..., in: result)
        if let regex = bearerRegex {
            result = regex.stringByReplacingMatches(in: result, range: fullRange, withTemplate: "Bearer [REDACTED]")
        }
        let updatedRange = NSRange(result.startIndex..., in: result)
        if let regex = passwordRegex {
            result = regex.stringByReplacingMatches(
                in: result,
                range: updatedRange,
                withTemplate: "password=[REDACTED]"
            )
        }
        return result
    }
}
