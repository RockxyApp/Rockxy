import Darwin
import Foundation

/// Synchronous runner for the helper's short-lived security command. The caller validates the
/// executable signature.
///
/// The child is spawned *and* reaped here rather than by Foundation. That ownership is what makes
/// termination safe: a PID is only ever signalled while this process still holds it as an unreaped
/// child, so the kernel cannot have recycled it for an unrelated process in between. Output is
/// drained without blocking and retained only up to a fixed budget; a child that outlives its
/// budget is terminated, then killed if it ignores SIGTERM, and is reaped in every case.
enum BoundedHelperCommand {
    // MARK: Internal

    struct Output {
        let status: Int32
        let diagnostic: Data
    }

    /// An exit status with the child's complete standard output beside the bounded stderr copy.
    ///
    /// `standardOutput` is whole or the call threw: a reading cut off at the budget is reported as
    /// `outputTooLarge`, because a caller parsing system state cannot tell a truncated list from
    /// a short one.
    struct CapturedOutput {
        let status: Int32
        let standardOutput: Data
        let diagnostic: Data
    }

    enum Failure: Error, Equatable {
        case invalidTimeout
        case pipeUnavailable(Int32)
        case nonblockingPipe(Int32)
        case spawnFailed(Int32)
        case waitFailed(Int32)
        case timedOut
        case outputTooLarge
    }

    /// The standard-output budget. The largest reading the helper's own supported API can ask for
    /// is a full bypass list, bounded at `ProxyBypassDomainValidator.maximumTotalBytes`; this
    /// leaves several times that for a list some other tool wrote.
    static let standardOutputLimit = 262_144

    /// The budget for `networksetup` and `route`. Both go through SystemConfiguration, which can
    /// stall behind another writer, so the window is far longer than any observed run — the point
    /// is that one exists at all, since these calls hold the mutation gate and the shared flock.
    static let networkConfigurationTimeout: TimeInterval = 10

    /// Runs `executable` with `arguments`, returning its exit status and a bounded copy of stderr.
    ///
    /// The default budget plus termination grace leaves room inside the XPC request timeout.
    /// Security framework calls around this command can still stall independently; a client
    /// timeout does not prove that no privileged mutation happened.
    static func run(executable: URL, arguments: [String], timeout: TimeInterval = 5) throws -> Output {
        let captured = try execute(
            executable: executable, arguments: arguments, timeout: timeout, outputLimit: nil
        )
        return Output(status: captured.status, diagnostic: captured.diagnostic)
    }

    /// The same bounded run, for a tool whose standard output the caller has to read.
    ///
    /// Everything `run` guarantees still holds: the child is owned and reaped here, both pipes are
    /// drained without blocking while it runs, and a child that outlives `timeout` is terminated.
    /// Output past `outputLimit` fails the call rather than being silently dropped.
    static func runCapturingStandardOutput(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval = 5,
        outputLimit: Int = standardOutputLimit
    )
        throws -> CapturedOutput
    {
        try execute(executable: executable, arguments: arguments, timeout: timeout, outputLimit: outputLimit)
    }

    // MARK: Private

    private enum WaitOutcome {
        case running
        case exited(Int32)
        /// The child can no longer be waited for, so it can no longer be signalled either.
        case unavailable(Int32)
    }

    private enum OutputDrainOutcome {
        case open
        case endOfFile
        /// The child produced more than the budget, so the reading is incomplete and unusable.
        case overflowed
    }

    /// Spawns, polls, drains and reaps. `outputLimit` is nil for a caller that only needs the exit
    /// status, and the child's standard output then goes to `/dev/null` as it always did.
    private static func execute(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int?
    )
        throws -> CapturedOutput
    {
        guard timeout.isFinite, timeout > 0, timeout <= 30 else {
            throw Failure.invalidTimeout
        }

        let diagnosticEnds = try makeChildPipe()
        var diagnosticWriteIsOpen = true
        var outputEnds: [Int32] = [-1, -1]
        var outputWriteIsOpen = false
        defer {
            close(diagnosticEnds[0])
            if diagnosticWriteIsOpen {
                close(diagnosticEnds[1])
            }
            if outputEnds[0] >= 0 {
                close(outputEnds[0])
            }
            if outputWriteIsOpen {
                close(outputEnds[1])
            }
        }
        try makeNonBlocking(diagnosticEnds[0])
        if outputLimit != nil {
            outputEnds = try makeChildPipe()
            outputWriteIsOpen = true
            try makeNonBlocking(outputEnds[0])
        }

        let pid = try spawn(
            executable: executable,
            arguments: arguments,
            diagnosticPipe: (diagnosticEnds[0], diagnosticEnds[1]),
            outputPipe: outputLimit == nil ? nil : (outputEnds[0], outputEnds[1])
        )
        // The parent's copies are closed at once so the read ends report EOF when the child exits.
        close(diagnosticEnds[1])
        diagnosticWriteIsOpen = false
        if outputWriteIsOpen {
            close(outputEnds[1])
            outputWriteIsOpen = false
        }

        // Both pipes are drained on every poll. Draining only one would leave the deadlock this
        // runner exists to prevent on the other.
        let readEnds = outputLimit == nil ? [diagnosticEnds[0]] : [diagnosticEnds[0], outputEnds[0]]
        var diagnostic = Data()
        var standardOutput = Data()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            switch reap(pid) {
            case let .exited(waitStatus):
                drain(diagnosticEnds[0], into: &diagnostic)
                if let outputLimit {
                    try drainToEndOfFile(outputEnds[0], into: &standardOutput, limit: outputLimit)
                }
                return CapturedOutput(
                    status: exitStatus(from: waitStatus), standardOutput: standardOutput, diagnostic: diagnostic
                )
            case let .unavailable(code):
                // This process no longer owns the child, so there is no status to report and
                // nothing that may be signalled: the PID is not ours to touch any more.
                throw Failure.waitFailed(code)
            case .running:
                break
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                break
            }
            drain(diagnosticEnds[0], into: &diagnostic)
            if let outputLimit,
               case .overflowed = drainOutput(outputEnds[0], into: &standardOutput, limit: outputLimit, reads: 16)
            {
                terminate(pid, draining: readEnds)
                throw Failure.outputTooLarge
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        terminate(pid, draining: readEnds)
        throw Failure.timedOut
    }

    private static func makeNonBlocking(_ descriptor: Int32) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw Failure.nonblockingPipe(errno)
        }
    }

    /// Keep the pipe above standard descriptors even when the daemon starts with one closed.
    /// Otherwise the child's /dev/null actions could replace the pipe before stderr is duplicated.
    private static func makeChildPipe() throws -> [Int32] {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else {
            throw Failure.pipeUnavailable(errno)
        }
        do {
            for index in descriptors.indices {
                let duplicate = fcntl(descriptors[index], F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
                guard duplicate >= 0 else {
                    throw Failure.pipeUnavailable(errno)
                }
                close(descriptors[index])
                descriptors[index] = duplicate
            }
            return descriptors
        } catch {
            descriptors.forEach { close($0) }
            throw error
        }
    }

    private static func requireSpawnSuccess(_ status: Int32) throws {
        guard status == 0 else {
            throw Failure.spawnFailed(status)
        }
    }

    /// The child's environment, restricted to what a system tool actually needs.
    ///
    /// `security` addresses the System keychain and the admin trust domain by absolute path, so it
    /// needs no user session state; `PATH` is fixed rather than inherited. `TMPDIR` and `HOME` are
    /// carried over only when the parent has them, so a tool that writes scratch files keeps the
    /// behavior it had under the previously inherited environment. Nothing here is logged.
    private static var childEnvironment: [String] {
        var values = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin"]
        let inherited = ProcessInfo.processInfo.environment
        for name in ["TMPDIR", "HOME"] {
            if let value = inherited[name] {
                values.append("\(name)=\(value)")
            }
        }
        return values
    }

    /// Spawns the child with stdin on `/dev/null`, stderr on the diagnostic pipe, and stdout
    /// either on `/dev/null` or on `outputPipe` when the caller reads it.
    ///
    /// stdin was previously inherited. The commands this runs — `security remove-trusted-cert -d`
    /// against a file, `networksetup`, `route` — never read it, and `/dev/null` means one that
    /// tried would see EOF rather than consume the helper daemon's own input.
    private static func spawn(
        executable: URL,
        arguments: [String],
        diagnosticPipe: (readEnd: Int32, writeEnd: Int32),
        outputPipe: (readEnd: Int32, writeEnd: Int32)?
    )
        throws -> pid_t
    {
        var fileActions: posix_spawn_file_actions_t?
        try requireSpawnSuccess(posix_spawn_file_actions_init(&fileActions))
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        var attributes: posix_spawnattr_t?
        try requireSpawnSuccess(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        // Every other descriptor this process holds — XPC connections, keychain handles — stays
        // out of the child; only the three named below survive the spawn.
        try requireSpawnSuccess(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)))

        try requireSpawnSuccess(posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        if let outputPipe {
            try requireSpawnSuccess(posix_spawn_file_actions_adddup2(&fileActions, outputPipe.writeEnd, STDOUT_FILENO))
        } else {
            try requireSpawnSuccess(
                posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
            )
        }
        try requireSpawnSuccess(posix_spawn_file_actions_adddup2(&fileActions, diagnosticPipe.writeEnd, STDERR_FILENO))
        try requireSpawnSuccess(posix_spawn_file_actions_addclose(&fileActions, diagnosticPipe.readEnd))
        try requireSpawnSuccess(posix_spawn_file_actions_addclose(&fileActions, diagnosticPipe.writeEnd))
        if let outputPipe {
            try requireSpawnSuccess(posix_spawn_file_actions_addclose(&fileActions, outputPipe.readEnd))
            try requireSpawnSuccess(posix_spawn_file_actions_addclose(&fileActions, outputPipe.writeEnd))
        }

        let argumentStrings = [executable.path] + arguments
        let environmentStrings = childEnvironment
        guard (argumentStrings + environmentStrings).allSatisfy({ !$0.utf8.contains(0) }) else {
            throw Failure.spawnFailed(EINVAL)
        }
        var argv: [UnsafeMutablePointer<CChar>?] = argumentStrings.map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environmentStrings.map { strdup($0) }
        envp.append(nil)
        defer {
            for value in argv {
                free(value)
            }
            for value in envp {
                free(value)
            }
        }

        guard argv.dropLast().allSatisfy({ $0 != nil }), envp.dropLast().allSatisfy({ $0 != nil }) else {
            throw Failure.spawnFailed(ENOMEM)
        }

        var pid = pid_t()
        // posix_spawn reports its failure in the return value, not in errno.
        let result = posix_spawn(&pid, executable.path, &fileActions, &attributes, argv, envp)
        guard result == 0 else {
            throw Failure.spawnFailed(result)
        }
        return pid
    }

    /// Ends a child that outlived its budget, without ever blocking indefinitely.
    ///
    /// SIGTERM, then a bounded grace window, then SIGKILL and a bounded settling window. If the
    /// child somehow survives both — an exceptional kernel delay, never a normal outcome — the
    /// final blocking wait is handed to a detached thread instead of stalling the helper. The
    /// child stays owned and unreaped until that wait completes, so its PID is never recycled.
    private static func terminate(_ pid: pid_t, draining descriptors: [Int32]) {
        // Bytes read during termination are discarded: a timed-out command reports no output.
        // Draining continues only so a child blocked on a full pipe can act on the signal, which
        // is why every pipe it writes to is drained here and not just the diagnostic one.
        var discarded = Data()
        _ = kill(pid, SIGTERM)
        if settled(pid, within: 0.2, draining: descriptors, into: &discarded) {
            return
        }
        _ = kill(pid, SIGKILL)
        if settled(pid, within: 1, draining: descriptors, into: &discarded) {
            return
        }
        Thread.detachNewThread {
            var waitStatus: Int32 = 0
            while waitpid(pid, &waitStatus, 0) < 0, errno == EINTR {
                continue
            }
        }
    }

    /// Whether the child stopped being ours within `interval`.
    private static func settled(
        _ pid: pid_t,
        within interval: TimeInterval,
        draining descriptors: [Int32],
        into sink: inout Data
    )
        -> Bool
    {
        let deadline = ProcessInfo.processInfo.systemUptime + interval
        while true {
            switch reap(pid) {
            case .exited,
                 .unavailable:
                return true
            case .running:
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    return false
                }
                for descriptor in descriptors {
                    drain(descriptor, into: &sink)
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }

    /// A single non-blocking reap attempt for this process's own child.
    private static func reap(_ pid: pid_t) -> WaitOutcome {
        var waitStatus: Int32 = 0
        while true {
            let result = waitpid(pid, &waitStatus, WNOHANG)
            if result == pid {
                return .exited(waitStatus)
            }
            if result == 0 {
                return .running
            }
            if errno == EINTR {
                continue
            }
            return .unavailable(errno)
        }
    }

    /// The conventional encoding of a wait status: the exit code for a normal exit, and 128 plus
    /// the signal number for a child that was signalled. Callers only separate zero from nonzero,
    /// and a signalled child must never read as success.
    private static func exitStatus(from waitStatus: Int32) -> Int32 {
        let terminatingSignal = waitStatus & 0x7F
        guard terminatingSignal == 0 else {
            return 128 + terminatingSignal
        }
        return (waitStatus >> 8) & 0xFF
    }

    /// Reads the rest of an exited child's standard output.
    ///
    /// This cannot spin: the parent's write end is closed, the child has been reaped, and
    /// `POSIX_SPAWN_CLOEXEC_DEFAULT` kept the descriptor out of everything else, so no write end
    /// survives and a read can only return data or EOF — never `EAGAIN`.
    private static func drainToEndOfFile(_ descriptor: Int32, into output: inout Data, limit: Int) throws {
        while true {
            switch drainOutput(descriptor, into: &output, limit: limit, reads: 16) {
            case .endOfFile:
                return
            case .overflowed:
                throw Failure.outputTooLarge
            case .open:
                continue
            }
        }
    }

    /// Up to `reads` non-blocking reads, keeping every byte until the budget is passed. Unlike the
    /// diagnostic drain this reports the overflow instead of discarding the excess, because a
    /// caller parses this output and a quietly shortened reading would parse as a valid one.
    private static func drainOutput(
        _ descriptor: Int32,
        into output: inout Data,
        limit: Int,
        reads: Int
    )
        -> OutputDrainOutcome
    {
        var bytes = [UInt8](repeating: 0, count: 4_096)
        for _ in 0 ..< reads {
            let count = read(descriptor, &bytes, bytes.count)
            if count < 0 {
                guard errno == EINTR else {
                    return .open
                }
                continue
            }
            guard count > 0 else {
                return .endOfFile
            }
            output.append(contentsOf: bytes.prefix(count))
            guard output.count <= limit else {
                return .overflowed
            }
        }
        return .open
    }

    private static func drain(_ descriptor: Int32, into diagnostic: inout Data) {
        var bytes = [UInt8](repeating: 0, count: 4_096)
        // Bound work per poll as well as retained memory, even for a continuously noisy child.
        for _ in 0 ..< 16 {
            let count = read(descriptor, &bytes, bytes.count)
            if count < 0 {
                guard errno == EINTR else {
                    return
                }
                continue
            }
            guard count > 0 else {
                return
            }
            let retained = min(count, 4_096 - diagnostic.count)
            if retained > 0 {
                diagnostic.append(contentsOf: bytes.prefix(retained))
            }
        }
    }
}
