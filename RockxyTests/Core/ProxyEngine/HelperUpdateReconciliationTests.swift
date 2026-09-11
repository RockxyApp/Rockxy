import Foundation
@testable import Rockxy
import Testing

// MARK: - Fixture

// Regression tests for issue #319: after the first valid macOS approval, updating Rockxy must not
// make the user approve the helper again.
//
// The defect had two halves. The trigger only fired on `installedBuild < bundledBuild`, so an
// update that changed the helper binary without changing its numbers looked like nothing to do —
// while `SMAppService` kept the *previously started* daemon alive, because `BundleProgram` is only
// resolved when a connection starts one. And when the refresh did run, failing it fell through to
// unregister/register, which clears Background Task Management trust and asks for approval again.
//
// These tests drive the production decision and orchestration seams — `HelperManager.updatePlan`,
// `HelperManager.updateRoute`, and `HelperExecutableRefreshOrchestrator` — so the real sequencing
// is what is being checked, with no `SMAppService` mutation anywhere.

private enum Fixture {
    static let bundledBuild = 10
    static let expectedProtocol = 5

    static let embeddedDigest = String(repeating: "a", count: 64)
    static let staleDigest = String(repeating: "b", count: 64)

    static var candidate: HelperExecutableRefreshOrchestrator.Candidate {
        HelperExecutableRefreshOrchestrator.Candidate(
            executableDigest: embeddedDigest,
            expectedProtocolVersion: expectedProtocol,
            bundledBuildNumber: bundledBuild
        )
    }

    static func info(protocolVersion: Int, build: Int) -> HelperInfo {
        HelperInfo(binaryVersion: "0.7.1", buildNumber: build, protocolVersion: protocolVersion)
    }

    static func identity(
        digest: String,
        launch: String,
        build: Int = bundledBuild,
        protocolVersion: Int = expectedProtocol,
        pid: Int32 = 4_242
    )
        -> HelperExecutableIdentity
    {
        HelperExecutableIdentity(
            executableDigest: digest,
            launchIdentity: launch,
            processIdentifier: pid,
            executablePath: "/Applications/Rockxy.app/Contents/Library/HelperTools/RockxyHelperTool",
            buildNumber: build,
            protocolVersion: protocolVersion
        )
    }

    static func snapshot(
        status: HelperManager.HelperStatus = .installedCompatible,
        info: HelperInfo? = info(protocolVersion: expectedProtocol, build: bundledBuild),
        identity: HelperExecutableIdentity? = nil
    )
        -> HelperExecutableRefreshOrchestrator.Snapshot
    {
        HelperExecutableRefreshOrchestrator.Snapshot(status: status, info: info, identity: identity)
    }

    static func plan(
        status: HelperManager.HelperStatus = .installedOutdated,
        info: HelperInfo?,
        identity: HelperExecutableIdentity? = nil,
        candidateDigest: String? = embeddedDigest,
        marker: HelperConvergenceMarker? = nil
    )
        -> HelperUpdatePlan
    {
        HelperManager.updatePlan(
            status: status,
            installedInfo: info,
            installedIdentity: identity,
            expectedProtocolVersion: expectedProtocol,
            bundledBuildNumber: bundledBuild,
            candidateDigest: candidateDigest,
            marker: marker
        )
    }
}

// MARK: - ScriptedHelper

/// A scripted helper for the orchestrator: it answers refresh requests from a queue and hands back
/// one prepared observation per poll, so a whole update sequence runs deterministically and with no
/// real sleeping.
@MainActor
private final class ScriptedHelper {
    // MARK: Lifecycle

    init(
        refreshResults: [Result<Void, any Error>],
        snapshots: [HelperExecutableRefreshOrchestrator.Snapshot]
    ) {
        self.refreshResults = refreshResults
        self.snapshots = snapshots
    }

    // MARK: Internal

    private(set) var refreshRequestCount = 0
    private(set) var transportResetCount = 0
    private(set) var waits: [Duration] = []

    /// The orchestrator with every side effect scripted and every wait recorded rather than taken.
    var orchestrator: HelperExecutableRefreshOrchestrator {
        HelperExecutableRefreshOrchestrator(
            requestRefresh: { [weak self] in
                guard let self else {
                    return
                }
                refreshRequestCount += 1
                guard !refreshResults.isEmpty else {
                    return
                }
                try refreshResults.removeFirst().get()
            },
            resetTransport: { [weak self] in self?.transportResetCount += 1 },
            snapshot: { [weak self] in
                guard let self, !snapshots.isEmpty else {
                    return Fixture.snapshot(status: .unreachable, info: nil)
                }
                if snapshots.count == 1 {
                    return snapshots[0]
                }
                return snapshots.removeFirst()
            },
            wait: { [weak self] duration in self?.waits.append(duration) }
        )
    }

    // MARK: Private

    private var refreshResults: [Result<Void, any Error>]
    private var snapshots: [HelperExecutableRefreshOrchestrator.Snapshot]
}

// MARK: - ScriptedStartupRecovery

/// A scripted launch reconciliation for the startup recovery orchestrator: it hands back one
/// prepared attempt per pass and records every wait and reconnect instead of taking them, so the
/// whole multi-minute migration window runs instantly and in order.
///
/// There is deliberately no unregister, register or approval seam here — the orchestrator has
/// nowhere to call one.
@MainActor
private final class ScriptedStartupRecovery {
    // MARK: Lifecycle

    init(attempts: [HelperUpdateStartupRecoveryOrchestrator.Attempt]) {
        self.attempts = attempts
    }

    // MARK: Internal

    private(set) var reconcileCount = 0
    private(set) var transportResetCount = 0
    private(set) var waits: [Duration] = []
    /// Ordered record of what the orchestrator did, so "reconnect before every retry" is observed
    /// rather than inferred from a count.
    private(set) var events: [String] = []

    var orchestrator: HelperUpdateStartupRecoveryOrchestrator {
        HelperUpdateStartupRecoveryOrchestrator(
            reconcile: { [weak self] in
                guard let self else {
                    return HelperUpdateStartupRecoveryOrchestrator.Attempt(
                        outcome: .blocked(.unreachable),
                        registrationIsEnabled: false
                    )
                }
                reconcileCount += 1
                events.append("reconcile")
                guard !attempts.isEmpty else {
                    return HelperUpdateStartupRecoveryOrchestrator.Attempt(
                        outcome: .blocked(.unreachable),
                        registrationIsEnabled: true
                    )
                }
                if attempts.count == 1 {
                    return attempts[0]
                }
                return attempts.removeFirst()
            },
            resetTransport: { [weak self] in
                self?.transportResetCount += 1
                self?.events.append("reset")
            },
            wait: { [weak self] duration in self?.waits.append(duration) }
        )
    }

    // MARK: Private

    private var attempts: [HelperUpdateStartupRecoveryOrchestrator.Attempt]
}

// MARK: - HelperUpdateStartupRecoveryTests

/// The other half of issue #319: a helper installed *before* the caller-validation launch snapshot
/// keeps validating callers against whatever now sits at its own path, so once Sparkle swaps the
/// bundle it refuses the relaunched app. That helper cannot be fixed over XPC — it exits on its own
/// after the five-minute idle timeout — so the app waits for launchd rather than falling back to
/// direct capture or offering a destructive reinstall.
@MainActor
struct HelperUpdateStartupRecoveryTests {
    @Test("an enabled registration that will not answer is waited out until launchd serves this bundle")
    func unreachableEnabledRegistrationIsRetriedUntilConvergence() async {
        let recovery = ScriptedStartupRecovery(attempts: [
            .init(outcome: .blocked(.unreachable), registrationIsEnabled: true),
            .init(outcome: .blocked(.unreachable), registrationIsEnabled: true),
            .init(outcome: .refreshed, registrationIsEnabled: true),
        ])

        let outcome = await recovery.orchestrator.run()

        #expect(outcome == .settled(.refreshed))
        #expect(recovery.reconcileCount == 3)
        // Every retry ran over a connection this orchestrator forced open again, before it probed.
        #expect(recovery.events == ["reconcile", "reset", "reconcile", "reset", "reconcile"])
        #expect(recovery.transportResetCount == 2)
    }

    @Test("recovery is bounded and leaves the registration exactly as it found it")
    func recoveryExhaustionIsBounded() async {
        let recovery = ScriptedStartupRecovery(attempts: [
            .init(outcome: .blocked(.unreachable), registrationIsEnabled: true),
        ])
        let orchestrator = recovery.orchestrator

        let outcome = await orchestrator.run()

        #expect(outcome == .recoveryExhausted(.blocked(.unreachable)))
        // One pass per configured step, plus the first immediate one. Nothing waits forever.
        #expect(recovery.reconcileCount == orchestrator.retryDelays.count + 1)
        #expect(recovery.waits == orchestrator.retryDelays)
        #expect(recovery.transportResetCount == orchestrator.retryDelays.count)
    }

    @Test("the recovery window outlasts the helper's five-minute idle exit timeout")
    func recoveryWindowOutlastsIdleExit() {
        let orchestrator = HelperUpdateStartupRecoveryOrchestrator(
            reconcile: { .init(outcome: .upToDate, registrationIsEnabled: true) },
            resetTransport: {},
            wait: { _ in }
        )

        let window = orchestrator.retryDelays.reduce(Duration.zero, +)

        // `IdleExitMonitor` exits the old daemon after exactly five minutes of no accepted XPC.
        #expect(window > .seconds(5 * 60))
        // Sparse, not a poll loop: a rejected connection never resets that timer, so hammering it
        // would add noise without bringing the exit forward.
        #expect(orchestrator.retryDelays.allSatisfy { $0 >= .seconds(5) })
        #expect(orchestrator.retryDelays == HelperUpdateStartupRecoveryOrchestrator.launchRetryDelays)
    }

    @Test("an explicit retry is short, bounded, and preserves the registration on exhaustion")
    func interactiveRecoveryIsShortAndBounded() async {
        let recovery = ScriptedStartupRecovery(attempts: [
            .init(outcome: .blocked(.unreachable), registrationIsEnabled: true),
        ])
        var orchestrator = recovery.orchestrator
        orchestrator.retryDelays = HelperUpdateStartupRecoveryOrchestrator.interactiveRetryDelays

        let outcome = await orchestrator.run()
        let window = orchestrator.retryDelays.reduce(Duration.zero, +)

        #expect(outcome == .recoveryExhausted(.blocked(.unreachable)))
        #expect(window < .seconds(30))
        #expect(recovery.waits == HelperUpdateStartupRecoveryOrchestrator.interactiveRetryDelays)
        #expect(recovery.transportResetCount == orchestrator.retryDelays.count)
    }

    @Test("approval, absence, signing, package, protocol and legacy results never wait")
    func terminalOutcomesAreReturnedImmediately() async {
        let terminal: [HelperManager.ReconciliationOutcome] = [
            .blocked(.requiresApproval),
            .blocked(.notInstalled),
            .blocked(.signingMismatch),
            .blocked(.embeddedPackageInvalid),
            .blocked(.incompatibleProtocol),
            .legacyMigrationRequired,
            .upToDate,
            .refreshed,
            .refreshFailed(.verificationIncomplete),
        ]

        for outcome in terminal {
            let recovery = ScriptedStartupRecovery(attempts: [
                .init(outcome: outcome, registrationIsEnabled: true),
            ])
            let result = await recovery.orchestrator.run()

            #expect(result == .settled(outcome))
            #expect(recovery.reconcileCount == 1)
            #expect(recovery.waits.isEmpty)
            #expect(recovery.transportResetCount == 0)
        }
    }

    @Test("a registration that is no longer enabled ends the wait instead of extending it")
    func disabledRegistrationEndsTheWait() async {
        let recovery = ScriptedStartupRecovery(attempts: [
            .init(outcome: .blocked(.unreachable), registrationIsEnabled: false),
        ])

        let outcome = await recovery.orchestrator.run()

        #expect(outcome == .settled(.blocked(.unreachable)))
        #expect(recovery.reconcileCount == 1)
        #expect(recovery.waits.isEmpty)
    }

    @Test("only an enabled, unreachable registration is worth waiting for")
    func onlyEnabledUnreachableIsWaitedOn() {
        #expect(HelperUpdateStartupRecoveryOrchestrator.shouldWaitForLaunchd(
            .init(outcome: .blocked(.unreachable), registrationIsEnabled: true)
        ))
        #expect(!HelperUpdateStartupRecoveryOrchestrator.shouldWaitForLaunchd(
            .init(outcome: .blocked(.unreachable), registrationIsEnabled: false)
        ))
        #expect(!HelperUpdateStartupRecoveryOrchestrator.shouldWaitForLaunchd(
            .init(outcome: .blocked(.requiresApproval), registrationIsEnabled: true)
        ))
        #expect(!HelperUpdateStartupRecoveryOrchestrator.shouldWaitForLaunchd(
            .init(outcome: .legacyMigrationRequired, registrationIsEnabled: true)
        ))
    }
}

// MARK: - HelperUpdatePlanTests

struct HelperUpdatePlanTests {
    @Test("protocol 1 and 2 helpers stay on the manual migration path")
    func legacyProtocolsRequireManualMigration() {
        for legacyProtocol in [1, 2] {
            #expect(
                Fixture.plan(info: Fixture.info(protocolVersion: legacyProtocol, build: 8))
                    == .legacyManualMigration
            )
        }
    }

    @Test("a protocol-4 helper with a newer bundled build is refreshed, not reinstalled")
    func protocolFourNewerBuildChoosesRefresh() {
        #expect(
            Fixture.plan(info: Fixture.info(protocolVersion: 4, build: 9))
                == .approvalPreservingRefresh
        )
    }

    @Test("a protocol-4 helper is refreshed on the way to protocol 5")
    func protocolFourToFiveChoosesRefresh() {
        // Protocol 4 cannot describe its own executable, so metadata drift is the whole signal —
        // and it is enough, because a protocol-4 daemon is by definition not the protocol-5
        // binary this bundle ships.
        #expect(
            Fixture.plan(info: Fixture.info(protocolVersion: 4, build: Fixture.bundledBuild))
                == .approvalPreservingRefresh
        )
    }

    @Test("identical version metadata with a different executable digest is still drift")
    func matchingMetadataWithDifferentDigestChoosesRefresh() {
        // This is the shape the reported bug actually took: the running daemon reports exactly the
        // numbers this app expects while executing the previous release's binary.
        let plan = Fixture.plan(
            status: .installedCompatible,
            info: Fixture.info(protocolVersion: 5, build: Fixture.bundledBuild),
            identity: Fixture.identity(digest: Fixture.staleDigest, launch: "old-process")
        )
        #expect(plan == .approvalPreservingRefresh)
    }

    @Test("a verified matching digest needs no refresh at all")
    func matchingDigestIsUpToDate() {
        let plan = Fixture.plan(
            status: .installedCompatible,
            info: Fixture.info(protocolVersion: 5, build: Fixture.bundledBuild),
            identity: Fixture.identity(digest: Fixture.embeddedDigest, launch: "current-process")
        )
        #expect(plan == .upToDate)
    }

    @Test("protocol 5 never substitutes an old marker for a missing live identity")
    func missingModernIdentityForcesReconnectAndRefresh() {
        let marker = HelperConvergenceMarker(
            executableDigest: Fixture.embeddedDigest,
            buildNumber: Fixture.bundledBuild,
            protocolVersion: Fixture.expectedProtocol
        )
        let plan = Fixture.plan(
            status: .installedCompatible,
            info: Fixture.info(protocolVersion: 5, build: Fixture.bundledBuild),
            identity: nil,
            marker: marker
        )
        #expect(plan == .approvalPreservingRefresh)
    }

    @Test("a helper that was not running, then started as the embedded candidate, is up to date")
    func helperStartedOnDemandAsCandidateNeedsNoExit() {
        // Nothing was running, so the first XPC activation started the executable from *this*
        // bundle. Asking it to exit would be a pointless restart of the binary already wanted.
        let plan = Fixture.plan(
            status: .installedCompatible,
            info: Fixture.info(protocolVersion: 5, build: Fixture.bundledBuild),
            identity: Fixture.identity(digest: Fixture.embeddedDigest, launch: "freshly-activated"),
            marker: nil
        )
        #expect(plan == .upToDate)
    }

    @Test("a helper that cannot describe itself is trusted only against a verified marker")
    func markerShortCircuitsOnlyWhenItMatchesTheEmbeddedExecutable() {
        let info = Fixture.info(protocolVersion: 4, build: 9)
        let matchingExpectations = HelperManager.updatePlan(
            status: .installedCompatible,
            installedInfo: info,
            installedIdentity: nil,
            expectedProtocolVersion: 4,
            bundledBuildNumber: 9,
            candidateDigest: Fixture.embeddedDigest,
            marker: HelperConvergenceMarker(
                executableDigest: Fixture.embeddedDigest,
                buildNumber: 9,
                protocolVersion: 4
            )
        )
        #expect(matchingExpectations == .upToDate)

        let markerFromAnotherBuild = HelperManager.updatePlan(
            status: .installedCompatible,
            installedInfo: info,
            installedIdentity: nil,
            expectedProtocolVersion: 4,
            bundledBuildNumber: 9,
            candidateDigest: Fixture.embeddedDigest,
            marker: HelperConvergenceMarker(
                executableDigest: Fixture.staleDigest,
                buildNumber: 9,
                protocolVersion: 4
            )
        )
        #expect(markerFromAnotherBuild == .approvalPreservingRefresh)

        let noMarker = HelperManager.updatePlan(
            status: .installedCompatible,
            installedInfo: info,
            installedIdentity: nil,
            expectedProtocolVersion: 4,
            bundledBuildNumber: 9,
            candidateDigest: Fixture.embeddedDigest,
            marker: nil
        )
        #expect(noMarker == .approvalPreservingRefresh)
    }

    @Test("an unreadable embedded helper fails closed and preserves the installed helper")
    func missingOrInvalidEmbeddedHelperIsBlocked() {
        for digest in [nil, "", "not-a-digest", String(repeating: "A", count: 64)] {
            #expect(
                Fixture.plan(
                    info: Fixture.info(protocolVersion: 4, build: 9),
                    candidateDigest: digest
                ) == .blocked(.embeddedPackageInvalid)
            )
        }
    }

    @Test("approval, absence, signing and reachability failures each stay distinct")
    func unusableStatesAreBlockedIndividually() {
        let cases: [(HelperManager.HelperStatus, HelperUpdateBlockReason)] = [
            (.notInstalled, .notInstalled),
            (.requiresApproval, .requiresApproval),
            (.unreachable, .unreachable),
            (.signingMismatch, .signingMismatch),
            (.installedIncompatible, .incompatibleProtocol),
        ]
        for (status, reason) in cases {
            #expect(
                Fixture.plan(status: status, info: Fixture.info(protocolVersion: 4, build: 9))
                    == .blocked(reason)
            )
        }
    }

    @Test("a helper newer than this build is never automatically replaced")
    func futureProtocolIsNeverDowngraded() {
        // A future protocol classifies as incompatible, and incompatible never plans a refresh.
        #expect(
            HelperCompatibilityPolicy.classify(
                installedProtocolVersion: 6,
                installedBuildNumber: 11,
                expectedProtocolVersion: Fixture.expectedProtocol,
                bundledBuildNumber: Fixture.bundledBuild
            ) == .incompatible
        )
        #expect(
            Fixture.plan(
                status: .installedIncompatible,
                info: Fixture.info(protocolVersion: 6, build: 11)
            ) == .blocked(.incompatibleProtocol)
        )
    }

    @Test("an unreachable probe result is never read as convergence")
    func missingInstalledInfoIsBlocked() {
        #expect(Fixture.plan(info: nil) == .blocked(.unreachable))
        #expect(Fixture.plan(info: Fixture.info(protocolVersion: 0, build: 0)) == .blocked(.unreachable))
    }

    @Test("embedded helper signing mismatch blocks refresh")
    func embeddedHelperSigningMismatchFailsClosed() {
        #expect(HelperManager.embeddedHelperSigningAllowsRefresh(.healthy))
        #expect(!HelperManager.embeddedHelperSigningAllowsRefresh(.signingIdentityMismatch(
            appSigner: "App signer",
            helperSigner: "Other signer"
        )))
        #expect(!HelperManager.embeddedHelperSigningAllowsRefresh(.certificateChainUnavailable))
        #expect(!HelperManager.embeddedHelperSigningAllowsRefresh(.appSignatureInvalid(detail: "invalid")))
        #expect(!HelperManager.embeddedHelperSigningAllowsRefresh(.runningCodeChanged(detail: "replaced")))
        #expect(!HelperManager.embeddedHelperSigningAllowsRefresh(.helperBinaryNotFound))
        #expect(!HelperManager.embeddedHelperSigningAllowsRefresh(.diagnosticError(detail: "error")))
    }
}

// MARK: - HelperUpdateRouteTests

struct HelperUpdateRouteTests {
    @Test("a modern helper's Update action takes the approval-preserving path")
    func modernProtocolsRouteToRefresh() {
        for protocolVersion in [3, 4, 5] {
            #expect(
                HelperManager.updateRoute(
                    status: .installedOutdated,
                    installedInfo: Fixture.info(protocolVersion: protocolVersion, build: 9),
                    expectedProtocolVersion: Fixture.expectedProtocol,
                    bundledBuildNumber: Fixture.bundledBuild
                ) == .approvalPreservingRefresh
            )
        }
    }

    @Test("only protocol 1 and 2 may reach the destructive migration")
    func onlyLegacyProtocolsRouteToDestructiveMigration() {
        for protocolVersion in [1, 2] {
            #expect(
                HelperManager.updateRoute(
                    status: .installedOutdated,
                    installedInfo: Fixture.info(protocolVersion: protocolVersion, build: 8),
                    expectedProtocolVersion: Fixture.expectedProtocol,
                    bundledBuildNumber: Fixture.bundledBuild
                ) == .legacyProtocolMigration
            )
        }
    }

    @Test("an approved or absent registration is never re-registered by Update")
    func unusableStatesRouteToUnavailable() {
        for status in [
            HelperManager.HelperStatus.notInstalled,
            .requiresApproval,
            .unreachable,
            .signingMismatch,
        ] {
            #expect(
                HelperManager.updateRoute(
                    status: status,
                    installedInfo: Fixture.info(protocolVersion: 5, build: 9),
                    expectedProtocolVersion: Fixture.expectedProtocol,
                    bundledBuildNumber: Fixture.bundledBuild
                ) == .unavailable
            )
        }
    }

    @Test("a future or unreadable protocol is neither refreshed nor destructively migrated")
    func futureProtocolRoutesToUnavailable() {
        for protocolVersion in [6, 99, 0, -1] {
            #expect(
                HelperManager.updateRoute(
                    status: .installedIncompatible,
                    installedInfo: Fixture.info(protocolVersion: protocolVersion, build: 11),
                    expectedProtocolVersion: Fixture.expectedProtocol,
                    bundledBuildNumber: Fixture.bundledBuild
                ) == .unavailable
            )
        }
        #expect(
            HelperManager.updateRoute(
                status: .installedIncompatible,
                installedInfo: nil,
                expectedProtocolVersion: Fixture.expectedProtocol,
                bundledBuildNumber: Fixture.bundledBuild
            ) == .unavailable
        )
    }

    @Test("a newer build of the same protocol is never downgraded")
    func newerSameProtocolBuildRoutesToUnavailable() {
        let installed = Fixture.info(
            protocolVersion: Fixture.expectedProtocol,
            build: Fixture.bundledBuild + 1
        )
        #expect(
            Fixture.plan(status: .installedCompatible, info: installed)
                == .blocked(.incompatibleProtocol)
        )
        #expect(
            HelperManager.updateRoute(
                status: .installedCompatible,
                installedInfo: installed,
                expectedProtocolVersion: Fixture.expectedProtocol,
                bundledBuildNumber: Fixture.bundledBuild
            ) == .unavailable
        )
    }
}

// MARK: - HelperExecutableRefreshOrchestratorTests

@MainActor
struct HelperExecutableRefreshOrchestratorTests {
    @Test("a protocol-5 refresh is accepted only once a different process reports the new digest")
    func refreshRequiresANewLaunchIdentityAndTheEmbeddedDigest() async {
        let old = Fixture.identity(digest: Fixture.staleDigest, launch: "old-process")
        let new = Fixture.identity(digest: Fixture.embeddedDigest, launch: "new-process")

        let helper = ScriptedHelper(
            refreshResults: [.success(())],
            snapshots: [
                // The daemon that was asked to exit answers the first poll.
                Fixture.snapshot(identity: old),
                Fixture.snapshot(identity: new),
            ]
        )
        let outcome = await helper.orchestrator.run(candidate: Fixture.candidate, preRefreshIdentity: old)

        #expect(outcome == .converged(HelperConvergenceMarker(
            executableDigest: Fixture.embeddedDigest,
            buildNumber: Fixture.bundledBuild,
            protocolVersion: Fixture.expectedProtocol
        )))
        // Every poll ran over a connection this orchestrator forced open again.
        #expect(helper.transportResetCount == 2)
    }

    @Test("the old executable answering with the app's own expectations is not accepted")
    func staleProcessAnsweringCorrectMetadataIsRejected() async {
        // The pre-refresh process is at the expected protocol and build, so nothing but its launch
        // identity and digest distinguishes it. It must not be mistaken for the new one.
        let old = Fixture.identity(digest: Fixture.embeddedDigest, launch: "old-process")
        let helper = ScriptedHelper(
            refreshResults: [.success(())],
            snapshots: [Fixture.snapshot(identity: old)]
        )
        let outcome = await helper.orchestrator.run(candidate: Fixture.candidate, preRefreshIdentity: old)

        #expect(outcome == .verificationIncomplete)
    }

    @Test("a helper still reporting the previous protocol is not accepted")
    func previousProtocolIsNotConvergence() async {
        let helper = ScriptedHelper(
            refreshResults: [.success(())],
            snapshots: [Fixture.snapshot(
                info: Fixture.info(protocolVersion: 4, build: 9),
                identity: nil
            )]
        )
        let outcome = await helper.orchestrator.run(candidate: Fixture.candidate, preRefreshIdentity: nil)

        #expect(outcome == .verificationIncomplete)
    }

    @Test("a stale connection is reset and the refresh retried rather than escalated")
    func staleTransportIsResetAndRetried() async {
        let helper = ScriptedHelper(
            refreshResults: [
                .failure(HelperConnectionError.connectionFailed),
                .failure(HelperConnectionError.xpcTimeout),
                .success(()),
            ],
            snapshots: [Fixture.snapshot(
                identity: Fixture.identity(digest: Fixture.embeddedDigest, launch: "new-process")
            )]
        )
        let outcome = await helper.orchestrator.run(candidate: Fixture.candidate, preRefreshIdentity: nil)

        #expect(outcome == .converged(HelperConvergenceMarker(
            executableDigest: Fixture.embeddedDigest,
            buildNumber: Fixture.bundledBuild,
            protocolVersion: Fixture.expectedProtocol
        )))
        #expect(helper.refreshRequestCount == 3)
        // Two transport failures reconnect, plus the poll that observed convergence.
        #expect(helper.transportResetCount == 3)
    }

    @Test("a helper that keeps deferring exhausts a bounded ladder and stays installed")
    func deferralExhaustionReportsDeferredWithoutUnregistering() async {
        let helper = ScriptedHelper(
            refreshResults: Array(
                repeating: .failure(HelperConnectionError.executableRefreshDeferred),
                count: 10
            ),
            snapshots: [Fixture.snapshot()]
        )
        let orchestrator = helper.orchestrator
        let outcome = await orchestrator.run(candidate: Fixture.candidate, preRefreshIdentity: nil)

        #expect(outcome == .refreshDeferred)
        // Bounded: one attempt per configured backoff step, plus the first immediate attempt.
        #expect(helper.refreshRequestCount == orchestrator.refreshRetryDelays.count + 1)
        #expect(helper.waits == orchestrator.refreshRetryDelays)
    }

    @Test("an acknowledged refresh that never converges times out without escalating")
    func verificationTimeoutLeavesTheRegistrationAlone() async {
        let helper = ScriptedHelper(
            refreshResults: [.success(())],
            // The daemon never comes back with anything usable.
            snapshots: [Fixture.snapshot(status: .unreachable, info: nil)]
        )
        let orchestrator = helper.orchestrator
        let outcome = await orchestrator.run(candidate: Fixture.candidate, preRefreshIdentity: nil)

        #expect(outcome == .verificationIncomplete)
        #expect(helper.waits == orchestrator.verificationDelays)
    }

    @Test("a helper without the refresh selector is reported, never replaced")
    func unsupportedRefreshIsReportedImmediately() async {
        let helper = ScriptedHelper(
            refreshResults: [.failure(HelperConnectionError.executableRefreshUnsupported)],
            snapshots: [Fixture.snapshot()]
        )
        let outcome = await helper.orchestrator.run(candidate: Fixture.candidate, preRefreshIdentity: nil)

        #expect(outcome == .refreshUnsupported)
        // No retry: nothing about the answer can change, and nothing else may substitute for it.
        #expect(helper.refreshRequestCount == 1)
    }

    @Test("a failed refresh leaves no marker, so the next launch retries and converges")
    func failureThenRelaunchRetriesAndConverges() async {
        let candidate = Fixture.candidate
        let old = Fixture.identity(digest: Fixture.staleDigest, launch: "old-process")

        let firstRun = ScriptedHelper(
            refreshResults: [.failure(HelperConnectionError.executableRefreshDeferred)],
            snapshots: [Fixture.snapshot(identity: old)]
        )
        let firstOutcome = await firstRun.orchestrator.run(candidate: candidate, preRefreshIdentity: old)
        #expect(firstOutcome != .converged(HelperConvergenceMarker(
            executableDigest: Fixture.embeddedDigest,
            buildNumber: Fixture.bundledBuild,
            protocolVersion: Fixture.expectedProtocol
        )))

        // Nothing was persisted, so the next launch sees the same drift it saw before.
        #expect(
            Fixture.plan(
                status: .installedCompatible,
                info: Fixture.info(protocolVersion: 5, build: Fixture.bundledBuild),
                identity: old,
                marker: nil
            ) == .approvalPreservingRefresh
        )

        let secondRun = ScriptedHelper(
            refreshResults: [.success(())],
            snapshots: [Fixture.snapshot(
                identity: Fixture.identity(digest: Fixture.embeddedDigest, launch: "new-process")
            )]
        )
        let secondOutcome = await secondRun.orchestrator.run(candidate: candidate, preRefreshIdentity: old)
        #expect(secondOutcome == .converged(HelperConvergenceMarker(
            executableDigest: Fixture.embeddedDigest,
            buildNumber: Fixture.bundledBuild,
            protocolVersion: Fixture.expectedProtocol
        )))
    }

    @Test("a malformed identity answer never counts as convergence")
    func malformedIdentityIsRejected() {
        let unreadable = Fixture.identity(digest: "", launch: "new-process")
        #expect(HelperExecutableRefreshOrchestrator.convergedMarker(
            snapshot: Fixture.snapshot(identity: unreadable),
            candidate: Fixture.candidate,
            preRefreshIdentity: nil
        ) == nil)

        let disagreeingMetadata = Fixture.identity(
            digest: Fixture.embeddedDigest,
            launch: "new-process",
            build: Fixture.bundledBuild - 1
        )
        #expect(HelperExecutableRefreshOrchestrator.convergedMarker(
            snapshot: Fixture.snapshot(identity: disagreeingMetadata),
            candidate: Fixture.candidate,
            preRefreshIdentity: nil
        ) == nil)
    }

    @Test("a protocol-5 helper that reports no identity at all is not accepted")
    func absentIdentityIsNotConvergence() {
        #expect(HelperExecutableRefreshOrchestrator.convergedMarker(
            snapshot: Fixture.snapshot(identity: nil),
            candidate: Fixture.candidate,
            preRefreshIdentity: nil
        ) == nil)
    }
}

// MARK: - HelperConvergenceMarkerStoreTests

struct HelperConvergenceMarkerStoreTests {
    @Test("the marker is namespaced through RockxyIdentity and round-trips only when well formed")
    func markerRoundTripsUnderTheNamespacedKey() throws {
        let identity = RockxyIdentity.current
        let suiteName = "rockxy.tests.helper-marker.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(HelperConvergenceMarkerStore.markerKey(identity: identity)
            == identity.defaultsKey("helper.verifiedExecutableIdentity"))
        #expect(HelperConvergenceMarkerStore.load(defaults: defaults, identity: identity) == nil)

        let marker = HelperConvergenceMarker(
            executableDigest: Fixture.embeddedDigest,
            buildNumber: Fixture.bundledBuild,
            protocolVersion: Fixture.expectedProtocol
        )
        HelperConvergenceMarkerStore.save(marker, defaults: defaults, identity: identity)
        #expect(HelperConvergenceMarkerStore.load(defaults: defaults, identity: identity) == marker)

        // A malformed digest is never recorded: it would compare equal to nothing and be trusted
        // as if it had.
        HelperConvergenceMarkerStore.clear(defaults: defaults, identity: identity)
        HelperConvergenceMarkerStore.save(
            HelperConvergenceMarker(executableDigest: "nope", buildNumber: 10, protocolVersion: 5),
            defaults: defaults,
            identity: identity
        )
        #expect(HelperConvergenceMarkerStore.load(defaults: defaults, identity: identity) == nil)
    }
}

// MARK: - HelperExecutableDigestTests

struct HelperExecutableDigestTests {
    @Test("the digest is the streamed SHA-256 of the file's bytes")
    func digestMatchesKnownVector() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-digest-\(UUID().uuidString).bin")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try HelperExecutableDigest.sha256Hex(atPath: url.path)
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("the same bytes digest identically however large the file is chunked")
    func digestIsStableAcrossChunkBoundaries() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-digest-\(UUID().uuidString).bin")
        // Larger than the internal chunk size, so the streaming path is exercised.
        let payload = Data(repeating: 0x5A, count: (1 << 20) + 12_345)
        try payload.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try HelperExecutableDigest.sha256Hex(atPath: url.path)
        let second = try HelperExecutableDigest.sha256Hex(atPath: url.path)
        #expect(first == second)
        #expect(HelperExecutableDigest.isWellFormedDigest(first))
    }

    @Test("an oversized, empty, or missing file is a failure rather than a digest")
    func unusableInputsFailClosed() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-digest-\(UUID().uuidString).bin")
        try Data(repeating: 0x11, count: 4_096).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: HelperExecutableDigest.Failure.tooLarge(path: url.path)) {
            try HelperExecutableDigest.sha256Hex(atPath: url.path, maximumByteCount: 1_024)
        }

        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-digest-empty-\(UUID().uuidString).bin")
        try Data().write(to: empty)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(throws: HelperExecutableDigest.Failure.unreadable(path: empty.path)) {
            try HelperExecutableDigest.sha256Hex(atPath: empty.path)
        }

        let missing = "/nonexistent/rockxy/\(UUID().uuidString)"
        #expect(throws: HelperExecutableDigest.Failure.unreadable(path: missing)) {
            try HelperExecutableDigest.sha256Hex(atPath: missing)
        }
    }

    @Test("only 64 lowercase hex characters are comparable")
    func wellFormednessIsExact() {
        #expect(HelperExecutableDigest.isWellFormedDigest(String(repeating: "0", count: 64)))
        #expect(HelperExecutableDigest.isWellFormedDigest(String(repeating: "f", count: 64)))
        for candidate in [
            "",
            String(repeating: "a", count: 63),
            String(repeating: "a", count: 65),
            String(repeating: "A", count: 64),
            String(repeating: "g", count: 64),
        ] {
            #expect(!HelperExecutableDigest.isWellFormedDigest(candidate))
        }
    }

    @Test("this process can locate and digest its own executable")
    func currentProcessExecutableIsDigestible() throws {
        // The same resolution the helper uses to describe itself. It must name a real file, or the
        // helper would report an empty digest and every update would appear unverifiable.
        let path = HelperExecutableLocation.currentProcessExecutablePath()
        #expect(!path.isEmpty)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try HelperExecutableDigest.isWellFormedDigest(HelperExecutableDigest.sha256Hex(atPath: path)))
    }
}
