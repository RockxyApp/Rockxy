import Foundation
@testable import Rockxy
import Testing

// Regression tests for the per-service recovery loop the app and the shipped watchdog binary both
// run. The states it leaves behind are only ever observed after a crash, so they are exercised
// here rather than left to be discovered there.

// MARK: - DirectProxyRecoveryRunnerTests

struct DirectProxyRecoveryRunnerTests {
    // MARK: Internal

    @Test("The record reaches disk before the first command and again once they have all landed")
    func theJournalBracketsEveryService() {
        let machine = RecoveryMachine(live: [service: ProxyRecoveryJournalFixtures.rockxyOverride])

        let result = machine.run(entries: [restoreEntry()])

        // The commit is the permission to issue a command, so it comes first; the completion is
        // recorded after, which is what keeps a death from that point on from looking like a
        // command that never ran.
        #expect(machine.steps == [
            "publish:inFlight",
            "proxyState:Wi-Fi",
            "bypassDomains:Wi-Fi",
            "publish:restored",
        ])
        #expect(result.allSucceeded)
        #expect(result.attemptedServices == [service])
        #expect(result.failedServices.isEmpty)
    }

    @Test("A record that cannot be stored issues no command for that service")
    func anUnrecordableServiceIsNeverWritten() {
        let machine = RecoveryMachine(live: [service: ProxyRecoveryJournalFixtures.rockxyOverride])
        machine.failPublishing = true

        let result = machine.run(entries: [restoreEntry()])

        // An unrecorded write is precisely what a later attempt has no way to reason about, so
        // the service is deferred with its restore point intact instead.
        #expect(machine.steps == ["publish:inFlight"])
        #expect(result.attemptedServices.isEmpty)
        #expect(result.deferredServices == [service])
        #expect(result.allSucceeded)
    }

    @Test("The bypass list is not written when the proxy state failed")
    func aFailedProxyStateStopsBeforeTheBypassList() {
        let machine = RecoveryMachine(live: [service: ProxyRecoveryJournalFixtures.rockxyOverride])
        machine.failProxyState = true

        let result = machine.run(entries: [restoreEntry()])

        // A restored bypass list beside a half-written proxy state is a shape no prefix of the
        // sequence produces, and recovery reads those as somebody else's.
        #expect(!machine.steps.contains("bypassDomains:Wi-Fi"))
        #expect(!machine.steps.contains("publish:restored"))
        #expect(!result.allSucceeded)
        #expect(result.failedServices == [service])
        #expect(result.attemptedServices == [service])
    }

    @Test("A service the user changed since the plan leaves recovery before anything is written")
    func aChangedServiceIsDroppedDurably() {
        // The plan was made for every service at once; this one is re-read immediately before its
        // own first command, which is what lets a change made in between be seen in time.
        let machine = RecoveryMachine(live: [service: ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.rockxyOverride,
            https: ProxyEndpointState(enabled: true, host: "vpn.example", port: 3_128)
        )])

        let result = machine.run(entries: [restoreEntry()])

        #expect(machine.steps == ["publish:"])
        #expect(result.attemptedServices.isEmpty)
        #expect(result.journal.isEmpty)
        // Its entry comes off disk before the loop moves on, so a process that dies straight
        // afterwards cannot come back and write over the change.
        #expect(result.retention.services.isEmpty)
        #expect(machine.published.last?.services.isEmpty == true)
    }

    @Test("A service changed while its journal is committed receives no recovery command")
    func aChangeDuringCommitIsRechecked() {
        let machine = RecoveryMachine(live: [service: ProxyRecoveryJournalFixtures.rockxyOverride])
        machine.stateAfterFirstPublish = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.rockxyOverride,
            https: ProxyEndpointState(enabled: true, host: "vpn.example", port: 3_128)
        )

        let result = machine.run(entries: [restoreEntry()])

        #expect(machine.steps == ["publish:inFlight"])
        #expect(!result.allSucceeded)
        #expect(result.failedServices == [service])
        #expect(!machine.steps.contains("proxyState:Wi-Fi"))
    }

    @Test("A service whose settings could not be read keeps its restore point and its stage")
    func anUnreadableServiceIsDeferred() {
        let machine = RecoveryMachine(live: [:])

        let result = machine.run(entries: [restoreEntry()])

        #expect(result.deferredServices == [service])
        #expect(result.attemptedServices.isEmpty)
        #expect(result.retention.services == [service])
        #expect(result.journal.first?.stage == .pending)
    }

    @Test("One service failing does not stop the next from being restored")
    func servicesAreAnsweredIndependently() {
        let machine = RecoveryMachine(live: [
            service: ProxyRecoveryJournalFixtures.rockxyOverride,
            "Ethernet": ProxyRecoveryJournalFixtures.renamed(
                ProxyRecoveryJournalFixtures.rockxyOverride,
                to: "Ethernet"
            ),
        ])
        machine.failProxyStateFor = [service]

        let result = machine.run(
            entries: [restoreEntry(), restoreEntry(service: "Ethernet")],
            services: [service, "Ethernet"]
        )

        #expect(result.failedServices == [service])
        #expect(result.attemptedServices == [service, "Ethernet"])
        #expect(!result.allSucceeded)
        #expect(machine.steps.contains("bypassDomains:Ethernet"))
    }

    // MARK: Private

    private let service = ProxyRecoveryJournalFixtures.service

    private func restoreEntry(service: String = ProxyRecoveryJournalFixtures.service) -> ProxyServiceRecoveryJournalEntry {
        let pre = ProxyRecoveryJournalFixtures.renamed(ProxyRecoveryJournalFixtures.rockxyOverride, to: service)
        let target = ProxyRecoveryJournalFixtures.renamed(ProxyRecoveryJournalFixtures.capturedSettings, to: service)
        return ProxyServiceRecoveryJournalEntry(
            service: service,
            stage: .pending,
            expectedPreStepState: pre,
            target: target
        )
    }
}

// MARK: - RecoveryMachine

/// A recovery run with the disk and `networksetup` replaced, so the ordering the loop produces is
/// what the test observes.
private final class RecoveryMachine {
    // MARK: Lifecycle

    init(live: [String: ProxyServiceRestorationState]) {
        self.live = live
    }

    // MARK: Internal

    var steps: [String] = []
    var published: [DirectProxyBackup] = []
    var failPublishing = false
    var failProxyState = false
    var failProxyStateFor: Set<String> = []
    var stateAfterFirstPublish: ProxyServiceRestorationState?

    func run(
        entries: [ProxyServiceRecoveryJournalEntry],
        services: [String] = [ProxyRecoveryJournalFixtures.service]
    )
        -> DirectProxyRecoveryResult
    {
        let backup = DirectProxyBackup(
            services: services.map(Self.serviceBackup(for:)),
            timestamp: Date(timeIntervalSince1970: 0),
            rockxyPort: ProxyRecoveryJournalFixtures.rockxyPort,
            recoveryPending: true,
            journal: entries
        )

        return DirectProxyRecoveryRunner.run(
            entriesToRestore: entries,
            backup: backup,
            journal: entries,
            retention: ProxyBackupRetention(authorized: services, preserved: []),
            deferredServices: [],
            effects: DirectProxyRecoveryEffects(
                readState: { [weak self] in self?.live[$0] },
                publishBackup: { [weak self] backup in
                    guard let self else {
                        return
                    }
                    let stages = backup.journal.map(\.stage.rawValue).joined(separator: ",")
                    steps.append("publish:\(stages)")
                    if failPublishing {
                        throw MachineFailure()
                    }
                    published.append(backup)
                    if let stateAfterFirstPublish {
                        live[stateAfterFirstPublish.service] = stateAfterFirstPublish
                        self.stateAfterFirstPublish = nil
                    }
                },
                restoreProxyState: { [weak self] entry in
                    guard let self else {
                        return
                    }
                    steps.append("proxyState:\(entry.service)")
                    if failProxyState || failProxyStateFor.contains(entry.service) {
                        throw MachineFailure()
                    }
                },
                restoreBypassDomains: { [weak self] entry in
                    self?.steps.append("bypassDomains:\(entry.service)")
                },
                log: { _ in }
            )
        )
    }

    // MARK: Private

    private var live: [String: ProxyServiceRestorationState]

    private static func serviceBackup(for service: String) -> DirectServiceBackup {
        let captured = ProxyRecoveryJournalFixtures.renamed(
            ProxyRecoveryJournalFixtures.capturedSettings,
            to: service
        )
        return DirectServiceBackup(
            service: service,
            httpEnabled: captured.http.enabled,
            httpHost: captured.http.host,
            httpPort: captured.http.port,
            httpsEnabled: captured.https.enabled,
            httpsHost: captured.https.host,
            httpsPort: captured.https.port,
            socksEnabled: captured.socks.enabled,
            socksHost: captured.socks.host,
            socksPort: captured.socks.port,
            pacEnabled: captured.pacEnabled,
            pacURL: captured.pacURL,
            autoDiscoveryEnabled: captured.autoDiscoveryEnabled,
            bypassDomains: captured.bypassDomains
        )
    }
}

// MARK: - MachineFailure

private struct MachineFailure: Error {}
