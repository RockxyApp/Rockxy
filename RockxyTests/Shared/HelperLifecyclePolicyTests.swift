import Foundation
@testable import Rockxy
import Testing

// Regression tests for when the privileged helper may exit, what an uninstall may tear down, and
// which process a proxy override is recorded for.

// MARK: - HelperIdleExitSequenceTests

/// Exercised at the seam rather than against a real timer: the failure this guards against is an
/// exit landing between two other steps, and a timing test would only observe that by luck.
struct HelperIdleExitSequenceTests {
    @Test("An idle helper with nothing running exits while still holding the barrier")
    func anIdleHelperExits() {
        let gate = HelperPrivilegedMutationGate()
        var released = 0

        let decision = HelperIdleExitSequence.run(
            proxyIsOverridden: { false },
            acquireExitBarrier: { gate.beginProcessExitBarrier() },
            release: { gate.release($0); released += 1 }
        )

        #expect(decision == .exit)
        // The barrier is deliberately not released: nothing may start between deciding to exit
        // and the process actually going away.
        #expect(released == 0)
        #expect(gate.isBusy)
    }

    @Test("A mutation already in flight defers the exit and keeps the gate with its owner")
    func aBusyGateDefersTheExit() {
        let gate = HelperPrivilegedMutationGate()
        let heldByAMutation = gate.tryAcquire()
        var released = 0

        let decision = HelperIdleExitSequence.run(
            proxyIsOverridden: { false },
            acquireExitBarrier: { gate.beginProcessExitBarrier() },
            release: { gate.release($0); released += 1 }
        )

        // A timer event that has already been dequeued cannot be cancelled, so this is the check
        // that keeps it from exiting in the middle of somebody else's privileged work.
        #expect(decision == .deferBusy)
        #expect(released == 0)
        #expect(heldByAMutation != nil)
        #expect(gate.isBusy)
    }

    @Test("An override that appears after the first check is caught by the second")
    func anOverrideStartedMidCheckDefersTheExit() {
        let gate = HelperPrivilegedMutationGate()
        var reads = 0
        var released = 0

        let decision = HelperIdleExitSequence.run(
            proxyIsOverridden: {
                reads += 1
                // Nothing was overridden when the timer fired; by the time the barrier is held,
                // something is. Reading once would have exited with the override in place and
                // nothing left alive to restore it.
                return reads > 1
            },
            acquireExitBarrier: { gate.beginProcessExitBarrier() },
            release: { gate.release($0); released += 1 }
        )

        #expect(decision == .deferOverridden)
        #expect(reads == 2)
        // The barrier is handed back on every path that does not exit, so a deferred check leaves
        // the helper exactly as it found it.
        #expect(released == 1)
        #expect(!gate.isBusy)
    }

    @Test("An override already in place is refused without taking the gate at all")
    func anExistingOverrideNeverTakesTheGate() {
        var acquisitions = 0

        let decision = HelperIdleExitSequence.run(
            proxyIsOverridden: { true },
            acquireExitBarrier: {
                acquisitions += 1
                return nil
            },
            release: { _ in }
        )

        #expect(decision == .deferOverridden)
        #expect(acquisitions == 0)
    }
}

// MARK: - HelperUninstallPreparationTests

/// Stopping the watchdog and clearing the backup together remove the last two things that could
/// put the user's settings back, so these cover that neither happens until the restore has.
struct HelperUninstallPreparationTests {
    @Test("Nothing is torn down until the restore has succeeded")
    func teardownFollowsASuccessfulRestore() {
        var steps: [String] = []

        let prepared = HelperUninstallPreparation.run(
            restore: { steps.append("restore") },
            stopWatchdog: { steps.append("stopWatchdog") },
            clearBackup: { steps.append("clearBackup") }
        )

        #expect(prepared)
        #expect(steps == ["restore", "stopWatchdog", "clearBackup"])
    }

    @Test("A restore that throws keeps the backup and the watchdog and reports failure")
    func aFailedRestoreTearsDownNothing() {
        var steps: [String] = []

        let prepared = HelperUninstallPreparation.run(
            restore: {
                steps.append("restore")
                throw TestFailure()
            },
            stopWatchdog: { steps.append("stopWatchdog") },
            clearBackup: { steps.append("clearBackup") }
        )

        // A failed uninstall must not become a permanent override with no way back: the restore
        // point and the watcher are the two things that could still fix it.
        #expect(!prepared)
        #expect(steps == ["restore"])
    }
}

// MARK: - HelperOwnerBindingPolicyTests

/// The owner identifier arrives in the message, so on its own it is a claim. These cover that the
/// helper acts on the connection it authenticated instead.
struct HelperOwnerBindingPolicyTests {
    @Test("A request naming its own connection is the one identity the helper acts on")
    func aMatchingConnectionIsAuthorized() {
        #expect(HelperOwnerBindingPolicy.authorizedOwnerPID(
            boundConnectionPID: 4_242,
            requestedOwnerPID: 4_242
        ) == 4_242)
    }

    @Test("A request naming some other process is refused outright")
    func aMismatchedOwnerIsRejected() {
        // Without this, a caller could have the helper arm a watchdog on a process it does not
        // own — or record that process as the session holding the user's proxy settings.
        #expect(HelperOwnerBindingPolicy.authorizedOwnerPID(
            boundConnectionPID: 4_242,
            requestedOwnerPID: 4_243
        ) == nil)
        #expect(HelperOwnerBindingPolicy.authorizedOwnerPID(
            boundConnectionPID: 4_242,
            requestedOwnerPID: 1
        ) == nil)
    }

    @Test("A request with no usable identifier on either side is refused")
    func anUnidentifiableRequestIsRejected() {
        #expect(HelperOwnerBindingPolicy.authorizedOwnerPID(
            boundConnectionPID: nil,
            requestedOwnerPID: 4_242
        ) == nil)
        #expect(HelperOwnerBindingPolicy.authorizedOwnerPID(
            boundConnectionPID: 0,
            requestedOwnerPID: 0
        ) == nil)
        #expect(HelperOwnerBindingPolicy.authorizedOwnerPID(
            boundConnectionPID: 4_242,
            requestedOwnerPID: 0
        ) == nil)
        #expect(HelperOwnerBindingPolicy.authorizedOwnerPID(
            boundConnectionPID: 4_242,
            requestedOwnerPID: -1
        ) == nil)
    }
}

// MARK: - HelperBoundProcessIdentityPolicyTests

struct HelperBoundProcessIdentityPolicyTests {
    @Test("A connection remains valid only for the process instance accepted by the listener")
    func exactProcessIdentityIsRequired() {
        #expect(HelperBoundProcessIdentityPolicy.isCurrent(
            boundPID: 4_242,
            boundStartSignature: "start-a",
            liveStartSignature: "start-a"
        ))
        #expect(!HelperBoundProcessIdentityPolicy.isCurrent(
            boundPID: 4_242,
            boundStartSignature: "start-a",
            liveStartSignature: "start-b"
        ))
        #expect(!HelperBoundProcessIdentityPolicy.isCurrent(
            boundPID: 4_242,
            boundStartSignature: "start-a",
            liveStartSignature: nil
        ))
    }

    @Test("A delayed mutation must still own the active backup")
    func existingSessionIdentityIsRequired() {
        #expect(HelperBoundProcessIdentityPolicy.ownsProxySession(
            boundPID: 4_242,
            boundStartSignature: "start-a",
            liveStartSignature: "start-a",
            recordedOwnerPID: 4_242,
            recordedOwnerStartSignature: "start-a",
            hasBackedUpServices: true
        ))
        #expect(!HelperBoundProcessIdentityPolicy.ownsProxySession(
            boundPID: 4_242,
            boundStartSignature: "start-a",
            liveStartSignature: "start-a",
            recordedOwnerPID: nil,
            recordedOwnerStartSignature: nil,
            hasBackedUpServices: true
        ))
        #expect(!HelperBoundProcessIdentityPolicy.ownsProxySession(
            boundPID: 4_242,
            boundStartSignature: "start-a",
            liveStartSignature: "start-a",
            recordedOwnerPID: 4_242,
            recordedOwnerStartSignature: "start-a",
            hasBackedUpServices: false
        ))
    }

    @Test("An existing backup can only be extended by its exact owner session")
    func recordedSessionCannotBeTakenOver() {
        #expect(HelperBoundProcessIdentityPolicy.recordedSessionBelongsToCaller(
            recordedOwnerPID: 4_242,
            recordedOwnerStartSignature: "start-a",
            callerPID: 4_242,
            callerStartSignature: "start-a"
        ))
        #expect(!HelperBoundProcessIdentityPolicy.recordedSessionBelongsToCaller(
            recordedOwnerPID: 4_242,
            recordedOwnerStartSignature: "start-a",
            callerPID: 4_243,
            callerStartSignature: "start-b"
        ))
        #expect(!HelperBoundProcessIdentityPolicy.recordedSessionBelongsToCaller(
            recordedOwnerPID: nil,
            recordedOwnerStartSignature: nil,
            callerPID: 4_243,
            callerStartSignature: "start-b"
        ))
    }

    @Test("A live session can only be restored by its exact owner")
    func liveSessionRestoreIsOwnerBound() {
        #expect(HelperBoundProcessIdentityPolicy.mayRestoreSession(
            ownerSessionIsLive: true,
            recordedOwnerPID: 4_242,
            recordedOwnerStartSignature: "start-a",
            callerPID: 4_242,
            callerStartSignature: "start-a"
        ))
        #expect(!HelperBoundProcessIdentityPolicy.mayRestoreSession(
            ownerSessionIsLive: true,
            recordedOwnerPID: 4_242,
            recordedOwnerStartSignature: "start-a",
            callerPID: 4_243,
            callerStartSignature: "start-b"
        ))
        #expect(HelperBoundProcessIdentityPolicy.mayRestoreSession(
            ownerSessionIsLive: false,
            recordedOwnerPID: 4_242,
            recordedOwnerStartSignature: "start-a",
            callerPID: 4_243,
            callerStartSignature: "start-b"
        ))
    }
}

// MARK: - HelperOverrideResidencyPolicyTests

/// The idle timer's question, and why the routed service's status is only half of it.
struct HelperOverrideResidencyPolicyTests {
    @Test("A live override on the routed service keeps the helper up")
    func aRoutedOverrideKeepsTheHelper() {
        #expect(HelperOverrideResidencyPolicy.overrideNeedsHelper(
            routedServiceIsOverridden: true,
            unresolvedBackupExists: false
        ))
    }

    @Test("An override left on a secondary service keeps the helper up too")
    func anUnresolvedBackupKeepsTheHelper() {
        // The routed service reads clean, so the status alone reports this machine as idle. The
        // services actually left changed are named by the restore point still on disk, and exiting
        // would take away the only process that could put them back.
        #expect(HelperOverrideResidencyPolicy.overrideNeedsHelper(
            routedServiceIsOverridden: false,
            unresolvedBackupExists: true
        ))
    }

    @Test("Nothing overridden and no restore point left means the helper may exit")
    func aResolvedMachineReleasesTheHelper() {
        #expect(!HelperOverrideResidencyPolicy.overrideNeedsHelper(
            routedServiceIsOverridden: false,
            unresolvedBackupExists: false
        ))
    }

    @Test("A partial override still defers the idle exit through the same sequence")
    func aPartialOverrideDefersTheIdleExit() {
        var barriersTaken = 0

        let decision = HelperIdleExitSequence.run(
            proxyIsOverridden: {
                HelperOverrideResidencyPolicy.overrideNeedsHelper(
                    routedServiceIsOverridden: false,
                    unresolvedBackupExists: true
                )
            },
            acquireExitBarrier: {
                barriersTaken += 1
                return nil
            },
            release: { _ in }
        )

        #expect(decision == .deferOverridden)
        // The refusal happens before the gate is touched at all, which is what keeps the common
        // case cheap.
        #expect(barriersTaken == 0)
    }
}

// MARK: - TestFailure

private struct TestFailure: Error {}
