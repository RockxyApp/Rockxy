import Foundation
@testable import Rockxy
import Testing

// Regression tests for the direct-mode watchdog: the invocation the app submits, the loop the
// shipped helper binary runs, and the swap that replaces one watcher with another.

// MARK: - DirectProxyWatchdogInvocationTests

/// The app formats the invocation and the helper binary parses it back, in two different
/// processes. These cover both halves against each other, because a field either side counted
/// differently would arm a watcher that silently watches the wrong thing.
struct DirectProxyWatchdogInvocationTests {
    @Test("What the app submits is exactly what the watchdog reads back")
    func formattingAndParsingAgree() {
        let arguments = DirectProxyWatchdogInvocation.watchArguments(
            executablePath: "/tmp/RockxyHelperTool",
            parentPID: 4_242,
            backupPath: "/tmp/proxy-backup-direct.plist",
            parentStartSignature: "1788787973.748707"
        )

        #expect(DirectProxyWatchdogInvocation.parse(arguments: arguments) == .watch(
            parentPID: 4_242,
            backupPath: "/tmp/proxy-backup-direct.plist",
            parentStartSignature: "1788787973.748707"
        ))
    }

    @Test("The launchctl submission carries the entrypoint, backup path, and parent identity")
    func submissionCarriesTheWholeInvocation() {
        let arguments = SystemProxyManager.directWatchdogSubmitArguments(
            label: "com.amunx.rockxy.community.direct-proxy-watchdog",
            executablePath: "/tmp/RockxyHelperTool",
            parentPID: 4_242,
            parentStartSignature: "1788787973.748707",
            backupPath: "/tmp/proxy-backup-direct.plist"
        )

        // The start signature travels beside the identifier so the watcher can tell the process
        // that took the override from whatever later inherits its identifier.
        #expect(arguments == [
            "submit",
            "-l",
            "com.amunx.rockxy.community.direct-proxy-watchdog",
            "--",
            "/tmp/RockxyHelperTool",
            "--rockxy-direct-proxy-watchdog",
            "4242",
            "/tmp/proxy-backup-direct.plist",
            "1788787973.748707",
        ])
    }

    @Test("An invocation with no parent identity is consumed but never watched")
    func anUnidentifiableParentIsNotWatched() {
        // Waiting on a bare identifier would keep watching whatever process later reuses it, so
        // the invocation is consumed and the backup is left for launch-time recovery instead.
        #expect(DirectProxyWatchdogInvocation.parse(arguments: [
            "/tmp/RockxyHelperTool",
            "--rockxy-direct-proxy-watchdog",
            "4242",
            "/tmp/proxy-backup-direct.plist",
        ]) == .unidentifiableParent)
        #expect(DirectProxyWatchdogInvocation.parse(arguments: [
            "/tmp/RockxyHelperTool",
            "--rockxy-direct-proxy-watchdog",
            "4242",
            "/tmp/proxy-backup-direct.plist",
            "",
        ]) == .unidentifiableParent)
        #expect(DirectProxyWatchdogInvocation.parse(arguments: [
            "/tmp/RockxyHelperTool",
            "--rockxy-direct-proxy-watchdog",
            "0",
            "/tmp/proxy-backup-direct.plist",
            "1788787973.748707",
        ]) == .unidentifiableParent)
    }

    @Test("A launch that is not a watchdog request is left alone")
    func aPlainLaunchIsNotAWatchdog() {
        #expect(DirectProxyWatchdogInvocation.parse(arguments: ["/tmp/RockxyHelperTool"]) == .notAWatchdog)
        #expect(DirectProxyWatchdogInvocation.parse(arguments: []) == .notAWatchdog)
        #expect(
            DirectProxyWatchdogInvocation.parse(arguments: ["/tmp/RockxyHelperTool", "--something-else"])
                == .notAWatchdog
        )
    }
}

// MARK: - DirectProxyWatchdogRuntimeTests

/// The loop the shipped helper binary runs. It is exercised here directly rather than through a
/// second implementation, so what these cover is the ordering the watchdog actually ships with.
struct DirectProxyWatchdogRuntimeTests {
    @Test("The watchdog exits once the backup is gone, even while the parent is still running")
    func aResolvedSessionEndsTheWatch() {
        var restores = 0
        let outcome = DirectProxyWatchdogRuntime.watch(
            parentIsLive: { true },
            backupExists: { false },
            restore: { restores += 1 },
            waitBeforeNextPoll: { Issue.record("A resolved session must not be polled again") }
        )

        #expect(outcome == .exit)
        #expect(restores == 0)
    }

    @Test("The watchdog waits while the parent is alive and restores as soon as it is not")
    func theParentIsWatchedUntilItGoes() {
        var polls = 0
        var restores = 0
        let outcome = DirectProxyWatchdogRuntime.watch(
            parentIsLive: { polls < 3 },
            backupExists: { restores == 0 },
            restore: { restores += 1 },
            waitBeforeNextPoll: { polls += 1 }
        )

        #expect(outcome == .restore)
        #expect(polls == 3)
        #expect(restores == 1)
    }

    @Test("A failed recovery keeps the watchdog alive until the backup is resolved")
    func aRetainedBackupIsRetried() {
        var restores = 0
        var waits = 0
        let outcome = DirectProxyWatchdogRuntime.watch(
            parentIsLive: { false },
            backupExists: { restores < 2 },
            restore: { restores += 1 },
            waitBeforeNextPoll: { waits += 1 }
        )

        #expect(outcome == .restore)
        #expect(restores == 2)
        #expect(waits == 1)
    }

    @Test("A backup that disappears mid-watch ends the loop without writing anything")
    func aBackupClearedByAnotherProcessStopsTheWatch() {
        var polls = 0
        var restores = 0
        let outcome = DirectProxyWatchdogRuntime.watch(
            parentIsLive: { true },
            backupExists: { polls < 2 },
            restore: { restores += 1 },
            waitBeforeNextPoll: { polls += 1 }
        )

        #expect(outcome == .exit)
        #expect(restores == 0)
    }

    @Test("A backup refused on consecutive polls ends the watch as refused instead of polling forever")
    func aRefusedBackupEndsTheWatchLoudly() {
        var waits = 0
        var restores = 0
        let outcome = DirectProxyWatchdogRuntime.watch(
            parentIsLive: { false },
            backupExists: { true },
            backupIsRefused: { true },
            restore: { restores += 1 },
            waitBeforeNextPoll: { waits += 1 }
        )

        #expect(outcome == .refused)
        #expect(restores == 0)
        #expect(waits == DirectProxyWatchdogRuntime.refusalPollLimit - 1)
    }

    @Test("A refusal that clears between polls is a race with the writer, not a verdict")
    func aTransientRefusalDoesNotEndTheWatch() {
        var polls = 0
        var restores = 0
        let outcome = DirectProxyWatchdogRuntime.watch(
            parentIsLive: { false },
            backupExists: { restores == 0 },
            backupIsRefused: { polls < 2 },
            restore: { restores += 1 },
            waitBeforeNextPoll: { polls += 1 }
        )

        #expect(outcome == .restore)
        #expect(restores == 1)
    }

    @Test("Refusals must be consecutive to count")
    func refusalsAreCountedConsecutively() {
        var poll = 0
        var restores = 0
        // Refused, clean, refused, clean, ... never reaches the limit, so the owner is still
        // restored once it goes.
        let outcome = DirectProxyWatchdogRuntime.watch(
            parentIsLive: { poll < 8 },
            backupExists: { restores == 0 },
            backupIsRefused: { poll % 2 == 0 && poll < 8 },
            restore: { restores += 1 },
            waitBeforeNextPoll: { poll += 1 }
        )

        #expect(outcome == .restore)
    }

    @Test("A refusal is reported as its own exit status, which launchd keeps for the job")
    func refusedLabelsAreReadFromTheJobTable() {
        let base = "app.test.direct-proxy-watchdog"
        let refused = "\(base).\(UUID().uuidString)"
        let resolved = "\(base).\(UUID().uuidString)"
        let running = "\(base).\(UUID().uuidString)"
        let output = """
        PID\tStatus\tLabel
        -\t\(DirectProxyWatchdogExit.refusedBackup)\t\(refused)
        -\t0\t\(resolved)
        4242\t0\t\(running)
        -\t\(DirectProxyWatchdogExit.refusedBackup)\tcom.apple.unrelated
        -\t\(DirectProxyWatchdogExit.refusedBackup)\t\(base).not-a-uuid
        """

        #expect(DirectProxyWatchdogJobDiscovery.refusedLabels(in: output, baseLabel: base) == [refused])
        // Discovery of owned jobs is unchanged by the status column.
        #expect(Set(DirectProxyWatchdogJobDiscovery.labels(in: output, baseLabel: base)) == [
            refused,
            resolved,
            running
        ])
        #expect(DirectProxyWatchdogExit.refusedBackup != 0)
    }

    @Test("The refusal status collides with no sysexits value, and 78 is read as never having run")
    func refusalExitCodeIsDistinctFromSysexitsAndLaunchdSetupFailure() {
        let sysexitsReserved: ClosedRange<Int32> = 64 ... 78
        #expect(!sysexitsReserved.contains(DirectProxyWatchdogExit.refusedBackup))
        #expect(DirectProxyWatchdogExit.refusedBackup != 78)
        #expect(DirectProxyWatchdogExit.refusedBackup != 0)
        #expect(DirectProxyWatchdogExit.refusedBackup < 126)
        #expect(DirectProxyWatchdogExit.jobSetupFailed == 78)

        #expect(DirectProxyWatchdogExit.diagnosis(forStatus: 0) == .resolved)
        #expect(DirectProxyWatchdogExit.diagnosis(forStatus: DirectProxyWatchdogExit.refusedBackup) == .refusedBackup)
        #expect(DirectProxyWatchdogExit.diagnosis(forStatus: 78) == .neverRan)
        #expect(DirectProxyWatchdogExit.diagnosis(forStatus: -9) == .other(-9))
        #expect(DirectProxyWatchdogExit.diagnosis(forStatus: 1) == .other(1))
    }

    @Test("The job table separates a refusal from a job that never ran")
    func jobTableSeparatesRefusedFromNeverRan() {
        let base = "app.test.direct-proxy-watchdog"
        let refused = "\(base).\(UUID().uuidString)"
        let neverRan = "\(base).\(UUID().uuidString)"
        let output = """
        PID\tStatus\tLabel
        -\t\(DirectProxyWatchdogExit.refusedBackup)\t\(refused)
        -\t78\t\(neverRan)
        -\t78\tcom.apple.unrelated
        """

        #expect(DirectProxyWatchdogJobDiscovery.refusedLabels(in: output, baseLabel: base) == [refused])
        #expect(DirectProxyWatchdogJobDiscovery.neverRanLabels(in: output, baseLabel: base) == [neverRan])
    }

    @Test("A watchdog killed by a signal or exiting with another status is classified, not dropped")
    func jobTableClassifiesSignalsAndOtherStatuses() {
        let base = "app.test.direct-proxy-watchdog"
        let killed = "\(base).\(UUID().uuidString)"
        let exitedOne = "\(base).\(UUID().uuidString)"
        let stillRunning = "\(base).\(UUID().uuidString)"
        let clean = "\(base).\(UUID().uuidString)"
        let output = """
        PID\tStatus\tLabel
        -\t-9\t\(killed)
        -\t1\t\(exitedOne)
        4242\t1\t\(stillRunning)
        -\t0\t\(clean)
        -\t-9\tcom.apple.unrelated
        """

        let failures = DirectProxyWatchdogJobDiscovery.failures(in: output, baseLabel: base)

        #expect(failures.refused.isEmpty)
        #expect(failures.neverRan.isEmpty)
        #expect(Set(failures.other) == [.init(label: killed, status: -9), .init(label: exitedOne, status: 1)])
        #expect(Set(failures.notRunning) == [killed, exitedOne])
    }

    @Test("Production discovery surfaces a signal-killed or oddly-exited watchdog as not running")
    func managerSurfacesNonRefusalFailures() {
        let base = SystemProxyManager.directWatchdogLabel
        let killed = "\(base).\(UUID().uuidString)"
        let exitedOne = "\(base).\(UUID().uuidString)"
        let output = """
        PID\tStatus\tLabel
        -\t-9\t\(killed)
        -\t1\t\(exitedOne)
        """
        let manager = SystemProxyManager()

        #expect(!manager.directWatchdogNeverRan)
        #expect(manager.noteDirectWatchdogFailures(in: output, context: "test"))
        // Surfaced on the existing "no automatic restore" state, not the refusal one: nothing was
        // read or rejected, and the remedy is the same manual restore.
        #expect(manager.directWatchdogNeverRan)
        #expect(!manager.directWatchdogRefusedItsRecord)
    }

    @Test("The reported fault matches the flag for each kind of failed watchdog")
    func managerReturnValueMeansAnyFaultWasFound() {
        let base = SystemProxyManager.directWatchdogLabel
        func table(status: String) -> String {
            "PID\tStatus\tLabel\n-\t\(status)\t\(base).\(UUID().uuidString)"
        }

        let neverRan = SystemProxyManager()
        #expect(neverRan.noteDirectWatchdogFailures(in: table(status: "78"), context: "test"))
        #expect(neverRan.directWatchdogNeverRan && !neverRan.directWatchdogRefusedItsRecord)

        let refused = SystemProxyManager()
        let refusedStatus = String(DirectProxyWatchdogExit.refusedBackup)
        #expect(refused.noteDirectWatchdogFailures(in: table(status: refusedStatus), context: "test"))
        #expect(refused.directWatchdogRefusedItsRecord && !refused.directWatchdogNeverRan)

        let healthy = SystemProxyManager()
        #expect(!healthy.noteDirectWatchdogFailures(in: table(status: "0"), context: "test"))
        #expect(!healthy.directWatchdogNeverRan && !healthy.directWatchdogRefusedItsRecord)
    }

    @Test("The backup is what decides, not the parent")
    func theActionPolicyChecksTheBackupFirst() {
        #expect(DirectProxyWatchdogPolicy.action(parentAlive: true, backupExists: false) == .exit)
        #expect(DirectProxyWatchdogPolicy.action(parentAlive: false, backupExists: false) == .exit)
        #expect(DirectProxyWatchdogPolicy.action(parentAlive: true, backupExists: true) == .wait)
        #expect(DirectProxyWatchdogPolicy.action(parentAlive: false, backupExists: true) == .restore)
    }
}

// MARK: - DirectProxyWatchdogInstallationTests

/// Replacing the watcher is the moment an override can end up unwatched. These cover the ordering
/// that keeps it covered throughout.
struct DirectProxyWatchdogInstallationTests {
    @Test("A submit that fails leaves the previous watcher in place and removes nothing")
    func aFailedSubmitKeepsTheOldWatcher() {
        var removed: [String] = []
        let outcome = DirectProxyWatchdogInstallation.install(
            newLabel: "watchdog.new",
            supersededLabel: "watchdog.old",
            submit: { _ in throw TestFailure() },
            remove: { removed.append($0) }
        )

        // Removing first and submitting after is what could leave the override with no watcher at
        // all the moment this throws.
        #expect(removed.isEmpty)
        #expect(!outcome.isInstalled)
        #expect(outcome.activeLabel == "watchdog.old")
    }

    @Test("The superseded watcher is only removed once its replacement is running")
    func theOldWatcherIsRemovedAfterTheNewOneIsUp() {
        var steps: [String] = []
        let outcome = DirectProxyWatchdogInstallation.install(
            newLabel: "watchdog.new",
            supersededLabel: "watchdog.old",
            submit: { steps.append("submit:\($0)") },
            remove: { steps.append("remove:\($0)") }
        )

        #expect(steps == ["submit:watchdog.new", "remove:watchdog.old"])
        #expect(outcome.isInstalled)
        #expect(outcome.activeLabel == "watchdog.new")
        guard case let .installed(_, _, retainedSupersededLabel) = outcome else {
            Issue.record("Expected an installed watchdog")
            return
        }
        #expect(retainedSupersededLabel == nil)
    }

    @Test("A first arming submits without removing anything")
    func aFirstArmingRemovesNothing() {
        var steps: [String] = []
        let outcome = DirectProxyWatchdogInstallation.install(
            newLabel: "watchdog.new",
            supersededLabel: nil,
            submit: { steps.append("submit:\($0)") },
            remove: { steps.append("remove:\($0)") }
        )

        #expect(steps == ["submit:watchdog.new"])
        #expect(outcome.activeLabel == "watchdog.new")
    }

    @Test("A stubborn old job does not unseat the watcher that already replaced it")
    func aFailedRemovalStillReportsTheNewWatcher() {
        let outcome = DirectProxyWatchdogInstallation.install(
            newLabel: "watchdog.new",
            supersededLabel: "watchdog.old",
            submit: { _ in },
            remove: { _ in throw TestFailure() }
        )

        // The replacement is already running, so a job that would not go away is a stray process
        // rather than a gap in cover — and it exits itself once the backup is resolved.
        #expect(outcome.isInstalled)
        #expect(outcome.activeLabel == "watchdog.new")
        guard case let .installed(_, _, retainedSupersededLabel) = outcome else {
            Issue.record("Expected an installed watchdog")
            return
        }
        #expect(retainedSupersededLabel == "watchdog.old")
    }
}

// MARK: - DirectProxyWatchdogJobDiscoveryTests

struct DirectProxyWatchdogJobDiscoveryTests {
    @Test("Discovery includes the legacy label and UUID session labels only")
    func discoveryIsStrictlyScoped() {
        let baseLabel = "com.amunx.rockxy.community.direct-proxy-watchdog"
        let sessionLabel = "\(baseLabel).1E5F233A-521D-447C-9946-55F62DEE004A"
        let output = """
        -\t0\t\(baseLabel)
        -\t0\t\(sessionLabel)
        -\t0\t\(baseLabel).not-a-uuid
        321\t0\tcom.amunx.rockxy.community.direct-proxy-watchdogger
        999\t0\tcom.example.unrelated
        """

        #expect(DirectProxyWatchdogJobDiscovery.labels(
            in: output,
            baseLabel: baseLabel
        ) == [baseLabel, sessionLabel])
    }

    @Test("Discovery de-duplicates repeated launchctl rows")
    func discoveryDeduplicatesRows() {
        let baseLabel = "com.amunx.rockxy.community.direct-proxy-watchdog"
        let output = """
        - 0 \(baseLabel)
        - 0 \(baseLabel)
        """

        #expect(DirectProxyWatchdogJobDiscovery.labels(
            in: output,
            baseLabel: baseLabel
        ) == [baseLabel])
    }
}

// MARK: - TestFailure

private struct TestFailure: Error {}
