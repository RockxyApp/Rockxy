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
    case certInstallUnsupported
    case certRemoveFailed(String)
    case certRemovalUnsupported
    case bypassDomainsFailed(String)
    case executableRefreshUnsupported
    case executableRefreshDeferred
    case applicationMustReopen
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
        case .certInstallUnsupported:
            "The installed Rockxy helper installs certificates destructively, so it was not used. Update it in Settings > Advanced > Proxy Helper Tool."
        case let .certRemoveFailed(reason):
            "Helper failed to remove root certificate: \(reason)"
        case .certRemovalUnsupported:
            "The installed Rockxy helper does not support safe certificate removal. Update the helper in Settings > Advanced > Proxy Helper Tool, then try again."
        case let .bypassDomainsFailed(reason):
            "Helper failed to set bypass domains: \(reason)"
        case .executableRefreshUnsupported:
            "The installed helper does not support approval-preserving executable refresh"
        case .executableRefreshDeferred:
            "The helper is busy with proxy or certificate work; executable refresh was deferred"
        case .applicationMustReopen:
            "Rockxy was updated or replaced while it was open. Quit and reopen Rockxy, then check the helper again."
        case .appSignatureInvalid:
            "Rockxy could not verify this app copy. Install a fresh copy of Rockxy, then check the helper again."
        case let .signingIdentityMismatch(app, helper):
            "This app is signed by \"\(app)\" but the installed helper was signed by \"\(helper)\""
        }
    }
}

// MARK: - XPCOperationCompletion

/// Completes one XPC operation exactly once.
///
/// A single call can be answered three ways — the helper's reply, the connection's error
/// handler, and the local timeout — and more than one of them can arrive. Resuming a
/// continuation twice traps, so every path claims completion first and only the winner
/// resumes.
final class XPCOperationCompletion: @unchecked Sendable {
    // MARK: Internal

    /// Whether some path has already completed this operation.
    ///
    /// Only meaningful to a caller that reads it under the session lock, which is why the send
    /// gate lives on `XPCFailureRouter` rather than here: an unsynchronized read would decide
    /// nothing, it would only move the window in which a completed operation can still send.
    var isFinished: Bool {
        state.withLock { $0 }
    }

    /// Returns true for the first caller only.
    func claim() -> Bool {
        state.withLock { finished in
            if finished {
                return false
            }
            finished = true
            return true
        }
    }

    // MARK: Private

    private let state = OSAllocatedUnfairLock(initialState: false)
}

// MARK: - XPCFailureRouter

/// Routes an XPC delivery failure to the operation currently waiting on a proxy, and gates what
/// that operation is still allowed to send.
///
/// `remoteObjectProxyWithErrorHandler` installs one handler per proxy, but a session sends more
/// than one message through the same proxy. Without routing, a message that never reaches the
/// helper would leave its caller waiting out the full timeout. A delivered failure poisons the
/// session permanently, including in the window between the info probe and the mutation: the
/// session belongs to one removal, and a transport failure must never authorize its next phase.
///
/// The lock is the session's, not just this type's. Claiming completion and committing a send both
/// run under it, so "this operation is already over" and "send the privileged message" cannot
/// interleave. It is recursive because a reply — a test double's, or a real connection's inline
/// error report — can arrive on the sending thread while the send is still in progress.
final class XPCFailureRouter: @unchecked Sendable {
    // MARK: Internal

    /// Opens the window for one message exchange.
    ///
    /// Returns false after reporting a transport failure this session has already seen; the
    /// handler has been called and nothing may be sent.
    @discardableResult
    func begin(
        operation: XPCOperationCompletion = XPCOperationCompletion(),
        _ handler: @escaping @Sendable (any Error) -> Void
    )
        -> Bool
    {
        lock.lock()
        self.handler = handler
        current = operation
        committed = false
        let replay = pendingFailure
        lock.unlock()

        if let replay {
            handler(replay)
            return false
        }
        return true
    }

    /// Sends under the session lock, and only while this exchange may still send.
    ///
    /// Dispatch commitment is the boundary this can honestly draw. Once the message is enqueued a
    /// later failure or cancellation may still find privileged work in flight, and nothing here
    /// promises to roll that back. What it does guarantee is that an exchange whose session was
    /// poisoned — or which some path already completed — *before* this point sends nothing at all.
    func commit(_ operation: XPCOperationCompletion, _ send: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard pendingFailure == nil, !committed, current === operation, !operation.isFinished else {
            return false
        }
        committed = true
        send()
        return true
    }

    /// Claims completion for `operation`, but only while it is this session's open exchange.
    ///
    /// A reply that arrives after its exchange ended — the late half of a timeout — loses here, so
    /// it can neither resume its own continuation twice nor complete the exchange that followed it.
    func claim(_ operation: XPCOperationCompletion) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard current === operation else {
            return false
        }
        return operation.claim()
    }

    /// Closes the current exchange's window. The recorded failure is deliberately not cleared.
    func end() {
        lock.lock()
        handler = nil
        current = nil
        committed = false
        lock.unlock()
    }

    func deliver(_ error: any Error) {
        lock.lock()
        let handler = handler
        pendingFailure = pendingFailure ?? error
        lock.unlock()

        handler?(error)
    }

    // MARK: Private

    private let lock = NSRecursiveLock()
    private var handler: (@Sendable (any Error) -> Void)?
    private var pendingFailure: (any Error)?
    private var current: XPCOperationCompletion?
    private var committed = false
}

// MARK: - HelperInstallNotDispatched

/// A helper certificate installation that is known to have sent nothing to the daemon.
///
/// The distinction matters exactly once: it is the only condition under which this app may go on
/// to raise its own authorization dialog for the same material. Anything that fails *after* the
/// message was committed — a reported error, a dropped connection, the local timeout — leaves the
/// system in a state this process cannot describe, so it is reported rather than retried, and
/// never with a second prompt in the same call.
struct HelperInstallNotDispatched: LocalizedError, Sendable, Equatable {
    // MARK: Lifecycle

    init(_ reason: any Error) {
        detail = reason.localizedDescription
    }

    // MARK: Internal

    /// Why nothing was sent, in the words of whatever refused. Kept as text so this error can
    /// cross actor boundaries as freely as the failure it describes.
    let detail: String

    var errorDescription: String? {
        detail
    }
}

// MARK: - HelperCertificateSession

/// One connection dedicated to a single certificate mutation — an exact removal, or an install.
///
/// The capability probe and the mutation share it, so the helper that answered "I speak protocol 2"
/// is the helper that receives the bytes. It is deliberately not the cached general-purpose
/// connection: that one is shared with every other operation and reconnects on demand, which would
/// let a replacement helper answer the mutation after a different helper passed the probe.
final class HelperCertificateSession: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        proxy: any RockxyHelperProtocol,
        router: XPCFailureRouter = XPCFailureRouter(),
        teardown: @escaping @Sendable () -> Void
    ) {
        self.proxy = proxy
        self.router = router
        self.teardown = teardown
    }

    // MARK: Internal

    let proxy: any RockxyHelperProtocol
    let router: XPCFailureRouter

    /// Tears the connection down. Idempotent, because every exit from the wrapper — the success,
    /// each throw, and cancellation — runs it.
    func invalidate() {
        let alreadyTornDown = tornDown.withLock { done -> Bool in
            if done {
                return true
            }
            done = true
            return false
        }
        guard !alreadyTornDown else {
            return
        }
        teardown()
    }

    // MARK: Private

    private let teardown: @Sendable () -> Void
    private let tornDown = OSAllocatedUnfairLock(initialState: false)
}

// MARK: - SigningPreflightCache

/// Memoized signing diagnostic. Caches the result until explicitly invalidated.
/// Provider is injectable for tests.
@MainActor
final class SigningPreflightCache {
    // MARK: Internal

    var provider: @Sendable () -> SigningDiagnostics.Result = { SigningDiagnostics.diagnose() }

    /// Return the memoized diagnosis, running the live provider off the main actor.
    ///
    /// Concurrent callers coalesce onto a single detached diagnosis per generation. If the
    /// cache is invalidated while a diagnosis is in flight, that result is discarded and the
    /// caller retries against the current generation so a stale result can never repopulate
    /// the cache.
    func evaluate() async -> SigningDiagnostics.Result {
        while true {
            if let cached {
                return cached
            }

            let generationAtStart = generation
            let task: Task<SigningDiagnostics.Result, Never>
            if let inFlightTask, inFlightGeneration == generationAtStart {
                task = inFlightTask
            } else {
                let provider = provider
                let newTask = Task.detached(priority: .userInitiated) { provider() }
                inFlightTask = newTask
                inFlightGeneration = generationAtStart
                task = newTask
            }

            let result = await task.value

            guard generation == generationAtStart else {
                // Invalidated while this diagnosis was in flight — discard the stale
                // generation and retry against the current one.
                continue
            }

            cached = result
            if inFlightGeneration == generationAtStart {
                inFlightTask = nil
                inFlightGeneration = nil
            }
            return result
        }
    }

    func invalidate() {
        cached = nil
        generation += 1
        inFlightTask = nil
        inFlightGeneration = nil
    }

    // MARK: Private

    private var cached: SigningDiagnostics.Result?
    private var generation = 0
    private var inFlightTask: Task<SigningDiagnostics.Result, Never>?
    private var inFlightGeneration: Int?
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

    // How long each phase of a dedicated certificate mutation may wait.
    //
    // The helper's privileged work runs a bounded `security` command — five seconds plus its
    // termination budget — with keychain reads and a verification pass around it. The request
    // timeout leaves room for surrounding work. Security framework calls may still stall
    // independently, so a timeout never promises that an enqueued mutation was rolled back.
    // Both are mutable in DEBUG only, so a test can drive a timeout without waiting one out.
    #if DEBUG
    /// Test seam: supplies the session one certificate mutation runs on, so the real wrapper —
    /// its probe, its capability gate, its cancellation check, and its send gate — can be
    /// exercised against a fake helper instead of a privileged one. Per instance; never set on
    /// `shared`.
    var certificateSessionProvider: (@MainActor () throws -> HelperCertificateSession)?

    var certificateProbeTimeout: Duration = .seconds(3)
    var certificateRequestTimeout: Duration = .seconds(15)
    #else
    let certificateProbeTimeout: Duration = .seconds(3)
    let certificateRequestTimeout: Duration = .seconds(15)
    #endif

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
        let proxy = try await getProxy()
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
        let proxy = try await getProxy()
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
        let proxy = try await getProxy()
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
        let proxy = try await getProxy()
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
        let proxy = try await getProxy()
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

    /// Ask a protocol-3 helper to exit without unregistering its approved SMAppService job.
    /// The manager reconnects afterward, causing launchd to start the helper embedded in the
    /// current app bundle.
    func refreshHelperExecutable() async throws {
        let proxy = try await getProxy()
        let info = try await helperInfo(using: proxy)
        guard HelperCompatibilityPolicy.supportsExecutableRefresh(
            protocolVersion: info.protocolVersion
        ) else {
            throw HelperConnectionError.executableRefreshUnsupported
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            proxy.prepareForExecutableRefresh { success in
                let alreadyResumed = resumed.withLock { value -> Bool in
                    if value {
                        return true
                    }
                    value = true
                    return false
                }
                guard !alreadyResumed else {
                    return
                }
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperConnectionError.executableRefreshDeferred)
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                let alreadyResumed = resumed.withLock { value -> Bool in
                    if value {
                        return true
                    }
                    value = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
        resetConnection()
        signingCache.invalidate()
    }

    private func helperInfo(using proxy: any RockxyHelperProtocol) async throws -> HelperInfo {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HelperInfo, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            proxy.getHelperInfo { version, build, protocolVersion in
                let alreadyResumed = resumed.withLock { value -> Bool in
                    if value {
                        return true
                    }
                    value = true
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
                let alreadyResumed = resumed.withLock { value -> Bool in
                    if value {
                        return true
                    }
                    value = true
                    return false
                }
                if !alreadyResumed {
                    continuation.resume(throwing: HelperConnectionError.xpcTimeout)
                }
            }
        }
    }

    /// Set the system proxy bypass domain list via the helper tool.
    func setBypassDomains(_ domains: [String]) async throws {
        let proxy = try await getProxy()
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

    /// Install exactly this root CA certificate in the System keychain and record admin trust for
    /// it, over a session dedicated to this call.
    ///
    /// The probe and the mutation share one connection, so the helper that answered "I speak
    /// protocol 2" is the helper that receives the bytes. The capability question is not academic:
    /// a protocol 1 helper implements this same selector but sweeps every certificate carrying the
    /// root CA label before adding the new one, destroying a root the user may still be relying on.
    /// A build number cannot answer it either — shipped copies embed a protocol 1 helper at or
    /// above this checkout's build.
    ///
    /// Everything that can refuse before the message is committed throws
    /// `HelperInstallNotDispatched`, which is the caller's only licence to install app-side
    /// instead. After the commit the outcome is genuinely unknown, so the failure is reported as
    /// itself and nothing here claims a rollback.
    func installRootCertificate(derData: Data) async throws {
        let session: HelperCertificateSession
        do {
            session = try await certificateSession()
        } catch {
            throw HelperInstallNotDispatched(error)
        }
        // Every exit tears the connection down: the success, each throw, and cancellation.
        defer { session.invalidate() }

        let info: HelperInfo
        do {
            info = try await helperInfo(over: session)
        } catch {
            throw HelperInstallNotDispatched(error)
        }
        guard HelperCompatibilityPolicy.supportsSafeCertificateInstall(
            protocolVersion: info.protocolVersion
        ) else {
            Self.logger.error(
                "Installed helper speaks protocol \(info.protocolVersion) — non-destructive install is unavailable"
            )
            throw HelperInstallNotDispatched(HelperConnectionError.certInstallUnsupported)
        }

        // The last opportunity to stop before privileged, irreversible work.
        try Task.checkCancellation()

        let timeout = certificateRequestTimeout
        Self.logger.info("Calling helper installRootCertificate (\(derData.count) bytes)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = XPCOperationCompletion()
            let router = session.router
            // Set inside the send gate, before the message goes out, so a transport failure
            // reported from within the send itself is already classified as dispatched.
            let dispatched = OSAllocatedUnfairLock(initialState: false)

            @Sendable
            func finish(_ result: Result<Void, any Error>) {
                guard router.claim(operation) else {
                    return
                }
                router.end()
                continuation.resume(with: result)
            }

            /// A dropped connection before the send means nothing was applied; after it, the
            /// helper may have applied the request and lost the reply.
            @Sendable
            func transportFailure(_ error: any Error) -> any Error {
                let failure = HelperConnectionError.certInstallFailed(error.localizedDescription)
                return dispatched.withLock { $0 } ? failure : HelperInstallNotDispatched(failure)
            }

            guard router.begin(operation: operation, { error in
                finish(.failure(transportFailure(error)))
            }) else {
                return
            }

            let sent = router.commit(operation) {
                dispatched.withLock { $0 = true }
                session.proxy.installRootCertificate(derData) { success, errorMessage in
                    if success {
                        Self.logger.info("Helper installed root certificate in system keychain")
                        finish(.success(()))
                    } else {
                        let reason = errorMessage ?? "Unknown error"
                        Self.logger.error("Helper failed to install root certificate: \(reason)")
                        finish(.failure(HelperConnectionError.certInstallFailed(reason)))
                    }
                }
            }
            guard sent else {
                // The session was poisoned, or the operation completed, between opening this
                // exchange and the send. Either way nothing reached the helper, so the caller may
                // still install app-side.
                Self.logger.error("Install request was not sent: the dedicated helper session ended first")
                finish(.failure(HelperInstallNotDispatched(HelperConnectionError.certInstallFailed(
                    "the helper connection ended before the request was sent"
                ))))
                return
            }

            Task {
                try? await Task.sleep(for: timeout)
                // Committed before the timer fired, so the helper may still be applying this
                // request. The app stopped waiting; it did not undo anything.
                finish(.failure(HelperConnectionError.xpcTimeout))
            }
        }
    }

    /// Remove exactly the root CA certificate whose DER bytes are supplied, together with its
    /// admin trust settings, from the system keychain.
    ///
    /// The capability probe and the mutation run over one proxy on one connection of this call's
    /// own, so the helper that answered "I speak protocol 2" is the helper that receives the
    /// bytes. A cached `HelperManager.installedInfo` cannot stand in for that probe — it may
    /// describe a helper that has since been replaced — and a build number never implied this
    /// selector at all: shipped app copies embed a helper at this build that still speaks
    /// protocol 1.
    func removeRootCertificate(matching derData: Data) async throws {
        let session = try await certificateSession()
        // Every exit tears the connection down: the success, each throw, and cancellation.
        defer { session.invalidate() }

        let info = try await helperInfo(over: session)
        guard HelperCompatibilityPolicy.supportsExactCertificateRemoval(
            protocolVersion: info.protocolVersion
        ) else {
            Self.logger.error(
                "Installed helper speaks protocol \(info.protocolVersion) — exact certificate removal is unavailable"
            )
            throw HelperConnectionError.certRemovalUnsupported
        }

        // The last opportunity to stop before privileged, irreversible work.
        try Task.checkCancellation()

        let timeout = certificateRequestTimeout
        Self.logger.info("Calling helper removeRootCertificateMatching (\(derData.count) bytes)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = XPCOperationCompletion()
            let router = session.router

            @Sendable
            func finish(_ result: Result<Void, any Error>) {
                guard router.claim(operation) else {
                    return
                }
                router.end()
                continuation.resume(with: result)
            }

            guard router.begin(operation: operation, { error in
                finish(.failure(HelperConnectionError.certRemoveFailed(error.localizedDescription)))
            }) else {
                return
            }

            let sent = router.commit(operation) {
                session.proxy.removeRootCertificateMatching(derData) { success, errorMessage in
                    if success {
                        Self.logger.info("Helper removed the requested root certificate from the system keychain")
                        finish(.success(()))
                    } else {
                        let reason = errorMessage ?? "Unknown error"
                        Self.logger.error("Helper failed to remove root certificate: \(reason)")
                        finish(.failure(HelperConnectionError.certRemoveFailed(reason)))
                    }
                }
            }
            guard sent else {
                // The session was poisoned, or the operation completed, between opening this
                // exchange and the send. Either way nothing reached the helper. A failure that
                // arrived through the router has already completed the continuation, so this is
                // the remaining case rather than a second answer.
                Self.logger.error("Removal request was not sent: the dedicated helper session ended first")
                finish(.failure(HelperConnectionError.certRemoveFailed(
                    "the helper connection ended before the request was sent"
                )))
                return
            }

            Task {
                try? await Task.sleep(for: timeout)
                finish(.failure(HelperConnectionError.xpcTimeout))
            }
        }
    }

    /// Verify that a certificate with the given SHA-256 fingerprint is trusted in the system keychain.
    func verifyRootCertificateTrusted(fingerprint: String) async throws -> Bool {
        let proxy = try await getProxy()
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
        let proxy = try await getProxy()
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

    /// A connection created for one certificate mutation and torn down when that call returns.
    ///
    /// Its interruption and invalidation handlers poison the session's router rather than clearing
    /// the cached general-purpose connection, so this call cannot silently reconnect to a
    /// replacement helper between the probe and the mutation, and the cached connection's own
    /// identity-scoped handlers are left alone.
    private func certificateSession() async throws -> HelperCertificateSession {
        #if DEBUG
        if let certificateSessionProvider {
            return try certificateSessionProvider()
        }
        #endif

        try await signingPreflight()

        let router = XPCFailureRouter()
        let conn = NSXPCConnection(machServiceName: Self.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: RockxyHelperProtocol.self)
        conn.invalidationHandler = {
            // Also fires for this call's own teardown, which is why it only poisons a session
            // that is by then finished with.
            Self.logger.debug("Dedicated certificate connection invalidated")
            router.deliver(HelperConnectionError.connectionFailed)
        }
        conn.interruptionHandler = { [weak conn] in
            Self.logger.warning("Dedicated certificate connection interrupted")
            router.deliver(HelperConnectionError.connectionFailed)
            // Do not let this one-operation connection automatically reconnect after its probe.
            conn?.invalidate()
        }
        conn.resume()

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak conn] error in
            Self.logger.error("Dedicated certificate proxy error: \(error.localizedDescription)")
            router.deliver(error)
            conn?.invalidate()
        }) as? any RockxyHelperProtocol else {
            Self.logger.error("Failed to obtain a dedicated certificate proxy")
            conn.invalidate()
            throw HelperConnectionError.connectionFailed
        }

        return HelperCertificateSession(proxy: proxy, router: router) { conn.invalidate() }
    }

    /// Reads the connected helper's info over an existing session, so a capability decision
    /// and the operation it authorizes address the same helper.
    private func helperInfo(over session: HelperCertificateSession) async throws -> HelperInfo {
        let timeout = certificateProbeTimeout
        return try await withCheckedThrowingContinuation { continuation in
            let operation = XPCOperationCompletion()
            let router = session.router

            @Sendable
            func finish(_ result: Result<HelperInfo, any Error>) {
                guard router.claim(operation) else {
                    return
                }
                router.end()
                continuation.resume(with: result)
            }

            guard router.begin(operation: operation, { _ in
                finish(.failure(HelperConnectionError.connectionFailed))
            }) else {
                return
            }

            let sent = router.commit(operation) {
                session.proxy.getHelperInfo { version, build, protocolVersion in
                    finish(.success(HelperInfo(
                        binaryVersion: version,
                        buildNumber: build,
                        protocolVersion: protocolVersion
                    )))
                }
            }
            guard sent else {
                finish(.failure(HelperConnectionError.connectionFailed))
                return
            }

            Task {
                try? await Task.sleep(for: timeout)
                finish(.failure(HelperConnectionError.xpcTimeout))
            }
        }
    }

    /// Evaluate the signing preflight cache and throw a typed error if the
    /// current app has a signing issue relative to the installed helper.
    private func signingPreflight() async throws {
        let result = await signingCache.evaluate()
        switch result {
        case .runningCodeChanged:
            throw HelperConnectionError.applicationMustReopen
        case let .appSignatureInvalid(detail):
            throw HelperConnectionError.appSignatureInvalid(detail)
        case let .signingIdentityMismatch(app, helper):
            throw HelperConnectionError.signingIdentityMismatch(app: app, helper: helper)
        case .healthy,
             .helperBinaryNotFound,
             .certificateChainUnavailable,
             .diagnosticError:
            break
        }
    }

    /// Create or reuse an NSXPCConnection to the helper's Mach service, after the signing
    /// preflight has cleared this app copy.
    private func activeConnection() async throws -> NSXPCConnection {
        try await signingPreflight()
        if let existing = connection {
            return existing
        }

        let conn = NSXPCConnection(machServiceName: Self.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: RockxyHelperProtocol.self)
        conn.invalidationHandler = { [weak self, weak conn] in
            Task { @MainActor in
                Self.logger.debug("XPC connection invalidated")
                if self?.connection === conn {
                    self?.connection = nil
                }
            }
        }
        conn.interruptionHandler = { [weak self, weak conn] in
            Task { @MainActor in
                Self.logger.warning("XPC connection interrupted")
                if self?.connection === conn {
                    self?.connection = nil
                }
            }
        }
        conn.resume()
        connection = conn
        return conn
    }

    /// A proxy for a single operation whose XPC failures are logged but not routed back to the
    /// caller; the operation's own timeout ends the wait.
    private func getProxy() async throws -> any RockxyHelperProtocol {
        let conn = try await activeConnection()

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self, weak conn] error in
            Self.logger.error("XPC remote object error: \(error.localizedDescription)")
            Task { @MainActor in
                conn?.invalidate()
                if self?.connection === conn {
                    self?.connection = nil
                }
            }
        }) as? any RockxyHelperProtocol else {
            Self.logger.error("Failed to obtain remote object proxy")
            throw HelperConnectionError.connectionFailed
        }

        return proxy
    }
}
