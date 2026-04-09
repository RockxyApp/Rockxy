import AppKit
import Foundation
import os
import UniformTypeIdentifiers

// Extends `MainContentCoordinator` with context menu behavior for the main workspace.

// MARK: - MainContentCoordinator + ContextMenu

/// Coordinator extension providing action methods for the request list context menu.
/// Each method operates on a specific transaction rather than the selected transaction,
/// since the right-clicked row may differ from the current selection.
extension MainContentCoordinator {
    // MARK: - Copy Actions

    func copyURL(for transaction: HTTPTransaction) {
        copyToClipboard(RequestCopyFormatter.url(for: transaction))
    }

    func copyCURL(for transaction: HTTPTransaction) {
        copyToClipboard(RequestCopyFormatter.curl(for: transaction))
    }

    func copyCellValue(for transaction: HTTPTransaction, column: String) {
        copyToClipboard(RequestCopyFormatter.cellValue(for: transaction, column: column))
    }

    // MARK: - Copy As Formats

    func copyAsJSON(for transaction: HTTPTransaction) {
        guard let json = RequestCopyFormatter.json(for: transaction) else {
            return
        }
        copyToClipboard(json)
    }

    func copyAsRawRequest(for transaction: HTTPTransaction) {
        copyToClipboard(RequestCopyFormatter.rawRequest(for: transaction))
    }

    func copyAsRawResponse(for transaction: HTTPTransaction) {
        guard let raw = RequestCopyFormatter.rawResponse(for: transaction) else {
            return
        }
        copyToClipboard(raw)
    }

    func copyAsRawHeaders(for transaction: HTTPTransaction) {
        var raw = "--- Request Headers ---\r\n"
        raw += RequestCopyFormatter.requestHeaders(for: transaction)
        if let responseHeaders = RequestCopyFormatter.responseHeaders(for: transaction) {
            raw += "\r\n\r\n--- Response Headers ---\r\n"
            raw += responseHeaders
        }
        copyToClipboard(raw)
    }

    func copyAsHAREntry(for transaction: HTTPTransaction) {
        guard let har = RequestCopyFormatter.harEntry(for: transaction) else {
            return
        }
        copyToClipboard(har)
    }

    // MARK: - Copy Headers / Body / Cookies

    func copyRequestHeaders(for transaction: HTTPTransaction) {
        copyToClipboard(RequestCopyFormatter.requestHeaders(for: transaction))
    }

    func copyResponseHeaders(for transaction: HTTPTransaction) {
        guard let headers = RequestCopyFormatter.responseHeaders(for: transaction) else {
            return
        }
        copyToClipboard(headers)
    }

    func copyRequestBody(for transaction: HTTPTransaction) {
        guard let body = RequestCopyFormatter.requestBody(for: transaction) else {
            return
        }
        copyToClipboard(body)
    }

    func copyResponseBody(for transaction: HTTPTransaction) {
        guard let body = RequestCopyFormatter.responseBody(for: transaction) else {
            return
        }
        copyToClipboard(body)
    }

    func copyRequestCookies(for transaction: HTTPTransaction) {
        let cookies = RequestCopyFormatter.requestCookies(for: transaction)
        guard !cookies.isEmpty else {
            return
        }
        copyToClipboard(cookies)
    }

    func copyResponseCookies(for transaction: HTTPTransaction) {
        let cookies = RequestCopyFormatter.responseCookies(for: transaction)
        guard !cookies.isEmpty else {
            return
        }
        copyToClipboard(cookies)
    }

    // MARK: - Clipboard Helper

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Replay

    func replayTransaction(_ transaction: HTTPTransaction) {
        performReplay(for: transaction)
    }

    func editAndReplayTransaction(_ transaction: HTTPTransaction) {
        ComposeStore.shared.pendingTransaction = transaction
        ComposeStore.shared.draftVersion &+= 1
        NotificationCenter.default.post(name: .openComposeWindow, object: nil)
    }

    // MARK: - Pin / Highlight / Comment

    func togglePin(for transaction: HTTPTransaction) {
        transaction.isPinned.toggle()
        persistTransaction(transaction)
        refreshRowsAfterMutation()
    }

    func setHighlight(_ color: HighlightColor?, for transaction: HTTPTransaction) {
        transaction.highlightColor = color
        refreshRowsAfterMutation()
    }

    func promptComment(for transaction: HTTPTransaction) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Add Comment")
        alert.informativeText = String(localized: "Enter a comment for this request:")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = transaction.comment ?? ""
        input.placeholderString = String(localized: "Comment…")
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            transaction.comment = input.stringValue.isEmpty ? nil : input.stringValue
            refreshRowsAfterMutation()
        }
    }

    // MARK: - Tools (Rule Creation)

    func createMapLocalRule(for transaction: HTTPTransaction) {
        let draft = MapLocalDraftBuilder.fromTransaction(transaction)
        MapLocalDraftStore.shared.setPending(draft)
        NotificationCenter.default.post(name: .openMapLocalWindow, object: nil)
        Self.logger.info("Created Map Local draft for \(transaction.request.url.absoluteString)")
    }

    func createMapRemoteRule(for transaction: HTTPTransaction) {
        let draft = MapRemoteDraftBuilder.fromTransaction(transaction)
        MapRemoteDraftStore.shared.setPending(draft)
        NotificationCenter.default.post(name: .openMapRemoteWindow, object: nil)
        Self.logger.info("Created Map Remote draft for \(transaction.request.url.absoluteString)")
    }

    func createBlockRule(for transaction: HTTPTransaction) {
        let context = BlockRuleEditorContextBuilder.fromTransaction(transaction)
        BlockRuleEditorContextStore.shared.setPending(context)
        NotificationCenter.default.post(name: .openBlockListWindow, object: nil)
        Self.logger.info("Created Block rule context for \(transaction.request.url.absoluteString)")
    }

    func createNetworkConditionsRule(for transaction: HTTPTransaction) {
        let draft = NetworkConditionsDraftBuilder.fromTransaction(transaction)
        NetworkConditionsDraftStore.shared.setPending(draft)
        NotificationCenter.default.post(name: .openNetworkConditionsWindow, object: nil)
        Self.logger.info("Created Network Conditions draft for \(transaction.request.url.absoluteString)")
    }

    func enableSSLProxying(for transaction: HTTPTransaction) {
        let host = transaction.request.host
        guard !host.isEmpty else {
            return
        }
        let rule = SSLProxyingRule(domain: host)
        Task {
            await SSLProxyingManager.shared.addRule(rule)
            Self.logger.info("Enabled SSL proxying for \(host)")
        }
    }

    // MARK: - Export Body

    func exportRequestBody(for transaction: HTTPTransaction) {
        guard let body = transaction.request.body else {
            return
        }
        exportBodyData(body, defaultName: "request-body")
    }

    func exportResponseBody(for transaction: HTTPTransaction) {
        guard let body = transaction.response?.body else {
            return
        }
        exportBodyData(body, defaultName: "response-body")
    }

    private func exportBodyData(_ data: Data, defaultName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try data.write(to: url)
            Self.logger.info("Exported body to \(url.path())")
        } catch {
            Self.logger.error("Failed to export body: \(error.localizedDescription)")
        }
    }

    // MARK: - Save Request

    func saveRequest(_ transaction: HTTPTransaction) {
        transaction.isSaved.toggle()
        persistTransaction(transaction)
        refreshRowsAfterMutation()
    }

    func exportTransactionAsHAR(_ transaction: HTTPTransaction) {
        let exporter = HARExporter()
        let data: Data
        do {
            data = try exporter.export(transactions: [transaction])
        } catch {
            Self.logger.error("Failed to serialize HAR: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Export Failed"),
                message: String(localized: "Could not create HAR data.\n\n\(error.localizedDescription)")
            )
            return
        }
        let safeName = transaction.request.host
            + transaction.request.path.replacingOccurrences(of: "/", with: "-")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeName).har"
        panel.allowedContentTypes = [.har]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try data.write(to: url)
            Self.logger.info("Saved request to \(url.path())")
        } catch {
            Self.logger.error("Failed to export request as HAR: \(error.localizedDescription)")
            showExportError(
                title: String(localized: "Export Failed"),
                message: String(localized: "Could not save HAR file.\n\n\(error.localizedDescription)")
            )
        }
    }

    // MARK: - Row Refresh After Mutation

    /// Refreshes all workspaces after a row-visible property mutation (pin, save, comment,
    /// highlight). Workspaces in saved/pinned scopes get a full recompute because membership
    /// may have changed. Other workspaces just re-derive rows.
    func refreshRowsAfterMutation() {
        for workspace in workspaceStore.workspaces {
            if workspace.filterCriteria.sidebarScope == .saved
                || workspace.filterCriteria.sidebarScope == .pinned
            {
                recomputeFilteredTransactions(for: workspace)
            } else {
                workspace.lastDeriveWasAppendOnly = false
                deriveFilteredRows(for: workspace)
            }
        }
    }

    // MARK: - Persistence

    private func persistTransaction(_ transaction: HTTPTransaction) {
        do {
            let store = try resolveSessionStore()
            Task {
                do {
                    try await store.saveTransaction(transaction)
                } catch {
                    Self.logger.error("Failed to persist transaction: \(error.localizedDescription)")
                }
            }
        } catch {
            Self.logger.error("Failed to create SessionStore: \(error.localizedDescription)")
        }
    }

    // MARK: - Compare

    func compareTransactions(_ a: HTTPTransaction, _ b: HTTPTransaction) {
        DiffTransactionStore.shared.setPending(a, b)
        NotificationCenter.default.post(name: .openDiffWindow, object: nil)
    }

    // MARK: - Delete

    func deleteTransactions(_ transactionsToDelete: [HTTPTransaction]) {
        let ids = Set(transactionsToDelete.map(\.id))
        transactions.removeAll { ids.contains($0.id) }
        persistedFavorites.removeAll { ids.contains($0.id) }

        // Prune selection state
        selectedTransactionIDs.subtract(ids)
        if let selected = selectedTransaction, ids.contains(selected.id) {
            selectedTransaction = nil
        }

        // Update all workspaces (same consistency as eviction)
        for workspace in workspaceStore.workspaces {
            workspace.filteredTransactions.removeAll { ids.contains($0.id) }
            if workspace.selectedTransaction.map({ ids.contains($0.id) }) == true {
                workspace.selectedTransaction = nil
            }
            rebuildSidebarIndexes(for: workspace)
            workspace.lastDeriveWasAppendOnly = false
            deriveFilteredRows(for: workspace)
        }

        // Always remove from SessionStore — a deleted row may have been persisted
        // via togglePin/saveRequest even if it was never loaded into persistedFavorites.
        // The store delete is a no-op when the IDs do not exist in SQLite.
        deleteFromSessionStore(ids: ids)
    }

    private func deleteFromSessionStore(ids: Set<UUID>) {
        do {
            let store = try resolveSessionStore()
            Task {
                do {
                    try await store.deleteTransactions(byIDs: ids)
                } catch {
                    Self.logger.error("Failed to delete persisted transactions: \(error.localizedDescription)")
                }
            }
        } catch {
            Self.logger.error("Failed to create SessionStore for delete: \(error.localizedDescription)")
        }
    }
}
