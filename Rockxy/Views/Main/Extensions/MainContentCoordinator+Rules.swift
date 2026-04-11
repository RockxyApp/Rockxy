import Foundation

// Extends `MainContentCoordinator` with rules behavior for the main workspace.

// MARK: - MainContentCoordinator + Rules

/// Coordinator extension for proxy rule management (block, map, breakpoint, throttle).
/// Delegates to `RuleSyncService` which coordinates between the shared `RuleEngine` actor,
/// disk persistence via `RuleStore`, and UI notification via `NotificationCenter`.
extension MainContentCoordinator {
    // MARK: - Rule Management

    func addRule(_ rule: ProxyRule) {
        Task { await RuleSyncService.addRule(rule) }
    }

    func removeRule(id: UUID) {
        Task { await RuleSyncService.removeRule(id: id) }
    }

    func toggleRule(id: UUID) {
        Task { await RuleSyncService.toggleRule(id: id) }
    }

    func createBreakpointRule(for transaction: HTTPTransaction) {
        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)
        BreakpointEditorContextStore.shared.setPending(context)
        NotificationCenter.default.post(name: .openBreakpointRulesWindow, object: nil)
    }
}
