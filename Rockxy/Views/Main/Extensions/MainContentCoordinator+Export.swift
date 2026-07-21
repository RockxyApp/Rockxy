import AppKit
import Foundation
import os
import UniformTypeIdentifiers

// Extends `MainContentCoordinator` with export behavior for the main workspace.

// MARK: - MainContentCoordinator + Export

/// Coordinator extension for exporting captured traffic as HAR files and copying
/// individual requests as cURL commands to the system pasteboard.
extension MainContentCoordinator {
    // MARK: - Traffic Export (Scope Sheet)

    func exportHAR() {
        presentExport(format: .har)
    }

    func exportOpenAPIYAML() {
        presentExport(format: .openAPIYAML)
    }

    func exportOpenAPIHTML() {
        presentExport(format: .openAPIHTML)
    }

    func presentExport(format: TrafficExportFormat) {
        let context = ExportScopeContext(
            format: format,
            allCount: transactions.count,
            filteredCount: filteredTransactions.count,
            selectedCount: selectedTransactionIDs.count,
            eligibleAllCount: eligibleExportCount(in: transactions, format: format),
            eligibleFilteredCount: eligibleExportCount(in: filteredTransactions, format: format),
            eligibleSelectedCount: eligibleExportCount(in: resolveSelectedTransactions(), format: format),
            initialScope: initialExportScope(format: format)
        )
        exportScopeContext = context
        showExportScope = true
    }

    /// Opens the existing native export review while locking the scope to the user's selection.
    /// Used by Assistant handoffs so analysis can never widen an export implicitly.
    func presentSelectedExport(format: TrafficExportFormat) {
        let selected = resolveSelectedTransactions()
        let context = ExportScopeContext(
            format: format,
            allCount: transactions.count,
            filteredCount: filteredTransactions.count,
            selectedCount: selected.count,
            eligibleAllCount: eligibleExportCount(in: transactions, format: format),
            eligibleFilteredCount: eligibleExportCount(in: filteredTransactions, format: format),
            eligibleSelectedCount: eligibleExportCount(in: selected, format: format),
            initialScope: .selected,
            restrictsToSelection: true
        )
        exportScopeContext = context
        showExportScope = true
    }

    func executeHARExport(scope: ExportScope) {
        executeExport(format: .har, scope: scope)
    }

    func executeExport(format: TrafficExportFormat, scope: ExportScope) {
        showExportScope = false

        let scopedTransactions: [HTTPTransaction] = switch scope {
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

        let transactionsToExport = eligibleExportTransactions(scopedTransactions, format: format)
        guard !transactionsToExport.isEmpty else {
            activeToast = ToastMessage(style: .error, text: String(localized: "No transactions to export"))
            return
        }

        let data: Data
        let skippedCount: Int
        do {
            switch format {
            case .har:
                data = try HARExporter().export(transactions: transactionsToExport)
                skippedCount = 0
            case .openAPIYAML:
                let result = try OpenAPIExporter().export(
                    transactions: scopedTransactions,
                    options: OpenAPIExportOptions(format: .yaml)
                )
                data = result.data
                skippedCount = result.skippedTransactionCount
            case .openAPIHTML:
                let result = try OpenAPIExporter().export(
                    transactions: scopedTransactions,
                    options: OpenAPIExportOptions(format: .html)
                )
                data = result.data
                skippedCount = result.skippedTransactionCount
            }
        } catch {
            Self.logger.error("Failed to serialize export: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Export Failed"),
                message: String(localized: "Could not create export data.\n\n\(error.localizedDescription)")
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes(for: format)
        panel.nameFieldStringValue = format.defaultFileName

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try data.write(to: url)
            activeToast = ToastMessage(
                style: .success,
                text: exportSuccessMessage(
                    format: format,
                    count: transactionsToExport.count,
                    skippedCount: skippedCount
                )
            )
            Self.logger.info("Exported \(transactionsToExport.count) transactions to \(url.path())")
        } catch {
            Self.logger.error("Failed to export traffic: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Export Failed"),
                message: String(localized: "Could not write export file.\n\n\(error.localizedDescription)")
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

    func eligibleExportTransactions(
        _ source: [HTTPTransaction],
        format: TrafficExportFormat
    ) -> [HTTPTransaction] {
        switch format {
        case .har:
            source
        case .openAPIYAML, .openAPIHTML:
            source.filter(OpenAPIExporter.isEligible)
        }
    }

    func exportOpenAPIContextSelection(
        clicked transaction: HTTPTransaction,
        format: TrafficExportFormat
    ) {
        let selected = selectedTransactionIDs.contains(transaction.id)
            ? resolveSelectedTransactions()
            : [transaction]
        exportTransactions(selected, format: format, defaultStem: exportFileStem(for: transaction))
    }

    func exportTransactions(
        _ source: [HTTPTransaction],
        format: TrafficExportFormat,
        defaultStem: String
    ) {
        let transactionsToExport = eligibleExportTransactions(source, format: format)
        guard !transactionsToExport.isEmpty else {
            activeToast = ToastMessage(style: .error, text: String(localized: "No OpenAPI-eligible requests to export"))
            return
        }

        let data: Data
        let skippedCount: Int
        do {
            switch format {
            case .har:
                data = try HARExporter().export(transactions: transactionsToExport)
                skippedCount = 0
            case .openAPIYAML:
                let result = try OpenAPIExporter().export(
                    transactions: source,
                    options: OpenAPIExportOptions(format: .yaml)
                )
                data = result.data
                skippedCount = result.skippedTransactionCount
            case .openAPIHTML:
                let result = try OpenAPIExporter().export(
                    transactions: source,
                    options: OpenAPIExportOptions(format: .html)
                )
                data = result.data
                skippedCount = result.skippedTransactionCount
            }
        } catch {
            showExportError(
                title: String(localized: "Export Failed"),
                message: String(localized: "Could not create export data.\n\n\(error.localizedDescription)")
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes(for: format)
        panel.nameFieldStringValue = "\(defaultStem).\(fileExtension(for: format))"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            activeToast = ToastMessage(
                style: .success,
                text: exportSuccessMessage(
                    format: format,
                    count: transactionsToExport.count,
                    skippedCount: skippedCount
                )
            )
        } catch {
            showExportError(
                title: String(localized: "Export Failed"),
                message: String(localized: "Could not write export file.\n\n\(error.localizedDescription)")
            )
        }
    }

    private func eligibleExportCount(
        in source: [HTTPTransaction],
        format: TrafficExportFormat
    ) -> Int {
        eligibleExportTransactions(source, format: format).count
    }

    private func initialExportScope(format: TrafficExportFormat) -> ExportScope {
        if selectedTransactionIDs.isEmpty == false,
           eligibleExportCount(in: resolveSelectedTransactions(), format: format) > 0
        {
            return .selected
        }
        if filteredTransactions.count != transactions.count,
           eligibleExportCount(in: filteredTransactions, format: format) > 0
        {
            return .filtered
        }
        return .all
    }

    private func allowedContentTypes(for format: TrafficExportFormat) -> [UTType] {
        switch format {
        case .har:
            [.har]
        case .openAPIYAML:
            [.openAPIYAML]
        case .openAPIHTML:
            [.openAPIHTML]
        }
    }

    private func fileExtension(for format: TrafficExportFormat) -> String {
        switch format {
        case .har:
            "har"
        case .openAPIYAML:
            "yaml"
        case .openAPIHTML:
            "html"
        }
    }

    private func exportFileStem(for transaction: HTTPTransaction) -> String {
        let rawName = (transaction.request.host + transaction.request.path)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return sanitized.isEmpty ? "rockxy-openapi" : sanitized
    }

    private func exportSuccessMessage(
        format: TrafficExportFormat,
        count: Int,
        skippedCount: Int
    ) -> String {
        if skippedCount > 0 {
            return String(
                localized: "Exported \(format.successLabel) from \(count) requests; skipped \(skippedCount) ineligible requests"
            )
        }
        return String(localized: "Exported \(format.successLabel) from \(count) requests")
    }
}
