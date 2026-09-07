import Foundation
@testable import Rockxy
import Testing

// Regression tests for the per-service recovery journal in the shared recovery layer: what a
// retry is allowed to write after a partial restore, a crash, or a user change.

// MARK: - ProxyRecoveryJournalFixtures

/// Shared shapes for the journal tests: the override Rockxy leaves on a service, and the corporate
/// configuration a restore has to put back.
enum ProxyRecoveryJournalFixtures {
    // MARK: Internal

    static let service = "Wi-Fi"
    static let rockxyPort = 9_090

    /// The strict loopback override Rockxy writes. With no application record naming a bypass
    /// update, the completed-state proof keeps the captured bypass list unchanged.
    static let rockxyOverride = ProxyServiceRestorationState(
        service: service,
        http: ProxyEndpointState(enabled: true, host: "127.0.0.1", port: rockxyPort),
        https: ProxyEndpointState(enabled: true, host: "127.0.0.1", port: rockxyPort),
        socks: ProxyEndpointState(enabled: false, host: "socks.corp.example", port: 1_080),
        pacEnabled: false,
        pacURL: "https://proxy.corp.example/config.pac",
        autoDiscoveryEnabled: false,
        bypassDomains: ["*.corp.internal", "localhost"]
    )

    /// Everything the user had configured before Rockxy took the route: both web proxies, SOCKS,
    /// PAC, auto discovery, and a bypass list.
    static let capturedSettings = ProxyServiceRestorationState(
        service: service,
        http: ProxyEndpointState(enabled: true, host: "proxy.corp.example", port: 8_080),
        https: ProxyEndpointState(enabled: true, host: "secure.corp.example", port: 8_443),
        socks: ProxyEndpointState(enabled: true, host: "socks.corp.example", port: 1_080),
        pacEnabled: true,
        pacURL: "https://proxy.corp.example/config.pac",
        autoDiscoveryEnabled: true,
        bypassDomains: ["*.corp.internal", "localhost"]
    )

    static var restoredSettings: ProxyServiceRestorationState {
        ProxyServiceRestorationState.expectedRestorationResult(
            target: capturedSettings,
            from: rockxyOverride
        )
    }

    static func entry(
        stage: ProxyRecoveryStage,
        pre: ProxyServiceRestorationState = rockxyOverride,
        target: ProxyServiceRestorationState = capturedSettings
    )
        -> ProxyServiceRecoveryJournalEntry
    {
        ProxyServiceRecoveryJournalEntry(
            service: pre.service,
            stage: stage,
            expectedPreStepState: pre,
            target: target
        )
    }

    static func renamed(
        _ state: ProxyServiceRestorationState,
        to service: String
    )
        -> ProxyServiceRestorationState
    {
        ProxyServiceRestorationState(
            service: service,
            http: state.http,
            https: state.https,
            socks: state.socks,
            pacEnabled: state.pacEnabled,
            pacURL: state.pacURL,
            autoDiscoveryEnabled: state.autoDiscoveryEnabled,
            bypassDomains: state.bypassDomains
        )
    }

    static func replacing(
        _ state: ProxyServiceRestorationState,
        http: ProxyEndpointState? = nil,
        https: ProxyEndpointState? = nil,
        socks: ProxyEndpointState? = nil,
        pacEnabled: Bool? = nil,
        pacURL: String? = nil,
        autoDiscoveryEnabled: Bool? = nil,
        bypassDomains: [String]? = nil
    )
        -> ProxyServiceRestorationState
    {
        ProxyServiceRestorationState(
            service: state.service,
            http: http ?? state.http,
            https: https ?? state.https,
            socks: socks ?? state.socks,
            pacEnabled: pacEnabled ?? state.pacEnabled,
            pacURL: pacURL ?? state.pacURL,
            autoDiscoveryEnabled: autoDiscoveryEnabled ?? state.autoDiscoveryEnabled,
            bypassDomains: bypassDomains ?? state.bypassDomains
        )
    }
}

// MARK: - ProxyRestorationStateTests

struct ProxyRestorationStateTests {
    // MARK: Internal

    @Test("A completed restore reproduces every captured proxy mode")
    func restorationResultCoversEveryProxyMode() {
        let restored = Fixtures.restoredSettings

        #expect(restored.http == Fixtures.capturedSettings.http)
        #expect(restored.https == Fixtures.capturedSettings.https)
        #expect(restored.socks == Fixtures.capturedSettings.socks)
        #expect(restored.pacEnabled)
        #expect(restored.pacURL == "https://proxy.corp.example/config.pac")
        #expect(restored.autoDiscoveryEnabled)
        #expect(restored.bypassDomains == ["*.corp.internal", "localhost"])
    }

    @Test("A captured protocol with no endpoint is only switched off, never re-pointed")
    func restorationLeavesUnnamedEndpointsWhereTheyAre() {
        let target = Fixtures.replacing(
            Fixtures.capturedSettings,
            http: ProxyEndpointState(enabled: false, host: "", port: 0),
            socks: ProxyEndpointState(enabled: false, host: "", port: 0),
            pacEnabled: false,
            autoDiscoveryEnabled: false
        )

        let restored = ProxyServiceRestorationState.expectedRestorationResult(
            target: target,
            from: Fixtures.rockxyOverride
        )

        // `networksetup` has no command that clears a stored endpoint, so the override's host and
        // port survive with the mode off — expecting the empty snapshot back would report a
        // finished restore as unfinished forever.
        #expect(restored.http == ProxyEndpointState(enabled: false, host: "127.0.0.1", port: 9_090))
        #expect(restored.socks == ProxyEndpointState(enabled: false, host: "socks.corp.example", port: 1_080))
        #expect(!restored.pacEnabled)
        #expect(restored.pacURL == Fixtures.rockxyOverride.pacURL)
        #expect(!restored.autoDiscoveryEnabled)
    }

    @Test("Switching every mode off keeps the endpoints, the PAC URL, and the bypass list")
    func disablingModesPreservesStoredValues() {
        let disabled = Fixtures.rockxyOverride.withProxyModesDisabled

        #expect(!disabled.http.enabled)
        #expect(disabled.http.host == "127.0.0.1")
        #expect(disabled.http.port == 9_090)
        #expect(!disabled.https.enabled)
        #expect(!disabled.socks.enabled)
        #expect(disabled.socks.host == "socks.corp.example")
        #expect(!disabled.pacEnabled)
        #expect(disabled.pacURL == Fixtures.rockxyOverride.pacURL)
        #expect(!disabled.autoDiscoveryEnabled)
        #expect(disabled.bypassDomains == Fixtures.rockxyOverride.bypassDomains)
    }

    @Test("The ownership projection reads the loopback override and a global bypass")
    func overrideProjectionMatchesOwnership() {
        #expect(ProxyOverrideOwnership.isOwnedByRockxy(
            Fixtures.rockxyOverride.overrideState,
            port: Fixtures.rockxyPort
        ))
        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            Fixtures.replacing(Fixtures.rockxyOverride, bypassDomains: ["*"]).overrideState,
            port: Fixtures.rockxyPort
        ))
        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            Fixtures.capturedSettings.overrideState,
            port: Fixtures.rockxyPort
        ))
    }

    @Test("A journal entry survives a plist roundtrip")
    func journalEntryRoundtrips() throws {
        let entry = Fixtures.entry(stage: .inFlight)

        let data = try PropertyListEncoder().encode([entry])
        let decoded = try PropertyListDecoder().decode([ProxyServiceRecoveryJournalEntry].self, from: data)

        #expect(decoded == [entry])
        #expect(decoded.first?.stage == .inFlight)
    }

    @Test("networksetup's empty bypass sentence parses as no bypass domains")
    func bypassOutputParsing() {
        #expect(ProxyBypassDomainOutput.parse(
            "There aren't any bypass domains set on Wi-Fi.\n"
        ).isEmpty)
        #expect(ProxyBypassDomainOutput.parse("*.corp.internal\nlocalhost\n\n") == [
            "*.corp.internal",
            "localhost",
        ])
    }

    // MARK: Private

    private typealias Fixtures = ProxyRecoveryJournalFixtures
}

// MARK: - ProxyServiceRecoveryPolicyTests

struct ProxyServiceRecoveryPolicyTests {
    // MARK: Internal

    @Test("Before any command runs, only the exact recorded override authorizes a write")
    func pendingRequiresTheRecordedOverride() {
        let entry = Fixtures.entry(stage: .pending)

        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.rockxyOverride
        ) == .restore)
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.rockxyOverride.withProxyModesDisabled
        ) == .abandon)
    }

    @Test("A user change between retries takes the service out of automatic recovery")
    func userChangeBetweenRetriesIsNeverOverwritten() {
        let userProxy = Fixtures.replacing(
            Fixtures.rockxyOverride,
            http: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
            https: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128)
        )

        for stage in [ProxyRecoveryStage.pending, .inFlight, .restored] {
            #expect(ProxyServiceRecoveryPolicy.continuation(
                for: Fixtures.entry(stage: stage),
                live: userProxy
            ) == .abandon)
        }
    }

    @Test("A bypass list the user edited between retries is not written over")
    func userBypassChangeIsNeverOverwritten() {
        let userBypass = Fixtures.replacing(
            Fixtures.rockxyOverride,
            bypassDomains: ["*.staging.internal"]
        )

        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: Fixtures.entry(stage: .inFlight),
            live: userBypass
        ) == .abandon)
    }

    @Test("An interrupted sequence is resumed at every point it can stop")
    func partialCommandStatesAreResumed() {
        let overrideWithAppliedBypass = Fixtures.replacing(
            Fixtures.rockxyOverride,
            bypassDomains: ["*.corp.internal"]
        )
        let entry = Fixtures.entry(stage: .inFlight, pre: overrideWithAppliedBypass)
        let disabled = overrideWithAppliedBypass.withProxyModesDisabled
        let restored = ProxyServiceRestorationState.expectedRestorationResult(
            target: Fixtures.capturedSettings,
            from: overrideWithAppliedBypass
        )

        // Stopped right after every mode was switched off.
        #expect(ProxyServiceRecoveryPolicy.continuation(for: entry, live: disabled) == .restore)
        // HTTP written back, HTTPS not reached yet.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(disabled, http: restored.http)
        ) == .restore)
        // Stopped between writing the HTTP endpoint and switching it on.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(disabled, http: restored.http.disabled)
        ) == .restore)
        // SOCKS and PAC written back, auto discovery and bypass not reached yet.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(
                disabled,
                http: restored.http,
                https: restored.https,
                socks: restored.socks,
                pacEnabled: true
            )
        ) == .restore)
        // Everything but the bypass list.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(restored, bypassDomains: overrideWithAppliedBypass.bypassDomains)
        ) == .restore)
    }

    @Test("A host from one step beside a port from another is not a state any step produced")
    func mixedHostAndPortIsTreatedAsForeign() {
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: Fixtures.entry(stage: .inFlight),
            live: Fixtures.replacing(
                Fixtures.rockxyOverride,
                http: ProxyEndpointState(enabled: true, host: "127.0.0.1", port: 8_080)
            )
        ) == .abandon)
    }

    @Test("A process that died between the commands and the journal update writes nothing again")
    func completedCommandsWithoutAJournalUpdateAreNotReplayed() {
        // The entry never advanced past `inFlight`, but the settings are already the restored
        // ones, so the sequence completed and there is nothing left to write.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: Fixtures.entry(stage: .inFlight),
            live: Fixtures.restoredSettings
        ) == .complete)
    }

    @Test("A recorded completion whose settings did not land is retried")
    func recordedCompletionThatDidNotLandIsRetried() {
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: Fixtures.entry(stage: .restored),
            live: Fixtures.rockxyOverride
        ) == .restore)
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: Fixtures.entry(stage: .restored),
            live: Fixtures.restoredSettings
        ) == .complete)
    }

    @Test("Settings that could not be read defer the service instead of guessing")
    func unreadableServiceIsDeferred() {
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: Fixtures.entry(stage: .inFlight),
            live: nil
        ) == .retryLater)
    }

    @Test("A record that names a different service never authorizes a write")
    func mismatchedServiceIsAbandoned() {
        let otherService = ProxyServiceRestorationState(
            service: "Ethernet",
            http: Fixtures.rockxyOverride.http,
            https: Fixtures.rockxyOverride.https,
            socks: Fixtures.rockxyOverride.socks,
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false,
            bypassDomains: []
        )

        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: Fixtures.entry(stage: .inFlight),
            live: otherService
        ) == .abandon)
    }

    // MARK: Private

    private typealias Fixtures = ProxyRecoveryJournalFixtures
}

// MARK: - ProxyRestoreTransitionTests

/// The restore is a fixed, ordered list of `networksetup` commands. These pin down that the
/// states it can be observed in are exactly the prefixes of that list — no more, so a foreign
/// change is caught, and no fewer, so an interrupted restore is still resumed.
struct ProxyRestoreTransitionTests {
    // MARK: Internal

    @Test("The reachable states start at the recorded settings and end at the finished restore")
    func transitionsSpanTheWholeStep() {
        let states = ProxyRestoreTransition.reachableStates(
            from: Fixtures.rockxyOverride,
            target: Fixtures.capturedSettings
        )

        #expect(states.first == Fixtures.rockxyOverride)
        #expect(states.last == Fixtures.restoredSettings)
    }

    @Test("Every state the ordered commands pass through authorizes the restore to continue")
    func everyOrderedPrefixIsResumable() {
        let entry = Fixtures.entry(stage: .inFlight)
        let states = ProxyRestoreTransition.reachableStates(
            from: Fixtures.rockxyOverride,
            target: Fixtures.capturedSettings
        )

        for state in states {
            let continuation = ProxyServiceRecoveryPolicy.continuation(for: entry, live: state)
            let expected: ProxyRecoveryContinuation = state == Fixtures.restoredSettings
                ? .complete
                : .restore
            #expect(continuation == expected)
        }
    }

    @Test("The commands are walked in the order the restore issues them")
    func statesFollowTheCommandOrder() {
        let disabled = Fixtures.rockxyOverride.withProxyModesDisabled
        let restored = Fixtures.restoredSettings
        let states = ProxyRestoreTransition.reachableStates(
            from: Fixtures.rockxyOverride,
            target: Fixtures.capturedSettings
        )

        // HTTP is switched off before HTTPS is, and the bypass list is not written until every
        // other command has run.
        let httpOff = Fixtures.replacing(Fixtures.rockxyOverride, http: Fixtures.rockxyOverride.http.disabled)
        #expect(index(of: httpOff, in: states) < index(of: disabled, in: states))
        #expect(index(of: disabled, in: states) < index(of: restored, in: states))

        // Each endpoint is written before the next protocol is touched.
        let httpWritten = Fixtures.replacing(disabled, http: restored.http)
        let httpsWritten = Fixtures.replacing(httpWritten, https: restored.https)
        #expect(index(of: httpWritten, in: states) < index(of: httpsWritten, in: states))
    }

    @Test("Setting an endpoint leaves its own mode uncertain and nothing else")
    func endpointWritesBranchOnlyOnTheirOwnMode() {
        let disabled = Fixtures.rockxyOverride.withProxyModesDisabled
        let restored = Fixtures.restoredSettings
        let entry = Fixtures.entry(stage: .inFlight)

        // `networksetup` does not define what writing an endpoint does to that mode's on/off
        // flag, so both answers are accepted at that command.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(disabled, http: restored.http.disabled)
        ) == .restore)
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(disabled, http: restored.http)
        ) == .restore)

        // The uncertainty does not spread: an HTTPS mode that is on while its endpoint is still
        // the override's is not something any command produced.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(disabled, http: restored.http, https: Fixtures.rockxyOverride.https)
        ) == .abandon)
    }

    @Test("A field combination no ordered prefix produces belongs to whoever wrote it")
    func impossibleCombinationsAreForeign() {
        let overrideWithAppliedBypass = Fixtures.replacing(
            Fixtures.rockxyOverride,
            bypassDomains: ["*.corp.internal"]
        )
        let entry = Fixtures.entry(stage: .inFlight, pre: overrideWithAppliedBypass)
        let restored = Fixtures.restoredSettings

        // The bypass list is written last, so it cannot be the restore's while HTTP and HTTPS
        // are still exactly as the override left them.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(
                overrideWithAppliedBypass,
                bypassDomains: Fixtures.capturedSettings.bypassDomains
            )
        ) == .abandon)

        // PAC is switched on after every endpoint has been written back.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(overrideWithAppliedBypass, pacEnabled: true)
        ) == .abandon)

        // Auto discovery comes after PAC, which comes after the endpoints.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(overrideWithAppliedBypass, autoDiscoveryEnabled: true)
        ) == .abandon)

        // A restored bypass list beside a half-written set of endpoints is not a prefix either.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(
                overrideWithAppliedBypass.withProxyModesDisabled,
                http: restored.http,
                bypassDomains: restored.bypassDomains
            )
        ) == .abandon)
    }

    @Test("A capture with no PAC and no auto discovery never passes through switching them on")
    func skippedCommandsAreNotReachable() {
        let target = Fixtures.replacing(
            Fixtures.capturedSettings,
            pacEnabled: false,
            autoDiscoveryEnabled: false
        )
        let entry = Fixtures.entry(stage: .inFlight, target: target)

        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: entry,
            live: Fixtures.replacing(
                ProxyServiceRestorationState.expectedRestorationResult(
                    target: target,
                    from: Fixtures.rockxyOverride
                ),
                pacEnabled: true
            )
        ) == .abandon)
    }

    // MARK: Private

    private typealias Fixtures = ProxyRecoveryJournalFixtures

    private func index(
        of state: ProxyServiceRestorationState,
        in states: [ProxyServiceRestorationState]
    )
        -> Int
    {
        states.firstIndex(of: state) ?? -1
    }
}

// MARK: - ProxyOverrideTransitionTests

/// Applying the override is a fixed seven-command sequence. These cover what that buys: a service
/// this process stopped part-way through can be proven to be its own work, and anything else
/// cannot.
struct ProxyOverrideTransitionTests {
    // MARK: Internal

    @Test("The reachable states start at the captured settings and end at the finished override")
    func transitionSpansTheWholeApply() {
        let states = ProxyOverrideTransition.reachableStates(
            from: Fixtures.capturedSettings,
            port: Fixtures.rockxyPort
        )

        #expect(states.first == Fixtures.capturedSettings)
        guard let final = states.last else {
            Issue.record("the override sequence produced no states")
            return
        }
        let loopback = ProxyEndpointState(enabled: true, host: "127.0.0.1", port: Fixtures.rockxyPort)
        #expect(final.http == loopback)
        #expect(final.https == loopback)
        #expect(!final.socks.enabled)
        #expect(!final.pacEnabled)
        #expect(!final.autoDiscoveryEnabled)
        // The bypass list is not part of the sequence: applying the override never writes it.
        #expect(final.bypassDomains == Fixtures.capturedSettings.bypassDomains)
        #expect(ProxyOverrideOwnership.isOwnedByRockxy(final.overrideState, port: Fixtures.rockxyPort))
    }

    @Test("The commands are walked in the order the override issues them")
    func statesFollowTheCommandOrder() {
        let states = ProxyOverrideTransition.reachableStates(
            from: Fixtures.capturedSettings,
            port: Fixtures.rockxyPort
        )
        let loopback = ProxyEndpointState(enabled: true, host: "127.0.0.1", port: Fixtures.rockxyPort)

        let httpWritten = index(of: Fixtures.replacing(
            Fixtures.capturedSettings,
            http: loopback.disabled
        ), in: states)
        let httpOn = index(of: Fixtures.replacing(Fixtures.capturedSettings, http: loopback), in: states)
        let httpsOn = index(of: Fixtures.replacing(
            Fixtures.capturedSettings,
            http: loopback,
            https: loopback
        ), in: states)
        let socksOff = index(of: Fixtures.replacing(
            Fixtures.capturedSettings,
            http: loopback,
            https: loopback,
            socks: Fixtures.capturedSettings.socks.disabled
        ), in: states)

        #expect(httpWritten != nil)
        #expect(httpOn != nil)
        #expect(httpsOn != nil)
        #expect(socksOff != nil)
        if let httpWritten, let httpOn, let httpsOn, let socksOff {
            #expect(httpWritten < httpOn)
            #expect(httpOn < httpsOn)
            #expect(httpsOn < socksOff)
        }
    }

    @Test("Setting an endpoint leaves its own mode uncertain and nothing else")
    func endpointWritesBranchOnlyOnTheirOwnMode() {
        let states = ProxyOverrideTransition.reachableStates(
            from: Fixtures.capturedSettings,
            port: Fixtures.rockxyPort
        )
        let loopback = ProxyEndpointState(enabled: true, host: "127.0.0.1", port: Fixtures.rockxyPort)

        // `networksetup` does not define what writing an endpoint does to that mode's flag, so
        // both answers are reachable — at that one command, for that one field.
        #expect(states.contains(Fixtures.replacing(Fixtures.capturedSettings, http: loopback.disabled)))
        #expect(states.contains(Fixtures.replacing(Fixtures.capturedSettings, http: loopback)))
        // The HTTPS endpoint is not written until two commands later, so it cannot be loopback
        // while HTTP is still undecided.
        #expect(!states.contains(Fixtures.replacing(
            Fixtures.capturedSettings,
            http: loopback.disabled,
            https: loopback
        )))
    }

    @Test("A field combination no ordered prefix produces belongs to whoever wrote it")
    func arbitraryForeignStatesAreRejected() {
        let loopback = ProxyEndpointState(enabled: true, host: "127.0.0.1", port: Fixtures.rockxyPort)
        let foreignStates: [ProxyServiceRestorationState] = [
            // Another proxy app on both protocols.
            Fixtures.replacing(
                Fixtures.capturedSettings,
                http: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
                https: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128)
            ),
            // Rockxy's host on somebody else's port.
            Fixtures.replacing(
                Fixtures.capturedSettings,
                http: ProxyEndpointState(enabled: true, host: "127.0.0.1", port: 4_444)
            ),
            // The override applied, with the bypass list edited underneath it.
            Fixtures.replacing(
                Fixtures.capturedSettings,
                http: loopback,
                https: loopback,
                socks: Fixtures.capturedSettings.socks.disabled,
                pacEnabled: false,
                autoDiscoveryEnabled: false,
                bypassDomains: ["*"]
            ),
            // The last command's effect without the ones before it.
            Fixtures.replacing(Fixtures.capturedSettings, autoDiscoveryEnabled: false),
        ]

        for foreign in foreignStates {
            #expect(!ProxyOverrideTransition.isReachedByApplying(
                foreign,
                from: Fixtures.capturedSettings,
                port: Fixtures.rockxyPort
            ))
        }
    }

    @Test("A record for one service never explains another service's settings")
    func aRenamedStateIsNotReachable() {
        #expect(!ProxyOverrideTransition.isReachedByApplying(
            Fixtures.renamed(Fixtures.capturedSettings, to: "Ethernet"),
            from: Fixtures.capturedSettings,
            port: Fixtures.rockxyPort
        ))
    }

    @Test("A backup that cannot name its port proves nothing beyond the captured settings")
    func anUnknownPortProvesNothing() {
        let states = ProxyOverrideTransition.reachableStates(from: Fixtures.capturedSettings, port: 0)

        #expect(states == [Fixtures.capturedSettings])
    }

    // MARK: Private

    private typealias Fixtures = ProxyRecoveryJournalFixtures

    private func index(
        of state: ProxyServiceRestorationState,
        in states: [ProxyServiceRestorationState]
    )
        -> Int?
    {
        states.firstIndex(of: state)
    }
}

// MARK: - ProxyBackupRetentionTests

/// A rollback that covers only the services one failed attempt touched must never be the moment
/// an untouched service loses the only restore point it has.
struct ProxyBackupRetentionTests {
    @Test("Entries this attempt may not write stay in the backup for its whole run")
    func preservedEntriesAreNeverAbsent() {
        var retention = ProxyBackupRetention(
            authorized: ["Wi-Fi", "Ethernet"],
            preserved: ["USB LAN", "Thunderbolt Bridge"]
        )

        #expect(retention.services == ["Wi-Fi", "Ethernet", "USB LAN", "Thunderbolt Bridge"])

        // A service the attempt finished with leaves. Every write from here on still carries the
        // preserved entries, because they were never this attempt's to delete.
        retention.drop("Wi-Fi")
        #expect(retention.services == ["Ethernet", "USB LAN", "Thunderbolt Bridge"])

        retention.drop("Ethernet")
        #expect(retention.services == ["USB LAN", "Thunderbolt Bridge"])
    }

    @Test("A preserved entry is never dropped, whatever the attempt decides about its own work")
    func preservedEntriesCannotBeDropped() {
        var retention = ProxyBackupRetention(authorized: ["Wi-Fi"], preserved: ["USB LAN"])

        retention.drop("USB LAN")

        #expect(retention.services.contains("USB LAN"))
        #expect(retention.preservedServices == ["USB LAN"])
    }

    @Test("With nothing preserved the retained set is exactly the authorized one")
    func wholeBackupRestoreIsUnchanged() {
        var retention = ProxyBackupRetention(authorized: ["Wi-Fi", "Ethernet"], preserved: [])

        retention.drop("Wi-Fi")

        #expect(retention.services == ["Ethernet"])
    }

    @Test("An entry this attempt captured for a service it never touched does not outlive it")
    func freshlyCapturedUntouchedEntriesAreNotKept() {
        // The attempt found a restore point for USB LAN already on disk and captured one for
        // Thunderbolt Bridge itself. Both are preserved while it runs, because a crash in
        // between must never be the moment an untouched service loses its only restore point.
        let retention = ProxyBackupRetention(
            authorized: ["Wi-Fi", "Ethernet"],
            preserved: ["USB LAN", "Thunderbolt Bridge"],
            preAttemptServices: ["USB LAN"]
        )

        #expect(retention.services == ["Wi-Fi", "Ethernet", "USB LAN", "Thunderbolt Bridge"])

        // Once it has finished, only the entry that predates it may stay. Thunderbolt Bridge was
        // never overridden, so its snapshot describes settings nobody changed — keeping it is
        // what would let the next enable write it back over whatever the user has set since.
        #expect(retention.preservedServicesPredatingAttempt == ["USB LAN"])
        #expect(retention.retainedAfterAttempt(unresolvedServices: []) == ["USB LAN"])
    }

    @Test("A rollback that could not finish keeps the touched services and the older entries")
    func anIncompleteRollbackKeepsBothKinds() {
        let retention = ProxyBackupRetention(
            authorized: ["Wi-Fi", "Ethernet"],
            preserved: ["USB LAN", "Thunderbolt Bridge"],
            preAttemptServices: ["USB LAN"]
        )

        #expect(
            retention.retainedAfterAttempt(unresolvedServices: ["Wi-Fi"]) == ["Wi-Fi", "USB LAN"]
        )
    }

    @Test("An attempt that captured nothing keeps every preserved entry")
    func anAttemptThatCapturedNothingKeepsEverything() {
        // No pre-attempt set is recorded when the caller captured nothing, which is the case for
        // a plain disable or a launch-time recovery: every entry it sees predates it.
        let retention = ProxyBackupRetention(authorized: ["Wi-Fi"], preserved: ["USB LAN"])

        #expect(retention.preservedServicesPredatingAttempt == ["USB LAN"])
        #expect(retention.retainedAfterAttempt(unresolvedServices: []) == ["USB LAN"])
    }
}

// MARK: - ProxyOverrideApplicationRecoveryPolicyTests

/// A crash in the middle of the seven-command override leaves a service that is neither Rockxy's
/// nor the user's. These cover what the durable record of that attempt does and does not
/// authorize once a relaunch or a watchdog reads it back.
struct ProxyOverrideApplicationRecoveryPolicyTests {
    // MARK: Internal

    @Test("A service no command reached is reported as untouched, not rolled back")
    func aServiceNoCommandReachedIsUntouched() {
        // The record is written before the first command, so `applying` on its own proves
        // nothing: the settings still reading exactly as captured is what proves nothing landed.
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying),
                live: ProxyRecoveryJournalFixtures.capturedSettings,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .untouched
        )
    }

    @Test("Every point the override sequence stops at authorizes the rollback")
    func everyOrderedPrefixIsRolledBack() {
        let states = ProxyOverrideTransition.reachableStates(
            from: ProxyRecoveryJournalFixtures.capturedSettings,
            port: ProxyRecoveryJournalFixtures.rockxyPort
        )

        for live in states where live != ProxyRecoveryJournalFixtures.capturedSettings {
            let continuation = ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying),
                live: live,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            )
            // The baseline a rollback starts from is what is live now, not what was captured:
            // the restore it is about to run has to record the state it actually begins at.
            #expect(continuation == .rollBack(baseline: live))
        }
    }

    @Test("Strict ownership alone would miss a service stopped after its first command")
    func halfAppliedServiceIsNotOwnedButIsStillRecoverable() {
        // Only the HTTP endpoint was written. `isOwnedByRockxy` requires both web proxies on the
        // loopback port, so it reports this service as nobody's — which is exactly why the
        // record has to carry the authorization instead.
        let halfApplied = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.capturedSettings,
            http: ProxyEndpointState(
                enabled: true,
                host: ProxyOverrideTransition.loopbackHost,
                port: ProxyRecoveryJournalFixtures.rockxyPort
            )
        )

        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            halfApplied.overrideState,
            port: ProxyRecoveryJournalFixtures.rockxyPort
        ))
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying),
                live: halfApplied,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .rollBack(baseline: halfApplied)
        )
    }

    @Test("A captured bypass of * survives the override and still authorizes the rollback")
    func aCapturedGlobalBypassIsHandled() {
        // Applying the override never writes the bypass list, so a user who had `*` still has it
        // afterwards — and `isOwnedByRockxy` refuses a global bypass outright. The record covers
        // the case without loosening that refusal anywhere else.
        let captured = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.capturedSettings,
            bypassDomains: ["*"]
        )
        let live = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.rockxyOverride,
            bypassDomains: ["*"]
        )

        #expect(ProxyOverrideTransition.isReachedByApplying(
            live,
            from: captured,
            port: ProxyRecoveryJournalFixtures.rockxyPort
        ))
        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            live.overrideState,
            port: ProxyRecoveryJournalFixtures.rockxyPort
        ))
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying, captured: captured),
                live: live,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .rollBack(baseline: live)
        )
    }

    @Test("A finished override whose bypass list Rockxy replaced is recoverable from the record of it")
    func aBypassListWrittenAfterTheOverrideIsStillOwned() {
        // The bounded bypass list is written after the seven commands, so this shape is not one of
        // their prefixes. The record names the list before that command runs, which is what puts
        // the finished shape back inside the sequence rather than outside it.
        let rockxyBypass = ["localhost", "127.0.0.1"]
        let live = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.rockxyOverride,
            bypassDomains: rockxyBypass
        )

        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying, appliedBypassDomains: rockxyBypass),
                live: live,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .rollBack(baseline: live)
        )
    }

    @Test("A bypass list no record names is not Rockxy's to undo, whatever the web proxies say")
    func anUnrecordedBypassListIsAbandoned() {
        // Both web proxies point at Rockxy's loopback port, which is all the ownership projection
        // ever asked for — and on that alone the whole captured snapshot used to be written back
        // over a bypass list nothing had shown was Rockxy's.
        let live = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.rockxyOverride,
            bypassDomains: ["intranet.corp.example"]
        )

        #expect(ProxyOverrideOwnership.isOwnedByRockxy(
            live.overrideState,
            port: ProxyRecoveryJournalFixtures.rockxyPort
        ))
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying),
                live: live,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .abandon
        )
    }

    @Test("A bypass list edited after the override is not the one the record names")
    func aUserEditedBypassListIsAbandoned() {
        let rockxyBypass = ["localhost", "127.0.0.1"]
        let live = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.rockxyOverride,
            bypassDomains: rockxyBypass + ["intranet.corp.example"]
        )

        // Not a global bypass, so the projection still calls this service Rockxy's. The record
        // names the exact list, and this is not it.
        #expect(ProxyOverrideOwnership.isOwnedByRockxy(
            live.overrideState,
            port: ProxyRecoveryJournalFixtures.rockxyPort
        ))
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying, appliedBypassDomains: rockxyBypass),
                live: live,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .abandon
        )
    }

    @Test("A SOCKS endpoint changed while the mode is off is not something the override wrote")
    func aChangedDisabledSocksEndpointIsAbandoned() {
        // Applying the override switches SOCKS off and never touches its host or port. The
        // projection only reads the on/off flag, so a re-pointed endpoint was invisible to it —
        // and restoring the captured snapshot would have written over it.
        let live = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.rockxyOverride,
            socks: ProxyEndpointState(enabled: false, host: "socks.vpn.example", port: 1_081),
            bypassDomains: ProxyRecoveryJournalFixtures.capturedSettings.bypassDomains
        )

        #expect(ProxyOverrideOwnership.isOwnedByRockxy(
            live.overrideState,
            port: ProxyRecoveryJournalFixtures.rockxyPort
        ))
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying),
                live: live,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .abandon
        )
    }

    @Test("A PAC URL changed while PAC is off is not something the override wrote")
    func aChangedPACURLIsAbandoned() {
        let live = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.rockxyOverride,
            pacURL: "https://vpn.example/other.pac",
            bypassDomains: ProxyRecoveryJournalFixtures.capturedSettings.bypassDomains
        )

        #expect(ProxyOverrideOwnership.isOwnedByRockxy(
            live.overrideState,
            port: ProxyRecoveryJournalFixtures.rockxyPort
        ))
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying),
                live: live,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .abandon
        )
    }

    @Test("The exact state the whole sequence ends at is what authorizes the rollback")
    func theExactCompletedStateIsRolledBack() throws {
        let rockxyBypass = ["localhost"]
        let completed = try #require(ProxyOverrideTransition.completedState(
            from: ProxyRecoveryJournalFixtures.capturedSettings,
            port: ProxyRecoveryJournalFixtures.rockxyPort,
            appliedBypassDomains: rockxyBypass
        ))

        #expect(completed.bypassDomains == rockxyBypass)
        #expect(completed.socks == ProxyRecoveryJournalFixtures.capturedSettings.socks.disabled)
        #expect(completed.pacURL == ProxyRecoveryJournalFixtures.capturedSettings.pacURL)
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying, appliedBypassDomains: rockxyBypass),
                live: completed,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .rollBack(baseline: completed)
        )
    }

    @Test("A configuration the override could not have produced is left to whoever wrote it")
    func aForeignConfigurationIsAbandoned() {
        let foreign = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.capturedSettings,
            http: ProxyEndpointState(enabled: true, host: "10.0.0.9", port: 3_128)
        )

        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying),
                live: foreign,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .abandon
        )
    }

    @Test("A service whose settings could not be read is deferred rather than guessed at")
    func anUnreadableServiceIsDeferred() {
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying),
                live: nil,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .retryLater
        )
    }

    @Test("A record whose commands were never issued authorizes no changed state")
    func applicationPendingDoesNotAuthorizeAPrefix() {
        let halfApplied = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.capturedSettings,
            http: ProxyEndpointState(
                enabled: true,
                host: ProxyOverrideTransition.loopbackHost,
                port: ProxyRecoveryJournalFixtures.rockxyPort
            )
        )

        // No command was issued under this record, so both a half-applied shape and a complete
        // override belong to something else. Strict ownership only proves a completed Rockxy
        // shape; it does not prove this pending attempt produced it.
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applicationPending),
                live: halfApplied,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .abandon
        )
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applicationPending),
                live: ProxyRecoveryJournalFixtures.rockxyOverride,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .abandon
        )
    }

    @Test("A record that names a different service never authorizes a write")
    func aMismatchedServiceIsAbandoned() {
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying),
                live: ProxyRecoveryJournalFixtures.renamed(
                    ProxyRecoveryJournalFixtures.rockxyOverride,
                    to: "Ethernet"
                ),
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .abandon
        )
    }

    @Test("A restore record is never read as an override record")
    func aRestoreRecordAuthorizesNothingHere() {
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: ProxyRecoveryJournalFixtures.entry(stage: .inFlight),
                live: ProxyRecoveryJournalFixtures.rockxyOverride,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .abandon
        )
        // And the reverse: the restore policy refuses an override record outright, because the
        // states it authorizes come from a different command sequence on a different port.
        #expect(
            ProxyServiceRecoveryPolicy.continuation(
                for: applicationEntry(stage: .applying),
                live: ProxyRecoveryJournalFixtures.rockxyOverride
            ) == .abandon
        )
    }

    @Test("An override record survives a plist roundtrip with the port it was written for")
    func anOverrideRecordRoundtrips() throws {
        let entry = applicationEntry(stage: .applying)

        let data = try PropertyListEncoder().encode([entry])
        let decoded = try PropertyListDecoder().decode([ProxyServiceRecoveryJournalEntry].self, from: data)

        #expect(decoded == [entry])
        #expect(decoded.first?.appliedOverridePort == ProxyRecoveryJournalFixtures.rockxyPort)
        #expect(decoded.first?.stage == .applying)
    }

    @Test("A record written before the port existed still decodes, and authorizes nothing on its own")
    func aRecordWithoutAPortDecodes() throws {
        let portless = ProxyServiceRecoveryJournalEntry(
            service: ProxyRecoveryJournalFixtures.service,
            stage: .applying,
            expectedPreStepState: ProxyRecoveryJournalFixtures.capturedSettings,
            target: ProxyRecoveryJournalFixtures.capturedSettings
        )

        #expect(portless.appliedOverridePort == nil)
        #expect(portless.appliedBypassDomains == nil)

        let finished = try #require(ProxyOverrideTransition.completedState(
            from: ProxyRecoveryJournalFixtures.capturedSettings,
            port: ProxyRecoveryJournalFixtures.rockxyPort
        ))

        // With no port on the record and none from the backup, there is nothing to compare a
        // half-applied shape against, so the service keeps its restore point instead.
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: portless,
                live: finished,
                ownedPort: nil
            ) == .abandon
        )
        // The port the backup records stands in for it, which is what keeps an older record
        // usable rather than merely readable.
        #expect(
            ProxyOverrideApplicationRecoveryPolicy.continuation(
                for: portless,
                live: finished,
                ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
            ) == .rollBack(baseline: finished)
        )
    }

    // MARK: Private

    private func applicationEntry(
        stage: ProxyRecoveryStage,
        captured: ProxyServiceRestorationState = ProxyRecoveryJournalFixtures.capturedSettings,
        port: Int = ProxyRecoveryJournalFixtures.rockxyPort,
        appliedBypassDomains: [String]? = nil
    )
        -> ProxyServiceRecoveryJournalEntry
    {
        ProxyServiceRecoveryJournalEntry(
            overrideApplicationFor: captured,
            stage: stage,
            port: port,
            appliedBypassDomains: appliedBypassDomains
        )
    }
}

// MARK: - ProxyBypassUpdatePreflightTests

struct ProxyBypassUpdatePreflightTests {
    @Test("A bypass update keeps both sides of its per-service crash window recoverable")
    func repeatedUpdateRetainsItsPreviousExactState() throws {
        let oldDomains = ["localhost"]
        let newDomains = ["localhost", "127.0.0.1"]
        let stable = ProxyServiceRecoveryJournalEntry(
            overrideApplicationFor: ProxyRecoveryJournalFixtures.capturedSettings,
            stage: .applying,
            port: ProxyRecoveryJournalFixtures.rockxyPort,
            appliedBypassDomains: oldDomains
        )
        let oldLive = try #require(ProxyOverrideTransition.completedState(
            from: ProxyRecoveryJournalFixtures.capturedSettings,
            port: ProxyRecoveryJournalFixtures.rockxyPort,
            appliedBypassDomains: oldDomains
        ))
        let pending = stable.recordingAppliedBypassDomains(
            newDomains,
            from: oldLive.bypassDomains
        )
        let newLive = try #require(ProxyOverrideTransition.completedState(
            from: ProxyRecoveryJournalFixtures.capturedSettings,
            port: ProxyRecoveryJournalFixtures.rockxyPort,
            appliedBypassDomains: newDomains
        ))

        #expect(ProxyBypassUpdatePreflight.decision(
            entry: pending,
            live: oldLive,
            ownedPort: ProxyRecoveryJournalFixtures.rockxyPort,
            requestedDomains: newDomains
        ) == .apply(baseline: oldLive))
        #expect(ProxyBypassUpdatePreflight.decision(
            entry: pending,
            live: newLive,
            ownedPort: ProxyRecoveryJournalFixtures.rockxyPort,
            requestedDomains: newDomains
        ) == .unchanged)
        #expect(ProxyOverrideApplicationRecoveryPolicy.continuation(
            for: pending,
            live: oldLive,
            ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
        ) == .rollBack(baseline: oldLive))
        #expect(ProxyOverrideApplicationRecoveryPolicy.continuation(
            for: pending,
            live: newLive,
            ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
        ) == .rollBack(baseline: newLive))

        let completed = pending.completingAppliedBypassUpdate(at: newDomains)
        #expect(completed.previousAppliedBypassDomains == nil)
        #expect(completed.appliedBypassDomains == newDomains)
        let stabilizedOldSide = pending.completingAppliedBypassUpdate(at: oldDomains)
        #expect(stabilizedOldSide.previousAppliedBypassDomains == nil)
        #expect(stabilizedOldSide.appliedBypassDomains == oldDomains)
    }

    @Test("A bypass update refuses a service whose other proxy fields moved")
    func foreignStateIsNotWritten() throws {
        let domains = ["localhost"]
        let entry = ProxyServiceRecoveryJournalEntry(
            overrideApplicationFor: ProxyRecoveryJournalFixtures.capturedSettings,
            stage: .applying,
            port: ProxyRecoveryJournalFixtures.rockxyPort,
            appliedBypassDomains: domains
        )
        let live = try #require(ProxyOverrideTransition.completedState(
            from: ProxyRecoveryJournalFixtures.capturedSettings,
            port: ProxyRecoveryJournalFixtures.rockxyPort,
            appliedBypassDomains: domains
        ))
        let foreign = ProxyRecoveryJournalFixtures.replacing(
            live,
            pacURL: "https://other.example/config.pac"
        )

        #expect(ProxyBypassUpdatePreflight.decision(
            entry: entry,
            live: foreign,
            ownedPort: ProxyRecoveryJournalFixtures.rockxyPort,
            requestedDomains: ["127.0.0.1"]
        ) == .abort)
    }
}

// MARK: - ProxyOverrideApplicationPlanningTests

/// The planner is where an override record turns into a restore. These cover that hand-off, which
/// is what makes a crash mid-override recoverable from a relaunch or a watchdog rather than only
/// from inside the process that caused it.
struct ProxyOverrideApplicationPlanningTests {
    @Test("A half-applied service is planned for rollback from what is live, not from the capture")
    func aHalfAppliedServiceIsPlannedFromLive() {
        let halfApplied = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.capturedSettings,
            http: ProxyEndpointState(
                enabled: true,
                host: ProxyOverrideTransition.loopbackHost,
                port: ProxyRecoveryJournalFixtures.rockxyPort
            )
        )

        let plan = ProxyRecoveryPlanner.plan(
            targets: [ProxyRecoveryJournalFixtures.capturedSettings],
            journal: [ProxyServiceRecoveryJournalEntry(
                overrideApplicationFor: ProxyRecoveryJournalFixtures.capturedSettings,
                stage: .applying,
                port: ProxyRecoveryJournalFixtures.rockxyPort
            )],
            liveStates: [ProxyRecoveryJournalFixtures.service: halfApplied],
            ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.count == 1)
        // A `pending` restore record: no restore command has been issued yet, and the state it
        // begins from is the half-applied one a later retry would have to recognise.
        #expect(plan.entriesToRestore.first?.stage == .pending)
        #expect(plan.entriesToRestore.first?.expectedPreStepState == halfApplied)
        #expect(plan.entriesToRestore.first?.target == ProxyRecoveryJournalFixtures.capturedSettings)
        #expect(plan.abandonedServices.isEmpty)
    }

    @Test("A service the override never reached leaves recovery with its entry dropped")
    func anUntouchedServiceLeavesRecovery() {
        let plan = ProxyRecoveryPlanner.plan(
            targets: [ProxyRecoveryJournalFixtures.capturedSettings],
            journal: [ProxyServiceRecoveryJournalEntry(
                overrideApplicationFor: ProxyRecoveryJournalFixtures.capturedSettings,
                stage: .applying,
                port: ProxyRecoveryJournalFixtures.rockxyPort
            )],
            liveStates: [
                ProxyRecoveryJournalFixtures.service: ProxyRecoveryJournalFixtures.capturedSettings,
            ],
            ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.completedServices == [ProxyRecoveryJournalFixtures.service])
        #expect(plan.servicesKeepingBackup.isEmpty)
    }

    @Test("A user change after the crash keeps its settings and its restore point")
    func aUserChangeAfterTheCrashIsNeverOverwritten() {
        let userConfiguration = ProxyRecoveryJournalFixtures.replacing(
            ProxyRecoveryJournalFixtures.capturedSettings,
            https: ProxyEndpointState(enabled: true, host: "vpn.example", port: 3_128)
        )

        let plan = ProxyRecoveryPlanner.plan(
            targets: [ProxyRecoveryJournalFixtures.capturedSettings],
            journal: [ProxyServiceRecoveryJournalEntry(
                overrideApplicationFor: ProxyRecoveryJournalFixtures.capturedSettings,
                stage: .applying,
                port: ProxyRecoveryJournalFixtures.rockxyPort
            )],
            liveStates: [ProxyRecoveryJournalFixtures.service: userConfiguration],
            ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.abandonedServices == [ProxyRecoveryJournalFixtures.service])
    }

    @Test("A service whose full state could not be read is deferred with its backup intact")
    func anUnreadableServiceKeepsItsRestorePoint() {
        let plan = ProxyRecoveryPlanner.plan(
            targets: [ProxyRecoveryJournalFixtures.capturedSettings],
            journal: [ProxyServiceRecoveryJournalEntry(
                overrideApplicationFor: ProxyRecoveryJournalFixtures.capturedSettings,
                stage: .applicationPending,
                port: ProxyRecoveryJournalFixtures.rockxyPort
            )],
            liveStates: [:],
            ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.deferredServices == [ProxyRecoveryJournalFixtures.service])
        #expect(plan.servicesKeepingBackup == [ProxyRecoveryJournalFixtures.service])
    }

    @Test("An override record that describes some other capture is not this backup's to act on")
    func aStaleOverrideRecordIsNotTrusted() {
        // The record names the same service but a different capture, so it belongs to an earlier
        // attempt. The service falls back to the proof any unrecorded service has to give.
        let plan = ProxyRecoveryPlanner.plan(
            targets: [ProxyRecoveryJournalFixtures.capturedSettings],
            journal: [ProxyServiceRecoveryJournalEntry(
                overrideApplicationFor: ProxyRecoveryJournalFixtures.replacing(
                    ProxyRecoveryJournalFixtures.capturedSettings,
                    bypassDomains: ["something.else"]
                ),
                stage: .applying,
                port: ProxyRecoveryJournalFixtures.rockxyPort
            )],
            liveStates: [
                ProxyRecoveryJournalFixtures.service: ProxyRecoveryJournalFixtures.rockxyOverride,
            ],
            ownedPort: ProxyRecoveryJournalFixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.count == 1)
        #expect(plan.entriesToRestore.first?.expectedPreStepState == ProxyRecoveryJournalFixtures.rockxyOverride)
    }
}

// MARK: - ProxyJournaledServiceRestoreTests

/// The `inFlight` record is the permission to issue a command, not a note about one that already
/// ran. These cover that order in both directions.
struct ProxyJournaledServiceRestoreTests {
    @Test("The record is committed before the first rollback command runs")
    func theRecordIsCommittedFirst() {
        var steps: [String] = []
        let attempt = ProxyJournaledServiceRestore.run(
            commitInFlight: { steps.append("commit") },
            restore: {
                steps.append("restore")
                return .restored
            }
        )

        #expect(steps == ["commit", "restore"])
        guard case .issued = attempt else {
            Issue.record("expected the commands to be issued")
            return
        }
    }

    @Test("A record that could not be committed issues no command at all")
    func aFailedCommitIssuesNothing() {
        var restoreRan = false
        let attempt = ProxyJournaledServiceRestore.run(
            commitInFlight: { throw RestoreStepError.failed },
            restore: {
                restoreRan = true
                return .restored
            }
        )

        // An unrecorded write is exactly the case a resumed attempt has no way to reason about:
        // it would believe a command may have run when none did.
        #expect(!restoreRan)
        guard case .notIssued = attempt else {
            Issue.record("expected no command to be issued")
            return
        }
    }

    @Test("A failed command is reported as the step it stopped at")
    func aFailedCommandIsReported() {
        let attempt = ProxyJournaledServiceRestore.run(
            commitInFlight: {},
            restore: { .failed(step: .proxyState, error: RestoreStepError.failed) }
        )

        guard case let .issued(outcome) = attempt else {
            Issue.record("expected the commands to be issued")
            return
        }
        #expect(outcome.failedStep == .proxyState)
    }
}

// MARK: - ProxyRecoveryPlannerTests

struct ProxyRecoveryPlannerTests {
    // MARK: Internal

    @Test("A first attempt baselines a service the live settings still prove is Rockxy's")
    func firstAttemptBaselinesAServiceRockxyStillOwns() {
        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [],
            liveStates: [Fixtures.service: Fixtures.rockxyOverride],
            ownedPort: Fixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.map(\.service) == [Fixtures.service])
        // The entry is handed back — and persisted — at `pending`. Nothing has been issued for
        // this service yet, and only the command that is about to run may advance it.
        #expect(plan.entriesToRestore.first?.stage == .pending)
        #expect(plan.entriesToRestore.first?.expectedPreStepState == Fixtures.rockxyOverride)
        #expect(plan.entriesToRestore.first?.expectedPostStepState == Fixtures.restoredSettings)
        #expect(plan.abandonedServices.isEmpty)
        #expect(plan.completedServices.isEmpty)
        #expect(plan.deferredServices.isEmpty)
    }

    @Test("A first attempt never baselines settings that are not Rockxy's own override")
    func firstAttemptDoesNotBaselineAForeignState() {
        // The user (or another proxy app) configured this service while capture was running. It
        // is readable, and on a first attempt there is no record to contradict it — which is
        // exactly the state that used to be adopted as "where the restore begins" and then
        // written over with a snapshot the user never asked for.
        let userProxy = Fixtures.replacing(
            Fixtures.rockxyOverride,
            http: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
            https: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
            bypassDomains: ["*.staging.internal"]
        )

        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [],
            liveStates: [Fixtures.service: userProxy],
            ownedPort: Fixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.deferredServices == [Fixtures.service])
        #expect(plan.servicesKeepingBackup == [Fixtures.service])
    }

    @Test("A legacy ownership projection cannot overwrite fields the override never changed")
    func legacyProjectionDoesNotAuthorizeAFullRestore() {
        let foreignStates = [
            Fixtures.replacing(Fixtures.rockxyOverride, bypassDomains: ["intranet.example"]),
            Fixtures.replacing(
                Fixtures.rockxyOverride,
                socks: ProxyEndpointState(enabled: false, host: "new-socks.example", port: 10_80)
            ),
            Fixtures.replacing(Fixtures.rockxyOverride, pacURL: "https://config.example/new.pac"),
        ]

        for live in foreignStates {
            // All three still satisfy the narrow HTTP/HTTPS ownership projection. None equals the
            // complete state of the recorded override sequence, so restoring a full captured
            // snapshot would overwrite a field this backup cannot prove it changed.
            #expect(ProxyOverrideOwnership.isOwnedByRockxy(
                live.overrideState,
                port: Fixtures.rockxyPort
            ))
            let plan = ProxyRecoveryPlanner.plan(
                targets: [Fixtures.capturedSettings],
                journal: [],
                liveStates: [Fixtures.service: live],
                ownedPort: Fixtures.rockxyPort
            )
            #expect(plan.entriesToRestore.isEmpty)
            #expect(plan.deferredServices == [Fixtures.service])
        }
    }

    @Test("A half-applied override is not proof of ownership either")
    func firstAttemptDoesNotBaselineAPartiallyOverriddenState() {
        // HTTP points at Rockxy but HTTPS never got there. Nothing about this shape says who
        // wrote it, so it is not a starting point recovery may claim.
        let halfApplied = Fixtures.replacing(
            Fixtures.rockxyOverride,
            https: ProxyEndpointState(enabled: false, host: "secure.corp.example", port: 8_443)
        )

        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [],
            liveStates: [Fixtures.service: halfApplied],
            ownedPort: Fixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.deferredServices == [Fixtures.service])
    }

    @Test("An override on another port is not this backup's to restore")
    func aDifferentPortIsNotBaselined() {
        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [],
            liveStates: [Fixtures.service: Fixtures.rockxyOverride],
            ownedPort: Fixtures.rockxyPort + 1
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.deferredServices == [Fixtures.service])
    }

    @Test("A backup that cannot name its port baselines nothing")
    func anUnknownPortBaselinesNothing() {
        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [],
            liveStates: [Fixtures.service: Fixtures.rockxyOverride],
            ownedPort: nil
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.deferredServices == [Fixtures.service])
    }

    @Test("Every state the override's own commands pass through may be undone by the process that wrote it")
    func aHalfAppliedOverrideIsBaselinedFromItsOwnTransition() {
        // An override that stopped part-way leaves a shape strict ownership does not recognise.
        // Refusing it a baseline would strand exactly the service that most needs putting back —
        // but only the states the override sequence really produces earn one.
        let prefixes = ProxyOverrideTransition.reachableStates(
            from: Fixtures.capturedSettings,
            port: Fixtures.rockxyPort
        )
        .dropFirst()

        for halfApplied in prefixes {
            let plan = ProxyRecoveryPlanner.plan(
                targets: [Fixtures.capturedSettings],
                journal: [],
                liveStates: [Fixtures.service: halfApplied],
                ownedPort: Fixtures.rockxyPort,
                locallyMutatedServices: [Fixtures.service]
            )

            #expect(plan.entriesToRestore.map(\.service) == [Fixtures.service])
            #expect(plan.entriesToRestore.first?.expectedPreStepState == halfApplied)
            #expect(plan.deferredServices.isEmpty)
        }
    }

    @Test("Having touched a service is not on its own a licence to write over what is there now")
    func aTouchedServiceWithAForeignStateIsNeverOverwritten() {
        // A service is recorded as touched before its first command runs. If that command failed
        // and somebody else changed the service in the meantime, the live settings are not a
        // state the override sequence produces — and the change stays exactly where it is.
        let foreign = Fixtures.replacing(
            Fixtures.capturedSettings,
            http: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
            https: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128)
        )

        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [],
            liveStates: [Fixtures.service: foreign],
            ownedPort: Fixtures.rockxyPort,
            locallyMutatedServices: [Fixtures.service]
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.abandonedServices.isEmpty)
        // Deferred, not abandoned: the restore point survives for an attempt that can prove
        // something about this service.
        #expect(plan.deferredServices == [Fixtures.service])
    }

    @Test("A first override command that changed nothing leaves the service alone")
    func aTouchedServiceThatWasNeverMutatedIsNotWritten() {
        // The very first command failed, so the service still reads exactly as it was captured.
        // There is nothing to undo, and issuing the restore anyway would write settings onto a
        // service this attempt never changed.
        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [],
            liveStates: [Fixtures.service: Fixtures.capturedSettings],
            ownedPort: Fixtures.rockxyPort,
            locallyMutatedServices: [Fixtures.service]
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.completedServices == [Fixtures.service])
        #expect(plan.deferredServices.isEmpty)
    }

    @Test("A service this process did not write is judged on ownership alone")
    func anUntouchedServiceGetsNoTransitionProof() {
        let halfApplied = Fixtures.replacing(
            Fixtures.capturedSettings,
            http: ProxyEndpointState(enabled: true, host: "127.0.0.1", port: Fixtures.rockxyPort)
        )

        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [],
            liveStates: [Fixtures.service: halfApplied],
            ownedPort: Fixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.deferredServices == [Fixtures.service])
    }

    @Test("One user-changed service does not strand the ones that still need recovery")
    func partiallyRestoredServicesAreNotAbandonedWithTheChangedOne() {
        let changed = renamed(Fixtures.rockxyOverride, to: "Ethernet")
        let userProxy = ProxyRecoveryJournalFixtures.replacing(
            changed,
            http: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
            https: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128)
        )
        let done = renamed(Fixtures.rockxyOverride, to: "USB LAN")

        let plan = ProxyRecoveryPlanner.plan(
            targets: [
                Fixtures.capturedSettings,
                renamed(Fixtures.capturedSettings, to: "Ethernet"),
                renamed(Fixtures.capturedSettings, to: "USB LAN"),
                renamed(Fixtures.capturedSettings, to: "Thunderbolt Bridge"),
            ],
            journal: [
                Fixtures.entry(stage: .inFlight),
                Fixtures.entry(stage: .inFlight, pre: changed, target: renamed(
                    Fixtures.capturedSettings,
                    to: "Ethernet"
                )),
                Fixtures.entry(stage: .restored, pre: done, target: renamed(
                    Fixtures.capturedSettings,
                    to: "USB LAN"
                )),
            ],
            liveStates: [
                Fixtures.service: Fixtures.rockxyOverride.withProxyModesDisabled,
                "Ethernet": userProxy,
                "USB LAN": ProxyServiceRestorationState.expectedRestorationResult(
                    target: renamed(Fixtures.capturedSettings, to: "USB LAN"),
                    from: done
                ),
            ],
            ownedPort: Fixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.map(\.service) == [Fixtures.service])
        #expect(plan.abandonedServices == ["Ethernet"])
        #expect(plan.completedServices == ["USB LAN"])
        #expect(plan.deferredServices == ["Thunderbolt Bridge"])
        // A finished or foreign service leaves recovery; an unreadable one keeps its restore point.
        #expect(plan.servicesKeepingBackup == [Fixtures.service, "Thunderbolt Bridge"])
    }

    @Test("A record that no longer describes the backup on disk is never trusted")
    func staleJournalRecordIsNeverTrusted() {
        let staleTarget = ProxyRecoveryJournalFixtures.replacing(
            Fixtures.capturedSettings,
            http: ProxyEndpointState(enabled: true, host: "old.corp.example", port: 3_128)
        )
        // The record describes a different restore than the backup asks for, so it says nothing
        // about what the live settings mean. With a live state that proves nothing either, the
        // service keeps its restore point rather than acquiring a baseline.
        let userProxy = Fixtures.replacing(
            Fixtures.rockxyOverride,
            http: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
            https: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128)
        )

        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [Fixtures.entry(stage: .restored, target: staleTarget)],
            liveStates: [Fixtures.service: userProxy],
            ownedPort: Fixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.deferredServices == [Fixtures.service])
        #expect(plan.abandonedServices.isEmpty)
        #expect(plan.servicesKeepingBackup == [Fixtures.service])
    }

    @Test("A stale record does not stop a service Rockxy provably still owns from recovering")
    func staleJournalRecordIsReplacedOnlyByProvenOwnership() {
        let staleTarget = ProxyRecoveryJournalFixtures.replacing(
            Fixtures.capturedSettings,
            http: ProxyEndpointState(enabled: true, host: "old.corp.example", port: 3_128)
        )

        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [Fixtures.entry(stage: .restored, target: staleTarget)],
            liveStates: [Fixtures.service: Fixtures.rockxyOverride],
            ownedPort: Fixtures.rockxyPort
        )

        // The service still carries the strict override, and no restore can produce that shape
        // once it has started — so nothing has been written to this service yet and a fresh
        // baseline is the truth, not a guess. The stale record itself is discarded.
        #expect(plan.entriesToRestore.map(\.service) == [Fixtures.service])
        #expect(plan.entriesToRestore.first?.stage == .pending)
        #expect(plan.entriesToRestore.first?.target == Fixtures.capturedSettings)
        #expect(plan.entriesToRestore.first?.expectedPreStepState == Fixtures.rockxyOverride)
    }

    @Test("A service with neither a record nor a readable state keeps its restore point")
    func unreadableServiceWithoutARecordIsDeferred() {
        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings],
            journal: [],
            liveStates: [:],
            ownedPort: Fixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.deferredServices == [Fixtures.service])
        #expect(plan.abandonedServices.isEmpty)
    }

    @Test("A pending backup with no readable journal still recovers the services Rockxy owns")
    func pendingBackupWithoutAJournalRecoversStrictlyOwnedServices() {
        // A backup written before the journal existed — or one whose journal this build could not
        // read — arrives with no records at all. The services that still carry the strict
        // override are provably Rockxy's, so they recover; the one the user re-pointed does not.
        let userProxy = Fixtures.renamed(
            Fixtures.replacing(
                Fixtures.rockxyOverride,
                http: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
                https: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128)
            ),
            to: "USB LAN"
        )

        let plan = ProxyRecoveryPlanner.plan(
            targets: [
                Fixtures.capturedSettings,
                Fixtures.renamed(Fixtures.capturedSettings, to: "Ethernet"),
                Fixtures.renamed(Fixtures.capturedSettings, to: "USB LAN"),
            ],
            journal: [],
            liveStates: [
                Fixtures.service: Fixtures.rockxyOverride,
                "Ethernet": Fixtures.renamed(Fixtures.rockxyOverride, to: "Ethernet"),
                "USB LAN": userProxy,
            ],
            ownedPort: Fixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.map(\.service) == [Fixtures.service, "Ethernet"])
        #expect(plan.entriesToRestore.allSatisfy { $0.stage == .pending })
        #expect(plan.deferredServices == ["USB LAN"])
        #expect(plan.abandonedServices.isEmpty)
    }

    @Test("One unusable record does not stop the services whose records are still good")
    func oneUnusableRecordDoesNotBlockTheOthers() {
        let ethernetTarget = Fixtures.renamed(Fixtures.capturedSettings, to: "Ethernet")
        let ethernetOverride = Fixtures.renamed(Fixtures.rockxyOverride, to: "Ethernet")
        let staleEthernetTarget = ProxyRecoveryJournalFixtures.replacing(
            ethernetTarget,
            https: ProxyEndpointState(enabled: true, host: "old.corp.example", port: 3_128)
        )
        let ethernetUserProxy = ProxyRecoveryJournalFixtures.replacing(
            ethernetOverride,
            http: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
            https: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128)
        )

        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings, ethernetTarget],
            journal: [
                Fixtures.entry(stage: .inFlight),
                Fixtures.entry(
                    stage: .inFlight,
                    pre: ethernetOverride,
                    target: staleEthernetTarget
                ),
            ],
            liveStates: [
                Fixtures.service: Fixtures.rockxyOverride,
                "Ethernet": ethernetUserProxy,
            ],
            ownedPort: Fixtures.rockxyPort
        )

        #expect(plan.entriesToRestore.map(\.service) == [Fixtures.service])
        #expect(plan.deferredServices == ["Ethernet"])
        #expect(plan.abandonedServices.isEmpty)
        #expect(plan.servicesKeepingBackup == [Fixtures.service, "Ethernet"])
    }

    @Test("A service the restore never reached stays pending, and a prefix match cannot claim it")
    func untouchedServiceStaysPendingAcrossACrash() throws {
        let ethernetTarget = Fixtures.renamed(Fixtures.capturedSettings, to: "Ethernet")
        let ethernetOverride = Fixtures.renamed(Fixtures.rockxyOverride, to: "Ethernet")

        // Both services are planned and persisted together, each at the stage it was planned at.
        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings, ethernetTarget],
            journal: [],
            liveStates: [
                Fixtures.service: Fixtures.rockxyOverride,
                "Ethernet": ethernetOverride,
            ],
            ownedPort: Fixtures.rockxyPort
        )
        #expect(plan.entriesToRestore.map(\.stage) == [.pending, .pending])

        // Wi-Fi is advanced to `inFlight` immediately before its first command; the process then
        // dies while writing it. Ethernet was never issued a command, so its record is still
        // `pending` on disk.
        let persistedJournal = plan.entriesToRestore.map {
            $0.service == Fixtures.service ? $0.advanced(to: .inFlight) : $0
        }
        #expect(persistedJournal.map(\.stage) == [.inFlight, .pending])

        // The user then switches Ethernet's proxies off — which happens to be the very first
        // shape Ethernet's own restore would have passed through. A record that claimed the
        // commands had started would read that as its own interrupted work and write over it.
        let userDisabledEthernet = ethernetOverride.withProxyModesDisabled
        let ethernetEntry = try #require(persistedJournal.first { $0.service == "Ethernet" })

        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: ethernetEntry,
            live: userDisabledEthernet
        ) == .abandon)
        // The same live settings against a record that claimed the commands had started would be
        // written over instead, which is exactly what persisting every service as in-flight up
        // front used to do.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: ethernetEntry.advanced(to: .inFlight),
            live: userDisabledEthernet
        ) == .restore)
    }

    @Test("A service deferred on the first attempt is not baselined from a foreign state later")
    func previouslyDeferredServiceStaysDeferred() {
        let ethernetTarget = Fixtures.renamed(Fixtures.capturedSettings, to: "Ethernet")
        let ethernetOverride = Fixtures.renamed(Fixtures.rockxyOverride, to: "Ethernet")

        // First attempt: Ethernet could not be read, so it was deferred and only Wi-Fi entered
        // the journal.
        let firstAttempt = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings, ethernetTarget],
            journal: [],
            liveStates: [Fixtures.service: Fixtures.rockxyOverride],
            ownedPort: Fixtures.rockxyPort
        )
        #expect(firstAttempt.entriesToRestore.map(\.service) == [Fixtures.service])
        #expect(firstAttempt.deferredServices == ["Ethernet"])

        // Second attempt: Ethernet reads fine now, but what it reads is somebody else's proxy.
        // Recording that as where its restore begins is what would put the user's own settings
        // under a snapshot they never asked for.
        let ethernetUserProxy = ProxyRecoveryJournalFixtures.replacing(
            ethernetOverride,
            http: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
            https: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128)
        )
        let secondAttempt = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings, ethernetTarget],
            journal: firstAttempt.entriesToRestore.map { $0.advanced(to: .inFlight) },
            liveStates: [
                Fixtures.service: Fixtures.rockxyOverride.withProxyModesDisabled,
                "Ethernet": ethernetUserProxy,
            ],
            ownedPort: Fixtures.rockxyPort
        )

        #expect(secondAttempt.entriesToRestore.map(\.service) == [Fixtures.service])
        #expect(secondAttempt.deferredServices == ["Ethernet"])
        #expect(secondAttempt.abandonedServices.isEmpty)
    }

    @Test("A service that changes between planning and its first command is dropped, not written")
    func serviceChangedAfterPlanningIsDroppedWithoutStrandingTheOther() throws {
        let ethernetTarget = Fixtures.renamed(Fixtures.capturedSettings, to: "Ethernet")
        let ethernetOverride = Fixtures.renamed(Fixtures.rockxyOverride, to: "Ethernet")

        let plan = ProxyRecoveryPlanner.plan(
            targets: [Fixtures.capturedSettings, ethernetTarget],
            journal: [],
            liveStates: [
                Fixtures.service: Fixtures.rockxyOverride,
                "Ethernet": ethernetOverride,
            ],
            ownedPort: Fixtures.rockxyPort
        )
        #expect(plan.entriesToRestore.map(\.service) == [Fixtures.service, "Ethernet"])

        // Wi-Fi is written first. While that is happening the user re-points Ethernet, so the
        // re-read that runs immediately before Ethernet's first command sees something the plan
        // never described. Wi-Fi still restores; Ethernet leaves recovery without being touched.
        let userProxy = ProxyRecoveryJournalFixtures.replacing(
            ethernetOverride,
            http: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128),
            https: ProxyEndpointState(enabled: true, host: "10.0.0.5", port: 3_128)
        )
        let preflight = plan.entriesToRestore.map { entry in
            ProxyServiceRecoveryPolicy.continuation(
                for: entry,
                live: entry.service == "Ethernet" ? userProxy : Fixtures.rockxyOverride
            )
        }

        #expect(preflight == [.restore, .abandon])

        // An unreadable service at the same moment keeps its restore point rather than losing it.
        #expect(ProxyServiceRecoveryPolicy.continuation(
            for: try #require(plan.entriesToRestore.first { $0.service == "Ethernet" }),
            live: nil
        ) == .retryLater)
    }

    // MARK: Private

    private typealias Fixtures = ProxyRecoveryJournalFixtures

    private func renamed(
        _ state: ProxyServiceRestorationState,
        to service: String
    )
        -> ProxyServiceRestorationState
    {
        ProxyRecoveryJournalFixtures.renamed(state, to: service)
    }
}

// MARK: - ProxyServiceRestoreExecutionTests

/// The restore of one service is an ordered sequence, and the bypass list is the last thing in
/// it. These cover the part of that order a failure has to respect.
struct ProxyServiceRestoreExecutionTests {
    @Test("A completed restore writes the proxy state and then the bypass list")
    func bothStepsRunInOrder() {
        var steps: [ProxyServiceRestoreStep] = []
        let outcome = ProxyServiceRestoreExecution.run(
            proxyState: { steps.append(.proxyState) },
            bypassDomains: { steps.append(.bypassDomains) }
        )

        #expect(steps == [.proxyState, .bypassDomains])
        #expect(outcome.failedStep == nil)
    }

    @Test("A failed proxy-state command is never followed by the bypass list")
    func bypassIsNotWrittenAfterAProxyStateFailure() {
        var bypassWasWritten = false
        let outcome = ProxyServiceRestoreExecution.run(
            proxyState: { throw RestoreStepError.failed },
            bypassDomains: { bypassWasWritten = true }
        )

        // Writing the bypass list on top of a half-written proxy state leaves a shape no prefix
        // of the restore sequence produces, and a later attempt has to read those as somebody
        // else's work — which is how a service loses its automatic recovery.
        #expect(!bypassWasWritten)
        #expect(outcome.failedStep == .proxyState)
        #expect(outcome.error != nil)
    }

    @Test("A failed bypass write is reported as the step it was")
    func bypassFailureIsReported() {
        let outcome = ProxyServiceRestoreExecution.run(
            proxyState: {},
            bypassDomains: { throw RestoreStepError.failed }
        )

        #expect(outcome.failedStep == .bypassDomains)
    }
}

// MARK: - RestoreStepError

private enum RestoreStepError: Error {
    case failed
}

// MARK: - ProxyBackupFilePublicationTests

/// A journal write is the permission to issue a command. These cover the one property that makes
/// that safe: a reported failure can never have left the new record on disk.
struct ProxyBackupFilePublicationTests {
    // MARK: Internal

    @Test("A published backup is readable and owner-only")
    func publishedFileIsOwnerOnly() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("proxy-backup.plist")

        try ProxyBackupFilePublication.publish(Data("in-flight".utf8), to: url)

        let published = try Data(contentsOf: url)
        #expect(published == Data("in-flight".utf8))
        let permissions = try FileManager.default
            .attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.int16Value == 0o600)
    }

    @Test("A failed commit leaves the previous record exactly where it was")
    func aFailedCommitPublishesNothing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("proxy-backup.plist")

        #expect(throws: (any Error).self) {
            try ProxyBackupFilePublication.publish(Data("in-flight".utf8), to: url)
        }

        // Nothing published, and no half-written temporary left behind for a later read to find.
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers.isEmpty)
    }

    @Test("An in-flight record replaces a pending one only when the commit succeeds")
    func aFailedCommitCannotAdvanceTheRecordOnDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("proxy-backup.plist")
        let pendingRecord = try encoded(stage: .pending)
        try ProxyBackupFilePublication.publish(pendingRecord, to: url)

        // The directory is made unwritable, so the temporary file cannot even be created — the
        // same shape as any failure before the rename.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        }

        let inFlightRecord = try encoded(stage: .inFlight)
        #expect(throws: (any Error).self) {
            try ProxyBackupFilePublication.publish(inFlightRecord, to: url)
        }

        // A caller that reads the throw as "no command may have run" must be right: a resumed
        // attempt still sees `pending`, which authorizes only the exact recorded state.
        let onDiskData = try Data(contentsOf: url)
        let onDisk = try PropertyListDecoder()
            .decode([ProxyServiceRecoveryJournalEntry].self, from: onDiskData)
        #expect(onDisk.first?.stage == .pending)
    }

    // MARK: Private

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-proxy-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    private func encoded(stage: ProxyRecoveryStage) throws -> Data {
        try PropertyListEncoder().encode([ProxyRecoveryJournalFixtures.entry(stage: stage)])
    }
}
