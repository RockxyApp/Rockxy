import Foundation

extension MainContentCoordinator {
    func attachToMCPServer(_ mcpCoordinator: MCPServerCoordinator) {
        mcpCoordinator.attachProviders(flow: self, state: self)
    }

    func detachFromMCPServer(_ mcpCoordinator: MCPServerCoordinator) {
        mcpCoordinator.detachProviders()
    }
}
