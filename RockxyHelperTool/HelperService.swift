import CommonCrypto
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

        do {
            try ProxyConfigurator.overrideProxy(port: port)
            lastProxyChangeTime = Date()
            startOwnerWatchdog(for: ownerPID)
            reply(true, nil)
        } catch {
            Self.logger.error("Failed to override proxy: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func restoreSystemProxy(withReply reply: @escaping (Bool, String?) -> Void) {
        Self.logger.info("restoreSystemProxy called")

        do {
            try ProxyConfigurator.restoreProxyOrThrow()
            stopOwnerWatchdog()
            reply(true, nil)
        } catch {
            Self.logger.error("Failed to restore proxy: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func getProxyStatus(withReply reply: @escaping (Bool, Int) -> Void) {
        let status = ProxyConfigurator.getCurrentStatus()
        reply(status.isOverridden, status.port)
    }

    func getHelperInfo(withReply reply: @escaping (String, Int, Int) -> Void) {
        let version = Self.version
        let build = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
        let protocol_ = Int(Bundle.main.infoDictionary?["RockxyHelperProtocolVersion"] as? String ?? "0") ?? 0
        reply(version, build, protocol_)
    }

    func prepareForUninstall(withReply reply: @escaping (Bool) -> Void) {
        Self.logger.info("prepareForUninstall called")

        stopOwnerWatchdog()
        ProxyConfigurator.restoreProxy()
        CrashRecovery.clearBackup()
        reply(true)
    }

    func handleConnectionInvalidated(processID: Int32) {
        let action: InvalidationAction

        if let ownerPID {
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
            stopOwnerWatchdog()
            ProxyConfigurator.restoreProxy()
        case let .watchdog(ownerPID):
            Self.logger.info("Owner pid \(ownerPID) still alive after XPC invalidation — deferring to watchdog")
            scheduleOwnerDisconnectRecheck(for: ownerPID)
        }
    }

    // MARK: - Bypass Domain Management

    func setBypassDomains(_ domains: [String], withReply reply: @escaping (Bool, String?) -> Void) {
        Self.logger.info("setBypassDomains called with \(domains.count) domain(s)")

        guard domains.count <= 500 else {
            Self.logger.warning("SECURITY: Too many bypass domains: \(domains.count)")
            reply(false, "Too many bypass domains (max 500)")
            return
        }

        do {
            try ProxyConfigurator.setBypassDomains(domains)
            reply(true, nil)
        } catch {
            Self.logger.error("Failed to set bypass domains: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    // MARK: - Certificate Trust Management

    func installRootCertificate(_ derData: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        Self.logger.info("SECURITY: installRootCertificate called (\(derData.count) bytes)")

        guard derData.count < 10000 else {
            Self.logger.error("SECURITY: Rejected oversized certificate data (\(derData.count) bytes)")
            reply(false, "Certificate data too large — maximum 10,000 bytes")
            return
        }

        guard let secCert = SecCertificateCreateWithData(nil, derData as CFData) else {
            Self.logger.error("SECURITY: Invalid certificate data — SecCertificateCreateWithData failed")
            reply(false, "Invalid certificate data")
            return
        }

        do {
            try addCertificateToSystemKeychain(secCert, derData: derData)
            Self.logger.info("SECURITY: Root CA certificate added to system keychain")

            // Set trust on the system keychain copy via `security add-trusted-cert` CLI.
            // This runs as root from the helper daemon — no UI dialog needed.
            // Trust must be set on the same keychain copy that SecTrust evaluates against.
            try setTrustSettings(derData: derData)

            reply(true, nil)
        } catch {
            Self.logger.error("SECURITY: Failed to install root certificate: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    func removeRootCertificate(withReply reply: @escaping (Bool, String?) -> Void) {
        Self.logger.info("SECURITY: removeRootCertificate called")

        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: Self.certLabel,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            Self.logger.info("SECURITY: No Rockxy root CA certificate found to remove")
            reply(true, nil)
            return
        }

        guard status == errSecSuccess, let certs = result as? [SecCertificate] else {
            Self.logger.error("SECURITY: Failed to find certificate for removal: \(status)")
            reply(false, "Failed to find certificate: OSStatus \(status)")
            return
        }

        var lastError: String?
        for cert in certs {
            if let data = SecCertificateCopyData(cert) as Data? {
                removeTrustSettings(derData: data)
            } else {
                Self.logger.warning("SECURITY: Could not extract DER data for trust removal")
                lastError = "Failed to extract certificate data for trust removal"
            }
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: Self.certLabel,
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        if deleteStatus != errSecSuccess, deleteStatus != errSecItemNotFound {
            Self.logger.error("SECURITY: Failed to delete certificate: \(deleteStatus)")
            reply(false, "Failed to delete certificate: OSStatus \(deleteStatus)")
            return
        }

        Self.logger.info("SECURITY: Root CA certificate and trust settings removed")
        reply(lastError == nil, lastError)
    }

    func verifyRootCertificateTrusted(_ fingerprint: String, withReply reply: @escaping (Bool) -> Void) {
        Self.logger.debug("verifyRootCertificateTrusted called for fingerprint: \(fingerprint)")

        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: Self.certLabel,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            reply(false)
            return
        }

        for item in items {
            guard let certData = item[kSecValueData as String] as? Data else {
                continue
            }

            let certFingerprint = computeSHA256Fingerprint(certData)
            if certFingerprint == fingerprint {
                // swiftlint:disable:next force_cast
                let cert = item[kSecValueRef as String] as! SecCertificate

                var trustSettings: CFArray?
                let trustStatus = SecTrustSettingsCopyTrustSettings(cert, .admin, &trustSettings)
                if trustStatus == errSecSuccess, trustSettings != nil {
                    reply(true)
                    return
                }
            }
        }

        reply(false)
    }

    func cleanupStaleCertificates(
        _ activeFingerprint: String,
        withReply reply: @escaping (Int, String?) -> Void
    ) {
        Self.logger.info("SECURITY: cleanupStaleCertificates called, keeping: \(activeFingerprint)")

        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: Self.certLabel,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            reply(0, nil)
            return
        }

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            reply(0, "Failed to enumerate certificates: OSStatus \(status)")
            return
        }

        var removedCount = 0
        for item in items {
            guard let certData = item[kSecValueData as String] as? Data else {
                continue
            }
            // swiftlint:disable:next force_cast
            let cert = item[kSecValueRef as String] as! SecCertificate

            let certFingerprint = computeSHA256Fingerprint(certData)
            if certFingerprint != activeFingerprint {
                removeTrustSettings(derData: certData)

                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassCertificate,
                    kSecValueRef as String: cert,
                ]
                let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
                if deleteStatus == errSecSuccess {
                    removedCount += 1
                    Self.logger.info("SECURITY: Removed stale certificate (fingerprint: \(certFingerprint))")
                }
            }
        }

        Self.logger.info("SECURITY: Cleaned up \(removedCount) stale certificate(s)")
        reply(removedCount, nil)
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
    private static let validPortRange = 1024 ... 65535
    private static let rateLimitInterval: TimeInterval = 2.0
    private static let ownerWatchdogInterval: TimeInterval = 2.0
    private static let connectionInvalidationGraceInterval: TimeInterval = 0.5

    // MARK: - Private Certificate Helpers

    private static let certLabel = RockxyIdentity.current.rootCACertificateLabel

    private static let securityToolPath = "/usr/bin/security"

    private var lastProxyChangeTime: Date?
    private var ownerWatchdog: DispatchSourceTimer?
    private var ownerPID: Int32?

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

        ownerPID = pid

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + Self.ownerWatchdogInterval, repeating: Self.ownerWatchdogInterval)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            guard let ownerPID = self.ownerPID else {
                return
            }

            if self.isProcessAlive(ownerPID) {
                return
            }

            Self.logger.warning("Owner app process \(ownerPID) is gone — restoring proxy override automatically")
            self.stopOwnerWatchdog()
            ProxyConfigurator.restoreProxy()
        }
        ownerWatchdog = timer
        timer.resume()
        Self.logger.info("Started owner watchdog for app PID \(pid)")
    }

    private func stopOwnerWatchdog() {
        ownerWatchdog?.cancel()
        ownerWatchdog = nil
        ownerPID = nil
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private func scheduleOwnerDisconnectRecheck(for pid: Int32) {
        let delay = Self.connectionInvalidationGraceInterval
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                return
            }
            guard let currentOwnerPID = self.ownerPID, currentOwnerPID == pid else {
                return
            }
            guard !self.isProcessAlive(pid) else {
                return
            }

            Self.logger.warning("Owner pid \(pid) disappeared after XPC invalidation grace period — restoring proxy")
            self.stopOwnerWatchdog()
            ProxyConfigurator.restoreProxy()
        }
    }

    private func addCertificateToSystemKeychain(
        _ certificate: SecCertificate,
        derData: Data
    )
        throws
    {
        var keychain: SecKeychain?
        let openStatus = SecKeychainOpen(
            "/Library/Keychains/System.keychain",
            &keychain
        )
        guard openStatus == errSecSuccess, let systemKeychain = keychain else {
            throw CertificateInstallError.keychainOpenFailed(openStatus)
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: Self.certLabel,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueData as String: derData,
            kSecAttrLabel as String: Self.certLabel,
            kSecUseKeychain as String: systemKeychain,
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw CertificateInstallError.certAddFailed(addStatus)
        }
    }

    /// Sets trust settings using `/usr/bin/security add-trusted-cert` CLI.
    /// `SecTrustSettingsSetTrustSettings(.admin)` requires interactive Authorization Services
    /// dialog, which fails with `-60007` from non-interactive launchd daemons even as root.
    private func setTrustSettings(derData: Data) throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-root-ca-\(UUID().uuidString).der")
        guard FileManager.default.createFile(
            atPath: tempURL.path,
            contents: derData,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CertificateInstallError.trustSettingsFailed(detail: "Failed to create temp DER file")
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.securityToolPath)
        process.arguments = [
            "add-trusted-cert", "-d",
            "-r", "trustRoot",
            "-k", "/Library/Keychains/System.keychain",
            tempURL.path,
        ]

        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CertificateInstallError.trustSettingsFailed(detail: error.localizedDescription)
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw CertificateInstallError.trustSettingsFailed(
                detail: "security add-trusted-cert exit \(process.terminationStatus): \(stderr)"
            )
        }

        Self.logger.info("SECURITY: Trust settings applied via security CLI")
    }

    /// Removes trust settings using `/usr/bin/security remove-trusted-cert` CLI.
    private func removeTrustSettings(derData: Data) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-remove-cert-\(UUID().uuidString).der")
        guard FileManager.default.createFile(
            atPath: tempURL.path,
            contents: derData,
            attributes: [.posixPermissions: 0o600]
        ) else {
            Self.logger.warning("SECURITY: Failed to create temp DER file for trust removal")
            return
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.securityToolPath)
        process.arguments = ["remove-trusted-cert", "-d", tempURL.path]

        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                Self.logger.warning("SECURITY: remove-trusted-cert exit \(process.terminationStatus): \(stderr)")
            }
        } catch {
            Self.logger.warning("SECURITY: Failed to run remove-trusted-cert: \(error.localizedDescription)")
        }
    }

    private func computeSHA256Fingerprint(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}

// MARK: - CertificateInstallError

private enum CertificateInstallError: LocalizedError {
    case keychainOpenFailed(OSStatus)
    case certAddFailed(OSStatus)
    case trustSettingsFailed(detail: String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .keychainOpenFailed(status):
            "Failed to open system keychain: OSStatus \(status)"
        case let .certAddFailed(status):
            "Failed to add certificate to keychain: OSStatus \(status)"
        case let .trustSettingsFailed(detail):
            "Failed to set trust settings: \(detail)"
        }
    }
}
