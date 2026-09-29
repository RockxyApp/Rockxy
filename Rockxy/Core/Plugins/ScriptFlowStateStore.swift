import Foundation
import JavaScriptCore

// Per-script storage for `context.sharedState`, scoped to one request/response flow.

// MARK: - ScriptFlowStateStore

/// Holds the `context.sharedState` object a script's `onRequest` populated so
/// the same flow's `onResponse` receives it. Entries are keyed by
/// `HTTPRequestData.flowID` and dropped when the response hook consumes them.
/// Flows that never reach the response phase (blocked, mocked, failed) age out
/// once `capacity` newer flows have started, so the store stays bounded.
///
/// Every `JSValue` belongs to the owning plugin's `JSContext`; callers use this
/// store only from that plugin's serial script queue. The lock guards the
/// dictionary itself across concurrent flows.
final class ScriptFlowStateStore: @unchecked Sendable {
    // MARK: Lifecycle

    init(capacity: Int = 1_024) {
        self.capacity = max(1, capacity)
    }

    // MARK: Internal

    let capacity: Int

    var count: Int {
        lock.withLock { states.count }
    }

    var isEmpty: Bool {
        lock.withLock { states.isEmpty }
    }

    /// Request phase: starts the flow with an empty object. A flow that is seen
    /// again (for example a replay) starts over rather than inheriting stale state.
    func beginFlow(_ flowID: UUID, in context: JSContext) -> JSValue? {
        guard let state = JSValue(newObjectIn: context) else {
            return nil
        }
        lock.withLock {
            if states[flowID] == nil {
                order.append(flowID)
            }
            states[flowID] = state
            while order.count > capacity {
                states.removeValue(forKey: order.removeFirst())
            }
        }
        return state
    }

    /// Response phase: hands back the request-phase object and forgets it. A flow
    /// whose request hook did not run gets a fresh empty object.
    func endFlow(_ flowID: UUID, in context: JSContext) -> JSValue? {
        let existing = lock.withLock { () -> JSValue? in
            guard let state = states.removeValue(forKey: flowID) else {
                return nil
            }
            order.removeAll { $0 == flowID }
            return state
        }
        return existing ?? JSValue(newObjectIn: context)
    }

    // MARK: Private

    private let lock = NSLock()
    private var states: [UUID: JSValue] = [:]
    private var order: [UUID] = []
}
