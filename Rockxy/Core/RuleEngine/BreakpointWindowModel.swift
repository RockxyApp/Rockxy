import Foundation
import os

// Owns shared selection state for paused items in the breakpoint window.

@MainActor @Observable
final class BreakpointWindowModel {
    // MARK: Internal

    enum SelectionMode {
        case none
        case pausedItem(UUID)
    }

    static let shared = BreakpointWindowModel()

    var selectionMode: SelectionMode {
        if let itemId = BreakpointManager.shared.selectedItemId {
            return .pausedItem(itemId)
        }
        return .none
    }

    func selectPausedItem(_ id: UUID) {
        BreakpointManager.shared.selectedItemId = id
    }

    func handlePausedResolutionFallback(remainingPausedItems: [PausedBreakpointItem]) {
        if let next = remainingPausedItems.first {
            selectPausedItem(next.id)
        } else {
            BreakpointManager.shared.selectedItemId = nil
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "BreakpointWindowModel"
    )
}
