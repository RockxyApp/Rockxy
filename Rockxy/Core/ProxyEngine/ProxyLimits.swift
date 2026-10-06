import Foundation

/// Central constants for proxy engine security limits.
enum ProxyLimits {
    /// Maximum HTTP request body size before rejection (100 MB).
    static let maxRequestBodySize = 100 * 1_024 * 1_024

    /// Maximum single WebSocket frame payload (10 MB).
    static let maxWebSocketFrameSize = 10 * 1_024 * 1_024

    /// Maximum total WebSocket payload per connection (100 MB).
    static let maxWebSocketConnectionSize = 100 * 1_024 * 1_024

    /// Maximum captured frames retained for one WebSocket connection. This count cap
    /// complements the byte cap so empty-frame floods cannot grow memory without bound.
    static let maxWebSocketFrameCount = 100_000

    /// Maximum HTTP response body size retained for capture/inspection (100 MB).
    /// Bodies exceeding this limit are truncated in the capture buffer while the full
    /// response continues to relay to the client.
    static let maxResponseBodySize = 100 * 1_024 * 1_024

    /// Maximum URI length accepted from clients (8 KB).
    static let maxURILength = 8_192

    /// Maximum upstream proxy handshake response head (16 KB).
    static let maxUpstreamHandshakeResponseSize = 16_384

    /// Maximum nested Protobuf heuristic decode depth.
    static let maxProtobufDecodeDepth = 32

    /// Maximum total Protobuf heuristic decode nodes.
    static let maxProtobufDecodeNodes = 10_000

    /// Maximum nesting of message types inside an uploaded schema (`.proto` source or descriptor set).
    static let maxProtobufSchemaNesting = 32

    /// Maximum uploaded .proto schema file size (1 MB).
    static let maxProtobufSchemaFileSize = 1 * 1_024 * 1_024
}

struct RequestBodyLimitState {
    private(set) var isRejected = false

    mutating func reset() {
        accumulatedBytes = 0
        isRejected = false
    }

    mutating func accept(
        _ byteCount: Int,
        maximum: Int = ProxyLimits.maxRequestBodySize
    )
        -> Bool
    {
        guard !isRejected,
              byteCount >= 0,
              byteCount <= maximum,
              accumulatedBytes <= maximum - byteCount else
        {
            isRejected = true
            return false
        }
        accumulatedBytes += byteCount
        return true
    }

    private var accumulatedBytes = 0
}
