import Foundation

// MARK: - TrafficCaptureContext

/// Immutable logical ownership captured when a request begins.
///
/// The proxy listener remains app-wide, but every completed transaction is routed
/// back to the Project and capture session that owned its request start. The
/// generation changes when that session is cleared, so late completions from the
/// cleared generation cannot reappear in the new history.
struct TrafficCaptureContext: Equatable, Hashable, Sendable {
    let projectID: UUID
    let sessionID: UUID
    let generation: UInt64
}

// MARK: - TrafficCaptureContextStore

/// Lock-backed bridge between main-actor Project selection and SwiftNIO event-loop
/// threads. NIO handlers take a synchronous snapshot; they never reach into UI or
/// actor-isolated state while a request is being decoded.
final class TrafficCaptureContextStore: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ context: TrafficCaptureContext? = nil) {
        currentContext = context
    }

    // MARK: Internal

    func snapshot() -> TrafficCaptureContext? {
        lock.lock()
        defer { lock.unlock() }
        return currentContext
    }

    func update(_ context: TrafficCaptureContext?) {
        lock.lock()
        currentContext = context
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var currentContext: TrafficCaptureContext?
}

// MARK: - CaptureRecordingGate

/// Synchronous recording-state snapshot used at capture intake boundaries.
///
/// UI delivery is intentionally batched. Sampling `isRecording` only when a batch reaches the
/// main actor makes Pause/Resume nondeterministic: a transaction completed before Pause can be
/// dropped, while one completed during Pause can appear after Resume. This lock-backed gate lets
/// proxy and log callbacks decide once, at intake time, before their asynchronous hops.
final class CaptureRecordingGate: @unchecked Sendable {
    // MARK: Lifecycle

    init(isRecording: Bool = true) {
        self.isRecording = isRecording
    }

    // MARK: Internal

    func update(isRecording: Bool) {
        lock.lock()
        self.isRecording = isRecording
        lock.unlock()
    }

    func allowsCapture() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRecording
    }

    // MARK: Private

    private let lock = NSLock()
    private var isRecording: Bool
}
