import Foundation

// Records which scripts actually ran for each client flow so captured rows can say so.

// MARK: - ScriptExecutionLedger

/// Thread-safe, bounded record of the scripts whose hooks ran for a flow
/// (`HTTPRequestData.flowID`). The script manager writes it as hooks run; the
/// proxy reads it when a transaction is emitted, so the inspector can show that
/// a script changed a request even when no rule matched. Only flows that ran a
/// script are stored, and the oldest flows are forgotten past `capacity`.
final class ScriptExecutionLedger: @unchecked Sendable {
    // MARK: Lifecycle

    init(capacity: Int = 2_048) {
        self.capacity = max(1, capacity)
    }

    // MARK: Internal

    let capacity: Int

    func record(scriptName: String, flowID: UUID) {
        lock.withLock {
            if var names = namesByFlow[flowID] {
                if !names.contains(scriptName) {
                    names.append(scriptName)
                    namesByFlow[flowID] = names
                }
                return
            }
            namesByFlow[flowID] = [scriptName]
            order.append(flowID)
            if order.count > capacity {
                namesByFlow.removeValue(forKey: order.removeFirst())
            }
        }
    }

    /// Script names in the order they first ran for the flow; empty when none ran.
    func scriptNames(for flowID: UUID) -> [String] {
        lock.withLock { namesByFlow[flowID] ?? [] }
    }

    // MARK: Private

    private let lock = NSLock()
    private var namesByFlow: [UUID: [String]] = [:]
    private var order: [UUID] = []
}
