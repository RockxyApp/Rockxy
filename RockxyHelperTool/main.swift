import Foundation
import os

// Boots the privileged helper, restores stale proxy state, and starts the XPC listener.

private let identity = RockxyIdentity.current
private let logger = Logger(subsystem: identity.logSubsystem, category: "Main")

// MARK: - DirectProxySnapshot

private struct DirectProxySnapshot {
    let httpEnabled: Bool
    let httpHost: String
    let httpPort: Int
    let httpsEnabled: Bool
    let httpsHost: String
    let httpsPort: Int
    let socksEnabled: Bool
    let socksHost: String
    let socksPort: Int
    let pacEnabled: Bool
    let pacURL: String
    let autoDiscoveryEnabled: Bool
}

// MARK: - DirectProxyWatchdog

private enum DirectProxyWatchdog {
    // MARK: Internal

    /// Watches the app process that took a direct-mode override and restores its settings once
    /// that exact process is gone.
    ///
    /// The parent's kernel start signature is passed on the command line beside its identifier,
    /// and both are compared on every poll. Watching the identifier alone would keep a watchdog
    /// waiting on whatever process later inherits it, so the override it was armed for would
    /// never be restored. An invocation that carries no signature is therefore not watched at
    /// all: it exits without touching a setting, leaving the backup on disk for the app's own
    /// launch-time recovery.
    static func run(arguments: [String]) -> Bool {
        switch DirectProxyWatchdogInvocation.parse(arguments: arguments) {
        case .notAWatchdog:
            return false
        case .unidentifiableParent:
            logger
                .error(
                    "Direct proxy watchdog was not given an identifiable parent process — exiting without watching"
                )
            return true
        case let .watch(parentPID, backupPath, parentStartSignature):
            let backupURL = URL(fileURLWithPath: backupPath)
            logger.info("RockxyHelperTool running direct proxy watchdog for parent pid \(parentPID)")

            DirectProxyWatchdogRuntime.watch(
                parentIsLive: {
                    parentSessionIsLive(pid: parentPID, startSignature: parentStartSignature)
                },
                backupExists: {
                    backupStillBelongsToWatchdog(
                        at: backupURL,
                        parentPID: parentPID,
                        parentStartSignature: parentStartSignature
                    )
                },
                restore: {
                    restoreIfNeeded(
                        from: backupURL,
                        parentPID: parentPID,
                        parentStartSignature: parentStartSignature
                    )
                },
                waitBeforeNextPoll: { Thread.sleep(forTimeInterval: pollInterval) }
            )
            return true
        }
    }

    // MARK: Private

    private static let networkSetupPath = "/usr/sbin/networksetup"
    private static let pollInterval: TimeInterval = 0.5

    /// Restores only the backed-up services the recovery journal still authorizes. A service the
    /// user re-pointed after the crash is left alone, and its absence never justifies deleting
    /// the restore point the remaining owned services still depend on.
    ///
    /// The journal is written before the first command and again after each service's commands
    /// return, so a watchdog that dies mid-restore leaves a record a later attempt can read:
    /// settings this restore could have produced are written again, and settings it could not are
    /// treated as the user's and dropped from recovery untouched.
    ///
    /// The per-service loop is `DirectProxyRecoveryRunner`, the same one the app runs. Sharing it
    /// rather than keeping a second copy here is deliberate: the states these two produce are only
    /// ever observed after a crash, which is exactly where a divergence between them would first
    /// be found — and it would be found as a user's settings overwritten.
    private static func restoreIfNeeded(
        from backupURL: URL,
        parentPID: Int32,
        parentStartSignature: String
    ) {
        do {
            try DirectProxySessionLock.withExclusiveAccess(backupURL: backupURL) {
                restoreIfNeededLocked(
                    from: backupURL,
                    parentPID: parentPID,
                    parentStartSignature: parentStartSignature
                )
            }
        } catch {
            logger.error("Direct proxy watchdog could not acquire the session lock: \(error.localizedDescription)")
        }
    }

    /// Reloads and validates ownership only after the cross-process lock is held.
    private static func restoreIfNeededLocked(
        from backupURL: URL,
        parentPID: Int32,
        parentStartSignature: String
    ) {
        guard let backup = loadBackup(from: backupURL) else {
            return
        }
        guard DirectProxyBackupOwnerPolicy.belongsToSession(
            backup,
            processIdentifier: parentPID,
            processStartSignature: parentStartSignature
        ) else {
            logger.info("Direct proxy watchdog leaving a backup owned by another app session untouched")
            return
        }

        // A recovery already under way keeps every retained service in play, because a partial
        // command can leave a shape strict ownership no longer recognises. An override this
        // machine recorded itself as applying does the same, because a sequence that stopped
        // half-way leaves a service strict ownership does not recognise either. Which of them may
        // still be written is then decided per service against the journal.
        let recoveryHasStarted = backup.recoveryPending || !backup.journal.isEmpty
        let ownedServices = recoveryHasStarted
            ? backup.services.map(\.service)
            : residualOwnedServices(in: backup)
        guard !ownedServices.isEmpty else {
            logger.info("Direct proxy watchdog clearing stale backup because no service still points at Rockxy")
            try? FileManager.default.removeItem(at: backupURL)
            return
        }

        let candidateEntries = ProxyBackupSubset.select(
            backup.services,
            services: Set(ownedServices),
            serviceName: \.service
        )
        // A service with no usable record enters recovery only when the live settings still prove
        // Rockxy owns it on the persisted port. Anything weaker keeps its restore point rather
        // than being adopted as the state a restore begins from.
        let plan = ProxyRecoveryPlanner.plan(
            targets: candidateEntries.map(\.restorationTarget),
            journal: backup.journal,
            liveStates: currentRestorationStates(for: candidateEntries.map(\.service)),
            ownedPort: backup.rockxyPort
        )

        if !plan.abandonedServices.isEmpty {
            logger
                .warning(
                    "Direct proxy watchdog leaving \(plan.abandonedServices.count) service(s) out of recovery — their proxy settings were changed outside this restore"
                )
        }

        let plannedJournal = plan.entriesToRestore + ProxyBackupSubset.select(
            backup.journal,
            services: Set(plan.deferredServices),
            serviceName: \.service
        )

        guard !plan.entriesToRestore.isEmpty else {
            // Nothing is written, so the backup keeps the flag it arrived with.
            retainOrClear(
                backup: backup,
                services: plan.deferredServices,
                journal: plannedJournal,
                recoveryPending: backup.recoveryPending,
                at: backupURL
            )
            return
        }

        // Narrow the backup and record the intent before mutating anything: if this write fails,
        // the original backup and the current settings both stay exactly as they are. Every
        // planned service is recorded at the stage it was planned at, so a service nothing has
        // been issued for stays `pending` even if this watchdog dies while writing another one.
        let retention = ProxyBackupRetention(authorized: plan.servicesKeepingBackup, preserved: [])
        let narrowedBackup = DirectProxyBackup(
            services: ProxyBackupSubset.select(
                backup.services,
                services: Set(retention.services),
                serviceName: \.service
            ),
            timestamp: backup.timestamp,
            rockxyPort: backup.rockxyPort,
            ownerPID: backup.ownerPID,
            ownerStartSignature: backup.ownerStartSignature,
            recoveryPending: true,
            journal: plannedJournal
        )
        do {
            try write(narrowedBackup, to: backupURL)
        } catch {
            logger
                .error(
                    "Direct proxy watchdog could not narrow the backup — leaving settings untouched: \(error.localizedDescription)"
                )
            return
        }

        logger
            .warning(
                "Direct proxy watchdog restoring \(plan.entriesToRestore.count) owned service(s) after parent exit"
            )

        let outcome = DirectProxyRecoveryRunner.run(
            entriesToRestore: plan.entriesToRestore,
            backup: narrowedBackup,
            journal: plannedJournal,
            retention: retention,
            deferredServices: plan.deferredServices,
            effects: recoveryEffects(at: backupURL)
        )

        let unresolvedServices = ProxyBackupSubset.unresolvedEntries(
            outcome.attemptedServices,
            failedServices: outcome.failedServices,
            stillOwnedServices: Set(residualOwnedServices(in: outcome.backup)),
            serviceName: { $0 }
        ) + outcome.deferredServices

        retainOrClear(
            backup: outcome.backup,
            services: outcome.retention.retainedAfterAttempt(unresolvedServices: unresolvedServices),
            journal: outcome.journal,
            recoveryPending: true,
            at: backupURL
        )
    }

    /// How the watchdog reaches `networksetup` and the backup file during a recovery run.
    private static func recoveryEffects(at backupURL: URL) -> DirectProxyRecoveryEffects {
        DirectProxyRecoveryEffects(
            readState: { readRestorationState(for: $0) },
            publishBackup: { try write($0, to: backupURL) },
            restoreProxyState: { entry in
                try restoreProxyState(for: entry.service, snapshot: snapshot(of: entry))
            },
            restoreBypassDomains: { entry in
                try restoreBypassDomains(for: entry.service, domains: entry.bypassDomains)
            },
            log: { event in
                switch event {
                case let .droppedChangedService(service):
                    logger
                        .warning(
                            "Direct proxy watchdog dropping '\(service)' — its proxy settings are no longer the ones this recovery planned for"
                        )
                case let .deferredUnreadableService(service):
                    logger
                        .warning(
                            "Direct proxy watchdog deferring '\(service)' — its proxy settings could not be read before restoring"
                        )
                case let .uncommittedService(service, error):
                    logger
                        .error(
                            "Direct proxy watchdog could not record the restore of '\(service)' — issuing no command for it: \(error.localizedDescription)"
                        )
                case let .failedStep(service, step, error):
                    logger
                        .error(
                            "Direct proxy watchdog stopped restoring '\(service)' at the \(step.rawValue) step: \(error?.localizedDescription ?? "unknown error")"
                        )
                case let .backupUpdateFailed(error):
                    logger
                        .error(
                            "Direct proxy watchdog could not update the retained backup: \(error.localizedDescription)"
                        )
                }
            }
        )
    }

    /// One service's captured settings in the shape the restore commands take.
    private static func snapshot(of entry: DirectServiceBackup) -> DirectProxySnapshot {
        DirectProxySnapshot(
            httpEnabled: entry.httpEnabled,
            httpHost: entry.httpHost,
            httpPort: entry.httpPort,
            httpsEnabled: entry.httpsEnabled,
            httpsHost: entry.httpsHost,
            httpsPort: entry.httpsPort,
            socksEnabled: entry.socksEnabled,
            socksHost: entry.socksHost,
            socksPort: entry.socksPort,
            pacEnabled: entry.pacEnabled,
            pacURL: entry.pacURL,
            autoDiscoveryEnabled: entry.autoDiscoveryEnabled
        )
    }

    /// Keeps exactly the services that still need a restore point, or removes the backup when
    /// none do.
    private static func retainOrClear(
        backup: DirectProxyBackup,
        services: [String],
        journal: [ProxyServiceRecoveryJournalEntry],
        recoveryPending: Bool,
        at backupURL: URL
    ) {
        guard !services.isEmpty else {
            try? FileManager.default.removeItem(at: backupURL)
            return
        }

        let retainedServices = Set(services)
        let retainedBackup = DirectProxyBackup(
            services: ProxyBackupSubset.select(
                backup.services,
                services: retainedServices,
                serviceName: \.service
            ),
            timestamp: backup.timestamp,
            rockxyPort: backup.rockxyPort,
            ownerPID: backup.ownerPID,
            ownerStartSignature: backup.ownerStartSignature,
            recoveryPending: recoveryPending,
            journal: ProxyBackupSubset.select(journal, services: retainedServices, serviceName: \.service)
        )
        do {
            try write(retainedBackup, to: backupURL)
        } catch {
            logger.error("Direct proxy watchdog could not narrow the retained backup: \(error.localizedDescription)")
        }
        logger
            .warning(
                "Direct proxy watchdog left \(services.count) service(s) in the backup for later recovery"
            )
    }

    /// Reads the full restoration-relevant shape of each service. A service whose settings cannot
    /// be read is left out rather than reported as empty, so recovery defers it instead of
    /// treating an unreadable service as a changed one.
    private static func currentRestorationStates(
        for services: [String]
    )
        -> [String: ProxyServiceRestorationState]
    {
        var states: [String: ProxyServiceRestorationState] = [:]
        for service in services {
            states[service] = readRestorationState(for: service)
        }
        return states
    }

    private static func readRestorationState(for service: String) -> ProxyServiceRestorationState? {
        guard let httpOutput = try? runNetworkSetup(["-getwebproxy", service]),
              let httpsOutput = try? runNetworkSetup(["-getsecurewebproxy", service]),
              let socksOutput = try? runNetworkSetup(["-getsocksfirewallproxy", service]),
              let pacOutput = try? runNetworkSetup(["-getautoproxyurl", service]),
              let autoDiscoveryOutput = try? runNetworkSetup(["-getproxyautodiscovery", service]),
              let bypassOutput = try? runNetworkSetup(["-getproxybypassdomains", service])
        else {
            return nil
        }

        let http = parseProxyOutput(httpOutput)
        let https = parseProxyOutput(httpsOutput)
        let socks = parseProxyOutput(socksOutput)
        let pac = parsePACOutput(pacOutput)

        return ProxyServiceRestorationState(
            service: service,
            http: ProxyEndpointState(enabled: http.enabled, host: http.host, port: http.port),
            https: ProxyEndpointState(enabled: https.enabled, host: https.host, port: https.port),
            socks: ProxyEndpointState(enabled: socks.enabled, host: socks.host, port: socks.port),
            pacEnabled: pac.enabled,
            pacURL: pac.url,
            autoDiscoveryEnabled: parseAutoDiscoveryOutput(autoDiscoveryOutput),
            bypassDomains: ProxyBypassDomainOutput.parse(bypassOutput)
        )
    }

    /// Publishes the backup with its permissions already in place, so a reported failure always
    /// means the previous record is still the one on disk.
    private static func write(_ backup: DirectProxyBackup, to backupURL: URL) throws {
        try ProxyBackupFilePublication.publish(PropertyListEncoder().encode(backup), to: backupURL)
    }

    private static func loadBackup(from backupURL: URL) -> DirectProxyBackup? {
        do {
            let data = try Data(contentsOf: backupURL)
            return try PropertyListDecoder().decode(DirectProxyBackup.self, from: data)
        } catch {
            logger.error("Direct proxy watchdog could not load backup: \(error.localizedDescription)")
            return nil
        }
    }

    /// An unreadable record is retained and retried. A readable record owned by a newer session
    /// ends this watcher, while a missing record means another recovery already completed.
    private static func backupStillBelongsToWatchdog(
        at backupURL: URL,
        parentPID: Int32,
        parentStartSignature: String
    )
        -> Bool
    {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            return false
        }
        guard let backup = loadBackup(from: backupURL) else {
            return true
        }
        return DirectProxyBackupOwnerPolicy.belongsToSession(
            backup,
            processIdentifier: parentPID,
            processStartSignature: parentStartSignature
        )
    }

    /// The backed-up services that still carry Rockxy's override on the persisted port.
    private static func residualOwnedServices(in backup: DirectProxyBackup) -> [String] {
        let services = backup.services.map(\.service)
        let liveStates = currentRestorationStates(for: services)
        guard liveStates.count == services.count else {
            // A transient read failure cannot prove an override disappeared. Keep all candidates
            // so the recovery planner defers unreadable services without dropping their backup.
            return services
        }
        return ProxyOverrideOwnership.residualOwnedServices(
            in: services.compactMap { liveStates[$0]?.overrideState },
            port: backup.rockxyPort
        )
    }

    /// A service whose settings cannot be read reports as not overridden, which keeps recovery
    /// from claiming ownership it cannot prove.
    private static func currentOverrideState(for service: String) -> ProxyServiceOverrideState {
        readRestorationState(for: service)?.overrideState
            ?? ProxyServiceOverrideState(
                service: service,
                httpEnabled: false,
                httpHost: "",
                httpPort: 0,
                httpsEnabled: false,
                httpsHost: "",
                httpsPort: 0
            )
    }

    private static func restoreProxyState(for service: String, snapshot: DirectProxySnapshot) throws {
        try runNetworkSetup(["-setwebproxystate", service, "off"])
        try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
        try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        try runNetworkSetup(["-setautoproxystate", service, "off"])
        try runNetworkSetup(["-setproxyautodiscovery", service, "off"])

        if !snapshot.httpHost.isEmpty, snapshot.httpPort > 0 {
            try runNetworkSetup(["-setwebproxy", service, snapshot.httpHost, String(snapshot.httpPort)])
            try runNetworkSetup(["-setwebproxystate", service, snapshot.httpEnabled ? "on" : "off"])
        }

        if !snapshot.httpsHost.isEmpty, snapshot.httpsPort > 0 {
            try runNetworkSetup(["-setsecurewebproxy", service, snapshot.httpsHost, String(snapshot.httpsPort)])
            try runNetworkSetup(["-setsecurewebproxystate", service, snapshot.httpsEnabled ? "on" : "off"])
        }

        if !snapshot.socksHost.isEmpty, snapshot.socksPort > 0 {
            try runNetworkSetup(["-setsocksfirewallproxy", service, snapshot.socksHost, String(snapshot.socksPort)])
            try runNetworkSetup(["-setsocksfirewallproxystate", service, snapshot.socksEnabled ? "on" : "off"])
        }

        if snapshot.pacEnabled {
            if !snapshot.pacURL.isEmpty {
                try runNetworkSetup(["-setautoproxyurl", service, snapshot.pacURL])
            }
            try runNetworkSetup(["-setautoproxystate", service, "on"])
        }

        if snapshot.autoDiscoveryEnabled {
            try runNetworkSetup(["-setproxyautodiscovery", service, "on"])
        }
    }

    private static func restoreBypassDomains(for service: String, domains: [String]) throws {
        if domains.isEmpty {
            try runNetworkSetup(["-setproxybypassdomains", service, "Empty"])
        } else {
            try runNetworkSetup(["-setproxybypassdomains", service] + domains)
        }
    }

    private static func parseProxyOutput(_ output: String) -> (enabled: Bool, host: String, port: Int) {
        var enabled = false
        var host = ""
        var port = 0

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                let value = trimmed.replacingOccurrences(of: "Enabled:", with: "").trimmingCharacters(in: .whitespaces)
                enabled = value.lowercased() == "yes"
            } else if trimmed.hasPrefix("Server:") {
                host = trimmed.replacingOccurrences(of: "Server:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Port:") {
                let value = trimmed.replacingOccurrences(of: "Port:", with: "").trimmingCharacters(in: .whitespaces)
                port = Int(value) ?? 0
            }
        }

        return (enabled, host, port)
    }

    private static func parsePACOutput(_ output: String) -> (enabled: Bool, url: String) {
        var enabled = false
        var url = ""
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                enabled = trimmed.replacingOccurrences(of: "Enabled:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased() == "yes"
            } else if trimmed.hasPrefix("URL:") {
                let value = trimmed.replacingOccurrences(of: "URL:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if value != "(null)" {
                    url = value
                }
            }
        }
        return (enabled, url)
    }

    private static func parseAutoDiscoveryOutput(_ output: String) -> Bool {
        output.components(separatedBy: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Auto Proxy Discovery:") else {
                return false
            }
            return trimmed.replacingOccurrences(of: "Auto Proxy Discovery:", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased() == "on"
        }
    }

    @discardableResult
    private static func runNetworkSetup(_ arguments: [String]) throws -> String {
        guard BinaryValidator.validateAppleSignedBinary(at: networkSetupPath) else {
            throw NSError(domain: "DirectProxyWatchdog", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "networksetup binary failed Apple code signature validation",
            ])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: networkSetupPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let output = stderr.isEmpty ? stdout : stderr
            throw NSError(domain: "DirectProxyWatchdog", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "networksetup \(arguments.joined(separator: " ")) failed: \(output)",
            ])
        }

        return stdout
    }

    /// Whether the watched parent is still the exact process this watchdog was armed for. A
    /// reused identifier answers false, which is what makes the stranded override get restored
    /// instead of waited on forever.
    private static func parentSessionIsLive(pid: Int32, startSignature: String) -> Bool {
        let processIsAlive = ProcessStartIdentity.isAlive(pid)
        return ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: pid,
            recordedStartSignature: startSignature,
            processIsAlive: processIsAlive,
            liveStartSignature: processIsAlive ? ProcessStartIdentity.startSignature(for: pid) : nil
        )
    }
}

if DirectProxyWatchdog.run(arguments: ProcessInfo.processInfo.arguments) {
    Foundation.exit(0)
}

logger.info("RockxyHelperTool starting up")

// Check for stale proxy settings from a previous crash. A session whose owner is still alive
// and still validates keeps its override, and its watchdog is re-armed before this helper takes
// any new work, so a later owner death still restores the user's settings.
switch HelperService.performStartupRecovery() {
case let .preserved(owner):
    if let owner {
        HelperService.resumeOwnerWatchdog(
            for: owner.processIdentifier,
            startSignature: owner.startSignature,
            userID: owner.userID
        )
    }
case .restoreIncomplete:
    HelperService.scheduleBackupRecovery(reason: "helper startup")
case .noBackup, .cleared, .restored:
    break
}

let delegate = HelperDelegate()
let machServiceName = identity.helperMachServiceName
let listener = NSXPCListener(machServiceName: machServiceName)
listener.delegate = delegate
listener.resume()

logger.info("RockxyHelperTool listening on Mach service \(machServiceName)")

IdleExitMonitor.start()

RunLoop.current.run()
