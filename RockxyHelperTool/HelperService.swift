import Darwin
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

    override private init() {
        super.init()
    }

    // MARK: Internal

    static let shared = HelperService()

    func overrideSystemProxy(port: Int, ownerPID: Int32, withReply reply: @escaping (Bool, String?) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("overrideSystemProxy called with port \(port), ownerPID \(ownerPID)")

        guard Self.validPortRange.contains(port) else {
            Self.logger.error("SECURITY: Rejected invalid port \(port) — must be \(Self.validPortRange)")
            reply(false, "Invalid port: must be \(Self.validPortRange.lowerBound)-\(Self.validPortRange.upperBound)")
            return
        }

        guard ownerPID > 0 else {
            Self.logger.error("SECURITY: Rejected invalid owner PID \(ownerPID)")
            reply(false, "Invalid owner PID")
            return
        }

        if let lastChange = lastProxyChangeTime,
           Date().timeIntervalSince(lastChange) < Self.rateLimitInterval
        {
            Self.logger.warning("SECURITY: Rate-limited proxy change request")
            reply(false, "Too many requests — wait before retrying")
            return
        }

        guard let result = Self.mutationGate.withExclusiveAccess({
            Result {
                try ProxyConfigurator.overrideProxy(port: port)
                lastProxyChangeTime = Date()
                startOwnerWatchdog(for: ownerPID)
            }
        }) else {
            reply(false, HelperPrivilegedMutationGate.busyMessage)
            return
        }
        switch result {
        case .success:
            reply(true, nil)
        case let .failure(error):
            Self.logger.error("Failed to override proxy: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func restoreSystemProxy(withReply reply: @escaping (Bool, String?) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("restoreSystemProxy called")

        guard let result = Self.mutationGate.withExclusiveAccess({
            Result {
                try ProxyConfigurator.restoreProxyOrThrow()
                stopOwnerWatchdog()
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
        let version = Self.version
        let build = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
        let protocolVersion = Int(Bundle.main.infoDictionary?["RockxyHelperProtocolVersion"] as? String ?? "0") ?? 0
        reply(version, build, protocolVersion)
    }

    func prepareForUninstall(withReply reply: @escaping (Bool) -> Void) {
        IdleExitMonitor.resetIdleTimer()
        Self.logger.info("prepareForUninstall called")

        let preparation: Void? = Self.mutationGate.withExclusiveAccess {
            stopOwnerWatchdog()
            ProxyConfigurator.restoreProxy()
            CrashRecovery.clearBackup()
        }
        guard preparation != nil else {
            reply(false)
            return
        }
        reply(true)
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

        stopOwnerWatchdog()
        reply(true)

        // Give XPC enough time to deliver the acknowledgement. A zero exit is intentional:
        // launchd keeps the approved on-demand service registered and resolves BundleProgram
        // from the app bundle again when the next connection arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Foundation.exit(0)
        }
    }

    func handleConnectionInvalidated(processID: Int32) {
        let action: InvalidationAction
        let owner = currentOwnerSnapshot()

        if let owner {
            let ownerPID = owner.processIdentifier
            let ownerAlive = isProcessAlive(ownerPID)
            action = Self.invalidationAction(
                ownerPID: ownerPID,
                invalidatedPID: processID,
                ownerAlive: ownerAlive
            )
        } else {
            action = .ignore
        }

        switch action {
        case .ignore:
            Self.logger.debug("Ignoring XPC invalidation for pid \(processID)")
        case let .restore(ownerPID):
            Self.logger.warning("XPC owner connection \(ownerPID) vanished — restoring proxy override automatically")
            requestAutomaticProxyRestore(
                for: ownerPID,
                ownershipToken: owner?.token,
                reason: "owner connection invalidation"
            )
        case let .watchdog(ownerPID):
            Self.logger.info("Owner pid \(ownerPID) still alive after XPC invalidation — deferring to watchdog")
            scheduleOwnerDisconnectRecheck(for: ownerPID, ownershipToken: owner?.token)
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
            Result { try ProxyConfigurator.setBypassDomains(domains) }
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

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperService"
    )
    private static let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    private static let validPortRange = 1_024 ... 65_535
    private static let rateLimitInterval: TimeInterval = 2.0
    private static let ownerWatchdogInterval: TimeInterval = 2.0
    private static let connectionInvalidationGraceInterval: TimeInterval = 0.5

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

    private var lastProxyChangeTime: Date?
    private let ownerStateLock = NSLock()
    private var ownerWatchdog: DispatchSourceTimer?
    private var ownerPID: Int32?
    private var ownerWatchdogToken: UUID?

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

    private func startOwnerWatchdog(for pid: Int32) {
        stopOwnerWatchdog()

        let ownershipToken = UUID()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + Self.ownerWatchdogInterval, repeating: Self.ownerWatchdogInterval)

        ownerStateLock.lock()
        ownerPID = pid
        ownerWatchdogToken = ownershipToken
        ownerWatchdog = timer
        ownerStateLock.unlock()
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            guard let owner = self.currentOwnerSnapshot(),
                  owner.token == ownershipToken
            else {
                return
            }
            let ownerPID = owner.processIdentifier

            if self.isProcessAlive(ownerPID) {
                return
            }

            Self.logger.warning("Owner app process \(ownerPID) is gone — restoring proxy override automatically")
            self.requestAutomaticProxyRestore(
                for: ownerPID,
                ownershipToken: ownershipToken,
                reason: "owner watchdog"
            )
        }
        timer.resume()
        Self.logger.info("Started owner watchdog for app PID \(pid)")
    }

    private func stopOwnerWatchdog() {
        ownerStateLock.lock()
        let watchdog = ownerWatchdog
        ownerWatchdog = nil
        ownerPID = nil
        ownerWatchdogToken = nil
        ownerStateLock.unlock()
        watchdog?.cancel()
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private func scheduleOwnerDisconnectRecheck(for pid: Int32, ownershipToken: UUID?) {
        let delay = Self.connectionInvalidationGraceInterval
        guard let ownershipToken else {
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                return
            }
            guard self.ownerMatches(processIdentifier: pid, token: ownershipToken)
            else {
                return
            }
            guard !self.isProcessAlive(pid) else {
                return
            }

            Self.logger.warning("Owner pid \(pid) disappeared after XPC invalidation grace period — restoring proxy")
            self.requestAutomaticProxyRestore(
                for: pid,
                ownershipToken: ownershipToken,
                reason: "owner disconnect recheck"
            )
        }
    }

    private func requestAutomaticProxyRestore(
        for expectedOwnerPID: Int32,
        ownershipToken: UUID?,
        reason: String
    ) {
        guard let ownershipToken else {
            return
        }
        let retryKey = ownershipToken.uuidString
        Self.automaticRestoreRetrier.run(
            key: retryKey,
            operation: { [weak self] in
                guard let self,
                      self.ownerMatches(processIdentifier: expectedOwnerPID, token: ownershipToken)
                else {
                    return true
                }

                do {
                    try ProxyConfigurator.restoreProxyOrThrow()
                    self.stopOwnerWatchdog()
                    Self.logger.info("Automatic proxy restoration completed after \(reason)")
                    return true
                } catch {
                    Self.logger.error(
                        "Automatic proxy restoration after \(reason) failed and will retry: \(error.localizedDescription)"
                    )
                    return false
                }
            },
            onExhausted: {
                Self.logger.error(
                    "Automatic proxy restoration after \(reason) exhausted bounded retries; preserving backup for recovery"
                )
            }
        )
    }

    private func currentOwnerSnapshot() -> (processIdentifier: Int32, token: UUID)? {
        ownerStateLock.lock()
        defer { ownerStateLock.unlock() }
        guard let ownerPID, let ownerWatchdogToken else {
            return nil
        }
        return (ownerPID, ownerWatchdogToken)
    }

    private func ownerMatches(processIdentifier: Int32, token: UUID) -> Bool {
        ownerStateLock.lock()
        defer { ownerStateLock.unlock() }
        return ownerPID == processIdentifier && ownerWatchdogToken == token
    }
}
