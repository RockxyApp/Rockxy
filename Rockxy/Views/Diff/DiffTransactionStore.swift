import Foundation
import os

/// Shared store for passing transaction pairs to the diff window.
/// The context menu sets the pending pair, opens the diff window, and
/// `DiffWindowView` picks it up on appear.
@MainActor @Observable
final class DiffTransactionStore {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    static let shared = DiffTransactionStore()

    var pendingTransactionA: HTTPTransaction?
    var pendingTransactionB: HTTPTransaction?

    var hasPendingComparison: Bool {
        pendingTransactionA != nil && pendingTransactionB != nil
    }

    func setPending(_ a: HTTPTransaction, _ b: HTTPTransaction) {
        pendingTransactionA = a
        pendingTransactionB = b
    }

    /// A single request chosen for one side of the comparison (Diff ▸ Set Selected as Left/Right).
    /// It waits here until the Diff window picks it up, so a pair can be built one request at a
    /// time while the user browses the list.
    var pendingLeft: HTTPTransaction?
    var pendingRight: HTTPTransaction?

    var hasPendingSide: Bool {
        pendingLeft != nil || pendingRight != nil
    }

    func consumePendingSides() -> (left: HTTPTransaction?, right: HTTPTransaction?) {
        defer {
            pendingLeft = nil
            pendingRight = nil
        }
        return (pendingLeft, pendingRight)
    }

    func consumePending() -> (HTTPTransaction, HTTPTransaction)? {
        guard let a = pendingTransactionA, let b = pendingTransactionB else {
            return nil
        }
        pendingTransactionA = nil
        pendingTransactionB = nil
        return (a, b)
    }
}
