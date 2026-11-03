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
    // MARK: Internal

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

    // MARK: Private

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
            let records = await Self.collect(using: provider, proxyPort: proxyPort, deadline: deadline)
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

    /// Collection shells out and blocks until the child exits or its deadline passes. Run
    /// directly from an async task that would park one of the cooperative pool's few threads
    /// for the whole bounded wait, once per connection burst, stalling every unrelated async
    /// task in the app. A dedicated queue keeps the block off that pool; it can be serial
    /// because the coordinator already allows only one collection in flight.
    private static let collectionQueue = DispatchQueue(
        label: "rockxy.client-identity.connection-table",
        qos: .utility
    )

    private let connectionTableProvider: @Sendable (_ proxyPort: Int, _ deadline: DispatchTime)
        -> [ProxyConnectionRecord]
    private let now: @Sendable () -> DispatchTime
    private let timeout: DispatchTimeInterval
    private let coalescingDelay: Duration
    private var latest: ProxyConnectionSnapshot?
    private var inFlight: InFlight?

    private static func collect(
        using provider: @escaping @Sendable (_ proxyPort: Int, _ deadline: DispatchTime)
            -> [ProxyConnectionRecord],
        proxyPort: Int,
        deadline: DispatchTime
    )
        async -> [ProxyConnectionRecord]
    {
        await withCheckedContinuation { continuation in
            collectionQueue.async {
                continuation.resume(returning: provider(proxyPort, deadline))
            }
        }
    }

    private func commit(_ snapshot: ProxyConnectionSnapshot, inFlightID: UUID) {
        latest = snapshot
        if inFlight?.id == inFlightID {
            inFlight = nil
        }
    }
}

// MARK: - ClientIdentityHandle

/// Per-connection handle retaining the descriptor and a single shared resolution Task. The
/// resolved identity is retained for the connection lifetime: `currentIdentity` provides a
/// non-blocking snapshot for transaction stamping, while `awaitIdentity()` bounds the TLS
/// decision. The proxy starts resolution at accept time so short-lived sockets remain observable;
/// later policy and stamping reads reuse that work without launching another OS lookup.
///
/// Lifetime. Everything the handle starts stays reachable and cancellable. Resolution is one
/// stored Task, and the connection deadline is a cancellable sibling of each bounded wait
/// rather than a Task of its own. The previous shape left an 850 ms sleeper per accepted
/// connection that expired even when the resolver had already won, plus an awaiter and a
/// late-identity Task nothing held a reference to; a capture running for hours therefore kept
/// a standing population of Tasks whose only remaining purpose was to expire. `cancel()` now
/// reclaims the work as soon as the client channel closes.
final class ClientIdentityHandle: @unchecked Sendable {
    // MARK: Lifecycle

    /// - Parameter decisionDeadline: how long `awaitIdentity()` waits before failing the TLS
    ///   decision closed. The OS lookup keeps its own independent bound and is deliberately
    ///   left running past this deadline so a late result can still be stamped onto the
    ///   connection's rows.
    init(
        descriptor: ProxyConnectionDescriptor,
        resolver: ClientIdentityResolver,
        decisionDeadline: Duration = .milliseconds(850)
    ) {
        self.descriptor = descriptor
        self.resolver = resolver
        self.decisionDeadline = decisionDeadline
    }

    // MARK: Internal

    let descriptor: ProxyConnectionDescriptor

    /// Non-blocking snapshot of the resolved identity (nil until resolution completes).
    var currentIdentity: ClientApplicationIdentity? {
        state.get()
    }

    /// Starts resolution without waiting for it. The proxy calls this as soon as a local
    /// connection is accepted so short-lived raw tunnels can still be attributed after their
    /// client socket disappears from the OS connection table.
    func startResolution() {
        _ = resolutionTask()
    }

    /// Starts resolution once, then waits for it until the connection deadline fails the
    /// decision closed. Both sides of that race are cancellable and structured, so the loser
    /// stops as soon as the winner is known and this call returns only once it has.
    func awaitIdentity() async -> ClientApplicationIdentity? {
        _ = resolutionTask()
        let gate = gate
        let deadline = decisionDeadline
        return await withTaskGroup(
            of: ClientApplicationIdentity?.self,
            returning: ClientApplicationIdentity?.self
        ) { group in
            group.addTask {
                await gate.awaitIdentity()
            }
            group.addTask {
                // Fails the decision closed. `cancelAll()` below wakes this sleep the moment
                // the lookup wins, instead of leaving it to run out its full deadline.
                try? await Task.sleep(for: deadline)
                return nil
            }
            let outcome = await group.next() ?? nil
            group.cancelAll()
            return outcome
        }
    }

    /// Stops the connection's identity work and releases every parked wait. The proxy calls
    /// this from the client channel's close, where the client socket the lookup matches
    /// against is already gone, so nothing is left to resolve or to stamp.
    func cancel() {
        taskLock.lock()
        let pending = task
        taskLock.unlock()
        pending?.cancel()
        // Resolve the gate as well: a cancelled lookup may still be coalesced behind an
        // in-flight connection-table collection, and no caller on a closed channel should
        // wait for that to land.
        gate.resolve(nil)
    }

    // MARK: Private

    private let resolver: ClientIdentityResolver
    private let decisionDeadline: Duration
    private let state = IdentityState()
    private let gate = IdentityResolutionGate()
    private let taskLock = NSLock()
    private var task: Task<ClientApplicationIdentity?, Never>?

    private func resolutionTask() -> Task<ClientApplicationIdentity?, Never> {
        taskLock.lock()
        defer { taskLock.unlock() }
        if let existing = task {
            return existing
        }
        let descriptor = descriptor
        let resolver = resolver
        let state = state
        let gate = gate
        // The only Task the handle owns, and the only work that outlives a bounded wait. The
        // lookup is still worth finishing after the deadline failed the decision closed,
        // because a short-lived raw tunnel resolved late still needs its rows attributed; the
        // separate late-identity Task that used to do that is folded in here, where it is
        // reachable by `cancel()`.
        let created = Task {
            let identity = await resolver.resolveIdentity(descriptor: descriptor)
            state.set(identity)
            gate.resolve(identity)
            return identity
        }
        task = created
        return created
    }
}

// MARK: - IdentityResolutionGate

/// Publishes a connection's resolution outcome to every bounded waiter exactly once. Waiters
/// park here instead of awaiting the resolution Task directly, because abandoning a wait must
/// not abandon the lookup: the deadline fails the TLS decision closed while the OS lookup
/// keeps running for late stamping. A parked wait is also abandonable, so the losing side of
/// the deadline race and a wait on a closed connection both stop immediately.
private final class IdentityResolutionGate: @unchecked Sendable {
    // MARK: Internal

    /// Resolves the gate once and wakes every parked waiter. Later calls are ignored, so a
    /// lookup that lands after the connection was cancelled cannot replace the outcome a
    /// caller already acted on.
    func resolve(_ identity: ClientApplicationIdentity?) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        resolvedIdentity = identity
        let parked = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()
        for continuation in parked {
            continuation.resume(returning: identity)
        }
    }

    /// Parks until the gate resolves or the calling task is cancelled, whichever comes first.
    func awaitIdentity() async -> ClientApplicationIdentity? {
        let waitID = UUID()
        let identity = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                guard !isResolved else {
                    let identity = resolvedIdentity
                    lock.unlock()
                    continuation.resume(returning: identity)
                    return
                }
                // The cancellation handler runs before this continuation exists when the task
                // was already cancelled on entry. It records the wait instead of resuming it,
                // and consuming that record here is what keeps a wait from parking unresumed.
                guard cancelledWaitIDs.remove(waitID) == nil else {
                    lock.unlock()
                    continuation.resume(returning: nil)
                    return
                }
                waiters[waitID] = continuation
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            guard let continuation = waiters.removeValue(forKey: waitID) else {
                cancelledWaitIDs.insert(waitID)
                lock.unlock()
                return
            }
            lock.unlock()
            continuation.resume(returning: nil)
        }
        // The handler above can record a cancellation that the resumed wait no longer needs.
        // Dropping it here is what stops the gate growing one entry per cancelled wait for as
        // long as the connection lives.
        discardWait(waitID)
        return identity
    }

    // MARK: Private

    private let lock = NSLock()
    private var waiters: [UUID: CheckedContinuation<ClientApplicationIdentity?, Never>] = [:]
    private var cancelledWaitIDs: Set<UUID> = []
    private var isResolved = false
    private var resolvedIdentity: ClientApplicationIdentity?

    private func discardWait(_ waitID: UUID) {
        lock.lock()
        waiters.removeValue(forKey: waitID)
        cancelledWaitIDs.remove(waitID)
        lock.unlock()
    }
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
