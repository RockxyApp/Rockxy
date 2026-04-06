import Foundation
import os

// Coordinates paused breakpoint items and user decisions across the breakpoint workflow.

// MARK: - PausedBreakpointItem

/// A single HTTP transaction paused by a breakpoint rule, queued for user inspection.
/// The `editableDraft` is mutated by the editor view; the final state is sent back
/// to the proxy pipeline when the user resolves the item.
struct PausedBreakpointItem: Identifiable {
    let id: UUID
    let phase: BreakpointPhase
    let host: String
    let path: String
    let method: String
    let statusCode: Int?
    let matchedRuleName: String?
    let createdAt: Date
    var editableDraft: BreakpointRequestData
}

// MARK: - BreakpointManager

/// Queue-backed breakpoint manager that holds multiple paused transactions simultaneously.
/// The proxy pipeline calls `enqueueAndWait(_:)` which suspends until the user resolves
/// the item in the Breakpoints window. Replaces the single-item `BreakpointViewModel`.
@MainActor @Observable
final class BreakpointManager {
    // MARK: Internal

    static let shared = BreakpointManager()

    private(set) var pausedItems: [PausedBreakpointItem] = []
    var selectedItemId: UUID?

    var hasPausedItems: Bool {
        !pausedItems.isEmpty
    }

    /// Called by the proxy pipeline to pause execution and wait for a user decision.
    /// Returns the decision AND the potentially-modified request data.
    func enqueueAndWait(_ data: BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData) {
        let components = URLComponents(string: data.url)
        let host = components?.host ?? ""
        let path = components?.path ?? "/"

        let itemId = UUID()
        let item = PausedBreakpointItem(
            id: itemId,
            phase: data.phase,
            host: host,
            path: path,
            method: data.method,
            statusCode: data.phase == .response ? data.statusCode : nil,
            matchedRuleName: nil,
            createdAt: Date(),
            editableDraft: data
        )

        return await withCheckedContinuation { continuation in
            continuations[itemId] = continuation
            pausedItems.append(item)
            if selectedItemId == nil {
                selectedItemId = itemId
            }
            BreakpointWindowModel.shared.selectPausedItem(item.id)
            Self.logger.info("Breakpoint paused: \(host)\(path)")
            NotificationCenter.default.post(name: .breakpointHit, object: nil)
        }
    }

    /// Resolve a single paused item with the given decision.
    func resolve(id: UUID, decision: BreakpointDecision) {
        guard let index = pausedItems.firstIndex(where: { $0.id == id }) else {
            return
        }
        let item = pausedItems[index]
        pausedItems.remove(at: index)

        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(returning: (decision, item.editableDraft))
        }

        if selectedItemId == id {
            selectedItemId = pausedItems.first?.id
        }

        BreakpointWindowModel.shared.handlePausedResolutionFallback(remainingPausedItems: pausedItems)

        Self.logger.info("Breakpoint resolved (\(String(describing: decision))): \(item.host)\(item.path)")
    }

    /// Resolve all paused items at once with the same decision.
    func resolveAll(decision: BreakpointDecision) {
        for item in pausedItems {
            if let continuation = continuations.removeValue(forKey: item.id) {
                continuation.resume(returning: (decision, item.editableDraft))
            }
        }
        let count = pausedItems.count
        pausedItems.removeAll()
        selectedItemId = nil
        Self.logger.info("Breakpoint resolved all (\(count) items, \(String(describing: decision)))")
    }

    /// Update the editable draft for a specific paused item (called by the editor view bindings).
    func updateDraft(id: UUID, _ transform: (inout BreakpointRequestData) -> Void) {
        guard let index = pausedItems.firstIndex(where: { $0.id == id }) else {
            return
        }
        transform(&pausedItems[index].editableDraft)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "BreakpointManager")

    private var continuations: [UUID: CheckedContinuation<(BreakpointDecision, BreakpointRequestData), Never>] = [:]
}
