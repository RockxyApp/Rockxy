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
              sourceClientID.map(Self.isValidSourceIdentifier) ?? true,
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

    // MARK: Internal

    let sourceClientID: String?
    let sessionID: String
    let traceID: String
    let stepID: String?

    // MARK: Private

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= BabylonCaptureProtocol.maximumClientIDSize
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            && !value.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isValidSourceIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= BabylonRuntimeEvent.maximumIdentifierByteCount
            && !value.contains(":")
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}
