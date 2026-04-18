import Foundation

// MARK: - MainContentCoordinator + MCPLiveFlowProvider

// Adopts MCP provider protocols to bridge live capture state to the MCP backend.

extension MainContentCoordinator: MCPLiveFlowProvider {
    var liveTransactions: [HTTPTransaction] {
        transactions
    }

    func liveTransaction(for id: UUID) -> HTTPTransaction? {
        transactions.first { $0.id == id }
    }

    var liveTransactionCount: Int {
        transactions.count
    }
}

// MARK: - MainContentCoordinator + MCPProxyStateProvider

extension MainContentCoordinator: MCPProxyStateProvider {
    var transactionCount: Int {
        transactions.count
    }
}
