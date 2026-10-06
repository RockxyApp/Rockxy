import Foundation

extension WebSocketFrameData {
    func protobufHeuristicTree() -> ProtobufDecodedTree? {
        ProtobufHeuristicDecoder.decode(payload)
    }

    func protobufSchemaTree(
        messageType: String,
        schema: ProtobufSchema,
        encoding: ProtobufPayloadEncoding = .auto
    )
        throws -> ProtobufDecodedTree
    {
        try ProtobufSchemaDecoder.decode(payload, messageType: messageType, schema: schema, encoding: encoding)
    }
}
