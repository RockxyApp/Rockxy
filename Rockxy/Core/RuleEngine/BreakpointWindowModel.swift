import Foundation
import os

// Owns shared selection state for rules and paused items in the breakpoint window.

@MainActor @Observable
final class BreakpointWindowModel {
    // MARK: Internal

    enum SelectionMode {
        case none
        case rule(UUID)
        case pausedItem(UUID)
    }

    static let shared = BreakpointWindowModel()

    private(set) var breakpointRules: [ProxyRule] = []
    var selectedBreakpointRuleId: UUID?

    var selectionMode: SelectionMode {
        if let ruleId = selectedBreakpointRuleId {
            return .rule(ruleId)
        }
        if let itemId = BreakpointManager.shared.selectedItemId {
            return .pausedItem(itemId)
        }
        return .none
    }

    func selectRule(_ id: UUID) {
        selectedBreakpointRuleId = id
        BreakpointManager.shared.selectedItemId = nil
    }

    func selectPausedItem(_ id: UUID) {
        selectedBreakpointRuleId = nil
        BreakpointManager.shared.selectedItemId = id
    }

    func refreshBreakpointRules(from allRules: [ProxyRule]) {
        breakpointRules = allRules.filter {
            if case .breakpoint = $0.action {
                return true
            }
            return false
        }
        if let selected = selectedBreakpointRuleId,
           !breakpointRules.contains(where: { $0.id == selected })
        {
            selectedBreakpointRuleId = breakpointRules.first?.id
        }
    }

    func handlePausedResolutionFallback(remainingPausedItems: [PausedBreakpointItem]) {
        if let next = remainingPausedItems.first {
            selectPausedItem(next.id)
        } else {
            selectFirstRuleIfAvailable()
        }
    }

    func selectFirstRuleIfAvailable() {
        if let firstRule = breakpointRules.first {
            selectRule(firstRule.id)
        } else {
            selectedBreakpointRuleId = nil
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "BreakpointWindowModel")
}
