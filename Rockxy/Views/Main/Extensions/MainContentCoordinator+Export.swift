import AppKit
import Foundation
import os
import UniformTypeIdentifiers

// Extends `MainContentCoordinator` with export behavior for the main workspace.

// MARK: - MainContentCoordinator + Export

/// Coordinator extension for exporting captured traffic as HAR files and copying
/// individual requests as cURL commands to the system pasteboard.
extension MainContentCoordinator {
    // MARK: - HAR Export (Scope Sheet)

    func exportHAR() {
        let context = ExportScopeContext(
            allCount: transactions.count,
            filteredCount: filteredTransactions.count,
            selectedCount: selectedTransactionIDs.count
        )
        exportScopeContext = context
        showExportScope = true
    }

    func executeHARExport(scope: ExportScope) {
        showExportScope = false

        let transactionsToExport: [HTTPTransaction] = switch scope {
        case .all:
            transactions
        case .filtered:
            filteredTransactions
        case .selected:
            if selectedTransactionIDs.isEmpty {
                transactions
            } else {
                resolveSelectedTransactions()
            }
        }

        guard !transactionsToExport.isEmpty else {
            activeToast = ToastMessage(style: .error, text: String(localized: "No transactions to export"))
            return
        }

        let exporter = HARExporter()
        let data: Data
        do {
            data = try exporter.export(transactions: transactionsToExport)
        } catch {
            Self.logger.error("Failed to serialize HAR: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Export Failed"),
                message: String(localized: "Could not create HAR data.\n\n\(error.localizedDescription)")
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.har]
        panel.nameFieldStringValue = "rockxy-export.har"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try data.write(to: url)
            activeToast = ToastMessage(
                style: .success,
                text: String(localized: "Exported \(transactionsToExport.count) transactions to HAR")
            )
            Self.logger.info("Exported \(transactionsToExport.count) transactions to \(url.path())")
        } catch {
            Self.logger.error("Failed to export HAR: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Export Failed"),
                message: String(localized: "Could not write HAR file.\n\n\(error.localizedDescription)")
            )
        }
    }

    // MARK: - Save Session

    func saveSession() {
        let metadata = SessionSerializer.makeMetadata(
            transactionCount: transactions.count,
            captureStartDate: transactions.first?.timestamp,
            captureEndDate: transactions.last?.timestamp
        )

        let data: Data
        do {
            data = try SessionSerializer.serialize(
                transactions: transactions,
                logEntries: logEntries,
                metadata: metadata
            )
        } catch {
            Self.logger.error("Failed to serialize session: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Save Failed"),
                message: String(localized: "Could not serialize session data.\n\n\(error.localizedDescription)")
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.rockxySession]
        panel.nameFieldStringValue = "rockxy-session.rockxysession"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            Self.logger.info("Saved session to \(url.path())")
        } catch {
            Self.logger.error("Failed to save session: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Save Failed"),
                message: String(localized: "Could not write session file.\n\n\(error.localizedDescription)")
            )
        }
    }

    // MARK: - cURL Copy

    func copyAsCURL() {
        guard let transaction = selectedTransaction else {
            return
        }
        copyCURL(for: transaction)
    }

    func copySelectedURL() {
        guard let transaction = selectedTransaction else {
            return
        }
        copyURL(for: transaction)
    }

    // MARK: - Selected Transaction Resolution

    /// Resolves selected transaction IDs against both live and persisted collections.
    /// Live transactions take precedence. Preserves live capture order for live rows
    /// and persisted collection order for persisted-only rows.
    func resolveSelectedTransactions() -> [HTTPTransaction] {
        guard !selectedTransactionIDs.isEmpty else {
            return []
        }
        var result: [HTTPTransaction] = []
        var resolved: Set<UUID> = []

        // Live transactions first (capture order)
        for transaction in transactions where selectedTransactionIDs.contains(transaction.id) {
            result.append(transaction)
            resolved.insert(transaction.id)
        }

        // Persisted-only rows (persisted collection order)
        let remaining = selectedTransactionIDs.subtracting(resolved)
        if !remaining.isEmpty {
            for transaction in persistedFavorites where remaining.contains(transaction.id) {
                result.append(transaction)
            }
        }

        return result
    }

    // MARK: - Private

    func showExportError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}
