import Foundation

// MARK: - GRPCInspection

/// Derived gRPC inspection model for HTTP transactions. This is intentionally computed
/// from captured request/response data so first-class inspection does not require a
/// persistence migration while schema-backed decoding remains an explicit future seam.
struct GRPCInspection: Equatable, Sendable {
    let serviceName: String?
    let methodName: String?
    let fullMethodPath: String?
    let requestContentType: String?
    let responseContentType: String?
    let requestEncoding: String?
    let responseEncoding: String?
    let httpStatusCode: Int?
    let httpStatusMessage: String?
    let grpcStatus: String?
    let grpcMessage: String?
    let grpcStatusDetails: String?
    let duration: TimeInterval?
    let requestFrames: [GRPCMessageFrame]
    let responseFrames: [GRPCMessageFrame]
    /// `grpc-timeout` as sent by the client (for example `5S` or `250m`).
    var timeout: String?
    /// Custom metadata the client sent, without transport and gRPC protocol headers.
    var requestMetadata: [HTTPHeader] = []
    /// Custom metadata the server returned in headers or trailers, without status fields.
    var responseMetadata: [HTTPHeader] = []

    var frames: [GRPCMessageFrame] {
        requestFrames + responseFrames
    }
}

// MARK: - GRPCMessageFrame

struct GRPCMessageFrame: Identifiable, Equatable, Sendable {
    let id: String
    let direction: GRPCMessageDirection
    let index: Int
    let offset: Int
    let compressedFlag: UInt8?
    let declaredLength: Int?
    let payload: Data
    let status: GRPCFrameParseStatus
    let heuristicTree: ProtobufDecodedTree?
    /// Fields carried by a gRPC-Web trailer frame; empty for message frames.
    var trailers: [HTTPHeader] = []

    var isCompressed: Bool {
        guard let compressedFlag, status != .trailers else {
            return false
        }
        return compressedFlag & 0x01 != 0
    }
}

// MARK: - GRPCMessageDirection

enum GRPCMessageDirection: String, Equatable, Sendable {
    case request
    case response
}

// MARK: - GRPCFrameParseStatus

enum GRPCFrameParseStatus: Equatable, Sendable {
    case complete
    case incompleteHeader(remainingBytes: Int)
    case truncatedPayload(expectedBytes: Int, actualBytes: Int)
    case unsupportedCompressionFlag(UInt8)
    /// A gRPC-Web trailer frame (flag bit `0x80`), which carries status and trailing metadata.
    case trailers
}
