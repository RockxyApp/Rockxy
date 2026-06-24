import Foundation

/// Normalized content type categories derived from the `Content-Type` header.
/// Used to select the appropriate body renderer (JSON tree, image preview, hex dump, etc.)
/// and to power content-type-based protocol filters.
enum ContentType: String, Sendable {
    case json
    case xml
    case html
    case image
    case form
    case multipartForm
    case protobuf
    case binary
    case text
    case unknown

    // MARK: Internal

    static func detect(from header: String?) -> ContentType {
        guard let header else {
            return .unknown
        }

        let mediaType = header
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? header.lowercased()

        if mediaType == "application/json" || mediaType.hasSuffix("+json") {
            return .json
        }
        if mediaType == "text/xml" || mediaType == "application/xml" || mediaType.hasSuffix("+xml") {
            return .xml
        }
        if mediaType == "text/html" {
            return .html
        }
        if mediaType.hasPrefix("image/") {
            return .image
        }
        if mediaType == "application/x-www-form-urlencoded" {
            return .form
        }
        if mediaType == "multipart/form-data" {
            return .multipartForm
        }
        if mediaType == "application/grpc"
            || mediaType.hasPrefix("application/grpc+")
            || mediaType == "application/grpc-web"
            || mediaType.hasPrefix("application/grpc-web+")
            || mediaType == "application/protobuf"
            || mediaType == "application/x-protobuf"
            || mediaType.hasSuffix("+proto")
        {
            return .protobuf
        }
        if mediaType.hasPrefix("text/") {
            return .text
        }
        return .unknown
    }
}
