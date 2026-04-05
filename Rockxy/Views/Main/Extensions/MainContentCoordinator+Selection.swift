import Foundation

// Extends `MainContentCoordinator` with selection behavior for the main workspace.

// MARK: - MainContentCoordinator + Selection

/// Coordinator extension for tracking the currently selected transaction, log entry,
/// and sidebar item across the three-column layout.
extension MainContentCoordinator {
    // MARK: - Selection Management

    func selectTransaction(_ transaction: HTTPTransaction?) {
        selectedTransaction = transaction
    }

    func selectLogEntry(_ entry: LogEntry?) {
        selectedLogEntry = entry
    }

    func selectSidebarItem(_ item: SidebarItem?) {
        sidebarSelection = item

        guard let item else {
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            recomputeFilteredTransactions()
            return
        }

        switch item {
        case let .domainNode(domain):
            filterCriteria.sidebarDomain = domain
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            recomputeFilteredTransactions()
        case let .app(name, _):
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarApp = name
            filterCriteria.sidebarScope = .allTraffic
            recomputeFilteredTransactions()
        case .allApps,
             .allDomains:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            recomputeFilteredTransactions()
        case .allSaved:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .saved
            selectedTransaction = nil
            recomputeFilteredTransactions()
        case .allPinned:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .pinned
            selectedTransaction = nil
            recomputeFilteredTransactions()
        case let .pinnedTransaction(id):
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .pinned
            recomputeFilteredTransactions()
            if let transaction = transaction(for: id) {
                selectedTransaction = transaction
            }
        case let .savedTransaction(id):
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .saved
            recomputeFilteredTransactions()
            if let transaction = transaction(for: id) {
                selectedTransaction = transaction
            }
        default:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            recomputeFilteredTransactions()
        }
    }

    func deleteSelectedTransaction() {
        guard let selected = selectedTransaction else {
            return
        }
        deleteTransactions([selected])
    }
}
