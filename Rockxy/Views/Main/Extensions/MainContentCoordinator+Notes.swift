import Foundation

// Extends `MainContentCoordinator` with the request-note mutation and persistence seam.

// MARK: - MainContentCoordinator + Notes

/// Coordinator extension owning every write to a transaction's user note (`HTTPTransaction.comment`).
/// Views never mutate `comment` directly — they route through `setNote` (immediate commit, used by the
/// menu / modal entry points) or `updateNoteDraft` (inline editors, debounced persistence). Both
/// normalize whitespace-only input to `nil`, keep the Library's Notes collection in sync, and persist
/// through `SessionStore` so note-only transactions survive restart.
extension MainContentCoordinator {
    // MARK: - Normalization

    /// Trims a raw note string and collapses whitespace-only input to `nil`.
    /// Pure and side-effect free so the normalization contract is directly testable.
    static func normalizedNote(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Mutation Entry Points

    /// Commits a note edit immediately. Used by the main-menu and right-click "Add Note…" modal,
    /// where the user has finished editing and there is a single discrete commit.
    func setNote(_ rawText: String?, for transaction: HTTPTransaction) {
        let changed = applyNoteInMemory(rawText, to: transaction)
        let pendingTask = noteFlushTasks.removeValue(forKey: transaction.id)
        pendingTask?.cancel()
        guard changed || pendingTask != nil else {
            return
        }
        persistTransaction(transaction)
    }

    /// Updates a note from an inline editor. Applies to the in-memory model immediately so the Notes
    /// scope and editor stay live, but debounces the SQLite write so a large transaction row is not
    /// rewritten on every keystroke.
    func updateNoteDraft(_ rawText: String?, for transaction: HTTPTransaction) {
        guard applyNoteInMemory(rawText, to: transaction) else {
            return
        }
        scheduleNotePersistence(for: transaction)
    }

    /// Cancels any pending debounced write and persists the current note value now. Inline editors
    /// call this on disappear so an in-flight edit is never lost when selection changes or the app quits.
    func flushNotePersistence(for transaction: HTTPTransaction) {
        guard let pendingTask = noteFlushTasks.removeValue(forKey: transaction.id) else {
            return
        }
        pendingTask.cancel()
        persistTransaction(transaction)
    }

    // MARK: - Private

    /// Applies a normalized note to the model. Returns `true` when the stored value actually changed.
    /// Membership in the Notes collection flips only when the note transitions empty↔non-empty, so the
    /// sidebar cache is invalidated and rows recomputed only then — keeping keystroke edits cheap while
    /// still dropping a transaction from the Notes scope the instant its last note is removed.
    @discardableResult
    private func applyNoteInMemory(_ rawText: String?, to transaction: HTTPTransaction) -> Bool {
        let normalized = Self.normalizedNote(rawText)
        guard transaction.comment != normalized else {
            return false
        }
        let membershipChanged = transaction.hasNote != (normalized != nil)
        transaction.comment = normalized
        if membershipChanged {
            invalidateSidebarFavoriteCache()
            updatePersistedFavoriteCache(after: transaction)
            if !transaction.hasNote,
               sidebarSelection == .noteTransaction(id: transaction.id)
            {
                sidebarSelection = .allNotes
            }
            refreshRowsAfterMutation()
        } else {
            refreshWorkspacesFilteringNotes()
        }
        return true
    }

    /// Note text can participate in both the simple search field and compound filters. When an edit
    /// keeps the request inside Notes, only those workspaces need a full filter recomputation.
    private func refreshWorkspacesFilteringNotes() {
        for workspace in workspaceStore.allWorkspaces {
            let criteria = workspace.filterCriteria
            let usesSimpleNoteSearch = criteria.isSearchEnabled
                && criteria.searchField == .comment
                && !criteria.searchText.isEmpty
            let usesCompoundNoteFilter = FilterRuleEvaluator.activeRules(
                in: workspace.filterRules,
                isFilterBarVisible: workspace.isFilterBarVisible
            ).contains { $0.field == .comment }

            if usesSimpleNoteSearch || usesCompoundNoteFilter {
                recomputeFilteredTransactions(for: workspace)
            }
        }
    }

    private func scheduleNotePersistence(for transaction: HTTPTransaction) {
        let id = transaction.id
        noteFlushTasks[id]?.cancel()
        noteFlushTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else {
                return
            }
            self.noteFlushTasks[id] = nil
            self.persistTransaction(transaction)
        }
    }
}
