import Foundation
@testable import Rockxy
import ServiceManagement
import Testing

// MARK: - HelperRegistrationRepairTests

// The dead-registration repair mutates `SMAppService`, which cannot be faked here. Everything that
// decides whether, and what, to mutate is a pure function, so these tests drive those decisions
// directly: the detection predicate, the one-attempt rate limit, the persisted record, and the
// approval routing. No test registers, unregisters, or reads live helper state.

struct HelperRegistrationRepairTests {
    // MARK: Internal

    // MARK: - Detection predicate

    @Test("the exact dead state is recognised")
    func deadStateIsRecognised() {
        #expect(HelperManager.isDeadRegistration(Self.dead))
    }

    @Test("each leg missing means the registration is not dead")
    func everyLegIsRequired() {
        var notEnabled = Self.dead
        notEnabled.registrationIsEnabled = false
        var jobLoaded = Self.dead
        jobLoaded.launchdJob = .loaded
        var jobUndetermined = Self.dead
        jobUndetermined.launchdJob = .undetermined
        var answered = Self.dead
        answered.xpcAnswered = true

        #expect(!HelperManager.isDeadRegistration(notEnabled))
        #expect(!HelperManager.isDeadRegistration(jobLoaded))
        #expect(!HelperManager.isDeadRegistration(jobUndetermined))
        #expect(!HelperManager.isDeadRegistration(answered))
    }

    @Test("a transient XPC timeout against a loaded job never qualifies")
    func transientTimeoutDoesNotTrigger() {
        // Enabled, XPC silent, but launchd holds the job: a slow start, or an old daemon refusing
        // the relaunched app. The existing launch wait owns that; repair must not.
        let transient = HelperRegistrationEvidence(
            registrationIsEnabled: true,
            launchdJob: .loaded,
            xpcAnswered: false,
            legacyArtifactsPresent: false,
            isLegacyFallbackBundle: false
        )
        #expect(!HelperManager.isDeadRegistration(transient))
        #expect(
            HelperManager.registrationRepairDecision(
                evidence: transient,
                previous: nil,
                currentAppBuild: Self.build,
                attemptedThisLaunch: false
            ) == .notDead
        )
    }

    @Test("legacy artifacts and Xcode bundles are excluded from the user-level repair")
    func legacyRoutesAreExcluded() {
        var legacyArtifacts = Self.dead
        legacyArtifacts.legacyArtifactsPresent = true
        var xcodeBundle = Self.dead
        xcodeBundle.isLegacyFallbackBundle = true

        #expect(!HelperManager.isDeadRegistration(legacyArtifacts))
        #expect(!HelperManager.isDeadRegistration(xcodeBundle))
    }

    // MARK: - launchd leg

    @Test("launchctl results map to presence, and anything unexpected is undetermined")
    func launchctlClassification() {
        let name = "com.example.helper"
        let missing = "Bad request.\nCould not find service \"\(name)\" in domain for system\n"
        let listing = "system/\(name) = {\n\tactive count = 0\n}\n"

        func classify(_ status: Int32, signalled: Bool = false, _ output: String) -> LaunchdJobPresence {
            HelperLaunchdProbe.classify(
                exitStatus: status,
                wasSignalled: signalled,
                output: output,
                machService: name
            )
        }

        #expect(classify(113, missing) == .absent)
        #expect(classify(0, listing) == .loaded)
        // A clean exit that does not describe this job proves nothing.
        #expect(classify(0, "") == .undetermined)
        #expect(classify(0, "system/other.job = {\n}\n") == .undetermined)
        // A failure that is not the explicit not-found message is not evidence of absence.
        #expect(classify(1, "Operation not permitted") == .undetermined)
        #expect(classify(113, "") == .undetermined)
        #expect(classify(15, signalled: true, missing) == .undetermined)
    }

    @Test("a Mach service nobody registered resolves as absent")
    func unregisteredNameIsAbsent() async {
        let name = "com.rockxy.tests.no-such-service.\(UUID().uuidString)"
        #expect(await HelperLaunchdProbe.presence(ofMachService: name) == .absent)
    }

    // MARK: - Rate limit and record

    @Test("a dead registration with no history gets one attempt")
    func firstAttemptIsAllowed() {
        #expect(Self.decision(previous: nil, attemptedThisLaunch: false) == .attempt)
    }

    @Test("the second attempt in the same launch is refused")
    func oneAttemptPerLaunch() {
        #expect(Self.decision(previous: nil, attemptedThisLaunch: true) == .alreadyAttemptedThisLaunch)
        #expect(
            Self.decision(previous: Self.record(.recovered, build: "0.0"), attemptedThisLaunch: true)
                == .alreadyAttemptedThisLaunch
        )
    }

    @Test("tried and still broken on this build is not repeated")
    func failedOnThisBuildIsNotRepeated() {
        for outcome in [HelperRegistrationRepairRecord.Outcome.stillBroken, .registerFailed] {
            #expect(
                Self.decision(previous: Self.record(outcome, build: Self.build), attemptedThisLaunch: false)
                    == .alreadyFailedOnThisBuild
            )
        }
    }

    @Test("a new app build earns a fresh attempt")
    func newBuildRetries() {
        #expect(
            Self.decision(previous: Self.record(.stillBroken, build: "0.40.0 (61)"), attemptedThisLaunch: false)
                == .attempt
        )
    }

    @Test("non-terminal history does not block a later attempt")
    func nonTerminalHistoryDoesNotBlock() {
        for outcome in [HelperRegistrationRepairRecord.Outcome.recovered, .requiresApproval] {
            #expect(
                Self.decision(previous: Self.record(outcome, build: Self.build), attemptedThisLaunch: false)
                    == .attempt
            )
        }
    }

    @Test("evidence that is not dead outranks every history rule")
    func notDeadWinsOverHistory() {
        var healthy = Self.dead
        healthy.xpcAnswered = true
        #expect(
            HelperManager.registrationRepairDecision(
                evidence: healthy,
                previous: Self.record(.stillBroken, build: Self.build),
                currentAppBuild: Self.build,
                attemptedThisLaunch: true
            ) == .notDead
        )
    }

    @Test("the record round-trips and its absence means never tried")
    func recordPersistence() {
        let defaults = IsolatedDefaultsSuite.make(prefix: "Rockxy.HelperRegistrationRepairTests")
        #expect(HelperRegistrationRepairStore.load(defaults: defaults) == nil)

        let record = HelperRegistrationRepairRecord(
            outcome: .stillBroken,
            appBuild: Self.build,
            attemptedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        HelperRegistrationRepairStore.save(record, defaults: defaults)
        #expect(HelperRegistrationRepairStore.load(defaults: defaults) == record)

        defaults.set(
            ["outcome": "unknown-future-value", "build": "x", "time": 1.0],
            forKey: HelperRegistrationRepairStore.key()
        )
        #expect(HelperRegistrationRepairStore.load(defaults: defaults) == nil)
    }

    @Test("the persisted key is identity-namespaced")
    func keyIsNamespaced() {
        #expect(HelperRegistrationRepairStore.key() == RockxyIdentity.current.defaultsKey("helper.registrationRepair"))
    }

    // MARK: - Outcome and approval routing

    @Test("register needing approval routes to approval, not failure")
    func approvalRoutesToApproval() {
        let denied = NSError(domain: "SMAppServiceErrorDomain", code: Int(kSMErrorLaunchDeniedByUser))
        #expect(
            HelperManager.registrationRepairOutcome(
                registerError: denied,
                serviceStatus: .notRegistered,
                helperAnswered: false
            ) == .requiresApproval
        )
        #expect(
            HelperManager.registrationRepairOutcome(
                registerError: nil,
                serviceStatus: .requiresApproval,
                helperAnswered: false
            ) == .requiresApproval
        )
        // The user-facing copy is the existing approval message, not "could not finish updating".
        #expect(
            HelperManager.approvalMessage(error: denied, serviceStatus: .requiresApproval)
                == HelperManager.HelperOperationError.helperApprovalRequired.localizedDescription
        )
    }

    @Test("an unrelated register error is a failure, and a silent helper after register is still broken")
    func failureAndStillBroken() {
        let unrelated = NSError(domain: "SMAppServiceErrorDomain", code: 9_999)
        #expect(
            HelperManager.registrationRepairOutcome(
                registerError: unrelated,
                serviceStatus: .notRegistered,
                helperAnswered: false
            ) == .registerFailed
        )
        #expect(
            HelperManager.registrationRepairOutcome(
                registerError: nil,
                serviceStatus: .enabled,
                helperAnswered: false
            ) == .stillBroken
        )
        #expect(
            HelperManager.registrationRepairOutcome(
                registerError: nil,
                serviceStatus: .enabled,
                helperAnswered: true
            ) == .recovered
        )
    }

    @Test("outcomes map to the results the launch flow acts on")
    func resultMapping() {
        #expect(HelperManager.registrationRepairResult(for: .recovered) == .recovered)
        #expect(HelperManager.registrationRepairResult(for: .requiresApproval) == .requiresApproval)
        #expect(HelperManager.registrationRepairResult(for: .stillBroken) == .stillBroken)
        #expect(HelperManager.registrationRepairResult(for: .registerFailed) == .stillBroken)
    }

    // MARK: - Launch wait and surfacing

    /// `shouldWaitForLaunchd` is static on a main-actor type, so the test has to be isolated too.
    @MainActor
    @Test("a dead registration ends the launch wait; a live-but-silent one keeps it")
    func launchWaitDistinguishesTheTwo() {
        typealias Attempt = HelperUpdateStartupRecoveryOrchestrator.Attempt
        #expect(
            !HelperUpdateStartupRecoveryOrchestrator.shouldWaitForLaunchd(
                Attempt(outcome: .blocked(.registrationBroken), registrationIsEnabled: true)
            )
        )
        #expect(
            HelperUpdateStartupRecoveryOrchestrator.shouldWaitForLaunchd(
                Attempt(outcome: .blocked(.unreachable), registrationIsEnabled: true)
            )
        )
    }

    @Test("the direct-mode warning names the broken registration only when it is known")
    func warningNamesBrokenRegistration() {
        func message(_ status: HelperManager.HelperStatus, broken: Bool) -> String? {
            ReadinessCoordinator.degradedCaptureWarning(
                tlsRejectionEvidence: TLSRejectionEvidence(),
                isSystemTrustValidated: true,
                proxyMode: .direct,
                helperReadiness: status,
                helperSigningIssue: nil,
                helperRegistrationBroken: broken
            )?.message
        }

        let generic = message(.unreachable, broken: false)
        let broken = message(.unreachable, broken: true)
        #expect(generic != nil)
        #expect(broken != nil)
        #expect(generic != broken)
        // The flag only matters while the helper is unreachable.
        #expect(message(.notInstalled, broken: true) == message(.notInstalled, broken: false))
        // And nothing is shown outside direct mode, so a healthy helper stays quiet.
        #expect(
            ReadinessCoordinator.degradedCaptureWarning(
                tlsRejectionEvidence: TLSRejectionEvidence(),
                isSystemTrustValidated: true,
                proxyMode: .helper,
                helperReadiness: .unreachable,
                helperSigningIssue: nil,
                helperRegistrationBroken: true
            ) == nil
        )
    }

    // MARK: Private

    private static let build = "0.41.0 (62)"

    private static let dead = HelperRegistrationEvidence(
        registrationIsEnabled: true,
        launchdJob: .absent,
        xpcAnswered: false,
        legacyArtifactsPresent: false,
        isLegacyFallbackBundle: false
    )

    private static func record(
        _ outcome: HelperRegistrationRepairRecord.Outcome,
        build: String
    )
        -> HelperRegistrationRepairRecord
    {
        HelperRegistrationRepairRecord(outcome: outcome, appBuild: build, attemptedAt: Date(timeIntervalSince1970: 0))
    }

    private static func decision(
        previous: HelperRegistrationRepairRecord?,
        attemptedThisLaunch: Bool
    )
        -> HelperManager.RegistrationRepairDecision
    {
        HelperManager.registrationRepairDecision(
            evidence: dead,
            previous: previous,
            currentAppBuild: build,
            attemptedThisLaunch: attemptedThisLaunch
        )
    }
}
