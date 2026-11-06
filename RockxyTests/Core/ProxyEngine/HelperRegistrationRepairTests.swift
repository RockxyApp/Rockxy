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

    @Test("a launchctl listing yields state, active count and BTM uuid, and ignores job state")
    func snapshotParsing() {
        let parsed = Self.snapshot(Self.btmListing)
        #expect(parsed.presence == .loaded)
        #expect(parsed.state == "spawn scheduled")
        #expect(parsed.activeCount == 0)
        #expect(parsed.btmUUID == "06F53892-A982-446F-8E1E-6B962061223F")
        #expect(parsed.isSpawnScheduledAndIdle)

        let noUUID = Self
            .snapshot("system/com.amunx.rockxy.helper = {\n\tactive count = 0\n\tstate = spawn scheduled\n}")
        #expect(noUUID.btmUUID == nil)
        #expect(noUUID.isSpawnScheduledAndIdle)

        let idle = Self.snapshot("system/com.amunx.rockxy.helper = {\n\tactive count = 0\n\tstate = not running\n}")
        #expect(!idle.isSpawnScheduledAndIdle)
        let running = Self
            .snapshot("system/com.amunx.rockxy.helper = {\n\tactive count = 1\n\tstate = spawn scheduled\n}")
        #expect(!running.isSpawnScheduledAndIdle)
        // `job state` must not be mistaken for `state`.
        let jobStateOnly = Self
            .snapshot("system/com.amunx.rockxy.helper = {\n\tactive count = 0\n\tjob state = spawn scheduled\n}")
        #expect(jobStateOnly.state == nil)
        #expect(!Self.snapshot("Could not find service \"x\"", status: 113).isSpawnScheduledAndIdle)
    }

    @Test("record identity compares uuids and reports unknown when either cannot be read")
    func recordIdentity() {
        let id = "06F53892-A982-446F-8E1E-6B962061223F"
        #expect(BTMRecordIdentity.compare(before: id, after: id.lowercased()) == .same)
        #expect(BTMRecordIdentity.compare(before: id, after: "11111111-2222-3333-4444-555555555555") == .different)
        #expect(BTMRecordIdentity.compare(before: nil, after: id) == .unknown)
        #expect(BTMRecordIdentity.compare(before: id, after: nil) == .unknown)
        #expect(BTMRecordIdentity.compare(before: "  ", after: id) == .unknown)
        #expect(BTMRecordIdentity.compare(before: nil, after: nil) == .unknown)
    }

    @Test("same record reused after re-register is unresolvable")
    func sameRecordIsUnresolvable() {
        let job = Self.snapshot(Self.btmListing)
        #expect(HelperManager.isUnresolvableRecord(job: job, beforeBTMUUID: job.btmUUID))
        #expect(
            HelperManager.registrationRepairOutcome(
                registerError: nil,
                serviceStatus: .enabled,
                helperAnswered: false,
                jobAfter: job,
                beforeBTMUUID: job.btmUUID
            ) == .recordUnresolvable
        )
    }

    @Test("an unreadable before-uuid does not block the finding, because launchd had no job to print")
    func unreadableBeforeUUID() {
        let job = Self.snapshot(Self.btmListing)
        #expect(HelperManager.isUnresolvableRecord(job: job, beforeBTMUUID: nil))
        // Unreadable after as well: the spawn-scheduled shape alone still decides.
        let noUUID = Self
            .snapshot("system/com.amunx.rockxy.helper = {\n\tactive count = 0\n\tstate = spawn scheduled\n}")
        #expect(HelperManager.isUnresolvableRecord(job: noUUID, beforeBTMUUID: "06F53892-A982-446F-8E1E-6B962061223F"))
    }

    @Test("a new record uuid is not unresolvable, so it stays an ordinary failure")
    func newRecordIsNotUnresolvable() {
        let job = Self.snapshot(Self.btmListing)
        #expect(!HelperManager.isUnresolvableRecord(job: job, beforeBTMUUID: "11111111-2222-3333-4444-555555555555"))
        #expect(
            HelperManager.registrationRepairOutcome(
                registerError: nil,
                serviceStatus: .enabled,
                helperAnswered: false,
                jobAfter: job,
                beforeBTMUUID: "11111111-2222-3333-4444-555555555555"
            ) == .stillBroken
        )
    }

    @Test("a healthy or merely idle job is never reported as unresolvable")
    func healthyJobIsNotUnresolvable() {
        let idle = Self.snapshot("system/com.amunx.rockxy.helper = {\n\tactive count = 0\n\tstate = not running\n}")
        #expect(!HelperManager.isUnresolvableRecord(job: idle, beforeBTMUUID: nil))
        #expect(
            HelperManager.registrationRepairOutcome(
                registerError: nil,
                serviceStatus: .enabled,
                helperAnswered: true,
                jobAfter: Self.snapshot(Self.btmListing),
                beforeBTMUUID: nil
            ) == .recovered
        )
        #expect(!HelperManager.isUnresolvableRecord(job: .undetermined, beforeBTMUUID: nil))
    }

    @Test("a later launch recognises the same unresolvable record without repeating the repair")
    func laterLaunchRecognisesRecord() {
        let job = Self.snapshot(Self.btmListing)
        let previous = HelperRegistrationRepairRecord(
            outcome: .recordUnresolvable,
            appBuild: Self.build,
            attemptedAt: Date(timeIntervalSince1970: 0),
            btmUUID: job.btmUUID
        )
        #expect(HelperManager.recordStillUnresolvable(previous: previous, job: job, xpcAnswered: false))
        // XPC answering, no history, other history, or a different record all clear it.
        #expect(!HelperManager.recordStillUnresolvable(previous: previous, job: job, xpcAnswered: true))
        #expect(!HelperManager.recordStillUnresolvable(previous: nil, job: job, xpcAnswered: false))
        #expect(
            !HelperManager.recordStillUnresolvable(
                previous: Self.record(.stillBroken, build: Self.build),
                job: job,
                xpcAnswered: false
            )
        )
        var replaced = previous
        replaced.btmUUID = "11111111-2222-3333-4444-555555555555"
        #expect(!HelperManager.recordStillUnresolvable(previous: replaced, job: job, xpcAnswered: false))
    }

    @Test("unresolvable is terminal for the build, maps to a stopped wait, and persists its uuid")
    func unresolvableIsTerminalAndPersists() {
        #expect(HelperRegistrationRepairRecord.Outcome.recordUnresolvable.isTerminalForBuild)
        #expect(HelperManager.registrationRepairResult(for: .recordUnresolvable) == .stillBroken)

        let defaults = IsolatedDefaultsSuite.make(prefix: "Rockxy.HelperRegistrationRepairTests")
        let withUUID = HelperRegistrationRepairRecord(
            outcome: .recordUnresolvable,
            appBuild: Self.build,
            attemptedAt: Date(timeIntervalSince1970: 1_700_000_000),
            btmUUID: "06F53892-A982-446F-8E1E-6B962061223F"
        )
        HelperRegistrationRepairStore.save(withUUID, defaults: defaults)
        #expect(HelperRegistrationRepairStore.load(defaults: defaults) == withUUID)

        var withoutUUID = withUUID
        withoutUUID.btmUUID = nil
        HelperRegistrationRepairStore.save(withoutUUID, defaults: defaults)
        #expect(HelperRegistrationRepairStore.load(defaults: defaults) == withoutUUID)
    }

    @Test("the remedy copy is password-free, never suggests restarting, and names a real control")
    func remedyCopy() {
        let message = HelperManager.registrationRecordUnresolvableMessage
        #expect(message != HelperManager.registrationBrokenMessage)
        #expect(!message.lowercased().contains("restart"))
        #expect(!message.lowercased().contains("force reset"))

        // Two earlier versions of this copy named actions that do not exist for this state.
        // It must not send the user to Login Items & Extensions: an SMAppService background item
        // shows there as a switch with no remove button, and that switch maps to the aggregate
        // "background tasks" record, which is already enabled in this state. The records that are
        // disabled are the per-bundle "app" records, which that pane does not list at all.
        #expect(!message.lowercased().contains("remove"))
        #expect(!message.lowercased().contains("delete"))
        #expect(!message.contains("Login Items"))
        #expect(!message.lowercased().contains("background"))
        #expect(message.lowercased().contains("applications folder"))
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

    // MARK: - Unresolvable BTM record

    private static let btmListing = """
    system/com.amunx.rockxy.helper = {
    \tactive count = 0
    \ttype = LaunchDaemon
    \tstate = spawn scheduled
    \tprogram identifier = Contents/Library/HelperTools/RockxyHelperTool (mode: 2)
    \tparent bundle identifier = com.amunx.rockxy.community
    \tBTM uuid = 06F53892-A982-446F-8E1E-6B962061223F
    \tjob state = uninitialized
    }
    """

    private static let build = "0.41.0 (62)"

    private static let dead = HelperRegistrationEvidence(
        registrationIsEnabled: true,
        launchdJob: .absent,
        xpcAnswered: false,
        legacyArtifactsPresent: false,
        isLegacyFallbackBundle: false
    )

    private static func snapshot(_ output: String, status: Int32 = 0) -> LaunchdJobSnapshot {
        HelperLaunchdProbe.makeSnapshot(
            exitStatus: status,
            wasSignalled: false,
            output: output,
            machService: "com.amunx.rockxy.helper"
        )
    }

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
