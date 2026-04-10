import Foundation

/// Central constants for proxy engine security limits.
enum ProxyLimits {
    /// Maximum HTTP request body size before rejection (100 MB).
    static let maxRequestBodySize = 100 * 1_024 * 1_024

    /// Maximum single WebSocket frame payload (10 MB).
    static let maxWebSocketFrameSize = 10 * 1_024 * 1_024

    /// Maximum total WebSocket payload per connection (100 MB).
    static let maxWebSocketConnectionSize = 100 * 1_024 * 1_024

    /// Maximum HTTP response body size retained for capture/inspection (100 MB).
    /// Bodies exceeding this limit are truncated in the capture buffer while the full
    /// response continues to relay to the client.
    static let maxResponseBodySize = 100 * 1_024 * 1_024

    /// Maximum URI length accepted from clients (8 KB).
    static let maxURILength = 8_192
}
