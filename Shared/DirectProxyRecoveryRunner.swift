import Foundation

// The per-service loop that writes a direct-mode backup back onto the machine.

// MARK: - DirectProxyRecoveryEvent

/// Something worth reporting that happened to one service during a recovery run. The runner
/// decides; the caller decides how to say it, because the app and the watchdog log differently.
enum DirectProxyRecoveryEvent {
    /// The service's live settings are no longer the ones this recovery planned for, so it left
    /// recovery untouched.
    case droppedChangedService(String)
    /// The service's settings could not be read before its first command, so nothing was written.
    case deferredUnreadableService(String)
    /// The record that authorizes this service's commands could not be stored, so no command was
    /// issued for it.
    case uncommittedService(service: String, error: any Error)
    /// A command sequence stopped part-way.
    case failedStep(service: String, step: ProxyServiceRestoreStep, error: (any Error)?)
    /// A journal update after the commands had already landed could not be persisted.
    case backupUpdateFailed(any Error)
}

// MARK: - DirectProxyRecoveryEffects

/// Everything the recovery loop does to the outside world.
struct DirectProxyRecoveryEffects {
    // MARK: Lifecycle

    init(
        readState: @escaping (String) -> ProxyServiceRestorationState?,
        publishBackup: @escaping (DirectProxyBackup) throws -> Void,
        restoreProxyState: @escaping (DirectServiceBackup) throws -> Void,
        restoreBypassDomains: @escaping (DirectServiceBackup) throws -> Void,
        log: @escaping (DirectProxyRecoveryEvent) -> Void
    ) {
        self.readState = readState
        self.publishBackup = publishBackup
        self.restoreProxyState = restoreProxyState
        self.restoreBypassDomains = restoreBypassDomains
        self.log = log
    }

    // MARK: Internal

    /// Reads every proxy field of one service, or nothing at all.
    let readState: (String) -> ProxyServiceRestorationState?
    /// Publishes the backup. A throw has to mean the previous record is still the one on disk —
    /// the loop treats a successful write as its permission to issue a command.
    let publishBackup: (DirectProxyBackup) throws -> Void
    let restoreProxyState: (DirectServiceBackup) throws -> Void
    let restoreBypassDomains: (DirectServiceBackup) throws -> Void
    let log: (DirectProxyRecoveryEvent) -> Void
}

// MARK: - DirectProxyRecoveryResult

/// What a recovery run decided, in the shape the caller needs to finish the attempt.
struct DirectProxyRecoveryResult {
    var backup: DirectProxyBackup
    var journal: [ProxyServiceRecoveryJournalEntry]
    var retention: ProxyBackupRetention
    var attemptedServices: [String] = []
    var failedServices: Set<String> = []
    var deferredServices: [String]
    var allSucceeded = true
}

// MARK: - DirectProxyRecoveryRunner

/// Restores the services a recovery plan authorized, one at a time, recording the intent before
/// each service's first command and its completion after the last.
///
/// The plan was made for every service at once, but the services are written one after another.
/// Re-reading a service immediately before its own first command is what lets a change made while
/// an earlier service was being restored be seen before anything is overwritten — and a service
/// that leaves recovery here leaves it durably, because its entry comes off disk before the loop
/// moves on.
///
/// The app and the watchdog binary run this same loop. They differ only in how they reach
/// `networksetup` and the backup file, which is exactly what `DirectProxyRecoveryEffects`
/// carries: a second implementation that merely resembled this one would drift, and the shape it
/// drifted into would only ever be observed after a crash.
enum DirectProxyRecoveryRunner {
    // MARK: Internal

    static func run(
        entriesToRestore: [ProxyServiceRecoveryJournalEntry],
        backup: DirectProxyBackup,
        journal: [ProxyServiceRecoveryJournalEntry],
        retention: ProxyBackupRetention,
        deferredServices: [String],
        effects: DirectProxyRecoveryEffects
    )
        -> DirectProxyRecoveryResult
    {
        var result = DirectProxyRecoveryResult(
            backup: backup,
            journal: journal,
            retention: retention,
            deferredServices: deferredServices
        )

        for journalEntry in entriesToRestore {
            restoreOne(journalEntry: journalEntry, result: &result, effects: effects)
        }

        return result
    }

    // MARK: Private

    private static func restoreOne(
        journalEntry: ProxyServiceRecoveryJournalEntry,
        result: inout DirectProxyRecoveryResult,
        effects: DirectProxyRecoveryEffects
    ) {
        guard let entry = result.backup.services.first(where: { $0.service == journalEntry.service }) else {
            return
        }

        switch ProxyServiceRecoveryPolicy.continuation(
            for: journalEntry,
            live: effects.readState(entry.service)
        ) {
        case .restore:
            break
        case .complete, .abandon:
            effects.log(.droppedChangedService(entry.service))
            result.retention.drop(entry.service)
            result.journal.removeAll { $0.service == entry.service }
            persistOrKeepPrevious(&result, effects: effects)
            return
        case .retryLater:
            effects.log(.deferredUnreadableService(entry.service))
            result.deferredServices.append(entry.service)
            result.journal = advanced(result.journal, service: entry.service, to: journalEntry.stage)
            persistOrKeepPrevious(&result, effects: effects)
            return
        }

        // Only now, and only for this one service, does the record advance to `inFlight`. The
        // commit is the permission to issue a command: a record that cannot be written means no
        // command is issued for that service, because an unrecorded write is precisely what a
        // later attempt has no way to reason about.
        let inFlightEntry = journalEntry.advanced(to: .inFlight)
        let inFlightJournal = advanced(result.journal, service: entry.service, to: .inFlight)
        let pendingBackup = result.backup
        let retainedServices = result.retention.services
        var committedBackup: DirectProxyBackup?
        // The bypass list is the last thing a restore writes, and it is not written at all when
        // the proxy state failed: a restored bypass list beside a half-written proxy state is a
        // shape no prefix of the sequence produces, and recovery has to read those as somebody
        // else's.
        let attempt = ProxyJournaledServiceRestore.run(
            commitInFlight: {
                committedBackup = try published(
                    pendingBackup,
                    retaining: retainedServices,
                    journal: inFlightJournal,
                    effects: effects
                )
            },
            restore: {
                switch ProxyServiceRecoveryPolicy.continuation(
                    for: inFlightEntry,
                    live: effects.readState(entry.service)
                ) {
                case .restore:
                    break
                case .complete:
                    return .restored
                case .abandon, .retryLater:
                    return .failed(
                        step: .proxyState,
                        error: ProxyRecoveryRevalidationError.stateChangedAfterCommit(
                            service: entry.service
                        )
                    )
                }
                return ProxyServiceRestoreExecution.run(
                    proxyState: { try effects.restoreProxyState(entry) },
                    bypassDomains: { try effects.restoreBypassDomains(entry) }
                )
            }
        )

        guard case let .issued(outcome) = attempt else {
            if case let .notIssued(commitError) = attempt {
                effects.log(.uncommittedService(service: entry.service, error: commitError))
            }
            result.deferredServices.append(entry.service)
            return
        }

        result.journal = inFlightJournal
        result.backup = committedBackup ?? result.backup
        result.attemptedServices.append(entry.service)

        if let failedStep = outcome.failedStep {
            effects.log(.failedStep(service: entry.service, step: failedStep, error: outcome.error))
            result.allSucceeded = false
            result.failedServices.insert(entry.service)
            return
        }

        // Every command for this service returned. Recording that now is what keeps a death from
        // this point on from looking like a command that never ran.
        result.journal = advanced(result.journal, service: entry.service, to: .restored)
        persistOrKeepPrevious(&result, effects: effects)
    }

    /// Rewrites the backup so the services and journal it holds match what the run has decided so
    /// far. A failed write leaves the previous contents in place, which is safe here because the
    /// next attempt re-reads every service before it writes one.
    private static func persistOrKeepPrevious(
        _ result: inout DirectProxyRecoveryResult,
        effects: DirectProxyRecoveryEffects
    ) {
        do {
            result.backup = try published(
                result.backup,
                retaining: result.retention.services,
                journal: result.journal,
                effects: effects
            )
        } catch {
            effects.log(.backupUpdateFailed(error))
        }
    }

    /// The same rewrite where a failed write has to reach the caller, because the write is the
    /// permission to issue a command rather than a record of one that already ran.
    private static func published(
        _ backup: DirectProxyBackup,
        retaining services: [String],
        journal: [ProxyServiceRecoveryJournalEntry],
        effects: DirectProxyRecoveryEffects
    )
        throws -> DirectProxyBackup
    {
        let retainedServices = Set(services)
        let updated = backup.with(
            services: ProxyBackupSubset.select(
                backup.services,
                services: retainedServices,
                serviceName: \.service
            ),
            journal: ProxyBackupSubset.select(journal, services: retainedServices, serviceName: \.service),
            recoveryPending: true
        )
        try effects.publishBackup(updated)
        return updated
    }

    private static func advanced(
        _ journal: [ProxyServiceRecoveryJournalEntry],
        service: String,
        to stage: ProxyRecoveryStage
    )
        -> [ProxyServiceRecoveryJournalEntry]
    {
        journal.map { $0.service == service ? $0.advanced(to: stage) : $0 }
    }
}
