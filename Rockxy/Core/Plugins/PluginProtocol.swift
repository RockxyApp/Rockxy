import Foundation

// Plugin protocols define the three extension points in Rockxy's architecture:
// inspectors (custom body viewers), exporters (session output formats),
// and protocol handlers (detection + inspection for non-HTTP protocols like GraphQL/gRPC).

// MARK: - InspectorPlugin

/// Provides custom body inspection for transactions of specific content types.
/// View rendering is handled in the Views layer, not by the plugin itself.
protocol InspectorPlugin {
    var name: String { get }
    var supportedContentTypes: [ContentType] { get }
    func canInspect(transaction: HTTPTransaction) -> Bool
}

extension InspectorPlugin {
    func canInspect(transaction: HTTPTransaction) -> Bool {
        guard let contentType = transaction.response?.contentType else {
            return false
        }
        return supportedContentTypes.contains(contentType)
    }
}

// MARK: - ExporterPlugin

/// Serializes captured transactions into a specific file format (e.g., HAR, cURL, Postman).
protocol ExporterPlugin {
    var name: String { get }
    var fileExtension: String { get }
    func export(transactions: [HTTPTransaction]) throws -> Data
}

// MARK: - ProtocolHandler

/// Detects application-layer protocols tunneled over HTTP
/// (e.g., GraphQL, gRPC-Web, WebSocket subprotocols).
protocol ProtocolHandler {
    var protocolName: String { get }
    func canHandle(request: HTTPRequestData) -> Bool
}
