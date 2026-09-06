import Foundation

// Defines the per-connection client-application identity resolution pipeline used to drive
// application-scoped SSL proxying decisions. Identity is resolved once per accepted
// connection, off the NIO event loop, when a TLS interception decision needs it.

// MARK: - ProxyConnectionDescriptor

/// Immutable snapshot of an accepted client connection, captured at accept time. Used to
/// match the connection against the OS connection table and to gate snapshot freshness.
struct ProxyConnectionDescriptor: Sendable {
    let acceptedAt: DispatchTime
    let clientHost: String?
    let clientPort: UInt16?
    let proxyHost: String?
    let proxyPort: Int
}

// MARK: - ProxyConnectionRecord

/// A single parsed local TCP connection to the proxy port, as reported by the OS
/// connection table (`lsof` in production).
struct ProxyConnectionRecord: Sendable, Equatable {
    let pid: Int32
    let command: String
    let sourceHost: String
    let sourcePort: UInt16
    let destHost: String
    let destPort: UInt16
}

// MARK: - ProxyConnectionSnapshot

/// A collected connection table plus the time collection *started*. Freshness is gated on
/// `startedAt` so a snapshot may only serve connections accepted before it began collecting.
struct ProxyConnectionSnapshot: Sendable {
    let startedAt: DispatchTime
    let proxyPort: Int
    let records: [ProxyConnectionRecord]
}

// MARK: - ClientConnectionMatcher

/// Pure directional endpoint matching against a connection table. Only a local (loopback)
/// client whose source endpoint (host + port) points at the proxy port is eligible; the
/// proxy's own reverse-accepted socket and remote devices are never matched.
enum ClientConnectionMatcher {
    /// Whether a host string denotes a local / loopback source. Remote-device traffic must
    /// never match application rules.
    static func isLocalSource(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower == "::1" || lower == "0.0.0.0" || lower == "::" {
            return true
        }
        if lower.hasPrefix("127.") {
            return true
        }
        // IPv4-mapped IPv6 loopback, e.g. ::ffff:127.0.0.1
        if lower.hasPrefix("::ffff:127.") {
            return true
        }
        return false
    }

    /// Returns the owning pid for the descriptor's connection, or nil when no unambiguous
    /// local match exists. Requires an exact source-port match, a destination on the proxy
    /// port, and a local source; excludes the proxy's own pid.
    static func matchingPID(
        records: [ProxyConnectionRecord],
        descriptor: ProxyConnectionDescriptor,
        excludePID: Int32
    )
        -> Int32?
    {
        guard let clientPort = descriptor.clientPort else {
            return nil
        }
        guard let clientHost = descriptor.clientHost, isLocalSource(clientHost) else {
            return nil
        }
        guard let proxyPort = UInt16(exactly: descriptor.proxyPort) else {
            return nil
        }

        let candidates = records.filter { record in
            record.pid != excludePID
                && record.sourcePort == clientPort
                && record.destPort == proxyPort
                && isLocalSource(record.sourceHost)
                && hostsRepresentSameEndpoint(record.sourceHost, clientHost)
        }

        // Exactly one client-side socket should own a given ephemeral source port; if the
        // table is ambiguous we decline rather than guess.
        guard candidates.count == 1 else {
            return nil
        }
        return candidates[0].pid
    }

    private static func hostsRepresentSameEndpoint(_ lhs: String, _ rhs: String) -> Bool {
        let normalizedLHS = lhs.lowercased()
        let normalizedRHS = rhs.lowercased()
        if normalizedLHS == normalizedRHS {
            return true
        }
        let loopbackAliases = ["localhost", "127.0.0.1", "::1", "::ffff:127.0.0.1"]
        return loopbackAliases.contains(normalizedLHS) && loopbackAliases.contains(normalizedRHS)
    }
}

// MARK: - ClientIdentityResolver

/// Resolves a `ClientApplicationIdentity` for an accepted connection. Connection-table
/// collection is coalesced across a burst of concurrent lookups and gated on freshness so a
/// single collection can serve many connections without re-shelling per connection. All
/// blocking work runs off the caller's executor.
final class ClientIdentityResolver: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        connectionTableProvider: @escaping @Sendable (_ proxyPort: Int, _ deadline: DispatchTime)
            -> [ProxyConnectionRecord],
        identityProvider: @escaping @Sendable (_ pid: Int32, _ command: String) -> ClientApplicationIdentity?,
        now: @escaping @Sendable () -> DispatchTime = { DispatchTime.now() },
        timeout: DispatchTimeInterval = .milliseconds(700),
        coalescingDelay: Duration = .milliseconds(10),
        excludePID: Int32
    ) {
        self.identityProvider = identityProvider
        self.excludePID = excludePID
        coordinator = SnapshotCoordinator(
            connectionTableProvider: connectionTableProvider,
            now: now,
            timeout: timeout,
            coalescingDelay: coalescingDelay
        )
    }

    // MARK: Internal

    /// Resolves the owning application identity, or nil when the source is remote, no fresh
    /// match exists, or resolution times out. Never blocks the calling executor.
    func resolveIdentity(descriptor: ProxyConnectionDescriptor) async -> ClientApplicationIdentity? {
        guard let clientHost = descriptor.clientHost, ClientConnectionMatcher.isLocalSource(clientHost) else {
            return nil
        }

        let snapshot = await coordinator.snapshot(freshAfter: descriptor.acceptedAt, proxyPort: descriptor.proxyPort)

        guard let pid = ClientConnectionMatcher.matchingPID(
            records: snapshot.records,
            descriptor: descriptor,
            excludePID: excludePID
        ) else {
            return nil
        }

        let command = snapshot.records.first { $0.pid == pid }?.command ?? ""
        return identityProvider(pid, command)
    }

    // MARK: Private

    private let identityProvider: @Sendable (_ pid: Int32, _ command: String) -> ClientApplicationIdentity?
    private let excludePID: Int32
    private let coordinator: SnapshotCoordinator
}

// MARK: - SnapshotCoordinator

/// Serializes connection-table collection and coalesces concurrent requests. A caller
/// accepted before an in-flight or committed collection began may reuse that collection.
private actor SnapshotCoordinator {
    // MARK: Lifecycle

    init(
        connectionTableProvider: @escaping @Sendable (_ proxyPort: Int, _ deadline: DispatchTime)
            -> [ProxyConnectionRecord],
        now: @escaping @Sendable () -> DispatchTime,
        timeout: DispatchTimeInterval,
        coalescingDelay: Duration
    ) {
        self.connectionTableProvider = connectionTableProvider
        self.now = now
        self.timeout = timeout
        self.coalescingDelay = coalescingDelay
    }

    // MARK: Internal

    func snapshot(freshAfter acceptedAt: DispatchTime, proxyPort: Int) async -> ProxyConnectionSnapshot {
        guard !Task.isCancelled else {
            return ProxyConnectionSnapshot(startedAt: now(), proxyPort: proxyPort, records: [])
        }
        if let latest,
           latest.proxyPort == proxyPort,
           latest.startedAt.uptimeNanoseconds > acceptedAt.uptimeNanoseconds
        {
            return latest
        }
        if let inFlight {
            let snapshot = await inFlight.task.value
            commit(snapshot, inFlightID: inFlight.id)
            guard !Task.isCancelled else {
                return ProxyConnectionSnapshot(startedAt: snapshot.startedAt, proxyPort: proxyPort, records: [])
            }
            if snapshot.proxyPort == proxyPort,
               snapshot.startedAt.uptimeNanoseconds > acceptedAt.uptimeNanoseconds
            {
                return snapshot
            }
            // The connection arrived after collection began. Serialize a follow-up
            // collection instead of spawning another blocking lsof task in parallel.
            return await self.snapshot(freshAfter: acceptedAt, proxyPort: proxyPort)
        }

        let id = UUID()
        let provider = connectionTableProvider
        let now = now
        let timeout = timeout
        let delay = coalescingDelay
        let task = Task<ProxyConnectionSnapshot, Never>.detached(priority: .utility) {
            try? await Task.sleep(for: delay)
            let started = now()
            let deadline = started + timeout
            let records = provider(proxyPort, deadline)
            return ProxyConnectionSnapshot(startedAt: started, proxyPort: proxyPort, records: records)
        }
        inFlight = InFlight(id: id, task: task)

        let snapshot = await task.value
        commit(snapshot, inFlightID: id)
        return snapshot
    }

    // MARK: Private

    private struct InFlight {
        let id: UUID
        let task: Task<ProxyConnectionSnapshot, Never>
    }

    private let connectionTableProvider: @Sendable (_ proxyPort: Int, _ deadline: DispatchTime)
        -> [ProxyConnectionRecord]
    private let now: @Sendable () -> DispatchTime
    private let timeout: DispatchTimeInterval
    private let coalescingDelay: Duration
    private var latest: ProxyConnectionSnapshot?
    private var inFlight: InFlight?

    private func commit(_ snapshot: ProxyConnectionSnapshot, inFlightID: UUID) {
        latest = snapshot
        if inFlight?.id == inFlightID {
            inFlight = nil
        }
    }
}

// MARK: - ClientIdentityHandle

/// Per-connection handle retaining the descriptor and a lazily started resolution Task. The
/// resolved identity is retained for the connection lifetime: `currentIdentity` provides a
/// non-blocking snapshot for transaction stamping, while `awaitIdentity()` bounds the TLS
/// decision. Laziness avoids running `lsof` for plain HTTP and raw tunnels whose policy cannot
/// depend on application identity.
final class ClientIdentityHandle: @unchecked Sendable {
    // MARK: Lifecycle

    init(descriptor: ProxyConnectionDescriptor, resolver: ClientIdentityResolver) {
        self.descriptor = descriptor
        self.resolver = resolver
    }

    // MARK: Internal

    let descriptor: ProxyConnectionDescriptor

    /// Non-blocking snapshot of the resolved identity (nil until resolution completes).
    var currentIdentity: ClientApplicationIdentity? {
        state.get()
    }

    /// Starts resolution once, then awaits the same bounded result for every caller.
    func awaitIdentity() async -> ClientApplicationIdentity? {
        await resolutionTask().value
    }

    // MARK: Private

    private func resolutionTask() -> Task<ClientApplicationIdentity?, Never> {
        taskLock.lock()
        defer { taskLock.unlock() }
        if let existing = task {
            return existing
        }
        let descriptor = descriptor
        let resolver = resolver
        let state = state
        let created = Task {
            let gate = IdentityResolutionGate()
            let resolverTask = Task {
                await resolver.resolveIdentity(descriptor: descriptor)
            }
            let identity = await withCheckedContinuation { continuation in
                Task {
                    let resolved = await resolverTask.value
                    _ = gate.resolve(resolved, continuation: continuation)
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(850))
                    if gate.resolve(nil, continuation: continuation) {
                        resolverTask.cancel()
                    }
                }
            }
            state.set(identity)
            return identity
        }
        task = created
        return created
    }

    private let resolver: ClientIdentityResolver
    private let state = IdentityState()
    private let taskLock = NSLock()
    private var task: Task<ClientApplicationIdentity?, Never>?
}

// MARK: - IdentityResolutionGate

/// Completes a connection's identity wait exactly once: either the resolver wins or the
/// connection-level deadline fails closed. The underlying OS lookup remains independently
/// bounded and may finish later without delaying the NIO pipeline.
private final class IdentityResolutionGate: @unchecked Sendable {
    func resolve(
        _ identity: ClientApplicationIdentity?,
        continuation: CheckedContinuation<ClientApplicationIdentity?, Never>
    ) -> Bool {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return false
        }
        isResolved = true
        lock.unlock()
        continuation.resume(returning: identity)
        return true
    }

    private let lock = NSLock()
    private var isResolved = false
}

// MARK: - IdentityState

private final class IdentityState: @unchecked Sendable {
    // MARK: Internal

    func set(_ value: ClientApplicationIdentity?) {
        lock.lock()
        stored = value
        lock.unlock()
    }

    func get() -> ClientApplicationIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    // MARK: Private

    private let lock = NSLock()
    private var stored: ClientApplicationIdentity?
}
