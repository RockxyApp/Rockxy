import Foundation
import os
import Security

// Implements the helper-side XPC service for proxy, certificate, and bypass-domain
// operations.

// MARK: - HelperService

/// Implements the RockxyHelperProtocol XPC interface.
/// Delegates proxy operations to ProxyConfigurator and crash recovery to CrashRecovery.
final class HelperService: NSObject, RockxyHelperProtocol {
    // MARK: Lifecycle

    /// One service object per accepted connection, bound to that connection's authenticated peer.
    ///
    /// The exported object used to be a process-wide singleton, which left every ownership-bearing
    /// method deciding from an identifier the message carried. That identifier is a claim: a
    /// caller could name any process at all and have the helper arm a watchdog on it, or record
    /// it as the session that owns the user's proxy settings. Binding the object to the
    /// connection replaces the claim with something the sender cannot choose.
    init(boundConnectionPID: Int32, boundConnectionStartSignature: String, boundUserID: uid_t) {
        self.boundConnectionPID = boundConnectionPID
        self.boundConnectionStartSignature = boundConnectionStartSignature
        self.boundUserID = boundUserID
        super.init()
    }

    // MARK: Internal

    /// Retries a retained launch-time restore point under the same gate as XPC mutations.
    /// Calls coalesce, and a later idle check starts a fresh bounded chain after exhaustion.
    static func scheduleBackupRecovery(reason: String) {
        automaticRestoreRetrier.run(
            key: startupRecoveryRetryKey,
            operation: {
                switch performStartupRecovery() {
                case let .preserved(owner):
                    if let owner {
                        resumeOwnerWatchdog(
                            for: owner.processIdentifier,
                            startSignature: owner.startSignature,
                            userID: owner.userID
                        )
                    }
                    return true
                case .noBackup,
                     .cleared,
                     .restored:
                    return true
                case .restoreIncomplete:
                    logger.warning("Proxy backup recovery after \(reason) remains incomplete and will retry")
                    return false
                }
            },
            onExhausted: {
                logger.error("Proxy backup recovery after \(reason) exhausted bounded retries; preserving backup")
            }
        )
    }

    /// Runs helper launch recovery under the same system-wide lock used by direct mode.
    static func performStartupRecovery() -> CrashRecovery.StartupRecoveryOutcome {
        do {
            return try DirectProxySessionLock.withExclusiveAccess(userID: 0) {
                CrashRecovery.restoreIfNeeded()
            }
        } catch {
            logger.error("Could not serialize helper startup recovery: \(error.localizedDescription)")
            return .restoreIncomplete
        }
    }

    /// Re-arms the owner watchdog for a session that survived a helper relaunch.
    /// Without this, an override preserved at startup would have no observer left, so the owner
    /// dying later would strand the user's proxy settings with nothing to restore them.
    ///
    /// The start signature comes from the backup recovery already authenticated, so the re-armed
    /// watchdog watches the same process identity rather than whatever later inherits the PID.
    static func resumeOwnerWatchdog(for pid: Int32, startSignature: String, userID: uid_t?) {
        guard pid > 0, !startSignature.isEmpty else {
            return
        }
        // Backups written before the user identity field existed still carry an exact PID and
        // start signature. Keep their recovery observer alive as well; the session lock is global,
        // so its compatibility parameter does not weaken which backup the watchdog may restore.
        let lockIdentity = userID ?? 0
        if userID == nil {
            logger.warning("Re-arming owner watchdog for a legacy proxy backup without a recorded user identity")
        }
        logger.info("Re-arming owner watchdog for preserved session pid \(pid)")
        startOwnerWatchdog(for: pid, startSignature: startSignature, userID: lockIdentity)
    }

    static func handleConnectionInvalidated(processID: Int32) {
        let action: InvalidationAction
        let owner = currentOwnerSnapshot()

        if let owner {
            let ownerPID = owner.processIdentifier
            let ownerAlive = ownerSessionIsLive(owner)
            action = invalidationAction(
                ownerPID: ownerPID,
                invalidatedPID: processID,
                ownerAlive: ownerAlive
            )
        } else {
            action = .ignore
        }

        switch action {
        case .ignore:
            logger.debug("Ignoring XPC invalidation for pid \(processID)")
        case let .restore(ownerPID):
            logger.warning("XPC owner connection \(ownerPID) vanished — restoring proxy override automatically")
            requestAutomaticProxyRestore(
                for: ownerPID,
                ownershipToken: owner?.token,
                reason: "owner connection invalidation"
            )
        case let .watchdog(ownerPID):
            logger.info("Owner pid \(ownerPID) still alive after XPC invalidation — deferring to watchdog")
            scheduleOwnerDisconnectRecheck(for: ownerPID, ownershipToken: owner?.token)
        }
    }

    /// Freeze the executable identity while the bytes that launched this process are still the
    /// bytes present at its path. An app update may replace that path while this daemon remains
    /// alive; computing the digest lazily on the first later XPC probe would then hash the new
    /// file and misidentify the old, already-running process as the candidate.
    static func prepareExecutableIdentityForLaunch() {
        _ = runningExecutableIdentity
    }

    func overrideSystemProxy(port: Int, ownerPID: Int32, withReply reply: @escaping (Bool, String?) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("overrideSystemProxy called with port \(port), ownerPID \(ownerPID)")

        guard Self.validPortRange.contains(port) else {
            Self.logger.error("SECURITY: Rejected invalid port \(port) — must be \(Self.validPortRange)")
            reply(false, "Invalid port: must be \(Self.validPortRange.lowerBound)-\(Self.validPortRange.upperBound)")
            return
        }

        // The override is recorded and watched for whoever this connection actually is, never for
        // whoever the message says. The parameter is kept and required to agree so the wire
        // protocol is unchanged and a disagreement is refused rather than quietly reinterpreted.
        guard let authorizedOwnerPID = HelperOwnerBindingPolicy.authorizedOwnerPID(
            boundConnectionPID: boundConnectionPID,
            requestedOwnerPID: ownerPID
        ) else {
            Self.logger
                .error(
                    "SECURITY: Rejected owner PID \(ownerPID) — it is not the authenticated connection \(self.boundConnectionPID)"
                )
            reply(false, "Owner PID does not match the calling process")
            return
        }

        // The rate-limit check reads and writes the same timestamp, so both halves happen inside
        // the gate. Deciding outside it let two concurrently delivered requests observe the same
        // stale value and then race on replacing it.
        guard let outcome = Self.mutationGate.withExclusiveAccess({ () -> ProxyOverrideOutcome in
            guard !HelperProxyRateLimitPolicy.isRateLimited(
                lastChange: Self.lastProxyChangeTime,
                now: Date(),
                interval: Self.rateLimitInterval
            ) else {
                return .rateLimited
            }

            // The owner's start identity is acquired before a single setting is touched. It is
            // what the watchdog compares against for the whole session, and a process identifier
            // on its own is recyclable — so an override that cannot be tied to an exact process
            // is refused rather than left with a watchdog that cannot tell one from another.
            let liveStartSignature = ProcessStartIdentity.startSignature(for: authorizedOwnerPID)
            guard HelperBoundProcessIdentityPolicy.isCurrent(
                boundPID: authorizedOwnerPID,
                boundStartSignature: boundConnectionStartSignature,
                liveStartSignature: liveStartSignature
            ) else {
                return .ownerIdentityUnavailable
            }
            let startSignature = boundConnectionStartSignature

            return .attempted(Result {
                try DirectProxySessionLock.withExclusiveAccess(userID: boundUserID) {
                    guard !DirectProxySessionLock.anyDirectBackupExists() else {
                        throw ProxyConfiguratorError.directSessionInUse
                    }
                    do {
                        try ProxyConfigurator.overrideProxy(
                            port: port,
                            ownerPID: authorizedOwnerPID,
                            ownerStartSignature: startSignature,
                            ownerUID: boundUserID
                        )
                    } catch let ProxyConfiguratorError.overrideRollbackIncomplete(services) {
                        // A partial rollback gets the same live watchdog as a successful override.
                        Self.lastProxyChangeTime = Date()
                        Self.startOwnerWatchdog(
                            for: authorizedOwnerPID,
                            startSignature: startSignature,
                            userID: boundUserID
                        )
                        throw ProxyConfiguratorError.overrideRollbackIncomplete(services: services)
                    }
                    Self.lastProxyChangeTime = Date()
                    Self.startOwnerWatchdog(
                        for: authorizedOwnerPID,
                        startSignature: startSignature,
                        userID: boundUserID
                    )
                }
            })
        }) else {
            reply(false, HelperPrivilegedMutationGate.busyMessage)
            return
        }

        switch outcome {
        case .rateLimited:
            Self.logger.warning("SECURITY: Rate-limited proxy change request")
            reply(false, "Too many requests — wait before retrying")
        case .ownerIdentityUnavailable:
            Self.logger.error("SECURITY: Refused proxy override — the requesting process could not be identified")
            reply(false, "Could not identify the requesting app — no proxy settings were changed")
        case .attempted(.success):
            reply(true, nil)
        case let .attempted(.failure(error)):
            Self.logger.error("Failed to override proxy: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func restoreSystemProxy(withReply reply: @escaping (Bool, String?) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("restoreSystemProxy called")

        guard let result = Self.mutationGate.withExclusiveAccess({
            Result {
                try DirectProxySessionLock.withExclusiveAccess(userID: boundUserID) {
                    if let backup = try CrashRecovery.loadBackup() {
                        let ownerSessionIsLive: Bool = if let ownerPID = backup.ownerPID {
                            ProxyBackupOwnerIdentityPolicy.ownerSessionIsLive(
                                recordedOwnerPID: ownerPID,
                                recordedStartSignature: backup.ownerStartSignature,
                                ownerProcessIsAlive: ProcessStartIdentity.isAlive(ownerPID),
                                liveStartSignature: ProcessStartIdentity.startSignature(for: ownerPID),
                                ownerPassesCallerValidation: true
                            )
                        } else {
                            false
                        }
                        guard HelperBoundProcessIdentityPolicy.mayRestoreSession(
                            ownerSessionIsLive: ownerSessionIsLive,
                            recordedOwnerPID: backup.ownerPID,
                            recordedOwnerStartSignature: backup.ownerStartSignature,
                            callerPID: boundConnectionPID,
                            callerStartSignature: boundConnectionStartSignature
                        ) else {
                            throw ProxyConfiguratorError.noOwnedProxySession
                        }
                    }
                    try ProxyConfigurator.restoreProxyOrThrow()
                    Self.stopOwnerWatchdog()
                }
            }
        }) else {
            reply(false, HelperPrivilegedMutationGate.busyMessage)
            return
        }
        switch result {
        case .success:
            reply(true, nil)
        case let .failure(error):
            Self.logger.error("Failed to restore proxy: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func getProxyStatus(withReply reply: @escaping (Bool, Int) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        let status = ProxyConfigurator.getCurrentStatus()
        reply(status.isOverridden, status.port)
    }

    func getHelperInfo(withReply reply: @escaping (String, Int, Int) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        reply(Self.version, Self.buildNumber, Self.protocolVersion)
    }

    /// Answers with the identity of the executable this process is actually running.
    ///
    /// Everything reported here is fixed for the lifetime of the process and computed once at
    /// first use, so repeated polling during an update cannot re-read a file that changed
    /// underneath a still-running binary, and cannot turn a poll loop into repeated hashing.
    ///
    /// This is a read. It is deliberately not gated behind the privileged mutation gate:
    /// answering "unknown" because a certificate operation happened to be running would be a
    /// wrong answer rather than a busy one, and the caller would read it as drift.
    func getExecutableIdentity(
        withReply reply: @escaping (String, String, Int32, String, Int, Int) -> Void
    ) {
        IdleExitMonitor.resetIdleTimer()
        let identity = Self.runningExecutableIdentity
        reply(
            identity.executableDigest,
            identity.launchIdentity,
            identity.processIdentifier,
            identity.executablePath,
            identity.buildNumber,
            identity.protocolVersion
        )
    }

    func prepareForUninstall(withReply reply: @escaping (Bool) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("prepareForUninstall called")

        // Nothing is torn down until the settings are provably back. Stopping the watchdog and
        // clearing the backup together remove the last two things that could restore them, so a
        // restore that failed must leave both exactly where they are — otherwise a failed
        // uninstall becomes a permanent override with no way back.
        guard let prepared = Self.mutationGate.withExclusiveAccess({
            HelperUninstallPreparation.run(
                restore: { try ProxyConfigurator.restoreProxyOrThrow() },
                stopWatchdog: { Self.stopOwnerWatchdog() },
                clearBackup: { CrashRecovery.clearBackup() }
            )
        }) else {
            Self.logger.error("prepareForUninstall refused — another privileged mutation is running")
            reply(false)
            return
        }
        if !prepared {
            Self.logger
                .error(
                    "prepareForUninstall could not restore the proxy — keeping the backup and the watchdog in place"
                )
        }
        reply(prepared)
    }

    func prepareForExecutableRefresh(withReply reply: @escaping (Bool) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("Preparing helper executable refresh without unregistering service")

        let proxyStatus = ProxyConfigurator.getCurrentStatus()
        guard !proxyStatus.isOverridden else {
            Self.logger.info(
                "Deferring helper executable refresh while Rockxy proxy override is active on port \(proxyStatus.port)"
            )
            reply(false)
            return
        }

        guard let exitBarrier = Self.mutationGate.beginProcessExitBarrier() else {
            Self.logger.info("Deferring helper executable refresh while a certificate operation is active")
            reply(false)
            return
        }

        // Close the race between the first proxy check and acquiring the certificate barrier.
        // If proxy ownership changed, do not exit and restore the gate by restarting naturally
        // through the helper's idle lifecycle rather than risking an interrupted override.
        let confirmedProxyStatus = ProxyConfigurator.getCurrentStatus()
        guard !confirmedProxyStatus.isOverridden else {
            Self.mutationGate.release(exitBarrier)
            Self.logger.info(
                "Deferring helper executable refresh because proxy override became active on port \(confirmedProxyStatus.port)"
            )
            reply(false)
            return
        }

        Self.stopOwnerWatchdog()
        reply(true)

        // Give XPC enough time to deliver the acknowledgement. A zero exit is intentional:
        // launchd keeps the approved on-demand service registered and resolves BundleProgram
        // from the app bundle again when the next connection arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Foundation.exit(0)
        }
    }

    // MARK: - Bypass Domain Management

    func setBypassDomains(_ domains: [String], withReply reply: @escaping (Bool, String?) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("setBypassDomains called with \(domains.count) domain(s)")

        guard domains.count <= 500 else {
            Self.logger.warning("SECURITY: Too many bypass domains: \(domains.count)")
            reply(false, "Too many bypass domains (max 500)")
            return
        }

        guard let result = Self.mutationGate.withExclusiveAccess({
            Result {
                guard let backup = try CrashRecovery.loadBackup(),
                      HelperBoundProcessIdentityPolicy.ownsProxySession(
                          boundPID: boundConnectionPID,
                          boundStartSignature: boundConnectionStartSignature,
                          liveStartSignature: ProcessStartIdentity.startSignature(for: boundConnectionPID),
                          recordedOwnerPID: backup.ownerPID,
                          recordedOwnerStartSignature: backup.ownerStartSignature,
                          hasBackedUpServices: !backup.services.isEmpty
                      ) else
                {
                    throw ProxyConfiguratorError.noOwnedProxySession
                }
                try ProxyConfigurator.setBypassDomains(
                    domains,
                    services: backup.services.map(\.service)
                )
            }
        }) else {
            reply(false, HelperPrivilegedMutationGate.busyMessage)
            return
        }
        switch result {
        case .success:
            reply(true, nil)
        case let .failure(error):
            Self.logger.error("Failed to set bypass domains: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    // MARK: - Certificate Trust Management

    /// Installs exactly the supplied root CA certificate and records admin trust for it.
    ///
    /// Nothing is removed, before or after. An earlier Rockxy root — and any root this app did
    /// not install — survives every outcome of this call, including a failed add, a refused trust
    /// write, and a postcondition that does not hold. Sweeping the label first is what made a
    /// reinstall destroy the certificate a user was still relying on, and it is not something
    /// this operation can do any more: `RootCertificateInstallOperations` has no removal member.
    ///
    /// A partial failure is reported as a failure with whatever succeeded left in place. There is
    /// no rollback: deleting the certificate that was just added to make the error look tidy is
    /// itself a destructive act on material the caller never asked to remove.
    func installRootCertificate(_ derData: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("SECURITY: installRootCertificate called (\(derData.count) bytes)")

        guard let result = Self.mutationGate.withExclusiveAccess({
            Result {
                try RootCertificateInstaller.installTrustedRoot(
                    derData: derData,
                    label: Self.certLabel,
                    using: Self.systemOperations
                )
            }
        }) else {
            Self.logger.error("SECURITY: installRootCertificate refused — another certificate mutation is running")
            reply(false, HelperPrivilegedMutationGate.busyMessage)
            return
        }

        switch result {
        case let .success(outcome):
            Self.logger.info(
                "SECURITY: Root CA installed (added: \(outcome.addedCertificate), trust applied: \(outcome.appliedTrustSettings))"
            )
            reply(true, nil)
        case let .failure(error):
            Self.logger.error("SECURITY: Failed to install root certificate: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    /// Removes exactly the certificate the caller identified, plus its admin trust settings.
    ///
    /// Introduced with protocol version 2. Current app builds address removal only through
    /// this selector: the DER bytes name one certificate, so nothing that merely shares a
    /// label or a common name can be swept up with it.
    func removeRootCertificateMatching(_ derData: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("SECURITY: removeRootCertificateMatching called (\(derData.count) bytes)")

        guard let result = Self.mutationGate.withExclusiveAccess({
            Result {
                try RootCertificateRemover.removeExactCertificate(
                    derData: derData,
                    using: Self.systemOperations
                )
            }
        }) else {
            Self.logger.error("SECURITY: removeRootCertificateMatching refused — another mutation is running")
            reply(false, HelperPrivilegedMutationGate.busyMessage)
            return
        }

        switch result {
        case let .success(outcome):
            Self.logger.info(
                "SECURITY: Removed \(outcome.removedCertificateCount) system certificate copy/copies, trust settings removed: \(outcome.removedTrustSettings)"
            )
            reply(true, nil)
        case let .failure(error):
            Self.logger.error("SECURITY: Exact root certificate removal failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    /// Legacy label sweep, kept for app builds that predate protocol version 2.
    ///
    /// Discovery is still the configured label — never a common-name search — and each
    /// discovered certificate goes through the same exact-DER removal, so the trust-before-
    /// delete ordering and the post-removal verification are identical.
    func removeRootCertificate(withReply reply: @escaping (Bool, String?) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("SECURITY: removeRootCertificate (legacy label sweep) called")

        guard let result = Self.mutationGate.withExclusiveAccess({
            Result {
                try RootCertificateRemover.removeLabeledCertificates(
                    label: Self.certLabel,
                    keepingFingerprint: nil,
                    using: Self.systemOperations
                )
            }
        }) else {
            Self.logger.error("SECURITY: removeRootCertificate refused — another certificate mutation is running")
            reply(false, HelperPrivilegedMutationGate.busyMessage)
            return
        }

        switch result {
        case let .success(outcome):
            if let detail = outcome.failureDetail {
                Self.logger.error("SECURITY: Legacy root certificate removal incomplete: \(detail)")
                reply(false, detail)
                return
            }
            Self.logger.info("SECURITY: Removed \(outcome.removedCount) root CA certificate(s) and trust settings")
            reply(true, nil)
        case let .failure(error):
            Self.logger.error("SECURITY: Legacy root certificate removal failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    /// Reports whether a certificate with this fingerprint is installed *and* positively trusted
    /// in the admin domain.
    ///
    /// This is a read, so it is never gated: answering "not trusted" because another operation
    /// held the mutation gate would be a wrong answer rather than a busy one. It is also strict
    /// about what trust means — a deny and an unreadable entry are settings that exist, and
    /// reporting either as trust is how a root macOS refuses gets presented as ready.
    func verifyRootCertificateTrusted(_ fingerprint: String, withReply reply: @escaping (Bool) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.debug("verifyRootCertificateTrusted called for fingerprint: \(fingerprint)")

        do {
            let installed = try Self.systemOperations.systemCertificates(label: Self.certLabel)
            for entry in installed
                where RootCertificateRemover.fingerprint(of: entry.derData) == fingerprint
            {
                if try Self.systemOperations.hasPositiveAdminTrustSettings(derData: entry.derData) {
                    reply(true)
                    return
                }
            }
        } catch {
            Self.logger.error("SECURITY: Trust verification read failed: \(error.localizedDescription)")
        }

        reply(false)
    }

    func cleanupStaleCertificates(
        _ activeFingerprint: String,
        withReply reply: @escaping (Int, String?) -> Void
    ) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("SECURITY: cleanupStaleCertificates called, keeping: \(activeFingerprint)")

        guard let result = Self.mutationGate.withExclusiveAccess({
            Result {
                try RootCertificateRemover.removeLabeledCertificates(
                    label: Self.certLabel,
                    keepingFingerprint: activeFingerprint,
                    using: Self.systemOperations
                )
            }
        }) else {
            Self.logger.error("SECURITY: cleanupStaleCertificates refused — another mutation is running")
            reply(0, HelperPrivilegedMutationGate.busyMessage)
            return
        }

        switch result {
        case let .success(outcome):
            if let detail = outcome.failureDetail {
                Self.logger.error("SECURITY: Stale certificate cleanup incomplete: \(detail)")
            }
            Self.logger.info("SECURITY: Cleaned up \(outcome.removedCount) stale certificate(s)")
            // Only removals that completed and verified are counted; anything that failed is
            // reported instead of being folded into the count.
            reply(outcome.removedCount, outcome.failureDetail)
        case let .failure(error):
            Self.logger.error("SECURITY: Stale certificate cleanup failed: \(error.localizedDescription)")
            reply(0, error.localizedDescription)
        }
    }

    // MARK: Private

    private enum InvalidationAction: Equatable {
        case ignore
        case restore(ownerPID: Int32)
        case watchdog(ownerPID: Int32)
    }

    /// Whether an override request was refused before it could run, or actually attempted. Every
    /// answer is produced inside the mutation gate so the rate limit sees a consistent timestamp
    /// and no refusal path can touch a setting, and each keeps the reply shape the caller expects.
    private enum ProxyOverrideOutcome {
        case rateLimited
        case ownerIdentityUnavailable
        case attempted(Result<Void, any Error>)
    }

    /// The app process a watchdog is watching. The start signature is carried alongside the
    /// identifier — and is never absent — because a recycled identifier would otherwise read as
    /// the same live owner.
    private struct OwnerSession {
        let processIdentifier: Int32
        let startSignature: String
        let userID: uid_t
        let token: UUID
    }

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperService"
    )
    private static let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    private static let buildNumber: Int = .init(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    private static let protocolVersion: Int = .init(
        Bundle.main.infoDictionary?["RockxyHelperProtocolVersion"] as? String ?? "0"
    ) ?? 0

    /// A UUID minted once per helper launch. Two answers carrying it came from the same process,
    /// which is what lets the app tell a helper that genuinely restarted from the old one still
    /// holding the Mach service.
    private static let launchIdentity = UUID().uuidString

    /// The running executable's identity, computed once and reused for every probe.
    ///
    /// A digest that could not be read is reported as an empty string rather than as some
    /// plausible-looking value: the app treats a malformed digest as "cannot be compared", which
    /// keeps the update pending instead of declaring a convergence that was never observed.
    private static let runningExecutableIdentity: HelperExecutableIdentity = {
        let executablePath = HelperExecutableLocation.currentProcessExecutablePath()
        let digest: String
        do {
            digest = try HelperExecutableDigest.sha256Hex(atPath: executablePath)
        } catch {
            logger.error("Could not digest the running helper executable: \(error.localizedDescription)")
            digest = ""
        }
        return HelperExecutableIdentity(
            executableDigest: digest,
            launchIdentity: launchIdentity,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            executablePath: executablePath,
            buildNumber: buildNumber,
            protocolVersion: protocolVersion
        )
    }()

    private static let validPortRange = 1_024 ... 65_535
    private static let rateLimitInterval: TimeInterval = 2.0
    private static let ownerWatchdogInterval: TimeInterval = 2.0
    private static let connectionInvalidationGraceInterval: TimeInterval = 0.5
    private static let startupRecoveryRetryKey = "retained-proxy-backup"

    // MARK: - Private Certificate Helpers

    private static let certLabel = RockxyIdentity.current.rootCACertificateLabel

    /// The System-keychain-scoped side effects every certificate install and removal path runs
    /// through. Trust writes go to the Apple-signed `security` tool, whose signature is validated
    /// before each run.
    private static let systemOperations = SystemKeychainCertificateOperations(
        keychainPath: SystemKeychainCertificateOperations.systemKeychainPath,
        trust: SecurityToolAdminTrustSettings(
            keychainPath: SystemKeychainCertificateOperations.systemKeychainPath,
            validateBinary: { BinaryValidator.validateAppleSignedBinary(at: $0) }
        )
    )

    /// Serializes every certificate mutation this daemon performs. XPC delivers messages
    /// concurrently, so without it an install's verification could read a concurrent removal's
    /// result — or delete the certificate the install had just added.
    private static let mutationGate = HelperPrivilegedMutationGate.shared
    private static let automaticRestoreRetrier = HelperPrivilegedMutationRetrier(gate: mutationGate)

    /// The owner session is process-global while the exported object is per-connection: one
    /// machine has one set of proxy settings and one watchdog over them, however many clients are
    /// talking to the helper.
    ///
    /// `lastProxyChangeTime` is only ever read or written while the privileged mutation gate is
    /// held.
    private static var lastProxyChangeTime: Date?
    private static let ownerStateLock = NSLock()
    private static var ownerWatchdog: DispatchSourceTimer?
    private static var ownerSession: OwnerSession?

    /// The authenticated peer of the connection this object was exported on. Every
    /// ownership-bearing method is answered for this identity and no other.
    private let boundConnectionPID: Int32
    private let boundConnectionStartSignature: String
    private let boundUserID: uid_t

    private static func invalidationAction(
        ownerPID: Int32?,
        invalidatedPID: Int32,
        ownerAlive: Bool
    )
        -> InvalidationAction
    {
        guard let ownerPID, ownerPID == invalidatedPID else {
            return .ignore
        }

        return ownerAlive ? .watchdog(ownerPID: ownerPID) : .restore(ownerPID: ownerPID)
    }

    // MARK: - Owner Watchdog

    private static func startOwnerWatchdog(for pid: Int32, startSignature: String, userID: uid_t) {
        stopOwnerWatchdog()

        let ownershipToken = UUID()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + ownerWatchdogInterval, repeating: ownerWatchdogInterval)

        ownerStateLock.lock()
        ownerSession = OwnerSession(
            processIdentifier: pid,
            startSignature: startSignature,
            userID: userID,
            token: ownershipToken
        )
        ownerWatchdog = timer
        ownerStateLock.unlock()
        timer.setEventHandler {
            guard let owner = currentOwnerSnapshot(),
                  owner.token == ownershipToken else
            {
                return
            }
            let ownerPID = owner.processIdentifier

            if ownerSessionIsLive(owner) {
                return
            }

            logger.warning("Owner app process \(ownerPID) is gone — restoring proxy override automatically")
            requestAutomaticProxyRestore(
                for: ownerPID,
                ownershipToken: ownershipToken,
                reason: "owner watchdog"
            )
        }
        timer.resume()
        logger.info("Started owner watchdog for app PID \(pid)")
    }

    private static func stopOwnerWatchdog() {
        ownerStateLock.lock()
        let watchdog = ownerWatchdog
        ownerWatchdog = nil
        ownerSession = nil
        ownerStateLock.unlock()
        watchdog?.cancel()
    }

    /// Whether the watched owner is still the exact process the watchdog was armed for. Every
    /// liveness and recheck path goes through here so a recycled identifier can never keep a
    /// stranded override alive.
    private static func ownerSessionIsLive(_ owner: OwnerSession) -> Bool {
        let processIsAlive = ProcessStartIdentity.isAlive(owner.processIdentifier)
        return ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: owner.processIdentifier,
            recordedStartSignature: owner.startSignature,
            processIsAlive: processIsAlive,
            liveStartSignature: processIsAlive
                ? ProcessStartIdentity.startSignature(for: owner.processIdentifier)
                : nil
        )
    }

    private static func scheduleOwnerDisconnectRecheck(for pid: Int32, ownershipToken: UUID?) {
        let delay = connectionInvalidationGraceInterval
        guard let ownershipToken else {
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            guard let owner = matchedOwnerSession(processIdentifier: pid, token: ownershipToken) else {
                return
            }
            guard !ownerSessionIsLive(owner) else {
                return
            }

            logger.warning("Owner pid \(pid) disappeared after XPC invalidation grace period — restoring proxy")
            requestAutomaticProxyRestore(
                for: pid,
                ownershipToken: ownershipToken,
                reason: "owner disconnect recheck"
            )
        }
    }

    private static func requestAutomaticProxyRestore(
        for expectedOwnerPID: Int32,
        ownershipToken: UUID?,
        reason: String
    ) {
        guard let ownershipToken else {
            return
        }
        let retryKey = ownershipToken.uuidString
        automaticRestoreRetrier.run(
            key: retryKey,
            operation: {
                guard let owner = matchedOwnerSession(
                    processIdentifier: expectedOwnerPID,
                    token: ownershipToken
                ) else {
                    return true
                }

                do {
                    try DirectProxySessionLock.withExclusiveAccess(userID: owner.userID) {
                        try ProxyConfigurator.restoreProxyOrThrow()
                    }
                    stopOwnerWatchdog()
                    logger.info("Automatic proxy restoration completed after \(reason)")
                    return true
                } catch {
                    logger.error(
                        "Automatic proxy restoration after \(reason) failed and will retry: \(error.localizedDescription)"
                    )
                    return false
                }
            },
            onExhausted: {
                logger.error(
                    "Automatic proxy restoration after \(reason) exhausted bounded retries; preserving backup for recovery"
                )
            }
        )
    }

    private static func currentOwnerSnapshot() -> OwnerSession? {
        ownerStateLock.lock()
        defer { ownerStateLock.unlock() }
        return ownerSession
    }

    private static func matchedOwnerSession(processIdentifier: Int32, token: UUID) -> OwnerSession? {
        ownerStateLock.lock()
        defer { ownerStateLock.unlock() }
        guard let ownerSession,
              ownerSession.processIdentifier == processIdentifier,
              ownerSession.token == token else
        {
            return nil
        }
        return ownerSession
    }
}
