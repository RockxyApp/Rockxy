import Foundation
@testable import Rockxy
import Testing

// Regression tests for what a helper launch may leave alone when the app process recorded in a
// backup is still running.

// MARK: - ProxyOverrideSessionCompletionPolicyTests

/// A live owner is not on its own a reason to preserve a session. The override it took either
/// finished on every service or it did not, and a sequence that stopped part-way left a shape that
/// is neither Rockxy's nor the user's — with the process that would have finished it already past
/// the point of doing so.
struct ProxyOverrideSessionCompletionPolicyTests {
    // MARK: Internal

    @Test("A session whose override finished exactly as recorded is left alone")
    func aFullyAppliedSessionIsPreserved() throws {
        let finished = try #require(ProxyOverrideTransition.completedState(
            from: Fixtures.capturedSettings,
            port: Fixtures.rockxyPort,
            appliedBypassDomains: rockxyBypass
        ))

        #expect(ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
            services: [Fixtures.service],
            journal: [applicationEntry(stage: .applying, appliedBypassDomains: rockxyBypass)],
            liveStates: [Fixtures.service: finished],
            ownedPort: Fixtures.rockxyPort
        ))
    }

    @Test("A sequence that stopped part-way is recovered even though its owner is alive")
    func aPartialPrefixIsNotPreserved() {
        let halfApplied = Fixtures.replacing(
            Fixtures.capturedSettings,
            http: ProxyEndpointState(
                enabled: true,
                host: ProxyOverrideTransition.loopbackHost,
                port: Fixtures.rockxyPort
            )
        )

        #expect(!ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
            services: [Fixtures.service],
            journal: [applicationEntry(stage: .applying)],
            liveStates: [Fixtures.service: halfApplied],
            ownedPort: Fixtures.rockxyPort
        ))
    }

    @Test("A record whose commands were never issued is not a finished session")
    func anApplicationPendingRecordIsNotPreserved() {
        // Whether the service is untouched or already overridden, nothing was recorded as issued
        // under this record, so nothing about it says the session finished.
        for live in [Fixtures.capturedSettings, Fixtures.rockxyOverride] {
            #expect(!ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
                services: [Fixtures.service],
                journal: [applicationEntry(stage: .applicationPending)],
                liveStates: [Fixtures.service: live],
                ownedPort: Fixtures.rockxyPort
            ))
        }
    }

    @Test("A service the override never reached takes the whole session out of preservation")
    func anUntouchedServiceIsNotPreserved() {
        #expect(!ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
            services: [Fixtures.service],
            journal: [applicationEntry(stage: .applying)],
            liveStates: [Fixtures.service: Fixtures.capturedSettings],
            ownedPort: Fixtures.rockxyPort
        ))
    }

    @Test("A restore already under way is never a finished override")
    func aRestoreRecordIsNotPreserved() {
        #expect(!ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
            services: [Fixtures.service],
            journal: [Fixtures.entry(stage: .inFlight)],
            liveStates: [Fixtures.service: Fixtures.rockxyOverride],
            ownedPort: Fixtures.rockxyPort
        ))
    }

    @Test("One service the journal says nothing about takes the whole session out of preservation")
    func anUnrecordedServiceIsNotPreserved() throws {
        let finished = try #require(ProxyOverrideTransition.completedState(
            from: Fixtures.capturedSettings,
            port: Fixtures.rockxyPort
        ))
        let secondary = Fixtures.renamed(finished, to: "Ethernet")

        #expect(!ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
            services: [Fixtures.service, "Ethernet"],
            journal: [applicationEntry(stage: .applying)],
            liveStates: [Fixtures.service: finished, "Ethernet": secondary],
            ownedPort: Fixtures.rockxyPort
        ))
    }

    @Test("A service whose settings could not be read is not proof of anything")
    func anUnreadableServiceIsNotPreserved() {
        #expect(!ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
            services: [Fixtures.service],
            journal: [applicationEntry(stage: .applying)],
            liveStates: [:],
            ownedPort: Fixtures.rockxyPort
        ))
    }

    @Test("A backup covering no service at all is never preserved")
    func anEmptyBackupIsNotPreserved() {
        #expect(!ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
            services: [],
            journal: [],
            liveStates: [:],
            ownedPort: Fixtures.rockxyPort
        ))
    }

    @Test("A backup written before the journal keeps the older ownership answer")
    func aLegacyBackupFallsBackToOwnership() {
        // There is no record to read a partial application out of, so tearing the session down
        // would be condemning a live session on evidence this build simply does not have. The
        // answer decides nothing but whether to write nothing.
        #expect(ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
            services: [Fixtures.service],
            journal: [],
            liveStates: [Fixtures.service: Fixtures.rockxyOverride],
            ownedPort: Fixtures.rockxyPort
        ))
        #expect(!ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
            services: [Fixtures.service],
            journal: [],
            liveStates: [Fixtures.service: Fixtures.capturedSettings],
            ownedPort: Fixtures.rockxyPort
        ))
        #expect(!ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
            services: [Fixtures.service],
            journal: [],
            liveStates: [Fixtures.service: Fixtures.rockxyOverride],
            ownedPort: nil
        ))
    }

    // MARK: Private

    private typealias Fixtures = ProxyRecoveryJournalFixtures

    private let rockxyBypass = ["localhost", "127.0.0.1"]

    private func applicationEntry(
        stage: ProxyRecoveryStage,
        appliedBypassDomains: [String]? = nil
    )
        -> ProxyServiceRecoveryJournalEntry
    {
        ProxyServiceRecoveryJournalEntry(
            overrideApplicationFor: ProxyRecoveryJournalFixtures.capturedSettings,
            stage: stage,
            port: ProxyRecoveryJournalFixtures.rockxyPort,
            appliedBypassDomains: appliedBypassDomains
        )
    }
}
