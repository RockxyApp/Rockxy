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
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
            return
        }

        switch item {
        case let .domainNode(domain):
            filterCriteria.sidebarDomain = domain
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
        case let .domainPath(domain, pathPrefix):
            filterCriteria.sidebarDomain = domain
            filterCriteria.sidebarPathPrefix = pathPrefix
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
        case let .app(name, _):
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = name
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
        case .allApps,
             .allDomains:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
        case .allSaved:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .saved
            filterCriteria.exactTransactionID = nil
            selectTransaction(nil)
            recomputeFilteredTransactions()
        case .allPinned:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .pinned
            filterCriteria.exactTransactionID = nil
            selectTransaction(nil)
            recomputeFilteredTransactions()
        case let .pinnedTransaction(id):
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .pinned
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
            selectTransaction(transaction(for: id))
        case let .savedTransaction(id):
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .saved
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
            selectTransaction(transaction(for: id))
        default:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
        }
    }

    func deleteSelectedTransaction() {
        guard let selected = selectedTransaction else {
            return
        }
        deleteTransactions([selected])
    }

    func selectFirstFilteredTransaction() {
        guard let first = filteredTransactions.first else {
            return
        }
        selectedTransactionIDs = [first.id]
        selectTransaction(first)
    }

    func selectLastFilteredTransaction() {
        guard let last = filteredTransactions.last else {
            return
        }
        selectedTransactionIDs = [last.id]
        selectTransaction(last)
    }
}
