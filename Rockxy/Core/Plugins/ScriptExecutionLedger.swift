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

    init(capacity: Int = 2_048, previewByteCapacity: Int = 32 * 1_024 * 1_024) {
        self.capacity = max(1, capacity)
        self.previewByteCapacity = max(1, previewByteCapacity)
    }

    // MARK: Internal

    let capacity: Int

    /// Total UTF-8 bytes of preview text and titles the ledger may hold across all flows.
    ///
    /// `capacity` bounds flows, not bytes, and `ScriptPreviewTab`'s own budgets are per tab:
    /// 8 tabs per panel, 2 panels, 256 KiB of text and a 40-character title each. That is
    /// ~4 MiB a flow, so 2,048 flows of count-capped previews is ~8 GiB — a script that
    /// publishes a large preview on every exchange could park all of it here, since nothing
    /// else drops a flow's previews before the FIFO reaches it. The byte bound evicts the
    /// oldest flows, in the same FIFO order the count cap uses, until the total fits.
    let previewByteCapacity: Int

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

    /// Replaces the preview tabs the scripts published for one panel of a flow. Empty
    /// input is ignored so a hook that publishes nothing never erases earlier tabs.
    func recordPreviews(_ tabs: [ScriptPreviewTab], panel: PreviewPanel, flowID: UUID) {
        guard !tabs.isEmpty else {
            return
        }
        lock.withLock {
            var existing = previewsByFlow[flowID] ?? []
            existing.removeAll { $0.panel == panel }
            existing.append(contentsOf: tabs)
            if previewsByFlow[flowID] == nil {
                previewOrder.append(flowID)
                if previewOrder.count > capacity {
                    dropOldestPreviewFlow()
                }
            }
            previewByteCount -= previewBytesByFlow[flowID] ?? 0
            let bytes = Self.byteCount(of: existing)
            previewBytesByFlow[flowID] = bytes
            previewByteCount += bytes
            previewsByFlow[flowID] = existing
            // The flow just written is never the victim: it is last in `previewOrder`, and a
            // single flow cannot exceed the budget on its own under `ScriptPreviewTab`'s
            // per-tab bounds. The `count > 1` guard keeps that true for a smaller injected
            // `previewByteCapacity` as well, so the caller always gets back what it recorded.
            while previewByteCount > previewByteCapacity, previewOrder.count > 1 {
                dropOldestPreviewFlow()
            }
        }
    }

    func previews(for flowID: UUID) -> [ScriptPreviewTab] {
        lock.withLock { previewsByFlow[flowID] ?? [] }
    }

    // MARK: Private

    private let lock = NSLock()
    private var previewsByFlow: [UUID: [ScriptPreviewTab]] = [:]
    private var previewOrder: [UUID] = []
    /// Each flow's contribution to `previewByteCount`, so a replaced panel can be subtracted
    /// without re-measuring every other flow.
    private var previewBytesByFlow: [UUID: Int] = [:]
    private var previewByteCount = 0
    private var namesByFlow: [UUID: [String]] = [:]
    private var order: [UUID] = []

    private static func byteCount(of tabs: [ScriptPreviewTab]) -> Int {
        tabs.reduce(0) { $0 + $1.title.utf8.count + $1.text.utf8.count }
    }

    /// Caller holds `lock`. Drops the front of `previewOrder`, which is the FIFO shape the
    /// count cap already used; only the byte accounting is new.
    private func dropOldestPreviewFlow() {
        let evicted = previewOrder.removeFirst()
        previewsByFlow.removeValue(forKey: evicted)
        previewByteCount -= previewBytesByFlow.removeValue(forKey: evicted) ?? 0
    }
}
