import Foundation

// The direct-mode proxy watchdog, in the one form both the process that submits it and the
// process that runs it agree on.

// MARK: - DirectProxyWatchdogAction

/// What a watchdog poll decides to do next.
enum DirectProxyWatchdogAction: Equatable {
    /// The override is still there and its owner is still running. Keep watching.
    case wait
    /// The owner is gone and the restore point is still on disk. Put the settings back.
    case restore
    /// There is no backup left, so somebody else already resolved this session.
    case exit
}

// MARK: - DirectProxyWatchdogPolicy

/// Decides a watchdog poll from the only two facts it has.
///
/// The backup is checked first on purpose: once it is gone there is nothing left to restore, and
/// a watchdog that kept waiting on a live parent would outlive the session it was armed for.
enum DirectProxyWatchdogPolicy {
    static func action(parentAlive: Bool, backupExists: Bool) -> DirectProxyWatchdogAction {
        guard backupExists else {
            return .exit
        }
        return parentAlive ? .wait : .restore
    }
}

// MARK: - DirectProxyWatchdogInvocation

/// How the watchdog is asked for on the command line, and what an invocation means.
///
/// Formatting and parsing live together because the two halves run in different processes: the
/// app builds the `launchctl submit` line, and the helper binary reads it back. A field either
/// side counted differently would arm a watchdog that silently watches the wrong thing.
enum DirectProxyWatchdogInvocation: Equatable {
    /// This process was not launched as a watchdog at all.
    case notAWatchdog
    /// A watchdog was asked for, but the parent it names cannot be identified. Nothing is
    /// watched: waiting on a bare identifier would keep watching whatever process later inherits
    /// it, so the backup is left on disk for the app's own launch-time recovery instead.
    case unidentifiableParent
    case watch(parentPID: Int32, backupPath: String, parentStartSignature: String)

    // MARK: Internal

    static let flag = "--rockxy-direct-proxy-watchdog"

    /// The arguments that ask a freshly launched binary to watch `parentPID`.
    static func watchArguments(
        executablePath: String,
        parentPID: Int32,
        backupPath: String,
        parentStartSignature: String
    )
        -> [String]
    {
        [
            executablePath,
            flag,
            String(parentPID),
            backupPath,
            parentStartSignature,
        ]
    }

    static func parse(arguments: [String]) -> DirectProxyWatchdogInvocation {
        guard arguments.count >= 2, arguments[1] == flag else {
            return .notAWatchdog
        }
        guard arguments.count >= 5,
              let parentPID = Int32(arguments[2]),
              parentPID > 0,
              !arguments[4].isEmpty else
        {
            return .unidentifiableParent
        }
        return .watch(
            parentPID: parentPID,
            backupPath: arguments[3],
            parentStartSignature: arguments[4]
        )
    }
}

// MARK: - DirectProxyWatchdogInstallation

/// Replaces the watcher guarding a direct override without ever leaving it unwatched.
///
/// `launchctl` will not accept a second job under a label it already knows, so replacing a
/// watcher used to mean removing the old one first. That order is the bug: a submit that then
/// fails leaves no watcher at all, and the override this attempt is about to write — or the one
/// already on the machine — has nothing left to put it back. Submitting under a label nothing is
/// using yet inverts it, so the old watcher stays effective for exactly as long as the new one is
/// not, and the superseded job is only removed once its replacement is known installed.
enum DirectProxyWatchdogInstallation {
    enum Outcome {
        /// The new watcher is running. A superseded label that launchd refused to remove is
        /// returned explicitly so the caller can retain durable cleanup ownership for the next
        /// restore or app launch.
        case installed(
            activeLabel: String,
            supersededLabel: String?,
            retainedSupersededLabel: String?
        )
        /// Nothing was submitted. Whatever was watching before still is, and the caller must not
        /// treat the override as watched by anything new.
        case failed(activeLabel: String?, error: any Error)

        // MARK: Internal

        /// The label of the job actually watching once this call returns, which is what decides
        /// whether the override is covered.
        var activeLabel: String? {
            switch self {
            case let .installed(activeLabel, _, _):
                activeLabel
            case let .failed(activeLabel, _):
                activeLabel
            }
        }

        var isInstalled: Bool {
            switch self {
            case .installed:
                true
            case .failed:
                false
            }
        }
    }

    static func install(
        newLabel: String,
        supersededLabel: String?,
        submit: (String) throws -> Void,
        remove: (String) throws -> Void
    )
        -> Outcome
    {
        do {
            try submit(newLabel)
        } catch {
            return .failed(activeLabel: supersededLabel, error: error)
        }

        var retainedSupersededLabel: String?
        if let supersededLabel, supersededLabel != newLabel {
            // The replacement is already running, so a stubborn old job is a stray process rather
            // than a gap in cover. Keep its label durable if removal fails so the app can retry
            // after the backup is resolved instead of forgetting an orphaned launchd record.
            do {
                try remove(supersededLabel)
            } catch {
                retainedSupersededLabel = supersededLabel
            }
        }
        return .installed(
            activeLabel: newLabel,
            supersededLabel: supersededLabel,
            retainedSupersededLabel: retainedSupersededLabel
        )
    }
}

// MARK: - DirectProxyWatchdogJobDiscovery

/// Finds launchd jobs owned by Rockxy even when they predate the durable label registry.
///
/// Older builds submitted a stable label, and an interrupted replacement build could submit a
/// UUID-suffixed label before persisting it. `launchctl list` is therefore the last-resort source
/// of truth during resolved-session cleanup. Matching stays deliberately exact: only the base
/// label itself or a UUID suffix is accepted, so cleanup cannot broaden to unrelated jobs that
/// merely share a textual prefix.
enum DirectProxyWatchdogJobDiscovery {
    static func labels(in launchctlListOutput: String, baseLabel: String) -> [String] {
        let labels = launchctlListOutput.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            line.split(whereSeparator: \.isWhitespace).last.flatMap { ownedLabel(String($0), baseLabel: baseLabel) }
        }
        return Array(Set(labels)).sorted()
    }

    /// The Rockxy watchdog jobs whose last exit was a refusal to trust their own backup.
    ///
    /// `launchctl submit` leaves the job registered after it exits, and `launchctl list` prints
    /// its last exit status in the middle column (`PID  Status  Label`). That is the channel a
    /// watchdog uses to say "I would not act on this record": there is no process left to ask and
    /// no connection to it, but the app already lists these jobs to retire them, so the answer is
    /// there to be read before they are removed.
    static func refusedLabels(in launchctlListOutput: String, baseLabel: String) -> [String] {
        let refused = launchctlListOutput.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 3,
                  fields[1] == String(DirectProxyWatchdogExit.refusedBackup) else
            {
                return nil
            }
            return ownedLabel(fields[fields.count - 1], baseLabel: baseLabel)
        }
        return Array(Set(refused)).sorted()
    }

    private static func ownedLabel(_ candidate: String, baseLabel: String) -> String? {
        if candidate == baseLabel {
            return candidate
        }
        let prefix = "\(baseLabel)."
        guard candidate.hasPrefix(prefix),
              UUID(uuidString: String(candidate.dropFirst(prefix.count))) != nil else
        {
            return nil
        }
        return candidate
    }
}

// MARK: - DirectProxyWatchdogExit

/// How a watchdog that gave up ends, in the one form the helper that exits and the app that reads
/// the exit status agree on.
enum DirectProxyWatchdogExit {
    /// `EX_CONFIG`. The watchdog could not vouch for its backup record and stopped. Distinct from
    /// zero, which means the session resolved, so a job that exited this way is a job to look at.
    static let refusedBackup: Int32 = 78
}

// MARK: - DirectProxyWatchdogOutcome

/// How a watchdog's polling loop ended.
enum DirectProxyWatchdogOutcome: Equatable {
    /// The owner was gone and a restore was issued; the backup is resolved.
    case restore
    /// The backup disappeared, so another recovery already resolved the session.
    case exit
    /// The backup stayed in place but failed the trust gate or its content checks on consecutive
    /// polls. The watchdog will not act on it and will not poll it forever: it ends so the refusal
    /// is visible (`DirectProxyWatchdogExit.refusedBackup`) instead of a silent no-op.
    case refused
}

// MARK: - DirectProxyWatchdogRuntime

/// The watchdog's polling loop, with every side effect supplied by the caller.
///
/// This is the loop the binary in `Contents/Library/HelperTools` actually runs. It is written
/// against injected effects rather than against `FileManager` and `Thread.sleep` so the shipped
/// behaviour — the ordering of the checks, when a restore is issued, when the loop ends — is the
/// behaviour under test, instead of a second copy that only resembles it.
enum DirectProxyWatchdogRuntime {
    /// Consecutive refused polls before the watchdog concludes the record is not coming back.
    /// A record being replaced is published atomically, so a refusal that survives this many
    /// polls is a verdict on the file, not a race with its writer.
    static let refusalPollLimit = 3

    /// Polls until the session resolves, and reports how it ended.
    @discardableResult
    static func watch(
        parentIsLive: () -> Bool,
        backupExists: () -> Bool,
        backupIsRefused: () -> Bool = { false },
        restore: () -> Void,
        waitBeforeNextPoll: () -> Void
    )
        -> DirectProxyWatchdogOutcome
    {
        var consecutiveRefusals = 0
        while true {
            // Fail closed on a record that cannot be vouched for -- but say so, and stop, rather
            // than polling a deterministic refusal forever while the services stay on a dead port.
            if backupIsRefused() {
                consecutiveRefusals += 1
                if consecutiveRefusals >= refusalPollLimit {
                    return .refused
                }
                waitBeforeNextPoll()
                continue
            }
            consecutiveRefusals = 0

            switch DirectProxyWatchdogPolicy.action(
                parentAlive: parentIsLive(),
                backupExists: backupExists()
            ) {
            case .wait:
                waitBeforeNextPoll()
            case .restore:
                restore()
                guard backupExists() else {
                    return .restore
                }
                // A transient read, publication, or system-command failure leaves the narrowed
                // backup on disk. Keep the watcher alive and retry instead of turning one failed
                // attempt into an override with no remaining recovery process.
                waitBeforeNextPoll()
            case .exit:
                return .exit
            }
        }
    }
}
