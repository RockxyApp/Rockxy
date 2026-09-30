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

    func exportRockxySession() {
        presentExport(format: .rockxySession)
    }

    func exportCSV() {
        presentExport(format: .csv)
    }

    func exportOpenAPIYAML() {
        presentExport(format: .openAPIYAML)
    }

    func exportOpenAPIHTML() {
        presentExport(format: .openAPIHTML)
    }

    func presentExport(format: TrafficExportFormat) {
        exportScopeContext = makeExportScopeContext(format: format)
    }

    /// Opens the native export review while locking the scope to the user's selection.
    /// Used by Assistant / Context Dock handoffs so analysis can never widen an export implicitly.
    func presentSelectedExport(format: TrafficExportFormat) {
        exportScopeContext = makeExportScopeContext(format: format, restrictsToSelection: true)
    }

    /// Freezes ordered all/filtered/selected membership from a single captured
    /// `activeWorkspace` reference. Counts derive from these snapshots, never
    /// from separate inputs, so nothing that changes after this call can widen
    /// or alter the reviewed export set.
    func makeExportScopeContext(
        format: TrafficExportFormat,
        restrictsToSelection: Bool = false
    )
        -> ExportScopeContext
    {
        let workspace = activeWorkspace
        return ExportScopeContext(
            format: format,
            originWorkspaceID: workspace.id,
            originWorkspaceTitle: workspace.title,
            allTransactions: transactions,
            filteredTransactions: filteredTransactions,
            selectedTransactions: resolveSelectedTransactions(),
            hasActiveFilter: exportFilterIsActive(for: workspace),
            restrictsToSelection: restrictsToSelection
        )
    }

    /// Validates a chosen scope against the frozen context and returns a pure
    /// plan (reviewed source + eligible set + skipped count). Restricted
    /// contexts reject all/filtered here; empty/invalid scopes fail closed.
    func makeExportExecutionPlan(context: ExportScopeContext, scope: ExportScope) -> ExportExecutionPlan? {
        guard context.isEnabled(scope) else {
            return nil
        }
        let snapshot = context.snapshot(for: scope)
        guard !snapshot.eligibleTransactions.isEmpty else {
            return nil
        }
        return ExportExecutionPlan(
            format: context.format,
            scope: scope,
            reviewedSource: snapshot.transactions,
            eligibleTransactions: snapshot.eligibleTransactions,
            skippedCount: snapshot.skippedCount
        )
    }

    /// Consumes only the passed review context — never live coordinator
    /// transactions, filteredTransactions, selection, or workspace state.
    func executeExport(context: ExportScopeContext, scope: ExportScope) {
        let format = context.format
        exportScopeContext = nil

        guard let plan = makeExportExecutionPlan(context: context, scope: scope) else {
            activeToast = ToastMessage(
                style: .error,
                text: String(localized: "No transactions to export", bundle: RockxyLocalization.bundle)
            )
            return
        }

        let data: Data
        let exportedCount: Int
        let skippedCount: Int
        do {
            switch format {
            case .rockxySession:
                data = try Self.sessionExportData(plan.eligibleTransactions)
                exportedCount = plan.eligibleTransactions.count
                skippedCount = 0
            case .har:
                data = try HARExporter().export(transactions: plan.eligibleTransactions)
                exportedCount = plan.eligibleTransactions.count
                skippedCount = 0
            case .csv:
                data = TrafficCSVExporter.export(transactions: plan.eligibleTransactions)
                exportedCount = plan.eligibleTransactions.count
                skippedCount = 0
            case .openAPIYAML:
                let result = try OpenAPIExporter().export(
                    transactions: plan.eligibleTransactions,
                    options: OpenAPIExportOptions(format: .yaml)
                )
                data = result.data
                exportedCount = result.exportedTransactionCount
                skippedCount = plan.skippedCount + result.skippedTransactionCount
            case .openAPIHTML:
                let result = try OpenAPIExporter().export(
                    transactions: plan.eligibleTransactions,
                    options: OpenAPIExportOptions(format: .html)
                )
                data = result.data
                exportedCount = result.exportedTransactionCount
                skippedCount = plan.skippedCount + result.skippedTransactionCount
            }
        } catch {
            Self.logger.error("Failed to serialize export: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Export Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not create export data.\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
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
            try data.write(to: url, options: .atomic)
            activeToast = ToastMessage(
                style: .success,
                text: exportSuccessMessage(
                    format: format,
                    count: exportedCount,
                    skippedCount: skippedCount
                )
            )
            Self.logger.info("Exported \(exportedCount) transactions to \(url.path())")
        } catch {
            Self.logger.error("Failed to export traffic: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Export Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not write export file.\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
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
                title: String(localized: "Save Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not serialize session data.\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
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
            RecentCaptureDocuments.shared.note(url)
        } catch {
            Self.logger.error("Failed to save session: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Save Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not write session file.\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
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
        alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))
        alert.runModal()
    }

    func eligibleExportTransactions(
        _ source: [HTTPTransaction],
        format: TrafficExportFormat
    )
        -> [HTTPTransaction]
    {
        switch format {
        case .rockxySession,
             .har,
             .csv:
            source
        case .openAPIYAML,
             .openAPIHTML:
            source.filter(OpenAPIExporter.isEligible)
        }
    }

    /// Exports the right-clicked row, or the whole selection when the clicked
    /// row is part of it, so a multi-row selection is never silently narrowed
    /// to the row under the pointer.
    func exportContextSelection(
        clicked transaction: HTTPTransaction,
        format: TrafficExportFormat
    ) {
        let selected = contextExportTransactions(clicked: transaction)
        let stem = selected.count > 1 ? "rockxy-export" : exportFileStem(for: transaction)
        exportTransactions(selected, format: format, defaultStem: stem)
    }

    func contextExportTransactions(clicked transaction: HTTPTransaction) -> [HTTPTransaction] {
        guard selectedTransactionIDs.contains(transaction.id) else {
            return [transaction]
        }
        let selected = resolveSelectedTransactions()
        return selected.isEmpty ? [transaction] : selected
    }

    /// Serializes transactions as a `.rockxysession` document, spanning the
    /// earliest to latest capture time of the exported rows.
    static func sessionExportData(_ transactions: [HTTPTransaction]) throws -> Data {
        let timestamps = transactions.map(\.timestamp)
        let metadata = SessionSerializer.makeMetadata(
            transactionCount: transactions.count,
            captureStartDate: timestamps.min(),
            captureEndDate: timestamps.max()
        )
        return try SessionSerializer.serialize(transactions: transactions, metadata: metadata)
    }

    func exportTransactions(
        _ source: [HTTPTransaction],
        format: TrafficExportFormat,
        defaultStem: String
    ) {
        let transactionsToExport = eligibleExportTransactions(source, format: format)
        guard !transactionsToExport.isEmpty else {
            activeToast = ToastMessage(
                style: .error,
                text: format.isOpenAPI
                    ? String(localized: "No OpenAPI-eligible requests to export", bundle: RockxyLocalization.bundle)
                    : String(localized: "No transactions to export", bundle: RockxyLocalization.bundle)
            )
            return
        }

        let data: Data
        let skippedCount: Int
        do {
            switch format {
            case .rockxySession:
                data = try Self.sessionExportData(transactionsToExport)
                skippedCount = 0
            case .har:
                data = try HARExporter().export(transactions: transactionsToExport)
                skippedCount = 0
            case .csv:
                data = TrafficCSVExporter.export(transactions: transactionsToExport)
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
                title: String(localized: "Export Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not create export data.\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
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
                title: String(localized: "Export Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not write export file.\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    /// Whether the workspace has an explicit visibility scope narrowing capture,
    /// judged from workspace state — search/filter criteria, active
    /// `FilterRuleEvaluator` rules, an active Focus Set or Traffic Signal, or
    /// muted sources — never inferred from a count difference between all and
    /// filtered (which can coincide when a filter simply matches everything).
    private func exportFilterIsActive(for workspace: WorkspaceState) -> Bool {
        if !workspace.filterCriteria.isEmpty {
            return true
        }
        let activeRules = FilterRuleEvaluator.activeRules(
            in: workspace.filterRules,
            isFilterBarVisible: workspace.isFilterBarVisible
        )
        if !activeRules.isEmpty {
            return true
        }
        return workspace.activeFocusSet != nil
            || workspace.activeTrafficSignal != nil
            || !workspace.mutedTrafficSources.isEmpty
    }

    private func allowedContentTypes(for format: TrafficExportFormat) -> [UTType] {
        switch format {
        case .rockxySession:
            [.rockxySession]
        case .har:
            [.har]
        case .csv:
            [.commaSeparatedText]
        case .openAPIYAML:
            [.openAPIYAML]
        case .openAPIHTML:
            [.openAPIHTML]
        }
    }

    private func fileExtension(for format: TrafficExportFormat) -> String {
        switch format {
        case .rockxySession:
            "rockxysession"
        case .har:
            "har"
        case .csv:
            "csv"
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
    )
        -> String
    {
        if skippedCount > 0 {
            return String(AttributedString(
                localized: "Exported \(format.successLabel) from ^[\(count) request](inflect: true); skipped ^[\(skippedCount) ineligible request](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        }
        return String(AttributedString(
            localized: "Exported \(format.successLabel) from ^[\(count) request](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }
}
