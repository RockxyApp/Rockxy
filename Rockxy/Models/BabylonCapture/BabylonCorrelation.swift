import Foundation

/// The Babylon runtime session, trace, and step a captured request was made in, as reported by
/// the app with that request.
///
/// It is stored on the transaction when the request arrives and saved with the session, so a
/// reloaded or imported session links to the same trace instead of guessing from timestamps.
struct BabylonCorrelation: Codable, Equatable, Hashable, Sendable {
    // MARK: Lifecycle

    init(sourceClientID: String? = nil, sessionID: String, traceID: String, stepID: String?) {
        self.sourceClientID = sourceClientID
        self.sessionID = sessionID
        self.traceID = traceID
        self.stepID = stepID
    }

    /// Returns `nil` unless every identifier is a usable, bounded identifier. An empty step
    /// means the request was made in the trace but outside any step.
    init?(context: BabylonTrafficPackageDTO.CorrelationContext?, sourceClientID: String? = nil) {
        guard let context,
              sourceClientID.map({ Self.isValidSourceIdentifier($0) }) ?? true,
              Self.isValidIdentifier(context.sessionID),
              Self.isValidIdentifier(context.traceID) else
        {
            return nil
        }
        let step = context.stepID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard step.isEmpty || Self.isValidIdentifier(context.stepID) else {
            return nil
        }
        self.init(
            sourceClientID: sourceClientID,
            sessionID: context.sessionID,
            traceID: context.traceID,
            stepID: step.isEmpty ? nil : context.stepID
        )
    }

    /// Decoding applies the same rules as `init?(context:)` so a correlation that arrives through
    /// an imported session or a nearby transfer is storable exactly when a captured one is. Size
    /// is checked against the frozen stored bound, not the ingress bound: a record an earlier
    /// build saved with a 257-512 byte identifier must keep loading. A correlation that fails
    /// throws; the caller decodes it with `try?`, so the request survives without its trace link.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decodeIfPresent(String.self, forKey: .sourceClientID)
        let session = try container.decode(String.self, forKey: .sessionID)
        let trace = try container.decode(String.self, forKey: .traceID)
        let step = try container.decodeIfPresent(String.self, forKey: .stepID)
        let limit = BabylonCaptureProtocol.maximumStoredIdentifierSize
        guard source.map({ Self.isValidSourceIdentifier($0, limit: limit) }) ?? true,
              Self.isValidIdentifier(session, limit: limit),
              Self.isValidIdentifier(trace, limit: limit),
              step.map({ Self.isValidIdentifier($0, limit: limit) }) ?? true else
        {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid Babylon correlation identifier")
            )
        }
        self.init(sourceClientID: source, sessionID: session, traceID: trace, stepID: step)
    }

    // MARK: Internal

    let sourceClientID: String?
    let sessionID: String
    let traceID: String
    let stepID: String?

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case sourceClientID
        case sessionID
        case traceID
        case stepID
    }

    private static func isValidIdentifier(
        _ value: String,
        limit: Int = BabylonCaptureProtocol.maximumCorrelationIdentifierSize
    )
        -> Bool
    {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= limit
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            && !value.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isValidSourceIdentifier(
        _ value: String,
        limit: Int = BabylonRuntimeEvent.maximumIdentifierByteCount
    )
        -> Bool
    {
        !value.isEmpty
            && value.utf8.count <= limit
            && !value.contains(":")
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}
