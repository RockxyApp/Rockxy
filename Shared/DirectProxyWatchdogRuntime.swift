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
    // MARK: Internal

    static func labels(in launchctlListOutput: String, baseLabel: String) -> [String] {
        let labels = launchctlListOutput.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            line.split(whereSeparator: \.isWhitespace).last.flatMap { ownedLabel(String($0), baseLabel: baseLabel) }
        }
        return Array(Set(labels)).sorted()
    }

    /// Every owned watchdog job that is not running and did not end cleanly, classified by
    /// `DirectProxyWatchdogExit.diagnosis(forStatus:)`. This is the one place production turns a
    /// `launchctl list` status into a fault, so a signal (launchd lists those as negative numbers,
    /// e.g. SIGKILL under memory pressure) or any other non-zero status is not silently dropped.
    ///
    /// A job with a live PID is still running, so a stale status beside it is not a failure. That
    /// holds for 78 and 79 as much as for any other status: a watchdog that refuses its backup
    /// exits immediately, so it cannot be the one holding that PID. Reading those two whatever the
    /// PID said let a retired label — one `launchctl remove` failed to clear, which `install`
    /// reports as `retainedSupersededLabel` — keep answering "refused" on every poll, so the user
    /// was told an override had no automatic restore while a freshly submitted watchdog was in
    /// fact watching it.
    static func failures(in launchctlListOutput: String, baseLabel: String) -> DirectProxyWatchdogFailures {
        var failures = DirectProxyWatchdogFailures()
        for (label, diagnosis, isRunning) in diagnosedJobs(in: launchctlListOutput, baseLabel: baseLabel)
            where !isRunning
        {
            switch diagnosis {
            case .resolved:
                break
            case .refusedBackup:
                failures.refused.append(label)
            case .neverRan:
                failures.neverRan.append(label)
            case let .other(status):
                failures.other.append(.init(label: label, status: status))
            }
        }
        failures.refused = Array(Set(failures.refused)).sorted()
        failures.neverRan = Array(Set(failures.neverRan)).sorted()
        failures.other = Array(Set(failures.other)).sorted { $0.label < $1.label }
        return failures
    }

    /// The Rockxy watchdog jobs whose last exit was a refusal to trust their own backup.
    ///
    /// `launchctl submit` leaves the job registered after it exits, and `launchctl list` prints
    /// its last exit status in the middle column (`PID  Status  Label`). That is the channel a
    /// watchdog uses to say "I would not act on this record": there is no process left to ask and
    /// no connection to it, but the app already lists these jobs to retire them, so the answer is
    /// there to be read before they are removed.
    static func refusedLabels(in launchctlListOutput: String, baseLabel: String) -> [String] {
        labels(in: launchctlListOutput, baseLabel: baseLabel, lastExitStatus: DirectProxyWatchdogExit.refusedBackup)
    }

    /// The Rockxy watchdog jobs whose last exit status is `EX_CONFIG` (78): the status launchd
    /// itself reports when it could not set the job up, so the watchdog never ran. Builds before
    /// the refusal had its own code also used 78 for a refusal, so a stale job can be either; the
    /// status alone cannot say which, and this list is deliberately kept apart from `refusedLabels`.
    static func neverRanLabels(in launchctlListOutput: String, baseLabel: String) -> [String] {
        labels(in: launchctlListOutput, baseLabel: baseLabel, lastExitStatus: DirectProxyWatchdogExit.jobSetupFailed)
    }

    // MARK: Private

    private static func diagnosedJobs(
        in launchctlListOutput: String,
        baseLabel: String
    )
        -> [(label: String, diagnosis: DirectProxyWatchdogExit.Diagnosis, isRunning: Bool)]
    {
        launchctlListOutput.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 3,
                  let status = Int32(fields[1]),
                  let label = ownedLabel(fields[fields.count - 1], baseLabel: baseLabel) else
            {
                return nil
            }
            return (label, DirectProxyWatchdogExit.diagnosis(forStatus: status), Int32(fields[0]) != nil)
        }
    }

    private static func labels(in launchctlListOutput: String, baseLabel: String, lastExitStatus: Int32) -> [String] {
        let matched = launchctlListOutput.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 3,
                  fields[1] == String(lastExitStatus) else
            {
                return nil
            }
            return ownedLabel(fields[fields.count - 1], baseLabel: baseLabel)
        }
        return Array(Set(matched)).sorted()
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

// MARK: - DirectProxyWatchdogFailures

/// The owned watchdog jobs that are not running and did not resolve their session, grouped by what
/// the user should be told.
struct DirectProxyWatchdogFailures: Equatable {
    /// A job that ended with a non-zero status other than 78 or 79.
    struct Other: Equatable, Hashable {
        let label: String
        let status: Int32
    }

    /// Ran and refused its record (`DirectProxyWatchdogExit.refusedBackup`).
    var refused: [String] = []
    /// `EX_CONFIG`: launchd could not set the job up.
    var neverRan: [String] = []
    /// Any other non-zero status, including a signal. The job started and then stopped.
    var other: [Other] = []

    /// Jobs that are no longer watching and did not refuse a record: never started, or started and
    /// died. The user-visible fact is the same for both, that no automatic restore stands behind
    /// the override.
    var notRunning: [String] {
        (neverRan + other.map(\.label)).sorted()
    }

    var isEmpty: Bool {
        refused.isEmpty && neverRan.isEmpty && other.isEmpty
    }
}

// MARK: - DirectProxyWatchdogExit

/// How a watchdog that gave up ends, in the one form the helper that exits and the app that reads
/// the exit status agree on.
enum DirectProxyWatchdogExit {
    /// What a watchdog job's last exit status means.
    enum Diagnosis: Equatable {
        /// Status 0: the session resolved.
        case resolved
        /// `refusedBackup`: the watchdog ran, read its record, and would not act on it.
        case refusedBackup
        /// `jobSetupFailed` (`EX_CONFIG`): the status launchd and sysexits use for "the job could
        /// not be set up", which Rockxy's own watchdog never emits. It did not run.
        case neverRan
        /// Anything else, including a signal (launchd lists those as negative numbers).
        case other(Int32)
    }

    /// Exit status of a watchdog that ran and refused its backup record.
    ///
    /// 79 sits just above `EX__MAX` (78), the top of the range `sysexits.h` reserves (64...78),
    /// so it equals no sysexits value; it is below the shell's 126/127 and 128+signal conventions;
    /// and `launchctl list` prints a job's last status verbatim, with no special meaning attached
    /// to 79 (negative numbers are signals). It was `EX_CONFIG` (78) before, which is also what
    /// launchd reports when a job could not be set up at all, so "refused" and "never ran" were
    /// indistinguishable.
    static let refusedBackup: Int32 = 79

    /// `EX_CONFIG`. Never emitted by the watchdog; recognised only so a job that reports it is
    /// diagnosed as one that did not run, not as a refusal.
    static let jobSetupFailed: Int32 = 78

    static func diagnosis(forStatus status: Int32) -> Diagnosis {
        switch status {
        case 0: .resolved
        case refusedBackup: .refusedBackup
        case jobSetupFailed: .neverRan
        default: .other(status)
        }
    }
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
