import Foundation
import os
import ServiceManagement

// Detects a helper registration that macOS approved but can no longer resolve, and repairs it
// with the user-level SMAppService calls only. Nothing here can prompt for an administrator
// password, and nothing here widens the Xcode-only privileged-shell fallback.

// MARK: - LaunchdJobPresence

/// Whether launchd currently serves the helper's Mach service.
enum LaunchdJobPresence: Equatable, Sendable {
    /// The Mach service resolves, so launchd loaded the job (it may or may not be running).
    case loaded
    /// launchd answered "unknown service": no job owns the name.
    case absent
    /// The lookup failed for any other reason. Never treated as evidence of a dead registration.
    case undetermined
}

// MARK: - LaunchdJobSnapshot

/// What one `launchctl print system/<name>` told us about the helper's job.
struct LaunchdJobSnapshot: Equatable, Sendable {
    static let undetermined = LaunchdJobSnapshot(presence: .undetermined)

    var presence: LaunchdJobPresence
    /// The top-level `state = …` line, for example "spawn scheduled" or "not running".
    var state: String?
    var activeCount: Int?
    /// The `BTM uuid = …` line: the Background Task Management record that owns the job. Only
    /// present while the job exists, so it cannot be read for a registration launchd has no job
    /// for. Not guaranteed on every macOS release; nil means "could not read", never "none".
    var btmUUID: String?

    /// launchd wants to start the job and has not managed to: the shape of a record whose parent
    /// bundle cannot be resolved. An on-demand job that simply has not been called is
    /// "not running", so this is not what a healthy idle helper looks like.
    var isSpawnScheduledAndIdle: Bool {
        presence == .loaded && state == "spawn scheduled" && activeCount == 0
    }
}

// MARK: - BTMRecordIdentity

/// Whether two readings of the BTM record uuid describe the same record.
enum BTMRecordIdentity: Equatable, Sendable {
    case same
    case different
    /// At least one side could not be read. Never evidence of either.
    case unknown

    // MARK: Internal

    static func compare(before: String?, after: String?) -> BTMRecordIdentity {
        guard let before = normalized(before), let after = normalized(after) else {
            return .unknown
        }
        return before == after ? .same : .different
    }

    // MARK: Private

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.uppercased()
    }
}

// MARK: - HelperLaunchdProbe

/// Asks launchd whether the system domain has a job for a Mach service, using the documented
/// `launchctl print system/<name>` that a person would run to establish the same thing.
///
/// The spawn is bounded by `BoundedProcessRun`, so a wedged launchd cannot hang a launch, and it
/// only ever runs once the helper is already unreachable. Any outcome that is not an explicit
/// "Could not find service" or an explicit job listing is `.undetermined`, which never repairs.
enum HelperLaunchdProbe {
    // MARK: Internal

    static let launchctlURL = URL(fileURLWithPath: "/bin/launchctl")
    static let timeout: TimeInterval = 5
    /// `print` output for a job is a few KB; this only stops a runaway child.
    static let outputLimit = 256 * 1_024

    static func presence(ofMachService name: String) async -> LaunchdJobPresence {
        await snapshot(ofMachService: name).presence
    }

    static func snapshot(ofMachService name: String) async -> LaunchdJobSnapshot {
        do {
            let result = try await BoundedProcessRun.runDetached(
                executable: launchctlURL,
                arguments: ["print", "system/\(name)"],
                timeout: timeout,
                outputLimit: outputLimit,
                mergesStandardError: true
            )
            return makeSnapshot(
                exitStatus: result.status,
                wasSignalled: result.wasSignalled,
                output: result.combinedText,
                machService: name
            )
        } catch {
            // Timeout, overflow, or a launch failure: no evidence either way.
            return .undetermined
        }
    }

    /// Pure: classification plus the fields of a listing that the unresolvable-record check reads.
    static func makeSnapshot(
        exitStatus: Int32,
        wasSignalled: Bool,
        output: String,
        machService: String
    )
        -> LaunchdJobSnapshot
    {
        let presence = classify(
            exitStatus: exitStatus,
            wasSignalled: wasSignalled,
            output: output,
            machService: machService
        )
        guard presence == .loaded else {
            return LaunchdJobSnapshot(presence: presence)
        }
        var snapshot = LaunchdJobSnapshot(presence: presence)
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if snapshot.state == nil, let value = value(of: "state", in: line) {
                snapshot.state = value
            } else if snapshot.activeCount == nil, let value = value(of: "active count", in: line) {
                snapshot.activeCount = Int(value)
            } else if snapshot.btmUUID == nil, let value = value(of: "BTM uuid", in: line) {
                snapshot.btmUUID = value
            }
        }
        return snapshot
    }

    /// Pure mapping from a finished `launchctl print`, so it is testable without launchd.
    static func classify(
        exitStatus: Int32,
        wasSignalled: Bool,
        output: String,
        machService: String
    )
        -> LaunchdJobPresence
    {
        guard !wasSignalled else {
            return .undetermined
        }
        if exitStatus == 0 {
            return output.hasPrefix("system/\(machService)") ? .loaded : .undetermined
        }
        return output.contains("Could not find service") ? .absent : .undetermined
    }

    // MARK: Private

    /// `key = value` for an exact key, so `state` never matches `job state`.
    private static func value(of key: String, in line: String) -> String? {
        let prefix = "\(key) = "
        guard line.hasPrefix(prefix) else {
            return nil
        }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

// MARK: - HelperRegistrationEvidence

/// Everything the dead-registration decision is allowed to look at.
struct HelperRegistrationEvidence: Equatable, Sendable {
    /// `SMAppService` reports the daemon as `.enabled`.
    var registrationIsEnabled: Bool
    var launchdJob: LaunchdJobPresence
    /// A fresh XPC probe received an answer.
    var xpcAnswered: Bool
    /// The Xcode-only legacy LaunchDaemon artifacts exist; some other mechanism owns the job.
    var legacyArtifactsPresent: Bool
    /// This is a DerivedData bundle, which already has its own repair route.
    var isLegacyFallbackBundle: Bool
}

// MARK: - HelperRegistrationRepairRecord

/// What the last automatic registration repair did, persisted so the next launch can tell
/// "never tried" (no record) from "tried and still broken".
struct HelperRegistrationRepairRecord: Equatable, Sendable {
    enum Outcome: String, Sendable {
        case recovered
        case requiresApproval
        case stillBroken
        case registerFailed
        /// launchd has a job for the helper but its approved BTM record cannot be resolved to the
        /// app that registered it, so re-registering reuses the same dead record.
        case recordUnresolvable

        // MARK: Internal

        /// Outcomes after which repeating the identical repair on the identical build is noise.
        var isTerminalForBuild: Bool {
            self == .stillBroken || self == .registerFailed || self == .recordUnresolvable
        }
    }

    var outcome: Outcome
    /// `CFBundleShortVersionString (CFBundleVersion)` of the app that made the attempt.
    var appBuild: String
    var attemptedAt: Date
    /// The BTM record uuid read after the attempt, when launchd exposed one.
    var btmUUID: String?
}

// MARK: - HelperRegistrationRepairStore

enum HelperRegistrationRepairStore {
    // MARK: Internal

    static func key(identity: RockxyIdentity = .current) -> String {
        identity.defaultsKey("helper.registrationRepair")
    }

    static func load(
        defaults: UserDefaults = .standard,
        identity: RockxyIdentity = .current
    )
        -> HelperRegistrationRepairRecord?
    {
        guard let stored = defaults.dictionary(forKey: key(identity: identity)),
              let raw = stored[outcomeField] as? String,
              let outcome = HelperRegistrationRepairRecord.Outcome(rawValue: raw),
              let build = stored[buildField] as? String,
              let timestamp = stored[timeField] as? Double else
        {
            return nil
        }
        return HelperRegistrationRepairRecord(
            outcome: outcome,
            appBuild: build,
            attemptedAt: Date(timeIntervalSince1970: timestamp),
            btmUUID: stored[btmField] as? String
        )
    }

    static func save(
        _ record: HelperRegistrationRepairRecord,
        defaults: UserDefaults = .standard,
        identity: RockxyIdentity = .current
    ) {
        var stored: [String: Any] = [
            outcomeField: record.outcome.rawValue,
            buildField: record.appBuild,
            timeField: record.attemptedAt.timeIntervalSince1970,
        ]
        if let uuid = record.btmUUID {
            stored[btmField] = uuid
        }
        defaults.set(stored, forKey: key(identity: identity))
    }

    // MARK: Private

    private static let outcomeField = "outcome"
    private static let buildField = "build"
    private static let timeField = "time"
    private static let btmField = "btm"
}

// MARK: - HelperManager registration repair

extension HelperManager {
    enum RegistrationRepairDecision: Equatable {
        /// The evidence does not describe a dead registration. Nothing is touched.
        case notDead
        /// Dead, and an attempt is allowed.
        case attempt
        /// Dead, but this launch already made its one attempt.
        case alreadyAttemptedThisLaunch
        /// Dead, and the identical repair already failed on this exact app build.
        case alreadyFailedOnThisBuild
    }

    enum RegistrationRepairResult: Equatable {
        /// Not the dead-registration state. The caller keeps whatever outcome it had.
        case notApplicable
        /// The helper answers again.
        case recovered
        /// macOS needs the user to approve the re-registered helper in Login Items.
        case requiresApproval
        /// Registration is dead and the repair did not, or may not, fix it.
        case stillBroken
    }

    /// A registration is dead only when macOS says it is enabled, launchd has no job for the
    /// Mach service, and XPC did not answer. Each leg alone is common: an enabled registration
    /// with a live job that is slow to answer is a transient or a stale old daemon, and a missing
    /// job on a registration that is not enabled is simply "not installed".
    nonisolated static func isDeadRegistration(_ evidence: HelperRegistrationEvidence) -> Bool {
        evidence.registrationIsEnabled
            && evidence.launchdJob == .absent
            && !evidence.xpcAnswered
            && !evidence.legacyArtifactsPresent
            && !evidence.isLegacyFallbackBundle
    }

    nonisolated static func registrationRepairDecision(
        evidence: HelperRegistrationEvidence,
        previous: HelperRegistrationRepairRecord?,
        currentAppBuild: String,
        attemptedThisLaunch: Bool
    )
        -> RegistrationRepairDecision
    {
        guard isDeadRegistration(evidence) else {
            return .notDead
        }
        guard !attemptedThisLaunch else {
            return .alreadyAttemptedThisLaunch
        }
        if let previous, previous.outcome.isTerminalForBuild, previous.appBuild == currentAppBuild {
            return .alreadyFailedOnThisBuild
        }
        return .attempt
    }

    /// Maps what the repair observed after `register()` to the outcome that is persisted.
    nonisolated static func registrationRepairOutcome(
        registerError: Error?,
        serviceStatus: SMAppService.Status,
        helperAnswered: Bool,
        jobAfter: LaunchdJobSnapshot? = nil,
        beforeBTMUUID: String? = nil
    )
        -> HelperRegistrationRepairRecord.Outcome
    {
        if let registerError {
            return requiresApproval(error: registerError, serviceStatus: serviceStatus)
                ? .requiresApproval
                : .registerFailed
        }
        if serviceStatus == .requiresApproval {
            return .requiresApproval
        }
        if helperAnswered {
            return .recovered
        }
        if let jobAfter, isUnresolvableRecord(job: jobAfter, beforeBTMUUID: beforeBTMUUID) {
            return .recordUnresolvable
        }
        return .stillBroken
    }

    /// The registered job exists and launchd is trying to spawn it, yet nothing answers and the
    /// record is not provably a new one. `beforeBTMUUID` is usually unreadable on the first
    /// attempt, because launchd had no job to print; `.unknown` therefore does not block the
    /// finding, but a uuid that demonstrably changed does, since a new record should resolve.
    nonisolated static func isUnresolvableRecord(job: LaunchdJobSnapshot, beforeBTMUUID: String?) -> Bool {
        job.isSpawnScheduledAndIdle
            && BTMRecordIdentity.compare(before: beforeBTMUUID, after: job.btmUUID) != .different
    }

    /// A later launch finding the same unresolvable record again, with no mutation needed.
    nonisolated static func recordStillUnresolvable(
        previous: HelperRegistrationRepairRecord?,
        job: LaunchdJobSnapshot,
        xpcAnswered: Bool
    )
        -> Bool
    {
        guard previous?.outcome == .recordUnresolvable, !xpcAnswered else {
            return false
        }
        return isUnresolvableRecord(job: job, beforeBTMUUID: previous?.btmUUID)
    }

    nonisolated static func registrationRepairResult(
        for outcome: HelperRegistrationRepairRecord.Outcome
    )
        -> RegistrationRepairResult
    {
        switch outcome {
        case .recovered:
            .recovered
        case .requiresApproval:
            .requiresApproval
        case .stillBroken,
             .registerFailed,
             .recordUnresolvable:
            .stillBroken
        }
    }

    nonisolated static var registrationBrokenMessage: String {
        String(
            localized: """
            Rockxy tried to repair the helper tool's macOS registration, but it still does not respond. \
            Restart your Mac, or use Force Reset in Advanced Settings if it stays unreachable.
            """, bundle: RockxyLocalization.bundle
        )
    }

    /// The remedy for a registration launchd keeps scheduling and cannot start.
    ///
    /// This is the `wantsToStartAndHasNot` shape: the job is loaded, `state = spawn scheduled`,
    /// `active count = 0`. Measured on one machine with `launchctl print system/<label>`:
    /// `runs = 7093`, `last exit code = 78: EX_CONFIG`, `parent bundle version = 28`. Three
    /// bundles carried that identifier at that version -- the installed app was a different
    /// version -- and every BTM `app` record for them read `disabled`, while the daemon record
    /// and the aggregate `background tasks` record were both `enabled`.
    ///
    /// Two earlier versions of this copy named actions that do not exist for this state, so be
    /// careful changing it:
    /// - "remove Rockxy's item" in Login Items & Extensions. A background item registered through
    ///   `SMAppService` appears there as a switch with no remove button; only "Open at Login"
    ///   entries can be removed.
    /// - "turn Rockxy on under Allow in the Background". That switch maps to the aggregate
    ///   `background tasks` record, which is already enabled in this state. The records that are
    ///   disabled are the per-bundle `app` records, which that pane does not list, so the user
    ///   cannot reach them.
    ///
    /// What is left is to make the registration point at the copy of Rockxy that is actually
    /// installed, which re-registering from that copy does.
    nonisolated static var registrationRecordUnresolvableMessage: String {
        String(
            localized: """
            macOS has Rockxy's helper tool registered but will not start it, so it keeps retrying. \
            Open Rockxy from your Applications folder so the registration points at that copy. \
            If more than one copy of Rockxy is installed, keep only that one.
            """, bundle: RockxyLocalization.bundle
        )
    }

    nonisolated static var registrationReapprovalMessage: String {
        String(
            localized: """
            macOS lost Rockxy's helper registration, so Rockxy registered it again. \
            Approve the helper tool in System Settings > Login Items to finish.
            """, bundle: RockxyLocalization.bundle
        )
    }

    nonisolated static var currentAppBuildIdentifier: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    /// Repairs a registration macOS approved but launchd cannot resolve.
    ///
    /// Call only after a status check left the helper `.unreachable`. At most one unregister and
    /// register is made per launch, and none when the same build already failed to repair it.
    /// The repair is user-level: no administrator prompt, no `launchctl`, no privileged shell.
    func repairDeadRegistrationIfNeeded(reason: String) async -> RegistrationRepairResult {
        guard status == .unreachable, !registrationRepairInFlight else {
            return .notApplicable
        }
        guard !HelperRegistrationGuard.refusesCurrentProcess(operation: "registration repair") else {
            return .notApplicable
        }
        let service = SMAppService.daemon(plistName: RockxyIdentity.current.helperPlistName)
        guard service.status == .enabled else {
            return .notApplicable
        }

        setRegistrationRepairInFlight(true)
        defer { setRegistrationRepairInFlight(false) }

        if registrationRepairRecord == nil {
            setRegistrationRepairRecord(HelperRegistrationRepairStore.load())
        }

        let (evidence, jobSnapshot) = await gatherRegistrationEvidence()

        // The same dead record seen again: launchd has the job and cannot spawn it. Nothing to
        // mutate, and the launch wait cannot help, so say what the user can do and stop.
        if Self.recordStillUnresolvable(
            previous: registrationRepairRecord,
            job: jobSnapshot,
            xpcAnswered: evidence.xpcAnswered
        ) {
            Self.registrationRepairLogger
                .info("Helper registration record is still unresolvable; not repeating the repair")
            publishRegistrationBroken()
            return .stillBroken
        }

        let decision = Self.registrationRepairDecision(
            evidence: evidence,
            previous: registrationRepairRecord,
            currentAppBuild: Self.currentAppBuildIdentifier,
            attemptedThisLaunch: registrationRepairAttemptedThisLaunch
        )

        switch decision {
        case .notDead:
            Self.registrationRepairLogger.info(
                "Helper unreachable but registration is not dead (job \(String(describing: evidence.launchdJob)), xpc answered \(evidence.xpcAnswered)); leaving it alone"
            )
            return .notApplicable

        case .alreadyAttemptedThisLaunch,
             .alreadyFailedOnThisBuild:
            Self.registrationRepairLogger.info(
                "Helper registration is dead; repair not repeated (\(String(describing: decision)))"
            )
            publishRegistrationBroken()
            return .stillBroken

        case .attempt:
            return await performRegistrationRepair(
                service: service,
                reason: reason,
                beforeBTMUUID: jobSnapshot.btmUUID
            )
        }
    }

    // MARK: Private

    private static let registrationRepairLogger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperRegistrationRepair"
    )

    private func gatherRegistrationEvidence() async -> (HelperRegistrationEvidence, LaunchdJobSnapshot) {
        let identity = RockxyIdentity.current
        let machService = identity.helperMachServiceName

        var snapshot = await HelperLaunchdProbe.snapshot(ofMachService: machService)
        var job = snapshot.presence
        if job == .absent {
            // One more look after a pause, so a job launchd is still loading at login is not
            // mistaken for a missing one. Anything but a second "absent" cancels the finding.
            try? await Task.sleep(for: .seconds(2))
            if await HelperLaunchdProbe.presence(ofMachService: machService) != .absent {
                job = .undetermined
                snapshot = .undetermined
            }
        }

        HelperConnection.shared.resetConnection()
        let answered: Bool
        do {
            _ = try await HelperConnection.shared.getHelperInfo()
            answered = true
        } catch {
            answered = false
        }

        let fileManager = FileManager.default
        let legacyPresent = fileManager.fileExists(atPath: Self.legacyInstalledHelperPath(identity: identity))
            || fileManager.fileExists(atPath: Self.legacyLaunchDaemonPlistPath(identity: identity))

        let evidence = HelperRegistrationEvidence(
            registrationIsEnabled: SMAppService.daemon(plistName: identity.helperPlistName).status == .enabled,
            launchdJob: job,
            xpcAnswered: answered,
            legacyArtifactsPresent: legacyPresent,
            isLegacyFallbackBundle: Self.shouldUseLegacyInstallFallbackForCurrentBundle()
        )
        return (evidence, snapshot)
    }

    private func performRegistrationRepair(
        service: SMAppService,
        reason: String,
        beforeBTMUUID: String?
    )
        async -> RegistrationRepairResult
    {
        // Same guard every other registration mutation uses: a replaced or invalid app copy
        // must reopen rather than churn the registration.
        do {
            try await ensureHelperMutationCanProceed()
        } catch {
            Self.registrationRepairLogger.warning(
                "Registration repair blocked by the signing preflight: \(error.localizedDescription)"
            )
            return .notApplicable
        }

        // Spent before the first suspension that mutates anything, so no path can repeat it.
        markRegistrationRepairAttempted()
        Self.registrationRepairLogger.warning(
            "Helper registration is enabled but launchd has no job for it (\(reason)); unregistering and registering once"
        )
        HelperConnection.shared.invalidateSigningCache()

        do {
            try await service.unregister()
        } catch {
            Self.registrationRepairLogger.warning(
                "Unregister during registration repair: \(error.localizedDescription)"
            )
        }
        HelperConnection.shared.resetConnection()
        try? await Task.sleep(for: .seconds(1))

        var registerError: Error?
        do {
            try service.register()
        } catch {
            registerError = error
        }
        try? await Task.sleep(for: .seconds(1))

        let serviceStatus = service.status
        var answered = false
        var jobAfter: LaunchdJobSnapshot?
        if registerError == nil, serviceStatus == .enabled {
            HelperConnection.shared.invalidateSigningCache()
            HelperConnection.shared.resetConnection()
            await performCheckStatus()
            answered = isReachable
            if !answered {
                jobAfter = await HelperLaunchdProbe
                    .snapshot(ofMachService: RockxyIdentity.current.helperMachServiceName)
            }
        }

        let outcome = Self.registrationRepairOutcome(
            registerError: registerError,
            serviceStatus: serviceStatus,
            helperAnswered: answered,
            jobAfter: jobAfter,
            beforeBTMUUID: beforeBTMUUID
        )
        setRegistrationRepairRecord(HelperRegistrationRepairRecord(
            outcome: outcome,
            appBuild: Self.currentAppBuildIdentifier,
            attemptedAt: Date(),
            btmUUID: jobAfter?.btmUUID
        ))
        if let record = registrationRepairRecord {
            HelperRegistrationRepairStore.save(record)
        }
        Self.registrationRepairLogger.info(
            "Registration repair finished: \(outcome.rawValue, privacy: .public)"
        )

        publishRegistrationRepairOutcome(outcome, registerError: registerError, serviceStatus: serviceStatus)
        return Self.registrationRepairResult(for: outcome)
    }

    private func publishRegistrationRepairOutcome(
        _ outcome: HelperRegistrationRepairRecord.Outcome,
        registerError: Error?,
        serviceStatus: SMAppService.Status
    ) {
        setAutomaticRefreshRecoveryPending(false)
        switch outcome {
        case .recovered:
            setLastErrorMessage(nil)
            notifyRegistrationRepairChanged()

        case .requiresApproval:
            // Approval is the correct end state, not a failure. Deliberately does not open
            // System Settings: this runs at launch without a user gesture, and the banner and
            // Advanced Settings already carry the Open Settings action.
            setLastErrorMessage(
                registerError.map { Self.approvalMessage(error: $0, serviceStatus: serviceStatus) }
                    ?? Self.registrationReapprovalMessage
            )
            markAwaitingApprovalAfterRepair()
            notifyRegistrationRepairChanged()

        case .stillBroken,
             .registerFailed,
             .recordUnresolvable:
            publishRegistrationBroken()
        }
    }

    private func publishRegistrationBroken() {
        setAutomaticRefreshRecoveryPending(false)
        // Restarting does not clear an unresolvable record and Force Reset needs a password, so
        // that state gets the password-free remedy instead of the generic advice.
        setLastErrorMessage(
            registrationRepairRecord?.outcome == .recordUnresolvable
                ? Self.registrationRecordUnresolvableMessage
                : Self.registrationBrokenMessage
        )
        notifyRegistrationRepairChanged()
    }

    /// The repair record changes what readiness says even when `status` stays `.unreachable`,
    /// which `postStatusChangeIfNeeded` does not treat as a change.
    private func notifyRegistrationRepairChanged() {
        NotificationCenter.default.post(name: .helperStatusChanged, object: nil)
    }
}
