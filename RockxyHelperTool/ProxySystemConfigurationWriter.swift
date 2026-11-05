import Foundation
import os
import SystemConfiguration

// Thin SystemConfiguration shell: executes the decisions `ProxySettingsTransaction.swift` makes.
// Which services, which keys, which values, and whether to fall back are all decided there.

// MARK: - ProxySystemConfigurationWriter

/// Writes the proxy settings of any number of services in one locked, committed transaction.
///
/// One `SCPreferences` session is created, locked, mutated for every admitted service, committed
/// once and applied once. The commit replaces the preferences file atomically, so a reader sees
/// all of the batch or none of it.
///
/// A commit is not the end, though. Every reader in the helper reads preferences, and
/// preferences say "restored" the instant the commit lands, before `configd` has adopted
/// anything. So an apply owed is recorded durably BEFORE the commit and forgotten only after an
/// apply that returned success (`ProxyApplyDebtLedger`); a process that dies in between leaves
/// the record, and the next operation settles it with `settleOwedApply`.
///
/// Every SystemConfiguration call here can block behind another writer or an unresponsive
/// `configd`, and none can be interrupted. The work runs on its own thread under a deadline. At
/// the deadline the job is told never to begin a commit; if one has already begun it is allowed a
/// short grace to finish, because the caller is about to run the `networksetup` fallback and
/// that must not collide with a lock this job still holds. Either way the caller does not get
/// control back until the job has released the lock, unless the job is still stuck past the
/// grace, in which case the fallback proceeds and the orphaned thread is left to finish on its
/// own (one per timed-out transaction, which the helper's rate limit bounds).
enum ProxySystemConfigurationWriter {
    // MARK: Internal

    /// How long the caller waits for the transaction before telling the job to stand down.
    static let overallDeadline: TimeInterval = 6

    /// How long a job that has been told to stand down gets to release the lock. Together with
    /// the deadline this stays inside `BoundedHelperCommand.networkConfigurationTimeout` plus one
    /// fallback command.
    static let handOffGrace: TimeInterval = 2

    /// How long the preferences lock is retried before another writer is given up on.
    static let lockBudget: TimeInterval = 3

    static func commit(
        _ items: [ProxyTransactionItem],
        ownedPort: Int? = nil,
        store: any ProxyApplyDebtStore = ProxyApplyDebtFileStore()
    )
        -> ProxyTransactionOutcome
    {
        guard !items.isEmpty else {
            return .notCommitted(reason: .noEligibleService)
        }

        let job = Job(items: items, ownedPort: ownedPort, store: store)
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            job.run()
            finished.signal()
        }
        thread.name = "com.rockxy.helper.proxy-transaction"
        thread.start()

        if finished.wait(timeout: .now() + overallDeadline) == .success {
            return job.outcome
        }

        let commitHadBegun = job.cancel()
        logger.error(
            "Proxy transaction passed its \(overallDeadline, privacy: .public)s deadline (commit begun: \(commitHadBegun, privacy: .public))"
        )
        if finished.wait(timeout: .now() + handOffGrace) == .success {
            // The job finished inside the grace, so its outcome is real: a landed commit is
            // reported as one, and the lock is free before any fallback runs.
            return job.outcome
        }
        logger.error("Proxy transaction still holds the preferences lock after the hand-off grace")
        return .indeterminate(reason: .timedOut)
    }

    /// Applies preferences a previous transaction committed but never confirmed applying.
    ///
    /// Recovery for an `owed` record: apply, and forget the debt only if the apply succeeded.
    /// Cheap when nothing is owed (one file read), so every privileged entry point may call it.
    static func settleOwedApply(
        store: any ProxyApplyDebtStore = ProxyApplyDebtFileStore()
    )
        -> ProxyApplySettlement
    {
        ProxyApplyDebtLedger.settle(in: store) {
            let done = DispatchSemaphore(value: 0)
            let result = OSAllocatedUnfairLock(initialState: false)
            let thread = Thread {
                if let preferences = SCPreferencesCreate(nil, "Rockxy Helper" as CFString, nil) {
                    let applied = SCPreferencesApplyChanges(preferences)
                    result.withLock { $0 = applied }
                }
                done.signal()
            }
            thread.name = "com.rockxy.helper.proxy-apply"
            thread.start()
            guard done.wait(timeout: .now() + overallDeadline) == .success else {
                return false
            }
            return result.withLock { $0 }
        }
    }

    /// What `configd` has adopted (not what preferences hold), or nil when it cannot be read.
    static func effectiveProxies() -> [String: Any]? {
        SCDynamicStoreCopyProxies(nil) as? [String: Any]
    }

    // MARK: Private

    /// One transaction. Reference type so the deadline path can cancel it from the caller's thread.
    private final class Job: @unchecked Sendable {
        // MARK: Lifecycle

        init(items: [ProxyTransactionItem], ownedPort: Int?, store: any ProxyApplyDebtStore) {
            self.items = items
            self.ownedPort = ownedPort
            self.store = store
        }

        // MARK: Internal

        var outcome: ProxyTransactionOutcome {
            state.withLock { $0.outcome }
        }

        /// Tells the job to stand down. Returns whether a commit had already begun, which is then
        /// beyond recall. After this returns false the job will never begin one.
        func cancel() -> Bool {
            state.withLock {
                $0.isCancelled = true
                return $0.commitBegun
            }
        }

        func run() {
            let result = transact()
            state.withLock { $0.outcome = result }
        }

        // MARK: Private

        private struct State {
            var isCancelled = false
            var commitBegun = false
            var outcome: ProxyTransactionOutcome = .indeterminate(reason: .timedOut)
        }

        private let items: [ProxyTransactionItem]
        private let ownedPort: Int?
        private let store: any ProxyApplyDebtStore
        private let state = OSAllocatedUnfairLock(initialState: State())

        private var isCancelled: Bool {
            state.withLock { $0.isCancelled }
        }

        /// Atomic with `cancel()`: either the job begins the commit and `cancel()` reports it, or
        /// `cancel()` wins and the job never commits.
        private func beginCommit() -> Bool {
            state.withLock {
                guard !$0.isCancelled else {
                    return false
                }
                $0.commitBegun = true
                return true
            }
        }

        private func transact() -> ProxyTransactionOutcome {
            guard let preferences = SCPreferencesCreate(nil, "Rockxy Helper" as CFString, nil) else {
                return .notCommitted(reason: .sessionUnavailable)
            }
            if let failure = lock(preferences) {
                return .notCommitted(reason: failure)
            }
            defer { SCPreferencesUnlock(preferences) }

            // The current set, not every service in the file: it is the list `networksetup`
            // names services from, so the names the rest of the helper holds resolve against it.
            guard let currentSet = SCNetworkSetCopyCurrent(preferences),
                  let services = SCNetworkSetCopyServices(currentSet) as? [SCNetworkService] else
            {
                return .notCommitted(reason: .unexpectedSchema)
            }
            var servicesByID: [String: SCNetworkService] = [:]
            var candidates: [ProxyServiceCandidate] = []
            for service in services {
                guard let id = SCNetworkServiceGetServiceID(service) as String?,
                      let name = SCNetworkServiceGetName(service) as String? else
                {
                    continue
                }
                servicesByID[id] = service
                candidates.append(ProxyServiceCandidate(id: id, name: name))
            }

            let plan = ProxyTransactionPlan.prepare(items: items, candidates: candidates)
            var declined = plan.declined
            var written: [String] = []

            for ready in plan.ready {
                if let reason = stage(ready, service: servicesByID[ready.serviceID]) {
                    declined[ready.item.service] = reason
                } else {
                    written.append(ready.item.service)
                }
            }

            guard !written.isEmpty else {
                // Staging nothing leaves nothing to discard. The per-service reasons are the only
                // record of why the fast path passed, so they travel with the outcome.
                return .notCommitted(reason: .noEligibleService, declined: declined)
            }

            // The debt is on disk before the commit can land. If it cannot be stored there is no
            // commit: an apply nothing remembers is exactly the case this exists to prevent.
            let recorded: ProxyApplyDebtLedger.Recorded
            do {
                recorded = try ProxyApplyDebtLedger.record(services: written, ownedPort: ownedPort, in: store)
            } catch {
                logger.error("Could not record the owed apply: \(error.localizedDescription, privacy: .public)")
                return .notCommitted(reason: .applyDebtUnrecorded, declined: declined)
            }

            // Nothing before this line has touched the preferences file; staged changes live in
            // this session only and vanish with it if the commit is never begun or is refused.
            guard beginCommit() else {
                ProxyApplyDebtLedger.discardUncommitted(recorded, in: store)
                return .notCommitted(reason: .timedOut, declined: declined)
            }
            guard SCPreferencesCommitChanges(preferences) else {
                logger.error("Proxy commit refused: \(lastSystemConfigurationError(), privacy: .public)")
                ProxyApplyDebtLedger.discardUncommitted(recorded, in: store)
                return .notCommitted(reason: .commitRefused, declined: declined)
            }
            // Past the point of no return: even a stood-down job applies what it committed.
            guard SCPreferencesApplyChanges(preferences) || SCPreferencesApplyChanges(preferences) else {
                logger.error("Proxy apply refused: \(lastSystemConfigurationError(), privacy: .public)")
                return .indeterminate(reason: .applyRefused, declined: declined)
            }
            ProxyApplyDebtLedger.confirmApplied(recorded, in: store)
            return .committed(services: written, declined: declined)
        }

        /// Retries the non-blocking lock until the budget is spent. A blocking lock would sit
        /// behind another writer for as long as it likes.
        private func lock(_ preferences: SCPreferences) -> ProxyFallbackReason? {
            let deadline = Date().addingTimeInterval(ProxySystemConfigurationWriter.lockBudget)
            while true {
                if SCPreferencesLock(preferences, false) {
                    return nil
                }
                guard SCError() == kSCStatusPrefsBusy else {
                    logger.error("Proxy preferences lock failed: \(lastSystemConfigurationError(), privacy: .public)")
                    return .sessionUnavailable
                }
                guard !isCancelled, Date() < deadline else {
                    return .lockBusy
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        /// Reads one service's stored configuration under the lock, applies the admission check,
        /// and stages the new configuration. Returns a reason to decline it, or nil when staged.
        private func stage(
            _ ready: ProxyTransactionPlan.Ready,
            service: SCNetworkService?
        )
            -> ProxyFallbackReason?
        {
            guard let service,
                  let proxies = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else
            {
                return .unexpectedSchema
            }
            let stored: [String: Any]
            if let configuration = SCNetworkProtocolGetConfiguration(proxies) {
                guard let dictionary = configuration as? [String: Any] else {
                    return .unexpectedSchema
                }
                stored = dictionary
            } else {
                stored = [:]
            }

            if let reason = ProxyTransactionPlan.decline(ready, storedConfiguration: stored) {
                return reason
            }
            let updated = ProxyWritePlan.apply(ready.item.writes, to: stored)
            guard SCNetworkProtocolSetConfiguration(proxies, updated as CFDictionary) else {
                logger.error("Proxy staging refused: \(lastSystemConfigurationError(), privacy: .public)")
                return .unexpectedSchema
            }
            return nil
        }
    }

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ProxySystemConfigurationWriter"
    )
}

private func lastSystemConfigurationError() -> String {
    String(cString: SCErrorString(SCError()))
}
