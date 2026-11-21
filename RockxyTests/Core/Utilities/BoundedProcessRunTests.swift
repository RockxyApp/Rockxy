import Darwin
import Foundation
@testable import Rockxy
import Testing

/// These spawn real children on purpose. A deadline, a signal escalation and a reap cannot be
/// asserted against a stub, and `BoundedHelperCommandTests` already establishes that idiom —
/// including `trap '' TERM` for a child that refuses to die politely.
struct BoundedProcessRunTests {
    // MARK: Internal

    @Test("exit status and both streams are reported separately")
    func separatesStreams() throws {
        let result = try BoundedProcessRun.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'to stdout'; printf 'to stderr' >&2; exit 7"],
            timeout: 5
        )
        #expect(result.status == 7)
        #expect(!result.wasSignalled)
        #expect(String(bytes: result.standardOutput, encoding: .utf8) == "to stdout")
        #expect(String(bytes: result.standardError, encoding: .utf8) == "to stderr")
    }

    @Test("merged streams land in one transcript")
    func mergesStandardError() throws {
        let result = try BoundedProcessRun.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'merged stderr' >&2; exit 0"],
            timeout: 5,
            mergesStandardError: true
        )
        #expect(result.combinedText == "merged stderr")
        #expect(result.standardError.isEmpty)
    }

    @Test("standard output past the pipe buffer comes back whole instead of deadlocking")
    func capturesOutputPastThePipeBuffer() throws {
        // 4,000 lines of 31 bytes is ~124 KB against a 64 KiB pipe buffer. That is exactly what
        // the readers this replaced — waitUntilExit() before reading, or never reading one of the
        // two pipes at all — blocked on forever.
        let result = try BoundedProcessRun.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "i=0; while [ $i -lt 4000 ]; do printf 'fixture-stdout-line-0123456789\\n'; i=$((i+1)); done",
            ],
            timeout: 20
        )
        #expect(result.status == 0)
        #expect(result.standardOutput.count == 4_000 * 31)
    }

    @Test("a child that ignores SIGTERM is killed at its deadline rather than waited on forever")
    func killsAChildPastItsDeadline() throws {
        let started = Date()
        #expect(throws: BoundedProcessRun.Failure.timedOut) {
            try BoundedProcessRun.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; sleep 60"],
                timeout: 1
            )
        }
        // The budget plus the SIGTERM and SIGKILL grace windows, with room to spare. Before the
        // deadline existed this call returned after a full minute.
        #expect(Date().timeIntervalSince(started) < 15)
    }

    @Test("a signalled child is reported as signalled rather than as an exit code")
    func reportsSignalledChild() throws {
        let result = try BoundedProcessRun.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "kill -TERM $$"],
            timeout: 5
        )
        #expect(result.wasSignalled)
        #expect(result.status == SIGTERM)
    }

    @Test("output past its budget fails the call instead of being silently shortened")
    func rejectsOversizedOutput() throws {
        #expect(throws: BoundedProcessRun.Failure.outputTooLarge) {
            try BoundedProcessRun.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "/bin/dd if=/dev/zero bs=4096 count=256 2>/dev/null"],
                timeout: 20,
                outputLimit: 16_384
            )
        }
    }

    @Test("the overflow path reaps the child it terminated")
    func reapsOnTheOverflowPath() throws {
        // The defect this pins: the previous reader called `terminate()` and threw straight away,
        // so an oversized command left a zombie behind for the rest of the session.
        let before = try zombieChildCount()
        for _ in 0 ..< 3 {
            #expect(throws: BoundedProcessRun.Failure.outputTooLarge) {
                try BoundedProcessRun.run(
                    executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "/bin/dd if=/dev/zero bs=4096 count=512 2>/dev/null"],
                    timeout: 20,
                    outputLimit: 8_192
                )
            }
        }
        let after = try zombieChildCount()
        #expect(after <= before)
    }

    @Test("a budget that cannot bound anything is refused")
    func refusesAnUnusableBudget() {
        #expect(throws: BoundedProcessRun.Failure.invalidTimeout) {
            try BoundedProcessRun.run(
                executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 0"], timeout: 0
            )
        }
    }

    @Test("a failure to launch is rethrown unchanged so callers keep their own mapping")
    func rethrowsLaunchFailure() {
        #expect(throws: (any Error).self) {
            try BoundedProcessRun.run(
                executable: URL(fileURLWithPath: "/nonexistent/rockxy-fixture"), arguments: [], timeout: 5
            )
        }
    }

    @Test("the detached entry point keeps the blocking waits off the caller's executor")
    func runsDetached() async throws {
        let result = try await BoundedProcessRun.runDetached(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'detached'"],
            timeout: 5
        )
        #expect(String(bytes: result.standardOutput, encoding: .utf8) == "detached")
    }

    // MARK: Private

    /// How many of this process's own children are currently unreaped.
    private func zombieChildCount() throws -> Int {
        let result = try BoundedProcessRun.run(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-A", "-o", "ppid=,stat="],
            timeout: 20
        )
        let ownIdentifier = String(ProcessInfo.processInfo.processIdentifier)
        return (String(bytes: result.standardOutput, encoding: .utf8) ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.split(separator: " ", omittingEmptySubsequences: true).map(String.init) }
            .filter { $0.count >= 2 && $0[0] == ownIdentifier && $0[1].hasPrefix("Z") }
            .count
    }
}
