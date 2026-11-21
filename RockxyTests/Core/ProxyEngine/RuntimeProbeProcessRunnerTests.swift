import Darwin
import Foundation
import Testing

@Suite(.serialized)
struct RuntimeProbeProcessRunnerTests {
    @Test("Omitted probe environment inherits the parent; explicit environment overrides it")
    func inheritsOrOverridesEnvironment() async throws {
        let key = "ROCKXY_PROBE_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let value = UUID().uuidString
        #expect(setenv(key, value, 1) == 0)
        defer { unsetenv(key) }
        let inherited = try await RuntimeProbeProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/printenv"), arguments: [key], timeout: .seconds(5)
        )
        #expect(inherited.terminationStatus == 0)
        #expect(inherited.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == value)
        let overridden = try await RuntimeProbeProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/printenv"), arguments: [key],
            environment: [key: "fixture-override"], timeout: .seconds(5)
        )
        #expect(overridden.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "fixture-override")
    }

    @Test("Probe output capture drains stdout and stderr larger than a pipe buffer")
    func drainsBothStreams() async throws {
        let result = try await RuntimeProbeProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-c", "import sys; sys.stdout.write('o' * 131072); sys.stderr.write('e' * 131072)"],
            timeout: .seconds(5)
        )
        #expect(result.terminationStatus == 0)
        #expect(result.stdout.count == 131_072)
        #expect(result.stderr.count == 131_072)
    }

    @Test("Probe completion does not await output from descendants after the root exits")
    func inheritedWriterCannotHoldCompletion() async throws {
        let result = try await RuntimeProbeProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "(sleep 2; printf late-child-output) & printf root-complete"],
            timeout: .seconds(5)
        )
        #expect(result.terminationStatus == 0)
        #expect(result.stdout == "root-complete")
    }

    @Test("A probe that ignores SIGTERM still yields a bounded timeout")
    func ignoresTerminationCannotHoldDeadline() async {
        do {
            _ = try await RuntimeProbeProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; while :; do sleep 1; done"],
                timeout: .milliseconds(100)
            )
            Issue.record("Expected a timeout")
        } catch RuntimeProbeProcessError.timedOut {
            // Expected; the collector force-terminates only its owned process/group.
        } catch {
            Issue.record("Expected a probe timeout, got \(error)")
        }
    }

    @Test("Cancelling a probe preserves CancellationError")
    func cancellationIsPreserved() async throws {
        let task = Task {
            try await RuntimeProbeProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 5"],
                timeout: .seconds(10)
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }
}
