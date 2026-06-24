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

    var isCompressed: Bool {
        guard let compressedFlag else {
            return false
        }
        return compressedFlag != 0
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
}
