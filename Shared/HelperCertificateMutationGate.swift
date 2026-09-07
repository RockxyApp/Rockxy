import Foundation

// MARK: - HelperPrivilegedMutationGate

/// Process-wide exclusive gate for privileged helper mutations and executable refresh.
///
/// NSXPCConnection delivers messages concurrently, so two clients — or one client retrying after
/// a timeout — can have keychain, trust, or system-proxy mutations in flight at the same time.
/// Certificate operations are read-mutate-verify sequences; proxy mutations carry crash-recovery
/// ownership. Interleaving either class with helper exit can leave partial state behind.
///
/// The gate is deliberately **non-blocking**. A busy request is refused immediately, before it
/// mutates anything, so nothing is queued to run later against state the caller can no longer
/// see: a client that gave up at its own timeout must not have privileged work start afterwards.
/// Reads are never gated — reporting "not installed" because another operation held the gate
/// would be a wrong answer, not a busy one.
final class HelperPrivilegedMutationGate: @unchecked Sendable {
    // MARK: Internal

    /// Proof of ownership for one mutation.
    ///
    /// `release` acts only when the ticket matches the mutation currently held, so a duplicate or
    /// stale release can never end a later owner's turn.
    struct Ticket: Equatable {
        fileprivate let id: UUID
    }

    /// One gate per helper process. Every privileged mutating entry point shares it.
    static let shared = HelperPrivilegedMutationGate()

    /// What a refused caller is told. Phrased so it reads as "try again", never as a result.
    static let busyMessage =
        "Another Rockxy privileged operation is already running. Wait for it to finish, then try again."

    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return heldTicketID != nil
    }

    /// Takes the gate, or returns `nil` when another mutation already owns it. Never waits.
    func tryAcquire() -> Ticket? {
        lock.lock()
        defer { lock.unlock() }

        guard heldTicketID == nil else {
            return nil
        }
        let ticket = Ticket(id: UUID())
        heldTicketID = ticket.id
        return ticket
    }

    /// Acquires the mutation gate for an intentional executable refresh. The caller normally
    /// retains the ticket until process exit; it may release the ticket only when a final proxy
    /// recheck cancels that exit.
    func beginProcessExitBarrier() -> Ticket? {
        lock.lock()
        defer { lock.unlock() }

        guard heldTicketID == nil else {
            return nil
        }
        let ticket = Ticket(id: UUID())
        heldTicketID = ticket.id
        return ticket
    }

    func release(_ ticket: Ticket) {
        lock.lock()
        defer { lock.unlock() }

        guard heldTicketID == ticket.id else {
            return
        }
        heldTicketID = nil
    }

    /// Runs `body` under the gate, or returns `nil` without running it when the gate is busy.
    ///
    /// The gate is released before the caller replies, so an XPC reply handler that starts the
    /// next operation cannot be refused by the operation that just finished.
    func withExclusiveAccess<T>(_ body: () throws -> T) rethrows -> T? {
        guard let ticket = tryAcquire() else {
            return nil
        }
        defer { release(ticket) }
        return try body()
    }

    // MARK: Private

    private let lock = NSLock()
    private var heldTicketID: UUID?
}

// MARK: - HelperPrivilegedMutationRetrier

/// Retries an internal recovery mutation only while the shared privileged gate is busy or the
/// recovery operation reports a transient failure. Requests with the same key coalesce, keeping
/// watchdog callbacks from creating overlapping retry chains.
final class HelperPrivilegedMutationRetrier: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        gate: HelperPrivilegedMutationGate,
        maximumAttempts: Int = 10,
        retryDelay: TimeInterval = 0.5,
        scheduler: @escaping Scheduler = { delay, operation in
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + delay,
                execute: operation
            )
        }
    ) {
        self.gate = gate
        self.maximumAttempts = max(1, maximumAttempts)
        self.retryDelay = max(0, retryDelay)
        self.scheduler = scheduler
    }

    // MARK: Internal

    typealias Scheduler = @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void

    func run(
        key: String,
        operation: @escaping @Sendable () -> Bool,
        onExhausted: @escaping @Sendable () -> Void = {}
    ) {
        lock.lock()
        let inserted = activeKeys.insert(key).inserted
        lock.unlock()
        guard inserted else {
            return
        }

        attempt(
            key: key,
            remainingAttempts: maximumAttempts,
            operation: operation,
            onExhausted: onExhausted
        )
    }

    // MARK: Private

    private let gate: HelperPrivilegedMutationGate
    private let maximumAttempts: Int
    private let retryDelay: TimeInterval
    private let scheduler: Scheduler
    private let lock = NSLock()
    private var activeKeys: Set<String> = []

    private func attempt(
        key: String,
        remainingAttempts: Int,
        operation: @escaping @Sendable () -> Bool,
        onExhausted: @escaping @Sendable () -> Void
    ) {
        if gate.withExclusiveAccess(operation) == true {
            finish(key: key)
            return
        }

        guard remainingAttempts > 1 else {
            finish(key: key)
            onExhausted()
            return
        }

        scheduler(retryDelay) { [weak self] in
            self?.attempt(
                key: key,
                remainingAttempts: remainingAttempts - 1,
                operation: operation,
                onExhausted: onExhausted
            )
        }
    }

    private func finish(key: String) {
        lock.lock()
        activeKeys.remove(key)
        lock.unlock()
    }
}
