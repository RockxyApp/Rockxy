import Foundation
import os

// swiftlint:disable file_length
// Applies and restores macOS network proxy settings on behalf of the helper tool.

// MARK: - ProxyConfigurator

/// Configures macOS system proxy settings by running `/usr/sbin/networksetup` as root.
/// The helper tool runs as a launch daemon with root privileges, so no password prompts are needed.
enum ProxyConfigurator {
    // MARK: Internal

    // MARK: - Proxy Output Parsing

    struct ProxyInfo {
        var enabled: Bool = false
        var host: String = ""
        var port: Int = 0
    }

    struct PACInfo {
        var enabled: Bool = false
        var url: String = ""
    }

    // MARK: - Public API

    /// Override system HTTP and HTTPS proxy to 127.0.0.1 on the given port.
    /// Saves current settings via CrashRecovery before making changes.
    ///
    /// `ownerStartSignature` is the kernel start identity of the app process taking the override,
    /// acquired by the caller before this point. It is required rather than looked up here: an
    /// override that cannot name the exact process it belongs to would leave a watchdog with
    /// nothing but a recyclable identifier to decide by.
    static func overrideProxy(
        port: Int,
        ownerPID: Int32,
        ownerStartSignature: String,
        ownerUID: uid_t
    )
        throws
    {
        settleOwedApply()
        let services = try detectAllEnabledServices()
        guard !services.isEmpty else {
            throw ProxyConfiguratorError.noActiveService
        }

        // Existing service snapshots are preserved, while newly enabled services are added
        // before they are mutated so every touched route has an exact restore point.
        let hadBackupBefore = CrashRecovery.hasBackup()
        // The services that already had a restore point. Only their entries may outlive a failed
        // attempt: an entry this attempt captures for a service it never touches describes
        // settings nobody overrode, and keeping it is how a later override comes to replay a
        // stale snapshot over a newer user setting.
        let preAttemptServices = try Set(CrashRecovery.loadBackup()?.services.map(\.service) ?? [])
        var backup = try CrashRecovery.saveOriginalSettings(
            services: services,
            rockxyPort: port,
            ownerPID: ownerPID,
            ownerStartSignature: ownerStartSignature,
            ownerUID: ownerUID
        )

        logger.info("Setting system proxy to 127.0.0.1:\(port) for \(services.count) service(s)")

        var configuredServices: [String] = []
        var partiallyAppliedServices: [String] = []
        var skippedServices: [String] = []

        for service in services {
            guard let serviceBackup = backup.services.first(where: { $0.service == service }) else {
                // No restore point exists for this service, so nothing may be written to it.
                logger.warning("Skipping proxy for '\(service)' — it has no captured restore point")
                continue
            }

            let captured = restorationTarget(for: serviceBackup)
            // The capture this backup holds was taken earlier — moments ago for a service just
            // added, a whole session ago for one being reclaimed. What the override is about to
            // start from is a fact about the machine now, so the settings are re-read here, in
            // full, and compared against what this machine can actually prove about them.
            guard case let .apply(baseline) = ProxyOverrideApplicationPreflight.decision(
                captured: captured,
                live: readRestorationState(for: service),
                priorEntry: backup.journal.first { $0.service == service },
                port: port
            ) else {
                logger
                    .warning(
                        "Skipping proxy for '\(service)' — its live settings are neither the ones captured for it nor any this machine wrote"
                    )
                skippedServices.append(service)
                continue
            }

            do {
                // Only this service's record changes, and it changes immediately before this
                // service's first command. Every other record is left exactly where it is: the
                // backup can already be mid-recovery, or already carry an override this attempt is
                // reclaiming, and those records are the only thing that says which live states may
                // still be written. A record that cannot be stored stops the sequence, because a
                // command nothing on disk accounts for is what a later relaunch cannot reason
                // about.
                backup = try CrashRecovery.recordOverrideApplication(
                    backup,
                    journal: advancedApplication(
                        backup.journal,
                        service: service,
                        captured: captured,
                        baseline: baseline,
                        to: .applying,
                        port: port
                    )
                )
                guard readRestorationState(for: service) == baseline else {
                    throw ProxyConfiguratorError.executionFailed(
                        command: "proxy preflight",
                        reason: "The live settings changed while the recovery record was being committed"
                    )
                }
                try applyOverride(service: service, port: port, baseline: baseline)
                configuredServices.append(service)
                logger.info("Proxy set on '\(service)' → 127.0.0.1:\(port)")
            } catch {
                // A sequence that stopped part-way leaves a shape that is neither Rockxy's nor
                // the user's, so the attempt stops here and puts back what it touched. A service
                // that still reads exactly as captured was never written and simply drops out.
                guard ProxyOverrideApplicationPolicy.serviceIsUntouched(
                    live: readRestorationState(for: service),
                    captured: baseline
                ) else {
                    partiallyAppliedServices.append(service)
                    logger
                        .error(
                            "Proxy override on '\(service)' stopped part-way: \(error.localizedDescription)"
                        )
                    break
                }
                logger.debug("Skipping proxy for '\(service)': \(error.localizedDescription)")
            }
        }

        let touchedServices = configuredServices + partiallyAppliedServices
        guard partiallyAppliedServices.isEmpty, !configuredServices.isEmpty else {
            try failOverride(
                backup: backup,
                touchedServices: touchedServices,
                partiallyAppliedServices: partiallyAppliedServices,
                configuredServices: configuredServices,
                port: port,
                preAttemptServices: preAttemptServices,
                clearsBackup: !hadBackupBefore
            )
            return
        }

        // An entry this attempt captured for a service it then skipped describes settings nobody
        // overrode. Keeping it would hand the next override a snapshot older than whatever the user
        // has set in the meantime. Entries that predate this attempt are left alone: they belong to
        // services an earlier session may still be overriding.
        let untouchedCapturedServices = skippedServices.filter { !preAttemptServices.contains($0) }
        do {
            try CrashRecovery.dropUntouchedCapturedServices(backup, services: untouchedCapturedServices)
        } catch {
            // A spare restore point costs a deferred service; a missing one costs the settings.
            logger
                .error(
                    "Could not drop the freshly captured entries for skipped services: \(error.localizedDescription)"
                )
        }

        logger.info("System proxy override complete on \(configuredServices.count) service(s)")
    }

    /// Restore proxy settings from backup. Logs errors but does not throw.
    static func restoreProxy() {
        do {
            try restoreProxyOrThrow()
        } catch {
            logger.error("Failed to restore proxy: \(error.localizedDescription)")
        }
    }

    /// Restore proxy settings from CrashRecovery backup. Throws on failure.
    static func restoreProxyOrThrow() throws {
        guard settleOwedApply() != .stillOwed else {
            throw ProxyConfiguratorError.executionFailed(
                command: "apply proxy settings",
                reason: "Committed proxy settings could not be applied"
            )
        }
        guard let sourceBackup = try CrashRecovery.loadBackup() else {
            logger.info("No proxy backup exists, so there is no owned proxy state to restore")
            return
        }
        let backedUpServices = sourceBackup.services.map(\.service)
        // Only a backup written before the port was recorded needs the live settings to say which
        // port it was overriding. Reading every service to compute a value the recorded port
        // makes unused was a quarter of a Stop's reads.
        let ownedPort = sourceBackup.rockxyPort ?? ProxyOverrideOwnership.inferredOwnedPort(
            in: overrideStatesPreferringSystemConfiguration(for: backedUpServices)
        )

        try failIfUnresolved(
            runJournaledRestore(
                backup: sourceBackup,
                candidateServices: backedUpServices,
                port: ownedPort
            ),
            command: "restore proxy"
        )
    }

    /// Restores only the backed-up services that still carry Rockxy's override, leaving any
    /// service the user (or another tool) has since re-pointed exactly as it is.
    ///
    /// The backup is narrowed to those services *before* the first setting is written, so a
    /// retry after a partial failure can never replay stale settings onto a service that is no
    /// longer Rockxy's. If that reduced backup cannot be persisted, the original backup stays
    /// on disk and nothing is mutated — losing the restore point is worse than a stranded
    /// override that can still be recovered later.
    static func restoreOwnedServicesOrThrow(ownedServices: [String], port: Int?) throws {
        settleOwedApply()
        guard let backup = try CrashRecovery.loadBackup() else {
            logger.info("No proxy backup exists, so there is no owned proxy state to restore")
            return
        }

        try failIfUnresolved(
            runJournaledRestore(
                backup: backup,
                candidateServices: ownedServices,
                port: backup.rockxyPort ?? port
            ),
            command: "restore owned proxy services"
        )
    }

    /// Reads the ownership-relevant proxy fields for each service. Services that cannot be read
    /// report as not overridden, which keeps recovery from claiming ownership it cannot prove.
    static func currentOverrideStates(for services: [String]) -> [ProxyServiceOverrideState] {
        services.map { service in
            readRestorationState(for: service)?.overrideState
                ?? ProxyServiceOverrideState.unreadable(service: service)
        }
    }

    /// Reads the full restoration-relevant shape of each service, keyed by service name.
    ///
    /// A service whose settings cannot be read is left out rather than reported as empty: an
    /// unreadable service is not a changed one, and guessing either way would decide whether
    /// recovery writes over it.
    static func currentRestorationStates(for services: [String]) -> [String: ProxyServiceRestorationState] {
        var states: [String: ProxyServiceRestorationState] = [:]
        for service in services {
            states[service] = readRestorationState(for: service)
        }
        return states
    }

    /// Set bypass domains on all enabled network services.
    /// Pass an empty array to clear the bypass list (uses "Empty" per macOS convention).
    static func setBypassDomains(_ domains: [String], services: [String]) throws {
        settleOwedApply()
        guard !services.isEmpty else {
            throw ProxyConfiguratorError.noActiveService
        }

        let indomains = domains.filter { domain in
            !ProxyBypassDomainValidator.isValid(domain)
        }
        if !indomains.isEmpty {
            logger.warning("SECURITY: Rejected \(indomains.count) invalid bypass domain(s): \(indomains)")
            throw ProxyConfiguratorError.executionFailed(
                command: "-setproxybypassdomains",
                reason: "Invalid bypass domains: \(indomains.joined(separator: ", "))"
            )
        }

        guard var backup = try CrashRecovery.loadBackup() else {
            throw ProxyConfiguratorError.noOwnedProxySession
        }
        var failedServices: [String] = []
        for service in services {
            guard let entry = backup.journal.first(where: { $0.service == service }) else {
                failedServices.append(service)
                continue
            }

            let live = readRestorationState(for: service)
            switch ProxyBypassUpdatePreflight.decision(
                entry: entry,
                live: live,
                ownedPort: backup.rockxyPort,
                requestedDomains: domains
            ) {
            case .abort:
                failedServices.append(service)
                continue
            case .unchanged:
                if entry.previousAppliedBypassDomains != nil {
                    do {
                        backup = try CrashRecovery.recordOverrideApplication(
                            backup,
                            journal: replacing(
                                backup.journal,
                                entry: entry.completingAppliedBypassUpdate(at: domains)
                            )
                        )
                    } catch {
                        failedServices.append(service)
                    }
                }
                continue
            case let .apply(baseline):
                do {
                    let pendingEntry = entry.recordingAppliedBypassDomains(
                        domains,
                        from: baseline.bypassDomains
                    )
                    backup = try CrashRecovery.recordOverrideApplication(
                        backup,
                        journal: replacing(backup.journal, entry: pendingEntry)
                    )

                    // The durable transition was published after the first read. Re-check the
                    // complete state now so a change during publication is never overwritten.
                    guard readRestorationState(for: service) == baseline else {
                        failedServices.append(service)
                        continue
                    }

                    try writeBypassDomains(service: service, domains: domains, baseline: baseline)

                    backup = try CrashRecovery.recordOverrideApplication(
                        backup,
                        journal: replacing(
                            backup.journal,
                            entry: pendingEntry.completingAppliedBypassUpdate(at: domains)
                        )
                    )
                    logger.debug("Set bypass domains on '\(service)': \(domains)")
                } catch {
                    failedServices.append(service)
                    logger.debug("Failed to set bypass domains for '\(service)': \(error.localizedDescription)")
                }
            }
        }

        guard failedServices.isEmpty else {
            throw ProxyConfiguratorError.executionFailed(
                command: "-setproxybypassdomains",
                reason: "Failed to update bypass domains on: \(failedServices.joined(separator: ", "))"
            )
        }

        logger.info("Bypass domains updated on \(services.count) service(s)")
    }

    /// Restore original bypass domains for a specific service.
    static func restoreBypassDomains(service: String, domains: [String]) throws {
        if domains.isEmpty {
            try runNetworkSetup(["-setproxybypassdomains", service, "Empty"])
        } else {
            let args = ["-setproxybypassdomains", service] + domains
            try runNetworkSetup(args)
        }
        logger.info("Restored original bypass domains for '\(service)'")
    }

    /// Returns whether the proxy is currently overridden by Rockxy and the active port.
    static func getCurrentStatus() -> (isOverridden: Bool, port: Int) {
        settleOwedApply()
        guard let services = try? detectAllEnabledServices(), !services.isEmpty else {
            return (false, 0)
        }
        guard let backup = try? CrashRecovery.loadBackup() else {
            return (false, 0)
        }

        let servicesToCheck = detectPrimaryService(from: services).map { [$0] } ?? services
        var matchedPort: Int?
        for service in servicesToCheck {
            guard let httpOutput = try? runNetworkSetup(["-getwebproxy", service]),
                  let httpsOutput = try? runNetworkSetup(["-getsecurewebproxy", service]),
                  let socksOutput = try? runNetworkSetup(["-getsocksfirewallproxy", service]),
                  let pacOutput = try? runNetworkSetup(["-getautoproxyurl", service]),
                  let autoDiscoveryOutput = try? runNetworkSetup(["-getproxyautodiscovery", service]),
                  let bypassOutput = try? runNetworkSetup(["-getproxybypassdomains", service]) else
            {
                return (false, 0)
            }

            let http = parseProxyOutput(httpOutput)
            let https = parseProxyOutput(httpsOutput)
            let socks = parseProxyOutput(socksOutput)
            let pac = parsePACOutput(pacOutput)
            let hasGlobalBypass = bypassOutput.components(separatedBy: "\n").contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == "*"
            }
            guard http.enabled,
                  http.host == "127.0.0.1",
                  https.enabled,
                  https.host == "127.0.0.1",
                  http.port == https.port,
                  !socks.enabled,
                  !pac.enabled,
                  !parseAutoDiscoveryOutput(autoDiscoveryOutput),
                  !hasGlobalBypass else
            {
                return (false, 0)
            }
            if let matchedPort, matchedPort != http.port {
                return (false, 0)
            }
            if let rockxyPort = backup.rockxyPort, rockxyPort != http.port {
                return (false, 0)
            }
            matchedPort = http.port
        }

        return matchedPort.map { (true, $0) } ?? (false, 0)
    }

    static func parseProxyOutput(_ output: String) -> ProxyInfo {
        var info = ProxyInfo()
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                let value = trimmed.replacingOccurrences(of: "Enabled:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                info.enabled = value.lowercased() == "yes"
            } else if trimmed.hasPrefix("Server:") {
                info.host = trimmed.replacingOccurrences(of: "Server:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Port:") {
                let portStr = trimmed.replacingOccurrences(of: "Port:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                info.port = Int(portStr) ?? 0
            }
        }
        return info
    }

    static func parsePACOutput(_ output: String) -> PACInfo {
        var info = PACInfo()
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                let value = trimmed.replacingOccurrences(of: "Enabled:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                info.enabled = value.lowercased() == "yes"
            } else if trimmed.hasPrefix("URL:") {
                let value = trimmed.replacingOccurrences(of: "URL:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if value != "(null)" {
                    info.url = value
                }
            }
        }
        return info
    }

    static func parseAutoDiscoveryOutput(_ output: String) -> Bool {
        output.components(separatedBy: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Auto Proxy Discovery:") else {
                return false
            }
            let value = trimmed.replacingOccurrences(of: "Auto Proxy Discovery:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return value.lowercased() == "on"
        }
    }

    // MARK: Private

    /// What a running restore has decided so far: the journal as it stands, the services the
    /// backup on disk still holds a restore point for, and how each attempted service turned out.
    private struct JournaledRestoreState {
        var journal: [ProxyServiceRecoveryJournalEntry]
        var retention: ProxyBackupRetention
        var deferredServices: [String]
        var attemptedServices: [String] = []
        var failedServices: Set<String> = []
    }

    /// Re-checks one service against its record immediately before its first command, and acts on
    /// the answer without writing a single setting.
    ///
    /// A service that changed since the plan was made leaves recovery here, and it leaves
    /// durably: its entry is removed from the backup on disk before the loop moves on, so a
    /// process that dies straight afterwards cannot come back and write over the change. A
    /// service that has simply become unreadable keeps its restore point and its recorded stage.
    private static func preflightAllowsRestore(
        entry: ProxyServiceRecoveryJournalEntry,
        state: inout JournaledRestoreState,
        backup: inout CrashRecovery.ProxyBackup,
        port: Int?
    )
        -> Bool
    {
        switch ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: liveStateForRestore(of: entry)
        ) {
        case .restore:
            return true
        case .complete,
             .abandon:
            logger
                .warning(
                    "Dropping '\(entry.service)' from this restore — its proxy settings are no longer the ones this recovery planned for"
                )
            state.retention.drop(entry.service)
            state.journal.removeAll { $0.service == entry.service }
        case .retryLater:
            logger
                .warning("Deferring '\(entry.service)' — its proxy settings could not be read before restoring")
            state.deferredServices.append(entry.service)
            state.journal = advanced(state.journal, service: entry.service, to: entry.stage)
        }

        do {
            backup = try CrashRecovery.reduceBackup(
                backup,
                to: state.retention.services,
                rockxyPort: port,
                journal: state.journal
            )
        } catch {
            logger.error("Could not update the retained proxy backup: \(error.localizedDescription)")
        }
        return false
    }

    /// Clears the backup when no service still needs one, or narrows it to exactly the services
    /// that do — the ones this attempt could not resolve, plus the ones it was never authorized
    /// to touch and that already had a restore point before it began. Reports back which of the
    /// authorized services are still unresolved.
    ///
    /// What survives the attempt is not the same set that survived inside it. Every preserved
    /// entry was kept for the whole run so no untouched service could lose its restore point
    /// mid-flight, but an entry this very attempt captured for a service it then never touched
    /// describes settings nobody overrode — and leaving it behind is how a later override comes
    /// to write a stale snapshot over a newer user setting.
    @discardableResult
    private static func finishRestore(
        backup: CrashRecovery.ProxyBackup,
        unresolvedServices: [String],
        retention: ProxyBackupRetention,
        journal: [ProxyServiceRecoveryJournalEntry],
        port: Int?,
        recoveryPending: Bool
    )
        -> [String]
    {
        let retainedServices = retention.retainedAfterAttempt(unresolvedServices: unresolvedServices)
        guard !retainedServices.isEmpty else {
            CrashRecovery.clearBackup()
            logger.info("Proxy settings restored successfully")
            return unresolvedServices
        }

        // Keep exactly the services that still need recovery so a retry has a restore point
        // for them and only them.
        do {
            try CrashRecovery.reduceBackup(
                backup,
                to: retainedServices,
                rockxyPort: port,
                journal: journal,
                recoveryPending: recoveryPending
            )
        } catch {
            logger.error("Could not narrow the retained proxy backup: \(error.localizedDescription)")
        }
        return unresolvedServices
    }

    /// Turns an unresolved-service list into the failure the restore APIs report.
    private static func failIfUnresolved(_ services: [String], command: String) throws {
        guard !services.isEmpty else {
            return
        }
        throw ProxyConfiguratorError.executionFailed(
            command: command,
            reason: "\(services.count) network service(s) could not be restored; the recovery backup was preserved"
        )
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

    /// The captured pre-Rockxy settings for one service, in the shape recovery compares against.
    private static func restorationTarget(
        for serviceBackup: CrashRecovery.ServiceProxyBackup
    )
        -> ProxyServiceRestorationState
    {
        ProxyServiceRestorationState(
            service: serviceBackup.service,
            http: ProxyEndpointState(
                enabled: serviceBackup.httpEnabled,
                host: serviceBackup.httpHost,
                port: serviceBackup.httpPort
            ),
            https: ProxyEndpointState(
                enabled: serviceBackup.httpsEnabled,
                host: serviceBackup.httpsHost,
                port: serviceBackup.httpsPort
            ),
            socks: ProxyEndpointState(
                enabled: serviceBackup.socksEnabled,
                host: serviceBackup.socksHost,
                port: serviceBackup.socksPort
            ),
            pacEnabled: serviceBackup.pacEnabled,
            pacURL: serviceBackup.pacURL,
            autoDiscoveryEnabled: serviceBackup.autoDiscoveryEnabled,
            bypassDomains: serviceBackup.bypassDomains
        )
    }

    // Two readers, one rule. `networksetup` is the authoritative reader: every answer that is not
    // "this restore may proceed" is given on it. SystemConfiguration is the fast one: it reads
    // the same preferences file in one session instead of six processes per service (about 45 ms
    // each on a working helper, 120 of them in a four-service Stop), and it may only confirm that
    // a restore can proceed, which the write then checks again under the preferences lock. A
    // service the fast reader cannot read is simply absent from its answer.

    /// The fast reading of every named service from one preferences session. A service that
    /// could not be read, or whose stored settings are not in a shape the reader accepts, is
    /// missing from the result.
    private static func systemConfigurationStates(
        for services: [String]
    )
        -> [String: ProxyServiceRestorationState]
    {
        guard let stored = ProxySystemConfigurationWriter.storedConfigurations(for: services) else {
            return [:]
        }
        return ProxyFastRead.states(from: stored)
    }

    /// The state one journaled service is judged by: the fast reading when it lets the restore
    /// proceed, the `networksetup` reading otherwise.
    private static func liveStateForRestore(
        of entry: ProxyServiceRecoveryJournalEntry
    )
        -> ProxyServiceRestorationState?
    {
        ProxyFastRead.liveState(
            for: entry,
            fast: { systemConfigurationStates(for: [entry.service])[entry.service] },
            authoritative: { readRestorationState(for: entry.service) }
        )
    }

    /// Ownership-relevant state of each service for the residual check and the port inference:
    /// from one fast session, with `networksetup` for any service that session could not read.
    /// An unreadable service still reports as not overridden, as `currentOverrideStates` does.
    private static func overrideStatesPreferringSystemConfiguration(
        for services: [String]
    )
        -> [ProxyServiceOverrideState]
    {
        let fast = systemConfigurationStates(for: services)
        return services.map { service in
            (fast[service] ?? readRestorationState(for: service))?.overrideState
                ?? ProxyServiceOverrideState.unreadable(service: service)
        }
    }

    /// Reads every proxy field of one service. Any read that fails makes the whole state nil:
    /// a partially read service cannot be compared against a journal without inventing values
    /// for the fields that were not read.
    private static func readRestorationState(for service: String) -> ProxyServiceRestorationState? {
        guard let httpOutput = try? runNetworkSetup(["-getwebproxy", service]),
              let httpsOutput = try? runNetworkSetup(["-getsecurewebproxy", service]),
              let socksOutput = try? runNetworkSetup(["-getsocksfirewallproxy", service]),
              let pacOutput = try? runNetworkSetup(["-getautoproxyurl", service]),
              let autoDiscoveryOutput = try? runNetworkSetup(["-getproxyautodiscovery", service]),
              let bypassOutput = try? runNetworkSetup(["-getproxybypassdomains", service]) else
        {
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

    /// Puts back every service a failed override attempt touched, then reports the failure.
    ///
    /// The backup stays on disk for the whole rollback, so a helper that dies half-way through it
    /// still leaves the restore points behind. It is cleared only when this attempt created it
    /// and every touched service is provably back: an earlier session's backup is never removed
    /// by a later session's failure.
    private static func failOverride(
        backup: CrashRecovery.ProxyBackup,
        touchedServices: [String],
        partiallyAppliedServices: [String],
        configuredServices: [String],
        port: Int,
        preAttemptServices: Set<String>,
        clearsBackup: Bool
    )
        throws
    {
        let unresolvedServices = rollBackOverride(
            touchedServices,
            backup: backup,
            port: port,
            preAttemptServices: preAttemptServices
        )

        switch ProxyOverrideApplicationPolicy.outcome(
            configuredServices: configuredServices,
            partiallyAppliedServices: partiallyAppliedServices,
            unresolvedServices: unresolvedServices
        ) {
        case .applied:
            return
        case .rolledBack:
            if clearsBackup {
                CrashRecovery.clearBackup()
            }
            throw ProxyConfiguratorError.executionFailed(
                command: "setwebproxy (all services)",
                reason: touchedServices.isEmpty
                    ? "Failed to configure proxy on any network service"
                    : "The proxy override was rolled back after it could not be applied to every network service"
            )
        case .rollbackIncomplete:
            logger
                .error(
                    "Proxy override rollback incomplete on \(unresolvedServices.count) service(s) — preserving the recovery backup"
                )
            throw ProxyConfiguratorError.overrideRollbackIncomplete(services: unresolvedServices)
        }
    }

    /// Writes the captured settings back onto the services an override attempt touched, and
    /// reports the ones that are still not back where they started.
    ///
    /// This runs through the same journaled machinery a crash recovery uses, for the same reason:
    /// each service records its intent before its first rollback command and its completion after
    /// the last, so a helper that dies part-way through leaves a record the next attempt can
    /// read. Running the commands raw would leave a half-restored service behind with nothing on
    /// disk saying a write had started, which is precisely the state startup recovery cannot
    /// reason about.
    ///
    /// Being touched is not on its own a licence to write. A service is recorded as touched
    /// before its first command runs, so each one has to show that its live settings really are a
    /// state the override sequence passes through; a command that mutated nothing, and a change
    /// somebody else made in the meantime, are both left exactly as they are. Backup entries for
    /// services this attempt never touched stay on disk throughout.
    private static func rollBackOverride(
        _ services: [String],
        backup: CrashRecovery.ProxyBackup,
        port: Int,
        preAttemptServices: Set<String>
    )
        -> [String]
    {
        let untouchedServices = backup.services.map(\.service).filter { !services.contains($0) }
        guard !services.isEmpty else {
            // Nothing was written, so nothing needs undoing — but this attempt may have captured
            // entries for services it never reached, and those describe settings nobody
            // overrode. Narrowing to what predates the attempt is what keeps a later override
            // from replaying them over a newer user setting.
            return finishRestore(
                backup: backup,
                unresolvedServices: [],
                retention: ProxyBackupRetention(
                    authorized: [],
                    preserved: untouchedServices,
                    preAttemptServices: preAttemptServices
                ),
                journal: backup.journal,
                port: port,
                recoveryPending: backup.recoveryPending
            )
        }

        logger.warning("Rolling back the proxy override on \(services.count) touched service(s)")
        return runJournaledRestore(
            backup: backup,
            candidateServices: services,
            port: port,
            locallyMutatedServices: Set(services),
            preservedServices: untouchedServices,
            preAttemptServices: preAttemptServices
        )
    }

    /// Replaces one service's override record, leaving every other service's record alone.
    private static func advancedApplication(
        _ journal: [ProxyServiceRecoveryJournalEntry],
        service: String,
        captured: ProxyServiceRestorationState,
        baseline: ProxyServiceRestorationState,
        to stage: ProxyRecoveryStage,
        port: Int
    )
        -> [ProxyServiceRecoveryJournalEntry]
    {
        journal.filter { $0.service != service } + [
            ProxyServiceRecoveryJournalEntry(
                overrideApplicationFor: captured,
                baseline: baseline,
                stage: stage,
                port: port
            ),
        ]
    }

    private static func replacing(
        _ journal: [ProxyServiceRecoveryJournalEntry],
        entry: ProxyServiceRecoveryJournalEntry
    )
        -> [ProxyServiceRecoveryJournalEntry]
    {
        journal.filter { $0.service != entry.service } + [entry]
    }

    /// Turns every proxy mode off for one service before its snapshot is written back, so a
    /// mode the snapshot does not mention cannot survive the restore.
    private static func disableProxyStates(for service: String) throws {
        try runNetworkSetup(["-setwebproxystate", service, "off"])
        try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
        try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        try runNetworkSetup(["-setautoproxystate", service, "off"])
        try runNetworkSetup(["-setproxyautodiscovery", service, "off"])
    }

    /// Writes one service's captured pre-Rockxy proxy configuration back verbatim, apart from the
    /// bypass list — that is written separately, and only once every proxy-state command has
    /// returned.
    private static func applyServiceProxyState(_ serviceBackup: CrashRecovery.ServiceProxyBackup) throws {
        let service = serviceBackup.service

        if !serviceBackup.httpHost.isEmpty, serviceBackup.httpPort > 0 {
            try runNetworkSetup([
                "-setwebproxy", service, serviceBackup.httpHost,
                String(serviceBackup.httpPort),
            ])
            try runNetworkSetup([
                "-setwebproxystate", service, serviceBackup.httpEnabled ? "on" : "off",
            ])
        }

        if !serviceBackup.httpsHost.isEmpty, serviceBackup.httpsPort > 0 {
            try runNetworkSetup([
                "-setsecurewebproxy", service, serviceBackup.httpsHost,
                String(serviceBackup.httpsPort),
            ])
            try runNetworkSetup([
                "-setsecurewebproxystate", service, serviceBackup.httpsEnabled ? "on" : "off",
            ])
        }

        if !serviceBackup.socksHost.isEmpty, serviceBackup.socksPort > 0 {
            try runNetworkSetup([
                "-setsocksfirewallproxy", service, serviceBackup.socksHost,
                String(serviceBackup.socksPort),
            ])
            try runNetworkSetup([
                "-setsocksfirewallproxystate", service, serviceBackup.socksEnabled ? "on" : "off",
            ])
        }

        if serviceBackup.pacEnabled {
            if !serviceBackup.pacURL.isEmpty {
                try runNetworkSetup(["-setautoproxyurl", service, serviceBackup.pacURL])
            }
            try runNetworkSetup(["-setautoproxystate", service, "on"])
        }

        if serviceBackup.autoDiscoveryEnabled {
            try runNetworkSetup(["-setproxyautodiscovery", service, "on"])
        }
    }

    private static func validateBinary(_ path: String) throws {
        guard BinaryValidator.validateAppleSignedBinary(at: path) else {
            throw ProxyConfiguratorError.executionFailed(
                command: path,
                reason: "Binary failed Apple code signature validation"
            )
        }
    }

    // MARK: - Network Service Detection

    /// Determines which enabled service is the actual primary by mapping the default
    /// route interface (from `route -n get 0.0.0.0`) to a service name via
    /// `networksetup -listnetworkserviceorder`. Falls back to nil if detection fails.
    private static func detectPrimaryService(from services: [String]) -> String? {
        guard let iface = detectPrimaryInterface() else {
            return nil
        }
        guard let orderOutput = try? runNetworkSetup(["-listnetworkserviceorder"]) else {
            return nil
        }

        var lastService: String?
        for line in orderOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let openParen = trimmed.firstIndex(of: "("),
               let closeParen = trimmed.firstIndex(of: ")"),
               openParen == trimmed.startIndex
            {
                let afterParen = trimmed.index(after: closeParen)
                let name = String(trimmed[afterParen...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    lastService = name
                }
            } else if trimmed.hasPrefix("(Hardware Port:"), let service = lastService {
                if let deviceRange = trimmed.range(of: "Device: ") {
                    let device = String(trimmed[deviceRange.upperBound...].prefix(while: { $0 != ")" }))
                    if device == iface, services.contains(service) {
                        logger.info("Primary service detected: '\(service)' (interface: \(iface))")
                        return service
                    }
                }
            }
        }

        return nil
    }

    private static func detectPrimaryInterface() -> String? {
        guard BinaryValidator.validateAppleSignedBinary(at: routePath) else {
            logger.error("SECURITY: /sbin/route failed Apple code signature validation")
            return nil
        }

        let result: BoundedHelperCommand.CapturedOutput
        do {
            result = try BoundedHelperCommand.runCapturingStandardOutput(
                executable: URL(fileURLWithPath: routePath),
                arguments: ["-n", "get", "0.0.0.0"],
                timeout: BoundedHelperCommand.networkConfigurationTimeout
            )
        } catch {
            logger.warning("Failed to detect primary interface: \(String(describing: error))")
            return nil
        }

        // swiftlint:disable:next optional_data_string_conversion
        let output = String(decoding: result.standardOutput, as: UTF8.self)
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                let iface = trimmed
                    .replacingOccurrences(of: "interface:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !iface.isEmpty {
                    return iface
                }
            }
        }

        return nil
    }

    private static func detectAllEnabledServices() throws -> [String] {
        let output = try runNetworkSetup(["-listallnetworkservices"])
        var services: [String] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty,
               !trimmed.hasPrefix("An asterisk"),
               !trimmed.hasPrefix("*")
            {
                services.append(trimmed)
            }
        }
        services = services
            .filter { !$0.isEmpty && !$0.contains("\0") && !$0.contains("\n") && !$0.contains("\r") && $0.count <= 128 }
        logger.info("Enabled network services: \(services)")
        return services
    }

    private static func detectActiveNetworkService() throws -> String {
        let output = try runNetworkSetup(["-listnetworkserviceorder"])
        let services = parseNetworkServices(from: output)

        for service in services {
            if let status = try? runNetworkSetup(["-getwebproxy", service]),
               !status.contains("** Error")
            {
                logger.debug("Detected active network service: '\(service)'")
                return service
            }
        }

        let allOutput = try runNetworkSetup(["-listallnetworkservices"])
        for line in allOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("An asterisk"), !trimmed.hasPrefix("*") {
                logger.debug("Falling back to network service: '\(trimmed)'")
                return trimmed
            }
        }

        logger.warning("No active network service found, defaulting to Wi-Fi")
        return "Wi-Fi"
    }

    private static func parseNetworkServices(from output: String) -> [String] {
        var services: [String] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let openParen = trimmed.firstIndex(of: "("),
               let closeParen = trimmed.firstIndex(of: ")"),
               openParen == trimmed.startIndex
            {
                let afterParen = trimmed.index(after: closeParen)
                let name = String(trimmed[afterParen...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    services.append(name)
                }
            }
        }
        return services
    }

    // MARK: - Process Execution

    @discardableResult
    private static func runNetworkSetup(_ arguments: [String]) throws -> String {
        try validateBinary(networkSetupPath)

        let command = arguments.joined(separator: " ")
        let output: BoundedHelperCommand.CapturedOutput
        do {
            output = try BoundedHelperCommand.runCapturingStandardOutput(
                executable: URL(fileURLWithPath: networkSetupPath),
                arguments: arguments,
                timeout: BoundedHelperCommand.networkConfigurationTimeout
            )
        } catch {
            // A failed spawn, a timeout and an overlong reading are all definite failures. None
            // may read as a service that simply has no proxy configured, because the caller would
            // then write that emptiness into the recovery backup.
            logger.error("Failed to run networksetup: \(String(describing: error))")
            throw ProxyConfiguratorError.executionFailed(command: command, reason: String(describing: error))
        }

        // Decoded leniently: both buffers are byte budgets, so the last character can be a
        // truncated multi-byte sequence a strict decode would discard the whole reading for.
        // swiftlint:disable:next optional_data_string_conversion
        let stdout = String(decoding: output.standardOutput, as: UTF8.self)
        guard output.status == 0 else {
            // swiftlint:disable:next optional_data_string_conversion
            let stderr = String(decoding: output.diagnostic, as: UTF8.self)
            let combined = stderr.isEmpty ? stdout : stderr
            logger.error("networksetup failed (\(output.status)): \(combined)")
            throw ProxyConfiguratorError.executionFailed(command: command, reason: combined)
        }

        return stdout
    }
}

// MARK: - Single-transaction writes

extension ProxyConfigurator {
    private enum ClearedStep {
        /// Nothing may be written for this service this time round; its record says why.
        case skipped
        /// Committed and revalidated: waiting only for the write.
        case cleared(PendingServiceRestore)
        /// Already settled without a write, successfully or not.
        case finished(ProxyServiceRestoreOutcome)
    }

    /// Phase one for one service: the re-read, the `inFlight` commit, and the revalidation after
    /// it. Nothing here writes a setting.
    private static func commitAndRevalidate(
        entry: ProxyServiceRecoveryJournalEntry,
        serviceBackup: CrashRecovery.ServiceProxyBackup,
        state: inout JournaledRestoreState,
        backup workingBackup: inout CrashRecovery.ProxyBackup,
        port: Int?
    )
        -> ClearedStep
    {
        // The plan was made for every service at once. Re-read this one immediately before it is
        // committed so a change made since the plan is seen before anything is written.
        guard preflightAllowsRestore(entry: entry, state: &state, backup: &workingBackup, port: port) else {
            return .skipped
        }

        // Only now, and only for this one service, does the record advance to `inFlight`. The
        // commit is the permission to write: if it cannot be recorded, nothing is sent for this
        // service, because an unrecorded write is exactly the case a later attempt has no way to
        // reason about.
        let inFlightEntry = entry.advanced(to: .inFlight)
        let inFlightJournal = replacing(state.journal, entry: inFlightEntry)
        var committedBackup: CrashRecovery.ProxyBackup?
        var cleared: PendingServiceRestore?
        let attempt = ProxyJournaledServiceRestore.run(
            commitInFlight: {
                committedBackup = try CrashRecovery.reduceBackup(
                    workingBackup,
                    to: state.retention.services,
                    rockxyPort: port,
                    journal: inFlightJournal
                )
                logger.info("Restoring proxy settings for '\(entry.service)'")
            },
            restore: {
                switch ProxyServiceRecoveryPolicy.continuation(
                    for: inFlightEntry,
                    live: liveStateForRestore(of: inFlightEntry)
                ) {
                case .restore:
                    break
                case .complete:
                    return .restored
                case .abandon,
                     .retryLater:
                    return .failed(
                        step: .proxyState,
                        error: ProxyRecoveryRevalidationError.stateChangedAfterCommit(service: entry.service)
                    )
                }
                // Cleared to write. The write waits for phase two; this return value is not used
                // for a service that reaches it.
                cleared = PendingServiceRestore(entry: inFlightEntry, backup: serviceBackup)
                return .restored
            }
        )

        guard case let .issued(outcome) = attempt else {
            if case let .notIssued(commitError) = attempt {
                logger
                    .error(
                        "Could not record the restore of '\(entry.service)' — issuing no command for it: \(commitError.localizedDescription)"
                    )
            }
            state.deferredServices.append(entry.service)
            return .skipped
        }

        state.journal = inFlightJournal
        workingBackup = committedBackup ?? workingBackup
        state.attemptedServices.append(entry.service)
        return cleared.map(ClearedStep.cleared) ?? .finished(outcome)
    }

    /// A service that has passed every check short of the write: its `inFlight` record is
    /// committed and the live settings were revalidated against it.
    private struct PendingServiceRestore {
        let entry: ProxyServiceRecoveryJournalEntry
        let backup: CrashRecovery.ServiceProxyBackup
    }

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProxyConfigurator")
    private static let networkSetupPath = "/usr/sbin/networksetup"
    private static let routePath = "/sbin/route"

    /// Restores the backed-up services a recovery journal still authorizes, one service at a
    /// time, recording the intent before each step and its completion after.
    ///
    /// The journal is what makes a retry safe. Before anything is written, the reduced backup and
    /// an `inFlight` record for every service about to be touched are persisted, so a process
    /// that dies part-way through leaves behind both the settings to write and the shape the
    /// write was expected to produce. A later attempt then compares the live settings against
    /// that record: settings this restore could have produced are written again, and settings it
    /// could not are treated as someone else's and dropped from recovery untouched.
    ///
    /// `preservedServices` names backup entries this attempt is not authorized to write but must
    /// keep on disk for its whole run. A rollback that only covers the services one failed
    /// override touched must never be the moment an untouched service loses the only restore
    /// point it has, so those entries are never removed and re-added — they are simply never
    /// dropped.
    private static func runJournaledRestore(
        backup: CrashRecovery.ProxyBackup,
        candidateServices: [String],
        port: Int?,
        locallyMutatedServices: Set<String> = [],
        preservedServices: [String] = [],
        preAttemptServices: Set<String>? = nil
    )
        -> [String]
    {
        let retentionOfPreservedOnly = ProxyBackupRetention(
            authorized: [],
            preserved: preservedServices,
            preAttemptServices: preAttemptServices
        )
        let candidateEntries = ProxyBackupSubset.select(
            backup.services,
            services: Set(candidateServices),
            serviceName: \.service
        )

        guard !candidateEntries.isEmpty else {
            logger.info("No backed-up service is still Rockxy-owned — dropping it from the backup")
            return finishRestore(
                backup: backup,
                unresolvedServices: [],
                retention: retentionOfPreservedOnly,
                journal: ProxyBackupSubset.select(
                    backup.journal,
                    services: Set(preservedServices),
                    serviceName: \.service
                ),
                port: port,
                recoveryPending: backup.recoveryPending
            )
        }

        // A service with no usable record may only enter recovery when the live settings still
        // prove Rockxy owns it on the persisted port, or when they are exactly one of the states
        // this process's own override commands pass through. Anything weaker — a readable but
        // foreign configuration, or one that could not be read at all — keeps its restore point
        // for a later attempt instead of being adopted as a starting point.
        let plan = ProxyFastRead.plan(
            targets: candidateEntries.map(restorationTarget(for:)),
            journal: backup.journal,
            fastStates: systemConfigurationStates(for: candidateEntries.map(\.service)),
            ownedPort: port,
            locallyMutatedServices: locallyMutatedServices,
            authoritative: currentRestorationStates(for:)
        )

        if !plan.abandonedServices.isEmpty {
            logger
                .warning(
                    "Leaving \(plan.abandonedServices.count) network service(s) out of automatic recovery — their proxy settings were changed outside this restore"
                )
        }
        if !plan.completedServices.isEmpty {
            logger.info("\(plan.completedServices.count) network service(s) were already restored")
        }

        // Entries for services that stay in the backup without being written this time round.
        let deferredJournal = ProxyBackupSubset.select(
            backup.journal,
            services: Set(plan.deferredServices + preservedServices),
            serviceName: \.service
        )

        guard !plan.entriesToRestore.isEmpty else {
            // Nothing is written, so the backup keeps the flag it arrived with: an attempt that
            // could read nothing must not count as the recovery that already started.
            return finishRestore(
                backup: backup,
                unresolvedServices: plan.deferredServices,
                retention: retentionOfPreservedOnly,
                journal: deferredJournal,
                port: port,
                recoveryPending: backup.recoveryPending
            )
        }

        logger.info("Restoring original proxy settings for \(plan.entriesToRestore.count) service(s)")

        // Persist the intent before the first command runs. Every planned service is recorded at
        // the stage it was planned at — a service nothing has been issued for stays `pending`, so
        // a crash while an earlier service is being written cannot make it look half-restored and
        // hand a later attempt a licence to overwrite a change made in the meantime.
        var state = JournaledRestoreState(
            journal: plan.entriesToRestore + deferredJournal,
            retention: ProxyBackupRetention(
                authorized: plan.servicesKeepingBackup,
                preserved: preservedServices,
                preAttemptServices: preAttemptServices
            ),
            deferredServices: plan.deferredServices
        )
        var workingBackup: CrashRecovery.ProxyBackup
        do {
            workingBackup = try CrashRecovery.reduceBackup(
                backup,
                to: state.retention.services,
                rockxyPort: port,
                journal: state.journal
            )
        } catch {
            // Nothing has been written, and nothing may be: the record that would let a later
            // attempt reason about a command is exactly what could not be stored.
            logger
                .error(
                    "Could not persist the reduced proxy backup — leaving settings untouched: \(error.localizedDescription)"
                )
            return plan.entriesToRestore.map(\.service) + plan.deferredServices
        }

        // The services are restored in three phases. Phase one is everything that only reads or
        // only records: the re-read, the `inFlight` commit, and the revalidation after it, one
        // service at a time exactly as before. Phase two is the write, once, for every service
        // phase one cleared. Phase three records each outcome. Services are independent, so
        // reading all of them before writing any changes nothing about what each one sees.
        var queued: [PendingServiceRestore] = []
        for entry in plan.entriesToRestore {
            guard let serviceBackup = candidateEntries.first(where: { $0.service == entry.service }) else {
                continue
            }
            switch commitAndRevalidate(
                entry: entry,
                serviceBackup: serviceBackup,
                state: &state,
                backup: &workingBackup,
                port: port
            ) {
            case .skipped:
                continue
            case let .cleared(pending):
                queued.append(pending)
            case let .finished(outcome):
                recordRestoreOutcome(
                    outcome,
                    service: entry.service,
                    state: &state,
                    backup: &workingBackup,
                    port: port
                )
            }
        }

        if !queued.isEmpty {
            let outcomes = writeQueuedRestores(queued, port: port)
            for pending in queued {
                recordRestoreOutcome(
                    outcomes[pending.entry.service] ?? .failed(
                        step: .proxyState,
                        error: ProxyRecoveryRevalidationError.stateChangedAfterCommit(
                            service: pending.entry.service
                        )
                    ),
                    service: pending.entry.service,
                    state: &state,
                    backup: &workingBackup,
                    port: port
                )
            }
        }

        let stillOwnedServices = Set(port.map { ownedPort in
            ProxyOverrideOwnership.residualOwnedServices(
                in: overrideStatesPreferringSystemConfiguration(for: state.attemptedServices),
                port: ownedPort
            )
        } ?? [])
        let unresolvedServices = ProxyBackupSubset.unresolvedEntries(
            state.attemptedServices,
            failedServices: state.failedServices,
            stillOwnedServices: stillOwnedServices,
            serviceName: { $0 }
        ) + state.deferredServices

        // Only a service this attempt could not resolve leaves the file mid-recovery. Entries it
        // was never authorized to write keep the flag they arrived with: claiming a recovery had
        // started for them would keep them in play at every later launch.
        return finishRestore(
            backup: workingBackup,
            unresolvedServices: unresolvedServices,
            retention: state.retention,
            journal: state.journal,
            port: port,
            recoveryPending: !unresolvedServices.isEmpty || backup.recoveryPending
        )
    }

    /// Records how one service's restore ended: a failure is remembered for the report, a success
    /// is written to the journal as `restored`.
    private static func recordRestoreOutcome(
        _ outcome: ProxyServiceRestoreOutcome,
        service: String,
        state: inout JournaledRestoreState,
        backup workingBackup: inout CrashRecovery.ProxyBackup,
        port: Int?
    ) {
        if let failedStep = outcome.failedStep {
            state.failedServices.insert(service)
            logger
                .error(
                    "Stopped restoring '\(service)' at the \(failedStep.rawValue) step: \(outcome.error?.localizedDescription ?? "unknown error")"
                )
            return
        }

        // Every write for this service has landed. Recording that now is what keeps a death from
        // this point on from looking like a write that never ran.
        state.journal = advanced(state.journal, service: service, to: .restored)
        do {
            workingBackup = try CrashRecovery.reduceBackup(
                workingBackup,
                to: state.retention.services,
                rockxyPort: port,
                journal: state.journal
            )
        } catch {
            // The writes already landed, so a lost journal update costs nothing: the next
            // attempt reads the live settings as the finished shape and stops there.
            logger
                .error("Could not record the completed restore for '\(service)': \(error.localizedDescription)")
        }
    }

    /// Writes every cleared service's captured settings, the bypass list included, in a single
    /// SystemConfiguration transaction, and hands back to `networksetup` whatever that
    /// transaction did not write.
    ///
    /// Crash analysis, since the journal protocol is unchanged and this is why it still holds. The
    /// `inFlight` record for every service in `queued` is already on disk, and the writer records
    /// that an apply is owed (`ProxyApplyDebt`) before it commits. The commit replaces the
    /// preferences file atomically, so a process that dies:
    /// - before the commit leaves every service exactly as it was, which `inFlight` explains as
    ///   the state before the step, so a later attempt writes again;
    /// - during the commit leaves either all of the batch or none of it, never a mixture;
    /// - after the commit, before the apply is confirmed, leaves the FILE finished and the LIVE
    ///   SYSTEM not. Every reader here reads preferences, so the next attempt reads `complete`
    ///   and would drop the service. What stops that is the debt record: `settleOwedApply` runs
    ///   first at every entry point and applies again before anything is read or journaled.
    /// - after the apply, before a `restored` record, leaves everything finished and applied; the
    ///   next attempt reads `complete` and drops the service.
    /// The shapes in between that the per-command sequence used to leave are no longer reachable
    /// by this path; they stay modelled because the fallback still produces them.
    private static func writeQueuedRestores(
        _ queued: [PendingServiceRestore],
        port: Int?
    )
        -> [String: ProxyServiceRestoreOutcome]
    {
        let items = queued.map { pending in
            ProxyTransactionItem(
                service: pending.entry.service,
                writes: ProxyWritePlan.restore(to: restorationTarget(for: pending.backup)),
                admission: .restoreContinuation(pending.entry)
            )
        }
        let outcome = ProxySystemConfigurationWriter.commit(items, ownedPort: port)
        let resolution = ProxyFallbackPolicy.resolve(requested: queued.map(\.entry.service), outcome: outcome)

        var outcomes: [String: ProxyServiceRestoreOutcome] = [:]
        for service in resolution.written {
            outcomes[service] = .restored
        }
        if !resolution.written.isEmpty {
            logger.info("Restored \(resolution.written.count) network service(s) in one transaction")
        }
        for (service, reason) in resolution.fallback {
            guard let pending = queued.first(where: { $0.entry.service == service }) else {
                continue
            }
            logger.warning("Restoring '\(service)' with networksetup instead: \(String(describing: reason))")
            outcomes[service] = restoreWithNetworkSetup(
                pending,
                rewritingFinishedSettings: ProxyFallbackPolicy.rewritesFinishedSettings(after: reason),
                ownedPort: port
            )
        }
        return outcomes
    }

    /// The per-command restore, one process per setting. Used only for a service the
    /// SystemConfiguration transaction did not write, and it revalidates first because time has
    /// passed since phase one.
    private static func restoreWithNetworkSetup(
        _ pending: PendingServiceRestore,
        rewritingFinishedSettings: Bool,
        ownedPort: Int?
    )
        -> ProxyServiceRestoreOutcome
    {
        let service = pending.entry.service
        switch ProxyServiceRecoveryPolicy.continuation(
            for: pending.entry,
            live: readRestorationState(for: service)
        ) {
        case .restore:
            break
        case .complete:
            // The preferences read as finished. They would read the same if a commit landed and
            // was never applied, so finished settings are left alone only when no reason suggests
            // an unconfirmed apply and `configd` is not still enforcing the override.
            guard rewritingFinishedSettings || effectiveSettingsStillOverridden(port: ownedPort) else {
                return .restored
            }
        case .abandon,
             .retryLater:
            return .failed(
                step: .proxyState,
                error: ProxyRecoveryRevalidationError.stateChangedAfterCommit(service: service)
            )
        }
        // The bypass list is the last thing written, and it is not written at all when a
        // proxy-state command failed: a restored bypass list beside a half-written proxy state is
        // a shape no prefix of the sequence produces.
        return ProxyServiceRestoreExecution.run(
            proxyState: {
                try disableProxyStates(for: service)
                try applyServiceProxyState(pending.backup)
            },
            bypassDomains: {
                try restoreBypassDomains(service: service, domains: pending.backup.bypassDomains)
            }
        )
    }

    /// Writes Rockxy's loopback override onto one service: in one SystemConfiguration
    /// transaction when it can, with the per-command sequence as the fallback.
    private static func applyOverride(service: String, port: Int, baseline: ProxyServiceRestorationState) throws {
        try writeInOneTransaction(
            service: service,
            writes: ProxyWritePlan.override(port: port),
            baseline: baseline,
            ownedPort: port
        ) {
            try applyOverrideWithNetworkSetup(service: service, port: port)
        }
    }

    /// Writes one service's bypass list the same way: one transaction, `networksetup` as fallback.
    private static func writeBypassDomains(
        service: String,
        domains: [String],
        baseline: ProxyServiceRestorationState
    )
        throws
    {
        try writeInOneTransaction(
            service: service,
            writes: ProxyWritePlan.bypass(domains),
            baseline: baseline,
            ownedPort: nil
        ) {
            try restoreBypassDomains(service: service, domains: domains)
        }
    }

    private static func writeInOneTransaction(
        service: String,
        writes: [ProxyKeyWrite],
        baseline: ProxyServiceRestorationState,
        ownedPort: Int?,
        fallback: () throws -> Void
    )
        throws
    {
        let outcome = ProxySystemConfigurationWriter.commit(
            [ProxyTransactionItem(service: service, writes: writes, admission: .equals(baseline))],
            ownedPort: ownedPort
        )
        guard let reason = ProxyFallbackPolicy.resolve(requested: [service], outcome: outcome).fallback.first?.reason else {
            return
        }
        logger.warning("Writing '\(service)' with networksetup instead: \(String(describing: reason))")
        // The in-lock check may have declined because the settings changed, or because this layer
        // read them differently. The authoritative read decides, as it did before the first write.
        // After a refused apply or a deadline the write may already have landed: the settings then
        // equal what it produces, and re-issuing it is what applies it, not a change to guard.
        guard ProxyFallbackPolicy.mayWriteOver(
            live: readRestorationState(for: service),
            baseline: baseline,
            writes: writes,
            after: reason
        ) else {
            throw ProxyConfiguratorError.executionFailed(
                command: "proxy preflight",
                reason: "The live settings changed before they could be written"
            )
        }
        try fallback()
    }

    /// Applies preferences an earlier transaction committed but never confirmed applying. Call it
    /// first at every privileged entry point, and once at helper launch: it is one file read when
    /// nothing is owed. A process that died between a commit and its apply is the case it exists
    /// for, because preferences alone then read as a finished restore.
    @discardableResult
    static func settleOwedApply() -> ProxyApplySettlement {
        let settlement = ProxySystemConfigurationWriter.settleOwedApply()
        switch settlement {
        case .nothingOwed:
            break
        case .settled:
            logger.info("Applied proxy settings an earlier transaction had committed but not applied")
        case .stillOwed:
            logger.error("Committed proxy settings are still waiting to be applied")
        }
        return settlement
    }

    /// Whether `configd` is still enforcing a loopback override on `port`. A read of what is in
    /// force, which preferences cannot say. It describes the primary service only, so a hit can
    /// cost one redundant rewrite but a miss never proves anything.
    private static func effectiveSettingsStillOverridden(port: Int?) -> Bool {
        guard let port, let effective = ProxySystemConfigurationWriter.effectiveProxies() else {
            return false
        }
        return ProxyEffectiveSettings.pointsAtLoopback(port: port, effective: effective)
    }

    /// The per-command override sequence, in a fixed order.
    private static func applyOverrideWithNetworkSetup(service: String, port: Int) throws {
        try runNetworkSetup(["-setwebproxy", service, "127.0.0.1", String(port)])
        try runNetworkSetup(["-setwebproxystate", service, "on"])
        try runNetworkSetup(["-setsecurewebproxy", service, "127.0.0.1", String(port)])
        try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
        try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        try runNetworkSetup(["-setautoproxystate", service, "off"])
        try runNetworkSetup(["-setproxyautodiscovery", service, "off"])
    }
}

// MARK: - ProxyConfiguratorError

enum ProxyConfiguratorError: LocalizedError {
    case directSessionInUse
    case executionFailed(command: String, reason: String)
    case noActiveService
    case noOwnedProxySession
    /// An override attempt failed and at least one service it touched could not be put back, so
    /// the recovery backup was preserved and those services still need a live restore path.
    case overrideRollbackIncomplete(services: [String])

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .directSessionInUse:
            "A direct-mode proxy session is already active for this user"
        case let .executionFailed(command, reason):
            "networksetup \(command) failed: \(reason)"
        case .noActiveService:
            "No active network service detected"
        case .noOwnedProxySession:
            "No proxy session owned by this connection is active"
        case let .overrideRollbackIncomplete(services):
            "The proxy override failed and \(services.count) network service(s) could not be restored; the recovery backup was preserved"
        }
    }
}
