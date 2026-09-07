import Foundation
@testable import Rockxy
import Testing

// Regression tests for the check that runs immediately before a service's first override command:
// what the capture in a backup still authorizes once the machine has moved on from it.

// MARK: - ProxyOverrideApplicationPreflightTests

struct ProxyOverrideApplicationPreflightTests {
    // MARK: Internal

    @Test("A service still reading exactly as captured is written from that capture")
    func aFreshServiceIsWritable() {
        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: Fixtures.capturedSettings,
                priorEntry: nil,
                port: Fixtures.rockxyPort
            ) == .apply(baseline: Fixtures.capturedSettings)
        )
    }

    @Test("A service changed since it was captured is left with no command issued against it")
    func aChangedFreshServiceIsAborted() {
        // The capture was taken moments ago and the user has re-pointed the service since. Writing
        // now would put the override over a configuration nothing recorded, and leave the rollback
        // aiming at a snapshot that no longer describes anything on the machine.
        let userProxy = Fixtures.replacing(
            Fixtures.capturedSettings,
            https: ProxyEndpointState(enabled: true, host: "vpn.example", port: 3_128)
        )

        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: userProxy,
                priorEntry: nil,
                port: Fixtures.rockxyPort
            ) == .abort
        )
    }

    @Test("A reclaim is written from the override already on the machine, not from the capture")
    func aReclaimBaselinesFromTheLiveOverride() throws {
        // The previous session's override is still in place, so the sequence about to run starts
        // there. The record it commits has to say so — while still naming the pre-Rockxy capture
        // as what a rollback puts back.
        let rockxyBypass = ["localhost"]
        let live = try #require(ProxyOverrideTransition.completedState(
            from: Fixtures.capturedSettings,
            port: Fixtures.rockxyPort,
            appliedBypassDomains: rockxyBypass
        ))

        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: live,
                priorEntry: applicationEntry(stage: .applying, appliedBypassDomains: rockxyBypass),
                port: Fixtures.rockxyPort
            ) == .apply(baseline: live)
        )
    }

    @Test("A reclaim resumes from a sequence that stopped part-way")
    func aReclaimBaselinesFromAHalfAppliedService() {
        let halfApplied = Fixtures.replacing(
            Fixtures.capturedSettings,
            http: ProxyEndpointState(
                enabled: true,
                host: ProxyOverrideTransition.loopbackHost,
                port: Fixtures.rockxyPort
            )
        )

        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: halfApplied,
                priorEntry: applicationEntry(stage: .applying),
                port: Fixtures.rockxyPort
            ) == .apply(baseline: halfApplied)
        )
    }

    @Test("A record whose commands were never issued authorizes no changed state")
    func anApplicationPendingRecordDoesNotAuthorizeAReclaim() {
        let halfApplied = Fixtures.replacing(
            Fixtures.capturedSettings,
            http: ProxyEndpointState(
                enabled: true,
                host: ProxyOverrideTransition.loopbackHost,
                port: Fixtures.rockxyPort
            )
        )

        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: halfApplied,
                priorEntry: applicationEntry(stage: .applicationPending),
                port: Fixtures.rockxyPort
            ) == .abort
        )
    }

    @Test("A foreign configuration is not reclaimable, whatever the record says")
    func aForeignConfigurationIsAborted() {
        let foreign = Fixtures.replacing(
            Fixtures.capturedSettings,
            http: ProxyEndpointState(enabled: true, host: "10.0.0.9", port: 3_128)
        )

        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: foreign,
                priorEntry: applicationEntry(stage: .applying),
                port: Fixtures.rockxyPort
            ) == .abort
        )
    }

    @Test("A record describing some other capture is not this attempt's to reclaim from")
    func aStaleRecordDoesNotAuthorizeAReclaim() throws {
        let live = try #require(ProxyOverrideTransition.completedState(
            from: Fixtures.capturedSettings,
            port: Fixtures.rockxyPort
        ))
        let staleRecord = applicationEntry(
            stage: .applying,
            captured: Fixtures.replacing(Fixtures.capturedSettings, bypassDomains: ["something.else"])
        )

        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: live,
                priorEntry: staleRecord,
                port: Fixtures.rockxyPort
            ) == .abort
        )
    }

    @Test("A restore record never authorizes an override to be written over it")
    func aRestoreRecordDoesNotAuthorizeAnOverride() {
        // A recovery was part-way through putting the captured settings back when this attempt
        // arrived. Its states belong to a different command sequence entirely.
        let midRestore = Fixtures.capturedSettings.withProxyModesDisabled

        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: midRestore,
                priorEntry: Fixtures.entry(stage: .inFlight),
                port: Fixtures.rockxyPort
            ) == .abort
        )
    }

    @Test("A service whose settings could not be read is never written to")
    func anUnreadableServiceIsAborted() {
        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: nil,
                priorEntry: applicationEntry(stage: .applying),
                port: Fixtures.rockxyPort
            ) == .abort
        )
    }

    @Test("A record naming another service authorizes nothing here")
    func aMismatchedServiceIsAborted() {
        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: Fixtures.renamed(Fixtures.capturedSettings, to: "Ethernet"),
                priorEntry: applicationEntry(stage: .applying),
                port: Fixtures.rockxyPort
            ) == .abort
        )
    }

    @Test("An override with no usable port is refused before anything is read")
    func anUnusablePortIsAborted() {
        #expect(
            ProxyOverrideApplicationPreflight.decision(
                captured: Fixtures.capturedSettings,
                live: Fixtures.capturedSettings,
                priorEntry: nil,
                port: 0
            ) == .abort
        )
    }

    @Test("The record a reclaim commits restores the original capture from the live baseline")
    func theCommittedRecordKeepsTheOriginalTarget() throws {
        let live = try #require(ProxyOverrideTransition.completedState(
            from: Fixtures.capturedSettings,
            port: Fixtures.rockxyPort
        ))
        guard case let .apply(baseline) = ProxyOverrideApplicationPreflight.decision(
            captured: Fixtures.capturedSettings,
            live: live,
            priorEntry: applicationEntry(stage: .applying),
            port: Fixtures.rockxyPort
        ) else {
            Issue.record("expected the reclaim to be writable")
            return
        }

        let committed = ProxyServiceRecoveryJournalEntry(
            overrideApplicationFor: Fixtures.capturedSettings,
            baseline: baseline,
            stage: .applying,
            port: Fixtures.rockxyPort
        )

        // The sequence starts at what is live, and the rollback still puts the user's own
        // configuration back rather than the override this attempt is reclaiming.
        #expect(committed.expectedPreStepState == live)
        #expect(committed.target == Fixtures.capturedSettings)
        // And the record still describes the backup on disk, so the planner keeps reading it.
        #expect(committed.describesRestore(of: Fixtures.capturedSettings))
        // A crash after this commit but before the first command still has the prior override live.
        // That is a reclaim to roll back, not an untouched fresh service whose restore point may go.
        #expect(ProxyOverrideApplicationRecoveryPolicy.continuation(
            for: committed,
            live: live,
            ownedPort: Fixtures.rockxyPort
        ) == .rollBack(baseline: live))
    }

    // MARK: Private

    private typealias Fixtures = ProxyRecoveryJournalFixtures

    private func applicationEntry(
        stage: ProxyRecoveryStage,
        captured: ProxyServiceRestorationState = ProxyRecoveryJournalFixtures.capturedSettings,
        appliedBypassDomains: [String]? = nil
    )
        -> ProxyServiceRecoveryJournalEntry
    {
        ProxyServiceRecoveryJournalEntry(
            overrideApplicationFor: captured,
            stage: stage,
            port: ProxyRecoveryJournalFixtures.rockxyPort,
            appliedBypassDomains: appliedBypassDomains
        )
    }
}
