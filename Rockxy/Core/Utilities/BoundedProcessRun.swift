import Darwin
import Foundation

// MARK: - BoundedProcessRun

/// Bounded runner for the app's short-lived, unprivileged child processes.
///
/// Every call site this exists for had the same two defects. The first is the ordering:
/// `waitUntilExit()` before `readDataToEndOfFile()` deadlocks outright once the child outgrows
/// the pipe buffer, because the child blocks writing while this process blocks waiting — the same
/// reasoning `SystemProxyManager.runNetworkSetup` spells out inline for `networksetup`. The second
/// is that there was no deadline at all, and several of these children are `osascript` showing a
/// modal administrator-password or Automation consent dialog: a user who ignores that dialog
/// parked a thread for as long as they liked, and the flow that spawned it never returned.
///
/// This is the app-side counterpart to `BoundedHelperCommand`, which the helper daemon uses for
/// the same reasons. It is a separate runner rather than a second entry point on that one because
/// `BoundedHelperCommand` deliberately refuses any budget over 30 seconds, and the two commands
/// here that wait on a human cannot be bounded that tightly without failing a user who is simply
/// slow to type a password.
///
/// Both pipes are drained concurrently and only then is the exit awaited, under a deadline. Output
/// past `outputLimit` fails the call instead of being silently shortened, because a caller parsing
/// a tool's output cannot tell a truncated reading from a short one. A child that outlives either
/// budget is terminated, killed if it ignores SIGTERM, and reaped on every exit path — including
/// the overflow path, which previously threw while leaving the child unreaped.
enum BoundedProcessRun {
    // MARK: Internal

    struct Output {
        let status: Int32
        /// True when the child was killed by a signal, in which case `status` is that signal
        /// number rather than an exit code. Foundation reports the two in the same property, so
        /// a caller that tells them apart needs this alongside it.
        let wasSignalled: Bool
        let standardOutput: Data
        let standardError: Data

        /// The child's complete output, for a caller that merged the two streams.
        ///
        /// Decoded leniently rather than failably: a reading that stops at the output budget can
        /// end mid-character, and a strict decode returns nil for the whole transcript when it
        /// does — which is how a readable error message becomes no error message at all.
        var combinedText: String {
            // swiftlint:disable:next optional_data_string_conversion
            String(decoding: standardOutput + standardError, as: UTF8.self)
        }
    }

    enum Failure: Error, Equatable {
        case invalidTimeout
        /// The child was still running at its deadline and has been terminated.
        case timedOut
        /// The child produced more than its budget, so the reading is incomplete and unusable.
        case outputTooLarge
    }

    /// The default output budget. Generous for the version strings and archive listings these
    /// commands produce, and small enough that a runaway child cannot grow the app's footprint.
    static let defaultOutputLimit = 4 * 1_024 * 1_024

    /// Runs `executable` under `timeout`, draining both pipes before awaiting the exit.
    ///
    /// A failure to launch is rethrown unchanged so callers keep their existing mapping for it.
    /// `mergesStandardError` points both of the child's streams at one pipe, which is what a
    /// caller that reports a single interleaved transcript needs; `standardError` is then empty.
    static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = defaultOutputLimit,
        mergesStandardError: Bool = false
    )
        throws -> Output
    {
        guard timeout.isFinite, timeout > 0 else {
            throw Failure.invalidTimeout
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = mergesStandardError ? outputPipe : Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        // Nothing here reads standard input, and inheriting the app's would let a child that
        // tried consume input meant for the app itself.
        process.standardInput = FileHandle.nullDevice

        try process.run()

        let sink = OutputSink(limit: outputLimit)
        let reads = DispatchGroup()
        let drains: [(Pipe, Bool)] = mergesStandardError
            ? [(outputPipe, true)]
            : [(outputPipe, true), (errorPipe, false)]
        for (pipe, isStandardOutput) in drains {
            Self.queue.async(group: reads) {
                sink.drain(pipe.fileHandleForReading, isStandardOutput: isStandardOutput)
            }
        }

        if let failure = Self.waitForDrains(reads, deadline: Date().addingTimeInterval(timeout), sink: sink) {
            terminateAndReap(process)
            // The drains are only waited for so their threads unwind; the child is gone, so both
            // read ends are at EOF and this cannot be the thing that blocks.
            _ = reads.wait(timeout: .now() + Self.drainUnwindGrace)
            throw failure
        }

        process.waitUntilExit()
        if sink.didOverflow {
            throw Failure.outputTooLarge
        }
        return Output(
            status: process.terminationStatus,
            wasSignalled: process.terminationReason == .uncaughtSignal,
            standardOutput: sink.standardOutput,
            standardError: sink.standardError
        )
    }

    /// The same bounded run, moved off the caller's executor.
    ///
    /// The waits above are blocking, so running them on the Swift cooperative pool — which is
    /// what a bare `Task.detached` does — spends one of its fixed threads for the whole budget.
    /// For a child sitting on a modal password dialog that is minutes of a pool thread, which is
    /// exactly how the force-remove flow used to wedge.
    static func runDetached(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = defaultOutputLimit,
        mergesStandardError: Bool = false
    )
        async throws -> Output
    {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    try run(
                        executable: executable,
                        arguments: arguments,
                        timeout: timeout,
                        outputLimit: outputLimit,
                        mergesStandardError: mergesStandardError
                    )
                })
            }
        }
    }

    // MARK: Private

    /// Collects both of a child's streams from the queue draining them, bounded.
    private final class OutputSink: @unchecked Sendable {
        // MARK: Lifecycle

        init(limit: Int) {
            self.limit = limit
        }

        // MARK: Internal

        var standardOutput: Data {
            lock.withLock { outputData }
        }

        var standardError: Data {
            lock.withLock { errorData }
        }

        var didOverflow: Bool {
            lock.withLock { overflowed }
        }

        /// Reads one stream to EOF, keeping bytes only while they fit the budget.
        ///
        /// Reading continues past the budget with the excess discarded. Stopping instead would
        /// recreate the full-pipe deadlock this runner exists to prevent, and the child has to be
        /// able to drain its buffer in order to act on the signal that ends it.
        func drain(_ handle: FileHandle, isStandardOutput: Bool) {
            while let chunk = try? handle.read(upToCount: Self.readSize), !chunk.isEmpty {
                lock.withLock {
                    guard !overflowed else {
                        return
                    }
                    if isStandardOutput {
                        outputData.append(chunk)
                    } else {
                        errorData.append(chunk)
                    }
                    if outputData.count + errorData.count > limit {
                        overflowed = true
                    }
                }
            }
        }

        // MARK: Private

        private static let readSize = 64 * 1_024

        private let limit: Int
        private let lock = NSLock()
        private var outputData = Data()
        private var errorData = Data()
        private var overflowed = false
    }

    /// Dedicated, concurrent, and not the cooperative pool. Concurrent because unrelated flows —
    /// a force reset, a Developer Setup readiness probe, a runtime install — legitimately run at
    /// once, and a serial queue would make one of them wait out another's password dialog.
    private static let queue = DispatchQueue(
        label: "\(RockxyIdentity.current.appBundleIdentifier).bounded-process",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// How long SIGTERM is given before SIGKILL, and SIGKILL before the reap is handed off.
    private static let terminationGrace: TimeInterval = 0.5
    private static let killGrace: TimeInterval = 1
    private static let drainUnwindGrace: TimeInterval = 1
    private static let pollInterval: TimeInterval = 0.02

    /// Waits for both drains, reporting the first budget the child broke.
    ///
    /// The group is polled rather than waited on in one shot so an overflow can end the call as
    /// soon as it happens instead of only at the deadline.
    private static func waitForDrains(_ reads: DispatchGroup, deadline: Date, sink: OutputSink) -> Failure? {
        while true {
            if reads.wait(timeout: .now() + pollInterval) == .success {
                return nil
            }
            if sink.didOverflow {
                return .outputTooLarge
            }
            if Date() >= deadline {
                return .timedOut
            }
        }
    }

    /// Ends a child that broke one of its budgets, and reaps it.
    ///
    /// Reaping on every exit path is the point. The overflow path this replaced called
    /// `terminate()` and threw immediately, so the child stayed a zombie for as long as the app
    /// ran. Here the terminate escalates and the wait that collects the status always happens.
    private static func terminateAndReap(_ process: Process) {
        if process.isRunning {
            process.terminate()
            if !settled(process, within: terminationGrace) {
                Darwin.kill(process.processIdentifier, SIGKILL)
                guard settled(process, within: killGrace) else {
                    // SIGKILL cannot be ignored, so a child still here is stuck in an
                    // uninterruptible kernel wait. The blocking reap goes to its own thread
                    // rather than stalling the caller; the child stays owned until it completes,
                    // so its PID can never be recycled underneath this process.
                    Thread.detachNewThread { process.waitUntilExit() }
                    return
                }
            }
        }
        process.waitUntilExit()
    }

    private static func settled(_ process: Process, within interval: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(interval)
        while process.isRunning {
            guard Date() < deadline else {
                return false
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return true
    }
}
