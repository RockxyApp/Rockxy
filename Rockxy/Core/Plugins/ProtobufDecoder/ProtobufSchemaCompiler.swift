import Foundation

// MARK: - ProtobufSchemaCompiler

/// Chooses the parser for an imported schema file by its extension.
nonisolated enum ProtobufSchemaCompiler {
    static func isDescriptorSet(fileName: String) -> Bool {
        ProtobufDescriptorSetParser.fileExtensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    static func isSupported(fileName: String) -> Bool {
        isDescriptorSet(fileName: fileName) || (fileName as NSString).pathExtension.lowercased() == "proto"
    }

    static func compile(_ data: Data, fileName: String) throws -> ProtobufSchema {
        if isDescriptorSet(fileName: fileName) {
            return try ProtobufDescriptorSetParser.parse(data)
        }
        guard let source = String(data: data, encoding: .utf8) else {
            throw ProtobufSchemaImportError.invalidEncoding
        }
        return try ProtobufSourceParser.parse(source)
    }
}
