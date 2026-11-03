import Foundation

/// Named constants for MCP server resource limits and defaults.
enum MCPLimits {
    /// Maximum JSON-RPC request body size (1 MB).
    static let maxRequestBodySize = 1 * 1_024 * 1_024

    /// Maximum response payload size returned to MCP clients (10 MB).
    static let maxResponsePayloadSize = 10 * 1_024 * 1_024

    /// Upper bound on flow results in a single tool call response.
    static let maxFlowResults = 500

    /// Default number of flow results when the client does not specify a limit.
    static let defaultFlowResults = 50

    /// Maximum simultaneous MCP sessions.
    static let maxConcurrentSessions = 10

    /// Idle session expiry interval in seconds.
    static let sessionTimeout: TimeInterval = 30 * 60

    /// Absolute ceiling on a session's life, however actively it is used. Long enough to
    /// cover a working day of agent traffic, short enough that a leaked session id cannot
    /// be refreshed indefinitely. Sits beside `sessionTimeout` because the two together
    /// are the session expiry policy; either one alone leaves a hole.
    static let maxSessionLifetime: TimeInterval = 8 * 60 * 60

    /// NIO-level connection idle timeout in seconds.
    static let connectionIdleTimeout: Int64 = 300

    /// Default TCP port for the MCP server.
    static let defaultPort = 9_710

    /// Maximum body preview size included in tool call responses (1 MB).
    static let maxBodyPreviewSize = 1 * 1_024 * 1_024
    /// Largest captured (wire) body that is decompressed before a preview is built.
    static let maxDecodedBodyBytes = 4 * 1_024 * 1_024
}
