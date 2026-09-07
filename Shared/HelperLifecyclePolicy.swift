import Foundation

// Decides when the privileged helper may exit, and what an uninstall is allowed to tear down.

// MARK: - HelperIdleExitDecision

/// What an idle timeout that has already fired is allowed to do.
enum HelperIdleExitDecision: Equatable {
    /// Nothing privileged is running and no override is in place. The exit barrier is still held
    /// when this is returned, so nothing can start between the decision and the exit.
    case exit
    /// Another privileged mutation owns the gate. The helper stays up and the timer is rearmed.
    case deferBusy
    /// A proxy override is in place, so the process that would restore it has to stay alive.
    case deferOverridden
}

// MARK: - HelperIdleExitSequence

/// Serializes the helper's idle exit with every other privileged mutation.
///
/// A dispatch timer event that has already been dequeued cannot be cancelled, so an idle check
/// that merely read the proxy status could reach `exit` while an override or a certificate
/// operation was half-written — the reply would never arrive and the settings would be left
/// mid-sequence. Taking the same exclusive gate those mutations take closes that: a busy gate
/// means the helper is needed, and an empty one cannot be filled while this decision is being
/// made.
///
/// The status is read twice on purpose. The first read is cheap and refuses the common case
/// without touching the gate; the second happens while the barrier is held, which is what makes
/// an override that started between them impossible to miss. The barrier is released on every
/// path that does not exit, so a deferred check leaves the helper exactly as it found it.
enum HelperIdleExitSequence {
    static func run(
        proxyIsOverridden: () -> Bool,
        acquireExitBarrier: () -> HelperPrivilegedMutationGate.Ticket?,
        release: (HelperPrivilegedMutationGate.Ticket) -> Void
    )
        -> HelperIdleExitDecision
    {
        guard !proxyIsOverridden() else {
            return .deferOverridden
        }
        guard let barrier = acquireExitBarrier() else {
            return .deferBusy
        }
        guard !proxyIsOverridden() else {
            release(barrier)
            return .deferOverridden
        }
        return .exit
    }
}

// MARK: - HelperOverrideResidencyPolicy

/// Whether something on this machine still needs the helper process alive.
///
/// The routed service's status answers for the common case, and only for it: an override that
/// stopped on a secondary service leaves the routed one reading clean, so a status check on its
/// own reports a machine that is still changed as idle — and the helper exits with the only
/// process that could put those services back. A restore point still on disk names exactly the
/// services in that position, so it is the second half of the question.
enum HelperOverrideResidencyPolicy {
    static func overrideNeedsHelper(
        routedServiceIsOverridden: Bool,
        unresolvedBackupExists: Bool
    )
        -> Bool
    {
        routedServiceIsOverridden || unresolvedBackupExists
    }
}

// MARK: - HelperBoundProcessIdentityPolicy

/// Keeps a privileged connection bound to the exact process instance accepted by the listener.
/// A process identifier can be recycled after that acceptance, so every later mutation must still
/// match the start signature captured at the same boundary.
enum HelperBoundProcessIdentityPolicy {
    static func isCurrent(
        boundPID: Int32,
        boundStartSignature: String,
        liveStartSignature: String?
    )
        -> Bool
    {
        boundPID > 0
            && !boundStartSignature.isEmpty
            && liveStartSignature == boundStartSignature
    }

    /// A session mutation is also tied to the backup created for this exact connection. This keeps
    /// a delayed request from changing services after restoration has removed the backup, or from
    /// acting on a later session owned by another process instance.
    static func ownsProxySession(
        boundPID: Int32,
        boundStartSignature: String,
        liveStartSignature: String?,
        recordedOwnerPID: Int32?,
        recordedOwnerStartSignature: String?,
        hasBackedUpServices: Bool
    )
        -> Bool
    {
        hasBackedUpServices
            && isCurrent(
                boundPID: boundPID,
                boundStartSignature: boundStartSignature,
                liveStartSignature: liveStartSignature
            )
            && recordedOwnerPID == boundPID
            && recordedOwnerStartSignature == boundStartSignature
    }

    static func recordedSessionBelongsToCaller(
        recordedOwnerPID: Int32?,
        recordedOwnerStartSignature: String?,
        callerPID: Int32,
        callerStartSignature: String
    )
        -> Bool
    {
        recordedOwnerPID == callerPID
            && ProcessStartIdentity.identifiesSameProcess(
                recordedPID: recordedOwnerPID,
                recordedStartSignature: recordedOwnerStartSignature,
                liveStartSignature: callerStartSignature
            )
    }

    /// A live session may only be restored by the exact connection that owns it. Once its owner
    /// is gone, any authenticated app connection may trigger the recovery the helper would run on
    /// restart anyway.
    static func mayRestoreSession(
        ownerSessionIsLive: Bool,
        recordedOwnerPID: Int32?,
        recordedOwnerStartSignature: String?,
        callerPID: Int32,
        callerStartSignature: String
    )
        -> Bool
    {
        !ownerSessionIsLive || recordedSessionBelongsToCaller(
            recordedOwnerPID: recordedOwnerPID,
            recordedOwnerStartSignature: recordedOwnerStartSignature,
            callerPID: callerPID,
            callerStartSignature: callerStartSignature
        )
    }
}

// MARK: - HelperUninstallPreparation

/// Tears down a helper session only once the user's proxy settings are provably back.
///
/// Stopping the watchdog and clearing the backup are both irreversible for this machine: together
/// they remove the last two things that could put the settings back. Doing either before the
/// restore has succeeded turns a failed uninstall into a permanent override with no restore point
/// — so a restore that throws leaves both exactly where they are and the caller is told the
/// preparation did not happen.
enum HelperUninstallPreparation {
    static func run(
        restore: () throws -> Void,
        stopWatchdog: () -> Void,
        clearBackup: () -> Void
    )
        -> Bool
    {
        do {
            try restore()
        } catch {
            return false
        }
        stopWatchdog()
        clearBackup()
        return true
    }
}
