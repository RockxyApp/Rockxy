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

// MARK: - MCPCaptureControlProvider

/// Capture-side changes an MCP client may request once the user allows changes. The main
/// workspace implements it with the same code paths its menus and context menus use.
@MainActor
protocol MCPCaptureControlProvider: AnyObject {
    func mcpEnableHTTPSDecryption(for domain: String) -> MCPDecryptionChange
    /// Returns false when the proxy is not running, because recording only applies to a live listener.
    func mcpSetRecording(_ isRecording: Bool) -> Bool
    func mcpClearSession() async
}

// MARK: - MCPDecryptionChange

enum MCPDecryptionChange: Equatable {
    case enabled(domain: String)
    case alreadyEnabled(domain: String)
    case refused(reason: String)
}
