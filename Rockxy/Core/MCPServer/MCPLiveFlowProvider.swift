import Foundation

/// Protocol providing read-only access to live HTTP transactions for MCP tools.
/// Adopted by MainContentCoordinator to bridge live capture state to the MCP backend
/// without creating a direct dependency on view logic.
@MainActor
protocol MCPLiveFlowProvider: AnyObject {
    /// All live transactions in the current session, ordered by capture time.
    var liveTransactions: [HTTPTransaction] { get }

    /// Look up a specific transaction by ID from the live session.
    func liveTransaction(for id: UUID) -> HTTPTransaction?

    /// The number of live transactions currently in memory.
    var liveTransactionCount: Int { get }
}
