import Foundation
import NIOCore
import os

private let liveTunnelLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "LiveTunnelRegistry"
)

// MARK: - LiveTunnelRegistry

/// Typed lifecycle seam that tracks live *raw* CONNECT tunnels (host + client application +
/// tunnel reason) so an SSL-proxying policy change can close exactly the tunnels the *current*
/// effective policy would now intercept. Closing a matched tunnel forces the client's next request to open a
/// fresh CONNECT that enters TLS interception, without restarting the proxy or disturbing
/// bypassed / auto-passthrough hosts or connections that are already being intercepted
/// (those are never registered here).
///
/// Race handling. A tunnel's raw classification is computed from SSL policy that may mutate
/// concurrently. Each handler captures `currentGeneration()` *before* it reads policy; the
/// registry bumps the generation on every policy change. At registration time the registry
/// re-checks: if a mutation landed after the captured generation and the current effective
/// policy now requires interception, the raw classification is stale and the channel is
/// closed immediately instead of tracked. Combined with the sweep in
/// `invalidateTunnelsNowRequiringInterception()`, no raw tunnel whose decision overlapped a
/// mutation can escape invalidation:
///   • registered before the sweep's snapshot → closed by the sweep, or
///   • registered after the mutation bumped the generation → closed by the register re-check.
final class LiveTunnelRegistry: @unchecked Sendable {
    // MARK: Lifecycle

    /// - Parameter shouldInterceptNow: predicate returning `true` when the current effective
    ///   policy would intercept `host` for the tunnel's resolved client application (typically
    ///   `initialTunnelMode(...) == .intercept`).
    ///   Injected so the registry stays testable and free of a hard dependency on the shared
    ///   managers.
    init(
        shouldInterceptNow: @escaping @Sendable (String, ClientApplicationIdentity?) -> Bool,
        shouldResolveApplicationNow: @escaping @Sendable () -> Bool = { false },
        resolveApplication: (@Sendable (ProxyConnectionDescriptor) async -> ClientApplicationIdentity?)? = nil
    ) {
        self.shouldInterceptNow = { host, application, _ in
            shouldInterceptNow(host, application)
        }
        self.shouldResolveApplicationNow = shouldResolveApplicationNow
        self.resolveApplication = resolveApplication
    }

    /// Connection-aware policy variant used by production. The descriptor distinguishes an
    /// unresolved local application (which must fail closed when Tunnel rules exist) from a
    /// remote client whose TLS recovery scope is its privacy-preserving network identity.
    init(
        shouldInterceptConnectionNow: @escaping @Sendable (
            String,
            ClientApplicationIdentity?,
            ProxyConnectionDescriptor?
        ) -> Bool,
        shouldResolveApplicationNow: @escaping @Sendable () -> Bool = { false },
        resolveApplication: (@Sendable (ProxyConnectionDescriptor) async -> ClientApplicationIdentity?)? = nil
    ) {
        shouldInterceptNow = shouldInterceptConnectionNow
        self.shouldResolveApplicationNow = shouldResolveApplicationNow
        self.resolveApplication = resolveApplication
    }

    // MARK: Internal

    /// Snapshot of the policy generation, captured by a handler *before* it classifies a
    /// tunnel from SSL policy. Passed back into `registerRawTunnel` so a mutation racing that
    /// classification is detectable at registration time.
    func currentGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// Registers a live raw tunnel keyed by its client channel. If a policy mutation occurred
    /// after `decisionGeneration` was captured, the current effective policy is re-evaluated.
    /// An unresolved application is resolved first when application rules could override the
    /// host decision; otherwise a newly-interceptable channel is closed immediately.
    func registerRawTunnel(
        channel: Channel,
        host: String,
        application: ClientApplicationIdentity? = nil,
        connectionDescriptor: ProxyConnectionDescriptor? = nil,
        reason: TLSInterceptHandler.RawTunnelReason,
        decisionGeneration: UInt64
    ) {
        let identifier = ObjectIdentifier(channel)
        lock.lock()
        let raced = decisionGeneration != generation
        tunnels[identifier] = Entry(
            channel: channel,
            host: host,
            application: application,
            connectionDescriptor: connectionDescriptor,
            reason: reason
        )
        lock.unlock()

        channel.closeFuture.whenComplete { [weak self] _ in
            self?.remove(identifier)
        }

        // Only a policy race makes this registration stale. Resolving every non-raced raw tunnel
        // would re-run the same lookup that just hit the connection deadline and could close the
        // channel into an unbounded reconnect loop. Later policy mutations use the invalidation
        // sweep below, where resolution is required to respect application Tunnel precedence.
        if raced,
           application == nil,
           connectionDescriptor != nil,
           resolveApplicationIfNeeded(for: identifier)
        {
            return
        }

        if raced, shouldInterceptNow(host, application, connectionDescriptor) {
            liveTunnelLogger.info(
                "Closing raced raw tunnel for \(host, privacy: .public) — policy now requires interception"
            )
            channel.close(promise: nil)
        }
    }

    /// Invoked when SSL-proxying policy changes. Bumps the generation and closes every tracked
    /// raw tunnel whose host the current effective policy would now intercept. Unrelated hosts,
    /// bypassed hosts, and still-auto-passthrough hosts are left untouched.
    func invalidateTunnelsNowRequiringInterception() {
        lock.lock()
        generation &+= 1
        let snapshot = Array(tunnels)
        lock.unlock()

        // Partition tracked tunnels into those whose close decision must wait for identity
        // resolution and those safe to evaluate immediately. A tunnel with no resolved identity
        // but a resolvable descriptor may belong to an application whose Tunnel rule outranks a
        // host Decrypt, so a host-only decision must not close it until resolution completes.
        var toClose: [Entry] = []

        for (identifier, entry) in snapshot {
            if entry.application == nil,
               entry.connectionDescriptor != nil,
               resolveApplicationIfNeeded(for: identifier)
            {
                continue
            }
            // Resolution may have completed between the snapshot and the attempt above. Read the
            // current entry so an application Tunnel identity cannot be lost to a stale nil.
            guard let currentEntry = currentEntry(for: identifier) else {
                continue
            }
            if shouldInterceptNow(
                currentEntry.host,
                currentEntry.application,
                currentEntry.connectionDescriptor
            ) {
                toClose.append(currentEntry)
            }
        }

        if !toClose.isEmpty {
            liveTunnelLogger.info("Resetting \(toClose.count) live raw tunnel(s) after SSL policy change")
            for entry in toClose {
                entry.channel.close(promise: nil)
            }
        }
    }

    /// Number of currently tracked tunnels. Test/diagnostics hook.
    func trackedTunnelCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return tunnels.count
    }

    // MARK: Private

    private struct Entry {
        let channel: Channel
        let host: String
        var application: ClientApplicationIdentity?
        let connectionDescriptor: ProxyConnectionDescriptor?
        let reason: TLSInterceptHandler.RawTunnelReason
    }

    private let lock = NSLock()
    private let shouldInterceptNow: @Sendable (
        String,
        ClientApplicationIdentity?,
        ProxyConnectionDescriptor?
    ) -> Bool
    private let shouldResolveApplicationNow: @Sendable () -> Bool
    private let resolveApplication: (@Sendable (ProxyConnectionDescriptor) async -> ClientApplicationIdentity?)?
    private var tunnels: [ObjectIdentifier: Entry] = [:]
    private var resolvingApplications: Set<ObjectIdentifier> = []
    private var generation: UInt64 = 0

    private func remove(_ identifier: ObjectIdentifier) {
        lock.lock()
        tunnels.removeValue(forKey: identifier)
        resolvingApplications.remove(identifier)
        lock.unlock()
    }

    private func currentEntry(for identifier: ObjectIdentifier) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return tunnels[identifier]
    }

    /// Resolves identity only after an SSL-policy mutation needs it. Host-only capture therefore
    /// keeps its fast path, while adding the first application rule can still distinguish and
    /// reset a pre-existing Chrome tunnel without touching Safari's tunnel to the same host.
    /// Returns `true` only when resolution was started or is already in flight. Callers use a
    /// `false` result to fall back to an immediate policy decision, so a missing resolver or an
    /// application-rule mutation racing this method can never strand an interceptable tunnel.
    private func resolveApplicationIfNeeded(for identifier: ObjectIdentifier) -> Bool {
        guard shouldResolveApplicationNow(), let resolver = resolveApplication else {
            return false
        }

        lock.lock()
        guard let entry = tunnels[identifier], entry.application == nil,
              let descriptor = entry.connectionDescriptor else {
            lock.unlock()
            return false
        }
        if resolvingApplications.contains(identifier) {
            lock.unlock()
            return true
        }
        resolvingApplications.insert(identifier)
        lock.unlock()

        Task { [weak self] in
            let application = await resolver(descriptor)
            guard let self else {
                return
            }
            guard let currentEntry = self.finishApplicationResolution(
                identifier: identifier,
                application: application
            ) else {
                return
            }

            // Re-evaluate the latest effective policy with the resolved identity. A resolved
            // application Tunnel rule preserves the channel; another application or a nil identity
            // still closes it when the current host policy requires interception.
            guard self.shouldInterceptNow(
                currentEntry.host,
                application,
                currentEntry.connectionDescriptor
            ) else {
                return
            }
            liveTunnelLogger.info(
                "Resetting resolved application tunnel for \(currentEntry.host, privacy: .public) after SSL policy change"
            )
            currentEntry.channel.close(promise: nil)
        }
        return true
    }

    /// Synchronous lock boundary kept outside the async task so the code remains valid under
    /// Swift 6's prohibition on directly locking from an asynchronous context.
    private func finishApplicationResolution(
        identifier: ObjectIdentifier,
        application: ClientApplicationIdentity?
    ) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        resolvingApplications.remove(identifier)
        guard var entry = tunnels[identifier] else {
            return nil
        }
        entry.application = application
        tunnels[identifier] = entry
        return entry
    }
}
