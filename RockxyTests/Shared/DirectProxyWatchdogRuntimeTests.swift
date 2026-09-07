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
    }
}

// MARK: - TestFailure

private struct TestFailure: Error {}
