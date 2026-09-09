import Foundation
import os

// Reconciles an already approved helper with the helper executable embedded in the app bundle
// that is running right now, without ever unregistering the approved service.

// MARK: - HelperUpdateBlockReason

/// Why a reconciliation may not proceed. Each case stays distinct because each one means
/// something different to the user, and folding them together is how "needs your approval" and
/// "Rockxy could not verify its own package" end up behind the same button.
enum HelperUpdateBlockReason: Equatable {
    case notInstalled
    case requiresApproval
    case unreachable
    case signingMismatch
    case incompatibleProtocol
    case embeddedPackageInvalid
}

// MARK: - HelperUpdatePlan

/// What reconciling the installed helper with this app bundle requires.
enum HelperUpdatePlan: Equatable {
    /// The live helper is already running the embedded executable.
    case upToDate
    /// Ask the running helper to exit so launchd resolves `BundleProgram` from this app bundle
    /// again. The `SMAppService` registration — and the user's Background Items approval — is
    /// left exactly as it is.
    case approvalPreservingRefresh
    /// Protocol 1 and 2 predate `prepareForExecutableRefresh` and cannot be replaced in place.
    /// Their one migration path is destructive and explicitly user-initiated.
    case legacyManualMigration
    case blocked(HelperUpdateBlockReason)
}

// MARK: - HelperConvergenceMarker

/// The last helper executable this app observed converge, recorded only after verification.
///
/// It exists for the helpers that cannot describe themselves: a protocol-3 or protocol-4 daemon
/// answers with build and protocol numbers and nothing else, so without a marker every launch
/// would have to assume drift and ask it to exit again. It is never evidence on its own — a
/// helper that *can* be probed is always compared against its live identity instead.
struct HelperConvergenceMarker: Equatable, Sendable {
    let executableDigest: String
    let buildNumber: Int
    let protocolVersion: Int
}

// MARK: - HelperConvergenceMarkerStore

/// Persists the convergence marker under a `RockxyIdentity`-namespaced defaults key.
enum HelperConvergenceMarkerStore {
    // MARK: Internal

    static func markerKey(identity: RockxyIdentity = .current) -> String {
        identity.defaultsKey("helper.verifiedExecutableIdentity")
    }

    static func load(
        defaults: UserDefaults = .standard,
        identity: RockxyIdentity = .current
    )
        -> HelperConvergenceMarker?
    {
        guard let stored = defaults.dictionary(forKey: markerKey(identity: identity)),
              let digest = stored[digestField] as? String,
              HelperExecutableDigest.isWellFormedDigest(digest),
              let build = stored[buildField] as? Int, build > 0,
              let protocolVersion = stored[protocolField] as? Int, protocolVersion > 0 else
        {
            return nil
        }
        return HelperConvergenceMarker(
            executableDigest: digest,
            buildNumber: build,
            protocolVersion: protocolVersion
        )
    }

    static func save(
        _ marker: HelperConvergenceMarker,
        defaults: UserDefaults = .standard,
        identity: RockxyIdentity = .current
    ) {
        guard HelperExecutableDigest.isWellFormedDigest(marker.executableDigest) else {
            return
        }
        defaults.set(
            [
                digestField: marker.executableDigest,
                buildField: marker.buildNumber,
                protocolField: marker.protocolVersion,
            ],
            forKey: markerKey(identity: identity)
        )
    }

    static func clear(defaults: UserDefaults = .standard, identity: RockxyIdentity = .current) {
        defaults.removeObject(forKey: markerKey(identity: identity))
    }

    // MARK: Private

    private static let digestField = "digest"
    private static let buildField = "build"
    private static let protocolField = "protocol"
}

// MARK: - HelperExecutableRefreshOrchestrator

/// Drives one approval-preserving helper refresh and proves it took effect.
///
/// Everything that touches the world arrives as a closure, so the real sequencing — the bounded
/// deferral backoff, the forced reconnect before each poll, and the convergence test itself — is
/// the code under test rather than a re-implementation of it. There is deliberately no way to
/// unregister anything from here: a refresh that fails leaves the registration exactly as it
/// found it, because that registration is the user's approval.
@MainActor
struct HelperExecutableRefreshOrchestrator {
    // MARK: Internal

    /// What the app bundle currently embeds, and what a converged helper must therefore report.
    struct Candidate: Equatable, Sendable {
        let executableDigest: String
        let expectedProtocolVersion: Int
        let bundledBuildNumber: Int
    }

    /// One observation of the live helper, taken over a freshly established connection.
    struct Snapshot: Equatable {
        var status: HelperManager.HelperStatus
        var info: HelperInfo?
        var identity: HelperExecutableIdentity?
    }

    enum Outcome: Equatable {
        case converged(HelperConvergenceMarker)
        /// The connected helper does not implement approval-preserving refresh.
        case refreshUnsupported
        /// The helper kept deferring because proxy or certificate work was in flight.
        case refreshDeferred
        /// The refresh request could not be delivered or acknowledged at all.
        case refreshUnavailable
        /// The refresh was acknowledged, but no poll ever observed the embedded executable.
        case verificationIncomplete
    }

    /// Waits between refresh attempts after the helper defers or the transport fails.
    var refreshRetryDelays: [Duration] = [
        .milliseconds(500),
        .seconds(1),
        .seconds(2),
        .seconds(3),
    ]

    /// Waits before each convergence poll. Preserves the ladder the previous implementation used
    /// and adds one more attempt, because a daemon that has just exited is started lazily by the
    /// next connection and occasionally needs longer than three seconds to answer.
    var verificationDelays: [Duration] = [
        .milliseconds(250),
        .milliseconds(500),
        .seconds(1),
        .seconds(2),
        .seconds(3),
        .seconds(3),
    ]

    var requestRefresh: () async throws -> Void
    var resetTransport: () async -> Void
    var snapshot: () async -> Snapshot
    var wait: (Duration) async -> Void
    var log: (String) -> Void = { _ in }

    /// Whether a live observation proves the embedded executable is the one now running.
    ///
    /// Metadata alone is never enough. A helper that can describe itself must report the exact
    /// digest of the embedded candidate, and — when the process that was asked to exit could be
    /// identified — a different launch identity, so the old executable answering one more time
    /// cannot be mistaken for the new one.
    static func convergedMarker(
        snapshot: Snapshot,
        candidate: Candidate,
        preRefreshIdentity: HelperExecutableIdentity?
    )
        -> HelperConvergenceMarker?
    {
        guard snapshot.status == .installedCompatible, let info = snapshot.info else {
            return nil
        }
        guard info.protocolVersion == candidate.expectedProtocolVersion,
              info.buildNumber == candidate.bundledBuildNumber else
        {
            return nil
        }

        guard HelperCompatibilityPolicy.supportsExecutableIdentity(
            protocolVersion: info.protocolVersion
        ) else {
            // This app build expects a helper that cannot describe its own executable. Matching
            // build and protocol numbers over a fresh connection is the strongest evidence such a
            // daemon can offer, and the marker records exactly that much.
            return HelperConvergenceMarker(
                executableDigest: candidate.executableDigest,
                buildNumber: info.buildNumber,
                protocolVersion: info.protocolVersion
            )
        }

        guard let identity = snapshot.identity, identity.isWellFormed else {
            return nil
        }
        guard identity.protocolVersion == info.protocolVersion,
              identity.buildNumber == info.buildNumber,
              identity.executableDigest == candidate.executableDigest else
        {
            return nil
        }
        if let preRefreshIdentity, preRefreshIdentity.launchIdentity == identity.launchIdentity {
            // The same process that was asked to exit is still answering.
            return nil
        }

        return HelperConvergenceMarker(
            executableDigest: identity.executableDigest,
            buildNumber: identity.buildNumber,
            protocolVersion: identity.protocolVersion
        )
    }

    func run(
        candidate: Candidate,
        preRefreshIdentity: HelperExecutableIdentity?
    )
        async -> Outcome
    {
        switch await requestRefreshWithBackoff() {
        case .acknowledged:
            break
        case .unsupported:
            return .refreshUnsupported
        case .deferred:
            return .refreshDeferred
        case .unavailable:
            return .refreshUnavailable
        }

        for (attempt, delay) in verificationDelays.enumerated() {
            await wait(delay)
            // Force a new connection for every poll. Reusing the cached one can hand back a proxy
            // still bound to the process that just exited, whose answer would describe the
            // executable this refresh is replacing.
            await resetTransport()
            let observation = await snapshot()
            if let marker = Self.convergedMarker(
                snapshot: observation,
                candidate: candidate,
                preRefreshIdentity: preRefreshIdentity
            ) {
                return .converged(marker)
            }
            log("Helper refresh poll \(attempt + 1) did not observe the embedded executable")
        }

        return .verificationIncomplete
    }

    // MARK: Private

    private enum RefreshRequestResult {
        case acknowledged
        case unsupported
        case deferred
        case unavailable
    }

    private func requestRefreshWithBackoff() async -> RefreshRequestResult {
        var lastResult = RefreshRequestResult.unavailable
        var attempt = 0
        while true {
            do {
                try await requestRefresh()
                return .acknowledged
            } catch HelperConnectionError.executableRefreshUnsupported {
                // Nothing a retry can change, and nothing else may be substituted for it.
                return .unsupported
            } catch HelperConnectionError.executableRefreshDeferred {
                lastResult = .deferred
                log("Helper deferred the executable refresh; proxy or certificate work is active")
            } catch {
                lastResult = .unavailable
                log("Helper executable refresh request failed: \(error.localizedDescription)")
                // A stale or broken connection is retried over a fresh one rather than escalated.
                await resetTransport()
            }

            guard attempt < refreshRetryDelays.count else {
                return lastResult
            }
            await wait(refreshRetryDelays[attempt])
            attempt += 1
        }
    }
}

// MARK: - HelperManager app update reconciliation

extension HelperManager {
    /// How an explicit "Update Helper" request is carried out.
    enum UpdateRoute: Equatable {
        /// Reconcile in place and verify. Never touches the `SMAppService` registration.
        case approvalPreservingRefresh
        /// The single destructive migration, reserved for protocol 1 and 2.
        case legacyProtocolMigration
        /// Nothing safe to do: absent, awaiting approval, unreachable, mis-signed, or speaking a
        /// protocol this build must not replace.
        case unavailable
    }

    enum ReconciliationOutcome: Equatable {
        case upToDate
        case refreshed
        case legacyMigrationRequired
        case blocked(HelperUpdateBlockReason)
        case refreshFailed(HelperExecutableRefreshOrchestrator.Outcome)

        // MARK: Internal

        var isConverged: Bool {
            switch self {
            case .upToDate,
                 .refreshed:
                true
            case .blocked,
                 .legacyMigrationRequired,
                 .refreshFailed:
                false
            }
        }
    }

    /// Decides what reconciling this helper requires, from evidence only.
    ///
    /// Drift is not "the installed build is lower". `SMAppService` resolves `BundleProgram` out of
    /// the app bundle, so an update replaces the file on disk while the previously started daemon
    /// keeps running — with whatever version metadata it was compiled with. Two builds can also
    /// carry identical numbers and different bytes. So any disagreement counts: a different
    /// protocol, a different build, or a different executable digest.
    nonisolated static func updatePlan(
        status: HelperStatus,
        installedInfo: HelperInfo?,
        installedIdentity: HelperExecutableIdentity?,
        expectedProtocolVersion: Int,
        bundledBuildNumber: Int,
        candidateDigest: String?,
        marker: HelperConvergenceMarker?
    )
        -> HelperUpdatePlan
    {
        switch status {
        case .notInstalled:
            return .blocked(.notInstalled)
        case .requiresApproval:
            return .blocked(.requiresApproval)
        case .unreachable:
            return .blocked(.unreachable)
        case .signingMismatch:
            return .blocked(.signingMismatch)
        case .installedIncompatible:
            // Covers both a protocol newer than this build understands and a downgrade. Neither
            // may be replaced automatically.
            return .blocked(.incompatibleProtocol)
        case .installedCompatible,
             .installedOutdated:
            break
        }

        guard let installedInfo, installedInfo.protocolVersion > 0 else {
            return .blocked(.unreachable)
        }
        guard let candidateDigest, HelperExecutableDigest.isWellFormedDigest(candidateDigest) else {
            // The embedded helper could not be validated or digested. Preserve what is installed.
            return .blocked(.embeddedPackageInvalid)
        }

        // A helper from a newer build of the same protocol is not update drift. Replacing it with
        // this bundle would be a downgrade, even though the protocol remains callable. Leave its
        // approved registration and executable untouched.
        if installedInfo.protocolVersion == expectedProtocolVersion,
           installedInfo.buildNumber > bundledBuildNumber
        {
            return .blocked(.incompatibleProtocol)
        }

        let metadataMatches = installedInfo.protocolVersion == expectedProtocolVersion
            && installedInfo.buildNumber == bundledBuildNumber

        guard HelperCompatibilityPolicy.supportsExecutableRefresh(
            protocolVersion: installedInfo.protocolVersion
        ) else {
            return metadataMatches ? .upToDate : .legacyManualMigration
        }

        if HelperCompatibilityPolicy.supportsExecutableIdentity(
            protocolVersion: installedInfo.protocolVersion
        ) {
            guard let installedIdentity, installedIdentity.isWellFormed else {
                // Protocol 5 can prove its live executable. A marker from an earlier launch must
                // never replace that proof when the current XPC connection is stale or the helper
                // is still coming up; force the bounded refresh/reconnect path instead.
                return .approvalPreservingRefresh
            }
            let converged = metadataMatches
                && installedIdentity.protocolVersion == installedInfo.protocolVersion
                && installedIdentity.buildNumber == installedInfo.buildNumber
                && installedIdentity.executableDigest == candidateDigest
            return converged ? .upToDate : .approvalPreservingRefresh
        }

        guard metadataMatches else {
            return .approvalPreservingRefresh
        }
        guard let marker,
              marker.executableDigest == candidateDigest,
              marker.buildNumber == bundledBuildNumber,
              marker.protocolVersion == expectedProtocolVersion else
        {
            // Either nothing was ever verified, or the verified executable is not this one.
            return .approvalPreservingRefresh
        }
        return .upToDate
    }

    /// Which update mechanism an explicit user request may use.
    nonisolated static func updateRoute(
        status: HelperStatus,
        installedInfo: HelperInfo?,
        expectedProtocolVersion: Int,
        bundledBuildNumber: Int
    )
        -> UpdateRoute
    {
        switch status {
        case .notInstalled,
             .requiresApproval,
             .unreachable,
             .signingMismatch:
            return .unavailable
        case .installedCompatible,
             .installedOutdated,
             .installedIncompatible:
            break
        }

        guard let installedInfo, installedInfo.protocolVersion > 0 else {
            return .unavailable
        }
        // A helper speaking a protocol newer than this build expects is never replaced: doing so
        // would downgrade whatever app copy installed it, and would ask the user to approve it.
        guard installedInfo.protocolVersion <= expectedProtocolVersion else {
            return .unavailable
        }
        guard installedInfo.protocolVersion != expectedProtocolVersion
            || installedInfo.buildNumber <= bundledBuildNumber else
        {
            return .unavailable
        }
        if HelperCompatibilityPolicy.supportsExecutableRefresh(
            protocolVersion: installedInfo.protocolVersion
        ) {
            return .approvalPreservingRefresh
        }
        return HelperCompatibilityPolicy.requiresLegacyDestructiveMigration(
            protocolVersion: installedInfo.protocolVersion
        )
            ? .legacyProtocolMigration
            : .unavailable
    }

    /// Update the installed helper to the executable embedded in this app bundle.
    ///
    /// A helper that implements approval-preserving refresh is reconciled in place and verified
    /// against the live process before this returns. A failure there is reported as a failure; it
    /// never falls through to unregister and re-register, which is what turned every app update
    /// into a fresh Background Items approval prompt.
    ///
    /// Protocol 1 and 2 keep the one destructive migration path, including its existing
    /// approval-required behaviour, because they have no way to be replaced in place.
    func update() async throws {
        HelperConnection.shared.invalidateSigningCache()
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        let previousSigningIssue = signingIssue
        setLastErrorMessage(nil)
        setBusy(true)
        defer {
            setBusy(false)
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo,
                previousSigningIssue: previousSigningIssue
            )
        }

        Self.appUpdateLogger.info("Updating helper tool")
        do {
            try await ensureHelperMutationCanProceed()
            await performCheckStatus()

            switch Self.updateRoute(
                status: status,
                installedInfo: installedInfo,
                expectedProtocolVersion: expectedProtocolVersion,
                bundledBuildNumber: bundledHelperBuild
            ) {
            case .approvalPreservingRefresh:
                let outcome = await reconcileEmbeddedHelper(reason: "manual update")
                guard outcome.isConverged else {
                    throw Self.updateFailure(for: outcome)
                }
            case .legacyProtocolMigration:
                try await performLegacyProtocolMigration()
            case .unavailable:
                throw HelperOperationError.helperUpdateUnavailable
            }
        } catch {
            setLastErrorMessage(error.localizedDescription)
            throw error
        }
    }

    /// The one destructive helper update path, reserved for protocol 1 and 2.
    ///
    /// Unregistering clears Background Task Management trust, so re-registration may ask the user
    /// for approval again. That is why nothing else is allowed through here.
    func performLegacyProtocolMigration() async throws {
        Self.appUpdateLogger.info("Migrating a pre-refresh helper by unregistering and re-registering it")
        try await performUninstall()
        try? await Task.sleep(nanoseconds: 500_000_000)
        try await performInstall()
        if status != .requiresApproval {
            await performCheckStatus()
        }
    }

    /// Launch-time reconciliation, owning the busy and notification wrapper.
    func reconcileEmbeddedHelperOnLaunch() async {
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        let previousSigningIssue = signingIssue
        setBusy(true)
        defer {
            setBusy(false)
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo,
                previousSigningIssue: previousSigningIssue
            )
        }

        do {
            try await ensureHelperMutationCanProceed()
        } catch {
            setAutomaticRefreshRecoveryPending(false)
            // The signing preflight already published the state the user has to act on.
            Self.appUpdateLogger.warning(
                "Skipping helper reconciliation: \(error.localizedDescription)"
            )
            return
        }
        _ = await reconcileEmbeddedHelper(reason: "app launch")
    }

    /// Reconciles the installed helper with the helper embedded in this app bundle.
    ///
    /// Callers own the busy and notification wrapper. Nothing here unregisters, re-registers, or
    /// installs anything: the only privileged request it can make is "exit so launchd starts the
    /// executable from this bundle", and it reports failure rather than escalating.
    @discardableResult
    func reconcileEmbeddedHelper(reason: String) async -> ReconciliationOutcome {
        await performCheckStatus()

        let candidate: HelperExecutableRefreshOrchestrator.Candidate
        do {
            candidate = try await embeddedHelperCandidate()
        } catch {
            setAutomaticRefreshRecoveryPending(false)
            Self.appUpdateLogger.error(
                "Embedded helper package could not be verified: \(error.localizedDescription, privacy: .private)"
            )
            setLastErrorMessage(error.localizedDescription)
            return .blocked(.embeddedPackageInvalid)
        }

        let installedIdentity = await currentHelperExecutableIdentity()
        let plan = Self.updatePlan(
            status: status,
            installedInfo: installedInfo,
            installedIdentity: installedIdentity,
            expectedProtocolVersion: expectedProtocolVersion,
            bundledBuildNumber: bundledHelperBuild,
            candidateDigest: candidate.executableDigest,
            marker: HelperConvergenceMarkerStore.load()
        )

        switch plan {
        case .upToDate:
            setAutomaticRefreshRecoveryPending(false)
            if let installedIdentity {
                HelperConvergenceMarkerStore.save(HelperConvergenceMarker(
                    executableDigest: installedIdentity.executableDigest,
                    buildNumber: installedIdentity.buildNumber,
                    protocolVersion: installedIdentity.protocolVersion
                ))
            }
            return .upToDate

        case let .blocked(blockReason):
            // An enabled registration that is temporarily unreachable is still an automatic
            // launchd/XPC recovery case. Keep destructive recovery UI hidden and retry on the
            // next launch (or the explicit automatic-retry action). The other blocks require a
            // package or user-state change and are not automatic-refresh work.
            let recoveryPending = blockReason == .unreachable
            setAutomaticRefreshRecoveryPending(recoveryPending)
            if recoveryPending {
                // `performCheckStatus` uses a general unreachable message that offers reinstall
                // and Force Reset. Neither is appropriate while the approved registration is an
                // automatic launchd/XPC recovery path, so replace that copy as well as hiding the
                // destructive controls.
                setLastErrorMessage(HelperOperationError.automaticHelperRefreshFailed.localizedDescription)
            }
            Self.appUpdateLogger.info(
                "Helper reconciliation (\(reason)) skipped: \(String(describing: blockReason))"
            )
            return .blocked(blockReason)

        case .legacyManualMigration:
            setAutomaticRefreshRecoveryPending(false)
            Self.appUpdateLogger.info(
                "Installed helper predates approval-preserving refresh; leaving it for an explicit update"
            )
            return .legacyMigrationRequired

        case .approvalPreservingRefresh:
            return await performApprovalPreservingRefresh(
                candidate: candidate,
                preRefreshIdentity: installedIdentity,
                reason: reason
            )
        }
    }

    // MARK: Private

    private static let appUpdateLogger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperAppUpdate"
    )

    private static func updateFailure(for outcome: ReconciliationOutcome) -> HelperOperationError {
        switch outcome {
        case let .blocked(reason):
            switch reason {
            case .requiresApproval:
                .helperApprovalRequired
            case .embeddedPackageInvalid:
                .helperPackageIncomplete
            case .notInstalled,
                 .unreachable,
                 .signingMismatch,
                 .incompatibleProtocol:
                .helperUpdateUnavailable
            }
        case .legacyMigrationRequired,
             .refreshFailed,
             .upToDate,
             .refreshed:
            .automaticHelperRefreshFailed
        }
    }

    private func performApprovalPreservingRefresh(
        candidate: HelperExecutableRefreshOrchestrator.Candidate,
        preRefreshIdentity: HelperExecutableIdentity?,
        reason: String
    )
        async -> ReconciliationOutcome
    {
        setAutomaticRefreshRecoveryPending(true)
        Self.appUpdateLogger.info(
            "Refreshing helper executable (\(reason)) without unregistering its approved service"
        )

        let orchestrator = HelperExecutableRefreshOrchestrator(
            requestRefresh: { try await HelperConnection.shared.refreshHelperExecutable() },
            resetTransport: {
                HelperConnection.shared.resetConnection()
                HelperConnection.shared.invalidateSigningCache()
            },
            snapshot: { [weak self] in
                guard let self else {
                    return HelperExecutableRefreshOrchestrator.Snapshot(
                        status: .unreachable,
                        info: nil,
                        identity: nil
                    )
                }
                await performCheckStatus()
                return await HelperExecutableRefreshOrchestrator.Snapshot(
                    status: status,
                    info: installedInfo,
                    identity: currentHelperExecutableIdentity()
                )
            },
            wait: { try? await Task.sleep(for: $0) },
            log: { Self.appUpdateLogger.info("\($0, privacy: .public)") }
        )

        let outcome = await orchestrator.run(
            candidate: candidate,
            preRefreshIdentity: preRefreshIdentity
        )

        switch outcome {
        case let .converged(marker):
            setAutomaticRefreshRecoveryPending(false)
            HelperConvergenceMarkerStore.save(marker)
            Self.appUpdateLogger.info(
                "Helper executable refresh verified: protocol \(marker.protocolVersion) build \(marker.buildNumber) digest \(marker.executableDigest.prefix(12), privacy: .private)"
            )
            return .refreshed

        case .refreshUnsupported,
             .refreshDeferred,
             .refreshUnavailable,
             .verificationIncomplete:
            // The marker is deliberately left as it was, so the next launch reconciles again.
            setLastErrorMessage(HelperOperationError.automaticHelperRefreshFailed.localizedDescription)
            Self.appUpdateLogger.warning(
                "Helper executable refresh did not converge: \(String(describing: outcome)). The approved registration is unchanged."
            )
            return .refreshFailed(outcome)
        }
    }

    /// Validates the helper this app bundle ships and returns what a converged daemon must report.
    ///
    /// The validation runs *before* anything is asked to exit. Replacing a working helper with a
    /// package that turns out to be missing, unreadable, or signed for a different identity would
    /// leave the machine with no helper and an approval the user has to give again.
    private func embeddedHelperCandidate() async throws
        -> HelperExecutableRefreshOrchestrator.Candidate
    {
        try Self.validateBundledHelperInstallResources()

        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent(Self.bundledHelperBinaryRelativePath, isDirectory: false)
        guard Self.embeddedHelperSigningAllowsRefresh(
            SigningDiagnostics.diagnose(helperExecutableURL: helperURL)
        ) else {
            throw HelperInstallPreflightError.invalidBundledHelperSignature
        }

        let helperPath = helperURL.path
        let canonicalPath = HelperExecutableDigest.canonicalPath(helperPath)
        let digest = try await Task.detached(priority: .userInitiated) {
            try HelperExecutableDigest.sha256Hex(atPath: canonicalPath)
        }.value

        return HelperExecutableRefreshOrchestrator.Candidate(
            executableDigest: digest,
            expectedProtocolVersion: expectedProtocolVersion,
            bundledBuildNumber: bundledHelperBuild
        )
    }

    /// Refreshing an approved daemon may only point launchd at an embedded helper whose code
    /// signature is valid and whose certificate chain exactly matches the running app.
    nonisolated static func embeddedHelperSigningAllowsRefresh(
        _ result: SigningDiagnostics.Result
    )
        -> Bool
    {
        result == .healthy
    }

    /// Reads the live helper's executable identity, when it speaks a protocol that can report one.
    ///
    /// A failure here is not drift on its own — it is simply an absence of evidence, and the plan
    /// treats it as such.
    private func currentHelperExecutableIdentity() async -> HelperExecutableIdentity? {
        guard let installedInfo,
              HelperCompatibilityPolicy.supportsExecutableIdentity(
                  protocolVersion: installedInfo.protocolVersion
              ) else
        {
            return nil
        }
        do {
            return try await HelperConnection.shared.executableIdentity()
        } catch {
            Self.appUpdateLogger.info(
                "Helper executable identity probe failed: \(error.localizedDescription)"
            )
            return nil
        }
    }
}

// MARK: - HelperUpdateStartupReconciliation

/// One process-wide helper reconciliation barrier, shared by the app delegate and the capture UI.
///
/// It runs after system-proxy startup recovery and before anything can start capture, so an
/// automatic launch capture cannot take the proxy through a helper that is about to be asked to
/// exit — and cannot race the moment launchd swaps in the executable from the updated bundle.
enum HelperUpdateStartupReconciliation {
    static let task = Task.detached(priority: .userInitiated) {
        await SystemProxyStartupRecovery.task.value
        if RockxyIdentity.isRunningTests {
            await HelperManager.shared.checkStatus()
        } else {
            await HelperManager.shared.reconcileEmbeddedHelperOnLaunch()
        }
    }
}
