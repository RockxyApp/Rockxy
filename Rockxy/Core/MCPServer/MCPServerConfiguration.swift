import Foundation

/// Configuration for the MCP Streamable HTTP server.
struct MCPServerConfiguration {
    // MARK: Lifecycle

    init(
        port: Int = MCPLimits.defaultPort,
        listenAddress: String = "127.0.0.1",
        allowedOrigins: Set<String> = ["localhost", "127.0.0.1"]
    ) {
        self.port = port
        self.listenAddress = listenAddress
        self.allowedOrigins = allowedOrigins
    }

    // MARK: Internal

    static let `default` = MCPServerConfiguration()

    /// TCP port. Defaults to `MCPLimits.defaultPort` (9710).
    let port: Int

    /// Bind address — always loopback for security.
    let listenAddress: String

    /// Origins permitted to connect. Validated against the HTTP `Origin` header.
    let allowedOrigins: Set<String>
}
