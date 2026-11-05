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

// MARK: - HelperLaunchdProbe

/// Asks launchd whether the system domain has a job for a Mach service, using the documented
/// `launchctl print system/<name>` that a person would run to establish the same thing.
///
/// The spawn is bounded by `BoundedProcessRun`, so a wedged launchd cannot hang a launch, and it
/// only ever runs once the helper is already unreachable. Any outcome that is not an explicit
/// "Could not find service" or an explicit job listing is `.undetermined`, which never repairs.
enum HelperLaunchdProbe {
    static let launchctlURL = URL(fileURLWithPath: "/bin/launchctl")
    static let timeout: TimeInterval = 5
    /// `print` output for a job is a few KB; this only stops a runaway child.
    static let outputLimit = 256 * 1_024

    static func presence(ofMachService name: String) async -> LaunchdJobPresence {
        do {
            let result = try await BoundedProcessRun.runDetached(
                executable: launchctlURL,
                arguments: ["print", "system/\(name)"],
                timeout: timeout,
                outputLimit: outputLimit,
                mergesStandardError: true
            )
            return classify(
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

        // MARK: Internal

        /// Outcomes after which repeating the identical repair on the identical build is noise.
        var isTerminalForBuild: Bool {
            self == .stillBroken || self == .registerFailed
        }
    }

    var outcome: Outcome
    /// `CFBundleShortVersionString (CFBundleVersion)` of the app that made the attempt.
    var appBuild: String
    var attemptedAt: Date
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
            attemptedAt: Date(timeIntervalSince1970: timestamp)
        )
    }

    static func save(
        _ record: HelperRegistrationRepairRecord,
        defaults: UserDefaults = .standard,
        identity: RockxyIdentity = .current
    ) {
        defaults.set(
            [
                outcomeField: record.outcome.rawValue,
                buildField: record.appBuild,
                timeField: record.attemptedAt.timeIntervalSince1970,
            ],
            forKey: key(identity: identity)
        )
    }

    // MARK: Private

    private static let outcomeField = "outcome"
    private static let buildField = "build"
    private static let timeField = "time"
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
        helperAnswered: Bool
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
        return helperAnswered ? .recovered : .stillBroken
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
             .registerFailed:
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
        let service = SMAppService.daemon(plistName: RockxyIdentity.current.helperPlistName)
        guard service.status == .enabled else {
            return .notApplicable
        }

        setRegistrationRepairInFlight(true)
        defer { setRegistrationRepairInFlight(false) }

        if registrationRepairRecord == nil {
            setRegistrationRepairRecord(HelperRegistrationRepairStore.load())
        }

        let evidence = await gatherRegistrationEvidence()
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
            return await performRegistrationRepair(service: service, reason: reason)
        }
    }

    // MARK: Private

    private static let registrationRepairLogger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperRegistrationRepair"
    )

    private func gatherRegistrationEvidence() async -> HelperRegistrationEvidence {
        let identity = RockxyIdentity.current
        let machService = identity.helperMachServiceName

        var job = await HelperLaunchdProbe.presence(ofMachService: machService)
        if job == .absent {
            // One more look after a pause, so a job launchd is still loading at login is not
            // mistaken for a missing one. Anything but a second "absent" cancels the finding.
            try? await Task.sleep(for: .seconds(2))
            if await HelperLaunchdProbe.presence(ofMachService: machService) != .absent {
                job = .undetermined
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

        return HelperRegistrationEvidence(
            registrationIsEnabled: SMAppService.daemon(plistName: identity.helperPlistName).status == .enabled,
            launchdJob: job,
            xpcAnswered: answered,
            legacyArtifactsPresent: legacyPresent,
            isLegacyFallbackBundle: Self.shouldUseLegacyInstallFallbackForCurrentBundle()
        )
    }

    private func performRegistrationRepair(
        service: SMAppService,
        reason: String
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
        if registerError == nil, serviceStatus == .enabled {
            HelperConnection.shared.invalidateSigningCache()
            HelperConnection.shared.resetConnection()
            await performCheckStatus()
            answered = isReachable
        }

        let outcome = Self.registrationRepairOutcome(
            registerError: registerError,
            serviceStatus: serviceStatus,
            helperAnswered: answered
        )
        setRegistrationRepairRecord(HelperRegistrationRepairRecord(
            outcome: outcome,
            appBuild: Self.currentAppBuildIdentifier,
            attemptedAt: Date()
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
             .registerFailed:
            publishRegistrationBroken()
        }
    }

    private func publishRegistrationBroken() {
        setAutomaticRefreshRecoveryPending(false)
        setLastErrorMessage(Self.registrationBrokenMessage)
        notifyRegistrationRepairChanged()
    }

    /// The repair record changes what readiness says even when `status` stays `.unreachable`,
    /// which `postStatusChangeIfNeeded` does not treat as a change.
    private func notifyRegistrationRepairChanged() {
        NotificationCenter.default.post(name: .helperStatusChanged, object: nil)
    }
}
