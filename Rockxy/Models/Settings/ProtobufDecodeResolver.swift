import Foundation

// MARK: - ProtobufPayloadDirection

/// Which side produced a payload. WebSocket client frames use the request type, server
/// frames the response type, matching the mapping editor's Request/Response fields.
enum ProtobufPayloadDirection: Equatable, Sendable {
    case request
    case response
}

// MARK: - ProtobufDecodeChoice

/// How a payload should be decoded: a message type from imported schemas, or best guess.
enum ProtobufDecodeChoice: Hashable {
    case bestGuess
    case messageType(String, encoding: ProtobufPayloadEncoding)

    // MARK: Internal

    var messageType: String? {
        if case let .messageType(name, _) = self {
            return name
        }
        return nil
    }
}

// MARK: - ProtobufDecodeResolver

/// Picks the message type for a payload automatically: an enabled Protobuf mapping definition
/// whose URL pattern and method match wins; otherwise a gRPC request path is looked up in the
/// services of the imported schemas.
@MainActor
enum ProtobufDecodeResolver {
    static func automaticChoice(
        url: URL?,
        method: String?,
        direction: ProtobufPayloadDirection,
        rules: [ProtobufMappingRule]? = nil,
        schema: ProtobufSchema? = nil
    )
        -> ProtobufDecodeChoice
    {
        let rules = rules ?? ProtobufMappingRuleStore.shared.rules
        if let url, let rule = matchingRule(url: url, method: method, rules: rules) {
            let specific = direction == .request ? rule.requestMessageType : rule.responseMessageType
            let name = [specific, rule.messageType]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if let name {
                return .messageType(name, encoding: rule.payloadEncoding)
            }
        }
        let schema = schema ?? ProtobufSchemaStore.shared.combinedSchema()
        if let path = url?.path, let grpc = schema.method(forGRPCPath: path) {
            return .messageType(direction == .request ? grpc.inputType : grpc.outputType, encoding: .singleMessage)
        }
        return .bestGuess
    }

    static func matchingRule(url: URL, method: String?, rules: [ProtobufMappingRule]) -> ProtobufMappingRule? {
        let urlString = url.absoluteString
        return rules.first { rule in
            guard rule.isEnabled else {
                return false
            }
            if let required = rule.method.methodValue,
               method?.caseInsensitiveCompare(required) != .orderedSame
            {
                return false
            }
            let pattern = rule.urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty,
                  case let .success(regex) = RegexValidator.compile(RulePatternBuilder.regexSource(
                      rawPattern: pattern,
                      matchType: rule.matchType,
                      includeSubpaths: rule.includeSubpaths
                  )) else
            {
                return false
            }
            let range = NSRange(urlString.startIndex ..< urlString.endIndex, in: urlString)
            return regex.firstMatch(in: urlString, range: range) != nil
        }
    }

    /// Decodes with the chosen type, or best guess. Safe to call off the main actor.
    nonisolated static func decode(
        _ data: Data,
        choice: ProtobufDecodeChoice,
        schema: ProtobufSchema
    )
        -> Result<ProtobufDecodedTree, Error>
    {
        switch choice {
        case .bestGuess:
            guard let tree = ProtobufHeuristicDecoder.decode(data), !tree.fields.isEmpty else {
                return .failure(ProtobufBestGuessError.notProtobuf)
            }
            return .success(tree)
        case let .messageType(name, encoding):
            return Result {
                try ProtobufSchemaDecoder.decode(data, messageType: name, schema: schema, encoding: encoding)
            }
        }
    }
}

// MARK: - ProtobufBestGuessError

enum ProtobufBestGuessError: LocalizedError {
    case notProtobuf

    // MARK: Internal

    var errorDescription: String? {
        String(
            localized: "This payload does not look like valid Protobuf wire format.",
            bundle: RockxyLocalization.bundle
        )
    }
}
