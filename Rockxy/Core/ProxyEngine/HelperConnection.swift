import Foundation
import os

// Defines `HelperConnection`, which coordinates helper connections in the proxy engine.

// MARK: - HelperConnectionError

/// Errors that can occur when communicating with the privileged helper tool via XPC.
enum HelperConnectionError: LocalizedError {
    case connectionFailed
    case proxyOverrideFailed(String)
    case proxyRestoreFailed(String)
    case uninstallFailed
    case xpcTimeout
    case certInstallFailed(String)
    case certRemoveFailed(String)
    case bypassDomainsFailed(String)
    case appSignatureInvalid(String)
    case signingIdentityMismatch(app: String, helper: String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            "Failed to establish XPC connection to helper tool"
        case let .proxyOverrideFailed(reason):
            "Helper failed to override system proxy: \(reason)"
        case let .proxyRestoreFailed(reason):
            "Helper failed to restore system proxy: \(reason)"
        case .uninstallFailed:
            "Helper failed to prepare for uninstall"
        case .xpcTimeout:
            "XPC call timed out — helper tool may not be responding"
        case let .certInstallFailed(reason):
            "Helper failed to install root certificate: \(reason)"
        case let .certRemoveFailed(reason):
            "Helper failed to remove root certificate: \(reason)"
        case let .bypassDomainsFailed(reason):
            "Helper failed to set bypass domains: \(reason)"
        case let .appSignatureInvalid(detail):
            "This app build has an invalid code signature: \(detail)"
        case let .signingIdentityMismatch(app, helper):
            "This app is signed by \"\(app)\" but the installed helper was signed by \"\(helper)\""
        }
    }
}

// MARK: - SigningPreflightCache

/// Memoized signing diagnostic. Caches the result until explicitly invalidated.
/// Provider is injectable for tests.
@MainActor
final class SigningPreflightCache {
    // MARK: Internal

    var provider: () -> SigningDiagnostics.Result = { SigningDiagnostics.diagnose() }

    func evaluate() -> SigningDiagnostics.Result {
        if let cached {
            return cached
        }
        let result = provider()
        cached = result
        return result
    }

    func invalidate() {
        cached = nil
    }

    // MARK: Private

    private var cached: SigningDiagnostics.Result?
}

// MARK: - HelperConnection

/// XPC client for communicating with the Rockxy privileged helper daemon.
///
/// The helper tool runs as a launch daemon with root privileges, enabling fast system proxy
/// changes without password prompts after initial installation approval.
@MainActor
final class HelperConnection {
    // MARK: Internal

    static let shared = HelperConnection()

    let signingCache = SigningPreflightCache()

    nonisolated static func performEmergencyProxyRestore(timeout: TimeInterval = 3) -> Bool {
        let connection = NSXPCConnection(machServiceName: Self.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: RockxyHelperProtocol.self)

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var finished = false
        var succeeded = false

        func finish(_ success: Bool) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            succeeded = success
            lock.unlock()
            semaphore.signal()
        }

        connection.invalidationHandler = {
            Self.logger.warning("Emergency helper connection invalidated during proxy restore")
            finish(false)
        }
        connection.interruptionHandler = {
            Self.logger.warning("Emergency helper connection interrupted during proxy restore")
            finish(false)
        }

        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            Self.logger.error("Emergency helper proxy error: \(error.localizedDescription)")
            finish(false)
        }) as? any RockxyHelperProtocol else {
            Self.logger.error("Failed to create emergency helper proxy")
            connection.invalidate()
            return false
        }

        Self.logger.info("Requesting emergency helper proxy restore")
        proxy.restoreSystemProxy { success, errorMessage in
            if success {
                Self.logger.info("Emergency helper proxy restore completed")
                finish(true)
            } else {
                let reason = errorMessage ?? "Unknown error"
                Self.logger.error("Emergency helper proxy restore failed: \(reason)")
                finish(false)
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        connection.invalidate()

        if waitResult == .timedOut {
            Self.logger.error("Emergency helper proxy restore timed out after \(timeout, privacy: .public)s")
            return false
        }

        return succeeded
    }

    func invalidateSigningCache() {
        signingCache.invalidate()
    }

    /// Check whether the helper daemon is installed and responding to XPC messages.
    func isHelperAvailable() async -> Bool {
        do {
            let info = try await getHelperInfo()
            Self.logger.info("Helper available, version: \(info.binaryVersion) build: \(info.buildNumber)")
            return true
        } catch {
            Self.logger.info("Helper not available: \(error.localizedDescription)")
            return false
        }
    }

    /// Override system HTTP and HTTPS proxy to 127.0.0.1 on the given port.
    func overrideSystemProxy(port: Int) async throws {
        let proxy = try getProxy()
        let ownerPID = Int32(ProcessInfo.processInfo.processIdentifier)
        Self.logger.info("Calling helper overrideSystemProxy for port \(port)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.overrideSystemProxy(port: port, ownerPID: ownerPID) { success, errorMessage in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                if success {
                    Self.logger.info("Helper overrode system proxy to port \(port)")
                    continuation.resume()
                } else {
                    let reason = errorMessage ?? "Unknown error"
                    Self.logger.error("Helper failed to override proxy: \(reason)")
                    continuation.resume(throwing: HelperConnectionError.proxyOverrideFailed(reason))
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
    }

    /// Restore the original system proxy settings that were saved before the override.
    func restoreSystemProxy() async throws {
        let proxy = try getProxy()
        Self.logger.info("Calling helper restoreSystemProxy")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.restoreSystemProxy { success, errorMessage in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                if success {
                    Self.logger.info("Helper restored system proxy settings")
                    continuation.resume()
                } else {
                    let reason = errorMessage ?? "Unknown error"
                    Self.logger.error("Helper failed to restore proxy: \(reason)")
                    continuation.resume(throwing: HelperConnectionError.proxyRestoreFailed(reason))
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
    }

    /// Query structured helper info: version, build number, and protocol version.
    func getHelperInfo() async throws -> HelperInfo {
        let proxy = try getProxy()
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.getHelperInfo { version, build, protocolVersion in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                continuation.resume(returning: HelperInfo(
                    binaryVersion: version,
                    buildNumber: build,
                    protocolVersion: protocolVersion
                ))
            }

            Task {
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
    }

    /// Query the current proxy status from the helper: (isOverridden, port).
    func getProxyStatus() async throws -> (isOverridden: Bool, port: Int) {
        let proxy = try getProxy()
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.getProxyStatus { isOverridden, port in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                continuation.resume(returning: (isOverridden, port))
            }

            Task {
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
    }

    /// Tell the helper to restore proxy settings and prepare for removal,
    /// then invalidate the XPC connection.
    func uninstallHelper() async throws {
        let proxy = try getProxy()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.prepareForUninstall { success in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                if success {
                    Self.logger.info("Helper prepared for uninstall")
                    continuation.resume()
                } else {
                    Self.logger.error("Helper failed to prepare for uninstall")
                    continuation.resume(throwing: HelperConnectionError.uninstallFailed)
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
        connection?.invalidate()
        connection = nil
        signingCache.invalidate()
    }

    /// Set the system proxy bypass domain list via the helper tool.
    func setBypassDomains(_ domains: [String]) async throws {
        let proxy = try getProxy()
        Self.logger.info("Calling helper setBypassDomains with \(domains.count) domain(s)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.setBypassDomains(domains) { success, errorMessage in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                if success {
                    Self.logger.info("Helper set bypass domains successfully")
                    continuation.resume()
                } else {
                    let reason = errorMessage ?? "Unknown error"
                    Self.logger.error("Helper failed to set bypass domains: \(reason)")
                    continuation.resume(throwing: HelperConnectionError.bypassDomainsFailed(reason))
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
    }

    /// Install a root CA certificate in the system keychain and trust it for SSL.
    func installRootCertificate(derData: Data) async throws {
        let proxy = try getProxy()
        Self.logger.info("Calling helper installRootCertificate (\(derData.count) bytes)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.installRootCertificate(derData) { success, errorMessage in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                if success {
                    Self.logger.info("Helper installed root certificate in system keychain")
                    continuation.resume()
                } else {
                    let reason = errorMessage ?? "Unknown error"
                    Self.logger.error("Helper failed to install root certificate: \(reason)")
                    continuation.resume(throwing: HelperConnectionError.certInstallFailed(reason))
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
    }

    /// Remove the Rockxy root CA certificate and trust settings from the system keychain.
    func removeRootCertificate() async throws {
        let proxy = try getProxy()
        Self.logger.info("Calling helper removeRootCertificate")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.removeRootCertificate { success, errorMessage in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                if success {
                    Self.logger.info("Helper removed root certificate from system keychain")
                    continuation.resume()
                } else {
                    let reason = errorMessage ?? "Unknown error"
                    Self.logger.error("Helper failed to remove root certificate: \(reason)")
                    continuation.resume(throwing: HelperConnectionError.certRemoveFailed(reason))
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
    }

    /// Verify that a certificate with the given SHA-256 fingerprint is trusted in the system keychain.
    func verifyRootCertificateTrusted(fingerprint: String) async throws -> Bool {
        let proxy = try getProxy()
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.verifyRootCertificateTrusted(fingerprint) { isTrusted in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                continuation.resume(returning: isTrusted)
            }

            Task {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
    }

    /// Remove stale Rockxy Root CA certificates from the system keychain,
    /// keeping only the one matching activeFingerprint. Returns count of removed certs.
    func cleanupStaleCertificates(activeFingerprint: String) async throws -> Int {
        let proxy = try getProxy()
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.cleanupStaleCertificates(activeFingerprint) { removedCount, errorMessage in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                if let errorMessage {
                    Self.logger.warning("Stale cert cleanup warning: \(errorMessage)")
                }
                continuation.resume(returning: removedCount)
            }

            Task {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val {
                        return true
                    }
                    val = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
    }

    /// Invalidate and clear the cached XPC connection, forcing a fresh connection on next use.
    func resetConnection() {
        connection?.invalidate()
        connection = nil
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperConnection"
    )

    private static let machServiceName = RockxyIdentity.current.helperMachServiceName

    private var connection: NSXPCConnection?

    /// Evaluate the signing preflight cache and throw a typed error if the
    /// current app has a signing issue relative to the installed helper.
    private func signingPreflight() throws {
        let result = signingCache.evaluate()
        switch result {
        case let .appSignatureInvalid(detail):
            throw HelperConnectionError.appSignatureInvalid(detail)
        case let .signingIdentityMismatch(app, helper):
            throw HelperConnectionError.signingIdentityMismatch(app: app, helper: helper)
        case .healthy,
             .helperBinaryNotFound,
             .diagnosticError:
            break
        }
    }

    /// Create or reuse an NSXPCConnection to the helper's Mach service.
    private func getProxy() throws -> any RockxyHelperProtocol {
        try signingPreflight()
        let conn: NSXPCConnection
        if let existing = connection {
            conn = existing
        } else {
            conn = NSXPCConnection(machServiceName: Self.machServiceName, options: .privileged)
            conn.remoteObjectInterface = NSXPCInterface(with: RockxyHelperProtocol.self)
            conn.invalidationHandler = { [weak self] in
                Task { @MainActor in
                    Self.logger.debug("XPC connection invalidated")
                    self?.connection = nil
                }
            }
            conn.interruptionHandler = { [weak self] in
                Task { @MainActor in
                    Self.logger.warning("XPC connection interrupted")
                    self?.connection = nil
                }
            }
            conn.resume()
            connection = conn
        }

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] error in
            Self.logger.error("XPC remote object error: \(error.localizedDescription)")
            Task { @MainActor in
                self?.connection?.invalidate()
                self?.connection = nil
            }
        }) as? any RockxyHelperProtocol else {
            Self.logger.error("Failed to obtain remote object proxy")
            throw HelperConnectionError.connectionFailed
        }

        return proxy
    }
}
