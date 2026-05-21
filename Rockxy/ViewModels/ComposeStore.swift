import Foundation

// Coordinates pending compose-window handoff state between the main workspace and the
// compose flow.

// MARK: - ComposeStore

/// Singleton that handles the handoff of an HTTPTransaction from the coordinator
/// to the Compose window. Owns only handoff state — the active editable draft
/// and response state live in `ComposeViewModel`.
@MainActor @Observable
final class ComposeStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = ComposeStore()

    /// The transaction to prefill the Compose window with. Set by the coordinator
    /// before opening the window, consumed by `ComposeWindowView` after prefill.
    var pendingTransaction: HTTPTransaction?

    /// Indicates that the next Compose window activation should start from a
    /// fresh blank draft, even if the window was already alive with old editor state.
    var shouldOpenBlankDraft = false

    /// Incremented each time a new draft is requested. The Compose window observes
    /// this to detect re-targeting when the window is already open.
    var draftVersion: UInt64 = 0

    func requestBlankDraft() {
        pendingTransaction = nil
        shouldOpenBlankDraft = true
        draftVersion &+= 1
    }

    func requestDraft(from transaction: HTTPTransaction) {
        pendingTransaction = transaction
        shouldOpenBlankDraft = false
        draftVersion &+= 1
    }
}
