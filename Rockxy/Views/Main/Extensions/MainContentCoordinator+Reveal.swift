import AppKit
import Foundation

// MARK: - MainContentCoordinator + Reveal

extension MainContentCoordinator {
    func revealTransaction(id: UUID) {
        guard let transaction = transaction(for: id) else {
            return
        }

        if let window = NSApp.windows.first(where: { $0.title == RockxyIdentity.current.displayName }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        filterCriteria = .empty
        sidebarSelection = nil
        activeMainTab = .traffic
        recomputeFilteredTransactions()
        selectTransaction(transaction)
    }
}
