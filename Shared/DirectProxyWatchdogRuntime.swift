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
              !arguments[4].isEmpty
        else {
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
    // MARK: Internal

    enum Outcome {
        /// The new watcher is running. The superseded label, if there was one, has been asked to
        /// go away; whether that removal itself succeeded does not change who is watching.
        case installed(activeLabel: String, supersededLabel: String?)
        /// Nothing was submitted. Whatever was watching before still is, and the caller must not
        /// treat the override as watched by anything new.
        case failed(activeLabel: String?, error: any Error)

        // MARK: Internal

        /// The label of the job actually watching once this call returns, which is what decides
        /// whether the override is covered.
        var activeLabel: String? {
            switch self {
            case let .installed(activeLabel, _):
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

        if let supersededLabel, supersededLabel != newLabel {
            // The replacement is already running, so a stubborn old job is a stray process rather
            // than a gap in cover. It exits on its own as soon as the backup is resolved.
            try? remove(supersededLabel)
        }
        return .installed(activeLabel: newLabel, supersededLabel: supersededLabel)
    }
}

// MARK: - DirectProxyWatchdogRuntime

/// The watchdog's polling loop, with every side effect supplied by the caller.
///
/// This is the loop the binary in `Contents/Library/HelperTools` actually runs. It is written
/// against injected effects rather than against `FileManager` and `Thread.sleep` so the shipped
/// behaviour — the ordering of the checks, when a restore is issued, when the loop ends — is the
/// behaviour under test, instead of a second copy that only resembles it.
enum DirectProxyWatchdogRuntime {
    /// Polls until the session resolves, and reports how it ended.
    @discardableResult
    static func watch(
        parentIsLive: () -> Bool,
        backupExists: () -> Bool,
        restore: () -> Void,
        waitBeforeNextPoll: () -> Void
    )
        -> DirectProxyWatchdogAction
    {
        while true {
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
