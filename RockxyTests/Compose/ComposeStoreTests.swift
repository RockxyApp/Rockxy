import Foundation
@testable import Rockxy
import Testing

// Regression tests for Compose menu/window handoff state.

// MARK: - ComposeStoreTests

@MainActor
struct ComposeStoreTests {
    // MARK: Internal

    @Test("Fresh Compose request clears pending selected transaction")
    func blankDraftRequestClearsPendingTransaction() {
        let store = ComposeStore.shared
        let transaction = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/stale")
        store.requestDraft(from: transaction)
        let previousVersion = store.draftVersion

        store.requestBlankDraft()

        #expect(store.pendingTransaction == nil)
        #expect(store.shouldOpenBlankDraft)
        #expect(store.draftVersion == previousVersion &+ 1)
        reset(store)
    }

    @Test("Edit and Repeat request targets the selected transaction")
    func transactionDraftRequestClearsBlankFlag() {
        let store = ComposeStore.shared
        store.requestBlankDraft()
        let previousVersion = store.draftVersion
        let transaction = TestFixtures.makeTransaction(method: "PATCH", url: "https://api.example.com/selected")

        store.requestDraft(from: transaction)

        #expect(store.pendingTransaction === transaction)
        #expect(store.shouldOpenBlankDraft == false)
        #expect(store.draftVersion == previousVersion &+ 1)
        reset(store)
    }

    // MARK: Private

    private func reset(_ store: ComposeStore) {
        store.pendingTransaction = nil
        store.shouldOpenBlankDraft = false
    }
}
