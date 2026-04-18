import Foundation

/// Protocol providing read-only access to proxy server state for MCP status tools.
/// Adopted by MainContentCoordinator.
@MainActor
protocol MCPProxyStateProvider: AnyObject {
    var isProxyRunning: Bool { get }
    var activeProxyPort: Int { get }
    var isRecording: Bool { get }
    var isSystemProxyConfigured: Bool { get }
    var transactionCount: Int { get }
}
