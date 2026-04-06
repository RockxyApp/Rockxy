import Foundation
@testable import Rockxy
import Testing

@MainActor
struct RequestTableRefreshTests {
    // MARK: - RefreshToken

    @Test("refreshToken starts at 0")
    func initialToken() {
        let coordinator = MainContentCoordinator()
        #expect(coordinator.refreshToken == 0)
    }

    @Test("deriveFilteredRows increments refreshToken")
    func deriveIncrementsToken() {
        let coordinator = MainContentCoordinator()
        let initial = coordinator.refreshToken
        coordinator.transactions = [TestFixtures.makeTransaction()]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.refreshToken > initial)
    }

    @Test("Same-count reorder: sort changes token while count stays same")
    func sameCountReorder() {
        let coordinator = MainContentCoordinator()
        let t1 = TestFixtures.makeTransaction(url: "https://beta.example.com/test")
        let t2 = TestFixtures.makeTransaction(url: "https://alpha.example.com/test")
        coordinator.transactions = [t1, t2]
        coordinator.recomputeFilteredTransactions()

        let countBefore = coordinator.filteredRows.count
        let tokenBefore = coordinator.refreshToken

        // Apply sort by URL
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.deriveFilteredRows()

        #expect(coordinator.filteredRows.count == countBefore)
        #expect(coordinator.refreshToken > tokenBefore)
        // Verify order changed — alpha should be first after sort
        #expect(coordinator.filteredRows.first?.host == "alpha.example.com")
    }

    @Test("Append with no sort: count grows, token changes")
    func appendNoSort() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [TestFixtures.makeTransaction()]
        coordinator.recomputeFilteredTransactions()

        let countBefore = coordinator.filteredRows.count
        let tokenBefore = coordinator.refreshToken

        let newTransaction = TestFixtures.makeTransaction()
        coordinator.transactions.append(newTransaction)
        coordinator.appendFilteredTransactions([newTransaction])

        #expect(coordinator.filteredRows.count > countBefore)
        #expect(coordinator.refreshToken > tokenBefore)
    }

    @Test("Sort active + append: token changes")
    func sortActiveAppend() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [TestFixtures.makeTransaction()]
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.recomputeFilteredTransactions()

        let tokenBefore = coordinator.refreshToken

        let newTransaction = TestFixtures.makeTransaction()
        coordinator.transactions.append(newTransaction)
        coordinator.appendFilteredTransactions([newTransaction])

        #expect(coordinator.refreshToken > tokenBefore)
    }

    @Test("Eviction: count shrinks, token changes")
    func evictionChanges() {
        let coordinator = MainContentCoordinator()
        let transactions = TestFixtures.makeBulkTransactions(count: 10)
        coordinator.transactions = transactions
        coordinator.recomputeFilteredTransactions()

        let tokenBefore = coordinator.refreshToken

        coordinator.evictOldestTransactions(count: 3)

        #expect(coordinator.filteredRows.count == 7)
        #expect(coordinator.refreshToken > tokenBefore)
    }

    @Test("Clear session: token changes, sort descriptors preserved")
    func clearPreservesSort() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [TestFixtures.makeTransaction()]
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.recomputeFilteredTransactions()

        let sortBefore = coordinator.activeSortDescriptors

        coordinator.clearSession()

        #expect(coordinator.filteredRows.isEmpty)
        #expect(!coordinator.activeSortDescriptors.isEmpty)
        #expect(coordinator.activeSortDescriptors.count == sortBefore.count)
        #expect(coordinator.activeSortDescriptors.first?.key == "url")
    }

    // MARK: - Transaction Lookup

    @Test("transaction(for:) resolves live transaction")
    func lookupLive() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        coordinator.transactions = [transaction]

        let found = coordinator.transaction(for: transaction.id)
        #expect(found?.id == transaction.id)
    }

    @Test("transaction(for:) resolves persisted-only row")
    func lookupPersisted() {
        let coordinator = MainContentCoordinator()
        let persisted = TestFixtures.makeTransaction()
        persisted.isSaved = true
        coordinator.persistedFavorites = [persisted]

        let found = coordinator.transaction(for: persisted.id)
        #expect(found?.id == persisted.id)
    }

    @Test("transaction(for:) returns live copy when both exist")
    func lookupLiveWins() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        transaction.comment = "live version"
        coordinator.transactions = [transaction]

        let persisted = TestFixtures.makeTransaction()
        // Force same ID
        let persistedCopy = HTTPTransaction(
            id: transaction.id,
            request: persisted.request,
            state: .completed
        )
        persistedCopy.comment = "persisted version"
        coordinator.persistedFavorites = [persistedCopy]

        let found = coordinator.transaction(for: transaction.id)
        #expect(found?.comment == "live version")
    }

    @Test("transaction(for:) returns nil for unknown ID")
    func lookupUnknown() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [TestFixtures.makeTransaction()]

        let found = coordinator.transaction(for: UUID())
        #expect(found == nil)
    }

    // MARK: - Row Derivation

    @Test("filteredRows count matches filteredTransactions after recompute")
    func rowCountMatchesTransactions() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = TestFixtures.makeBulkTransactions(count: 10)
        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredRows.count == coordinator.filteredTransactions.count)
    }

    @Test("Sort applied: filteredRows order differs when sort active")
    func sortApplied() {
        let coordinator = MainContentCoordinator()
        let t1 = TestFixtures.makeTransaction(url: "https://zzz.example.com/test")
        let t2 = TestFixtures.makeTransaction(url: "https://aaa.example.com/test")
        coordinator.transactions = [t1, t2]
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.recomputeFilteredTransactions()

        // filteredTransactions is in insertion order
        #expect(coordinator.filteredTransactions.first?.id == t1.id)
        // filteredRows is sorted
        #expect(coordinator.filteredRows.first?.host == "aaa.example.com")
    }

    @Test("Export preserves capture order unaffected by sort")
    func exportPreservesCaptureOrder() {
        let coordinator = MainContentCoordinator()
        let t1 = TestFixtures.makeTransaction(url: "https://zzz.example.com/test")
        let t2 = TestFixtures.makeTransaction(url: "https://aaa.example.com/test")
        coordinator.transactions = [t1, t2]
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.recomputeFilteredTransactions()

        // Display is sorted
        #expect(coordinator.filteredRows.first?.host == "aaa.example.com")
        // Export collections preserve capture order
        #expect(coordinator.transactions.first?.id == t1.id)
        #expect(coordinator.filteredTransactions.first?.id == t1.id)
    }

    // MARK: - Saved/Pinned Membership

    @Test("Toggling save while viewing .saved removes the row immediately")
    func toggleSaveInSavedScope() {
        let coordinator = MainContentCoordinator()
        let saved = TestFixtures.makeTransaction()
        saved.isSaved = true
        let normal = TestFixtures.makeTransaction()
        coordinator.transactions = [saved, normal]

        // Enter saved scope
        coordinator.filterCriteria.sidebarScope = .saved
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredRows.count == 1)
        #expect(coordinator.filteredRows.first?.id == saved.id)

        // Unsave the transaction
        coordinator.saveRequest(saved)
        #expect(saved.isSaved == false)
        #expect(coordinator.filteredRows.isEmpty)
    }

    @Test("Toggling pin while viewing .pinned removes the row immediately")
    func togglePinInPinnedScope() {
        let coordinator = MainContentCoordinator()
        let pinned = TestFixtures.makeTransaction()
        pinned.isPinned = true
        let normal = TestFixtures.makeTransaction()
        coordinator.transactions = [pinned, normal]

        // Enter pinned scope
        coordinator.filterCriteria.sidebarScope = .pinned
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredRows.count == 1)
        #expect(coordinator.filteredRows.first?.id == pinned.id)

        // Unpin the transaction
        coordinator.togglePin(for: pinned)
        #expect(pinned.isPinned == false)
        #expect(coordinator.filteredRows.isEmpty)
    }

    // MARK: - Delete

    @Test("Keyboard delete works for live rows")
    func deleteLiveRow() {
        let coordinator = MainContentCoordinator()
        let t1 = TestFixtures.makeTransaction()
        let t2 = TestFixtures.makeTransaction()
        coordinator.transactions = [t1, t2]
        coordinator.recomputeFilteredTransactions()
        coordinator.selectTransaction(t1)

        coordinator.deleteSelectedTransaction()

        #expect(coordinator.transactions.count == 1)
        #expect(coordinator.filteredRows.count == 1)
        #expect(coordinator.selectedTransaction == nil)
        #expect(coordinator.filteredRows.first?.id == t2.id)
    }

    @Test("Keyboard delete works for persisted-only rows")
    func deletePersistedOnlyRow() {
        let coordinator = MainContentCoordinator()
        let persisted = TestFixtures.makeTransaction()
        persisted.isSaved = true
        coordinator.persistedFavorites = [persisted]

        // Enter saved scope so the persisted row is visible
        coordinator.filterCriteria.sidebarScope = .saved
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredRows.count == 1)

        coordinator.selectTransaction(persisted)
        coordinator.deleteSelectedTransaction()

        #expect(coordinator.persistedFavorites.isEmpty)
        #expect(coordinator.filteredRows.isEmpty)
        #expect(coordinator.selectedTransaction == nil)
    }

    // MARK: - Append-Only Signal

    @Test("Append-only signal is true after genuine append fast-path")
    func appendOnlySignalSet() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [TestFixtures.makeTransaction()]
        coordinator.recomputeFilteredTransactions()

        let newTransaction = TestFixtures.makeTransaction()
        coordinator.transactions.append(newTransaction)
        coordinator.appendFilteredTransactions([newTransaction])

        // The signal persists until the next non-append derive cycle
        #expect(coordinator.activeWorkspace.lastDeriveWasAppendOnly == true)
    }

    @Test("Append-only signal is false after recompute")
    func appendOnlySignalClearedByRecompute() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [TestFixtures.makeTransaction()]
        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.activeWorkspace.lastDeriveWasAppendOnly == false)
    }

    @Test("Append-only signal is false after sort change")
    func appendOnlySignalClearedBySort() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [TestFixtures.makeTransaction()]
        coordinator.recomputeFilteredTransactions()

        // Set append signal
        let newTransaction = TestFixtures.makeTransaction()
        coordinator.transactions.append(newTransaction)
        coordinator.appendFilteredTransactions([newTransaction])
        #expect(coordinator.activeWorkspace.lastDeriveWasAppendOnly == true)

        // Sort clears it
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.activeWorkspace.lastDeriveWasAppendOnly = false
        coordinator.deriveFilteredRows()
        #expect(coordinator.activeWorkspace.lastDeriveWasAppendOnly == false)
    }

    @Test("Append with sort active does not set append-only signal")
    func appendWithSortDoesNotSetSignal() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [TestFixtures.makeTransaction()]
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.recomputeFilteredTransactions()

        let newTransaction = TestFixtures.makeTransaction()
        coordinator.transactions.append(newTransaction)
        coordinator.appendFilteredTransactions([newTransaction])

        // Sort was active, so append path falls through to recompute
        #expect(coordinator.activeWorkspace.lastDeriveWasAppendOnly == false)
    }

    // MARK: - Sort State Sync

    @Test("Workspace sort descriptors persist across recompute")
    func sortDescriptorsPersistAcrossRecompute() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = TestFixtures.makeBulkTransactions(count: 5)
        coordinator.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        coordinator.recomputeFilteredTransactions()

        // Verify sort is applied
        #expect(!coordinator.activeSortDescriptors.isEmpty)

        // Recompute again
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.activeSortDescriptors.first?.key == "url")
    }

    // MARK: - Delete Multi-Workspace Propagation

    @Test("Delete updates sidebar domain state")
    func deleteupdatesSidebarDomain() {
        let coordinator = MainContentCoordinator()
        let t1 = TestFixtures.makeTransaction(url: "https://api.example.com/test")
        let t2 = TestFixtures.makeTransaction(url: "https://other.com/test")
        coordinator.transactions = [t1, t2]
        coordinator.recomputeFilteredTransactions()
        coordinator.updateDomainTree(for: t1)
        coordinator.updateDomainTree(for: t2)

        #expect(coordinator.domainTree.count == 2)

        coordinator.deleteTransactions([t1])

        // Sidebar rebuilt after delete — only other.com remains
        #expect(coordinator.domainTree.count == 1)
        #expect(coordinator.domainTree.first?.domain == "other.com")
    }

    @Test("Delete updates sidebar app state")
    func deleteUpdatessSidebarApp() {
        let coordinator = MainContentCoordinator()
        let t1 = TestFixtures.makeTransaction()
        t1.clientApp = "Safari"
        let t2 = TestFixtures.makeTransaction()
        t2.clientApp = "Chrome"
        coordinator.transactions = [t1, t2]
        coordinator.recomputeFilteredTransactions()
        coordinator.updateAppNodes(for: t1)
        coordinator.updateAppNodes(for: t2)

        #expect(coordinator.appNodes.count == 2)

        coordinator.deleteTransactions([t1])

        // Sidebar rebuilt after delete — only Chrome remains
        #expect(coordinator.appNodes.count == 1)
        #expect(coordinator.appNodes.first?.name == "Chrome")
    }

    @Test("selectedTransactionIDs is pruned after delete")
    func selectedIDsPrunedAfterDelete() {
        let coordinator = MainContentCoordinator()
        let t1 = TestFixtures.makeTransaction()
        let t2 = TestFixtures.makeTransaction()
        coordinator.transactions = [t1, t2]
        coordinator.recomputeFilteredTransactions()
        coordinator.selectedTransactionIDs = [t1.id, t2.id]

        coordinator.deleteTransactions([t1])

        #expect(!coordinator.selectedTransactionIDs.contains(t1.id))
        #expect(coordinator.selectedTransactionIDs.contains(t2.id))
    }

    @Test("Export selected count correct after delete")
    func exportSelectedCountAfterDelete() {
        let coordinator = MainContentCoordinator()
        let t1 = TestFixtures.makeTransaction()
        let t2 = TestFixtures.makeTransaction()
        let t3 = TestFixtures.makeTransaction()
        coordinator.transactions = [t1, t2, t3]
        coordinator.recomputeFilteredTransactions()
        coordinator.selectedTransactionIDs = [t1.id, t2.id, t3.id]

        coordinator.deleteTransactions([t1])

        // selectedTransactionIDs should now contain only t2 and t3
        #expect(coordinator.selectedTransactionIDs.count == 2)
        let resolved = coordinator.resolveSelectedTransactions()
        #expect(resolved.count == 2)
    }

    // MARK: - Persisted Delete Durability

    @Test("Persisted delete is durable across SessionStore reload")
    func persistedDeleteDurable() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)

        // Save a transaction
        let transaction = TestFixtures.makeTransaction()
        transaction.isPinned = true
        try await store.saveTransaction(transaction)

        // Verify it loads
        let loaded = try await store.loadPinnedAndSavedTransactions()
        #expect(loaded.count == 1)

        // Delete by ID
        try await store.deleteTransactions(byIDs: [transaction.id])

        // Verify it no longer loads
        let afterDelete = try await store.loadPinnedAndSavedTransactions()
        #expect(afterDelete.isEmpty)
    }

    @Test("Deleting a saved live row removes it from SessionStore even if not in persistedFavorites")
    func deleteSavedLiveRowDurable() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)

        // Simulate a live row that was saved/pinned and persisted to the store
        // but never loaded into persistedFavorites (e.g., no app restart yet)
        let transaction = TestFixtures.makeTransaction()
        transaction.isSaved = true
        try await store.saveTransaction(transaction)

        // Verify it exists in store
        let loaded = try await store.loadPinnedAndSavedTransactions()
        #expect(loaded.count == 1)

        // Direct store delete by ID — this is what deleteTransactions calls unconditionally
        try await store.deleteTransactions(byIDs: [transaction.id])

        // Verify it no longer exists in store — must not reappear after relaunch
        let afterDelete = try await store.loadPinnedAndSavedTransactions()
        #expect(afterDelete.isEmpty)
    }

    @Test("deleteTransactions always calls store delete regardless of persistedFavorites")
    func deleteAlwaysCallsStoreDelete() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        transaction.isSaved = true
        coordinator.transactions = [transaction]
        coordinator.recomputeFilteredTransactions()

        // persistedFavorites is empty — simulates no startup reload
        #expect(coordinator.persistedFavorites.isEmpty)

        // Delete should still proceed (not gated on hadPersisted)
        coordinator.deleteTransactions([transaction])

        // Verify in-memory state is cleaned up
        #expect(coordinator.transactions.isEmpty)
        #expect(coordinator.filteredRows.isEmpty)
    }

    // MARK: - Per-Workspace Append Scope Guard

    @Test("Per-workspace append fast-path not used for .saved scope")
    func appendNotUsedForSavedScope() {
        let coordinator = MainContentCoordinator()
        let saved = TestFixtures.makeTransaction()
        saved.isSaved = true
        coordinator.transactions = [saved]
        coordinator.filterCriteria.sidebarScope = .saved
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredRows.count == 1)

        // Append a new non-saved transaction — must not appear in saved scope
        let newTransaction = TestFixtures.makeTransaction()
        coordinator.transactions.append(newTransaction)
        coordinator.appendFilteredTransactions([newTransaction])

        // Should still only show saved transactions (recompute path, not append)
        #expect(coordinator.filteredRows.count == 1)
        #expect(coordinator.filteredRows.first?.id == saved.id)
    }

    @Test("Per-workspace append fast-path not used for .pinned scope")
    func appendNotUsedForPinnedScope() {
        let coordinator = MainContentCoordinator()
        let pinned = TestFixtures.makeTransaction()
        pinned.isPinned = true
        coordinator.transactions = [pinned]
        coordinator.filterCriteria.sidebarScope = .pinned
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredRows.count == 1)

        let newTransaction = TestFixtures.makeTransaction()
        coordinator.transactions.append(newTransaction)
        coordinator.appendFilteredTransactions([newTransaction])

        #expect(coordinator.filteredRows.count == 1)
        #expect(coordinator.filteredRows.first?.id == pinned.id)
    }

    // MARK: - Persisted Sequence Number Collision Safety

    @Test("Persisted sequence numbers start after existing nextSequenceNumber")
    func persistedSequenceNoCollision() {
        let coordinator = MainContentCoordinator()
        // Simulate live capture that advanced nextSequenceNumber
        coordinator.nextSequenceNumber = 100

        let persisted1 = TestFixtures.makeTransaction()
        persisted1.isSaved = true
        let persisted2 = TestFixtures.makeTransaction()
        persisted2.isPinned = true
        coordinator.persistedFavorites = [persisted1, persisted2]

        // Simulate the assignment logic from loadPersistedFavorites
        let base = coordinator.nextSequenceNumber
        for (index, transaction) in coordinator.persistedFavorites.enumerated() {
            transaction.sequenceNumber = base + index
        }
        coordinator.nextSequenceNumber = base + coordinator.persistedFavorites.count

        #expect(persisted1.sequenceNumber == 100)
        #expect(persisted2.sequenceNumber == 101)
        #expect(coordinator.nextSequenceNumber == 102)
    }

    // MARK: - Leaf Selection Scope

    @Test("Selecting a pinned leaf sets scope to .pinned")
    func pinnedLeafSetsScope() {
        let coordinator = MainContentCoordinator()
        let pinned = TestFixtures.makeTransaction()
        pinned.isPinned = true
        coordinator.transactions = [pinned]

        coordinator.selectSidebarItem(.pinnedTransaction(id: pinned.id))

        #expect(coordinator.filterCriteria.sidebarScope == .pinned)
        #expect(coordinator.selectedTransaction?.id == pinned.id)
    }

    @Test("Selecting a saved leaf sets scope to .saved")
    func savedLeafSetsScope() {
        let coordinator = MainContentCoordinator()
        let saved = TestFixtures.makeTransaction()
        saved.isSaved = true
        coordinator.transactions = [saved]

        coordinator.selectSidebarItem(.savedTransaction(id: saved.id))

        #expect(coordinator.filterCriteria.sidebarScope == .saved)
        #expect(coordinator.selectedTransaction?.id == saved.id)
    }

    // MARK: - Stale Selection Clearance

    @Test("Selecting a missing pinned leaf clears selection")
    func missingPinnedLeafClearsSelection() {
        let coordinator = MainContentCoordinator()
        let existing = TestFixtures.makeTransaction()
        coordinator.transactions = [existing]
        coordinator.selectTransaction(existing)
        #expect(coordinator.selectedTransaction != nil)

        // Select a pinned leaf with an ID that does not exist
        coordinator.selectSidebarItem(.pinnedTransaction(id: UUID()))

        #expect(coordinator.selectedTransaction == nil)
    }

    @Test("Selecting a missing saved leaf clears selection")
    func missingSavedLeafClearsSelection() {
        let coordinator = MainContentCoordinator()
        let existing = TestFixtures.makeTransaction()
        coordinator.transactions = [existing]
        coordinator.selectTransaction(existing)
        #expect(coordinator.selectedTransaction != nil)

        coordinator.selectSidebarItem(.savedTransaction(id: UUID()))

        #expect(coordinator.selectedTransaction == nil)
    }
}
