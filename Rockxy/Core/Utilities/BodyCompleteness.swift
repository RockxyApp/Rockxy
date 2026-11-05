import Foundation

// Decides how completely a captured body can be trusted, and the words every surface uses
// to say so. "Known truncated" and "completeness unknown" are different claims: the first
// says bytes were cut, the second says only that the evidence needed to know was lost.

enum BodyCompleteness: Equatable, Sendable {
    /// Nothing recorded against the body.
    case complete
    /// Capture cut or omitted bytes; the recorded metadata says so.
    case knownTruncated
    /// A saved session's capture evidence could not be read, so the body may or may not be whole.
    case unknown

    // MARK: Lifecycle

    init(truncated: Bool, omission: BodyOmissionMetadata?) {
        if omission?.reason == SessionStore.unreadableEvidenceOmissionReason {
            self = .unknown
        } else if truncated || omission != nil {
            self = .knownTruncated
        } else {
            self = .complete
        }
    }

    init(_ request: HTTPRequestData) {
        self.init(truncated: request.bodyTruncated, omission: request.bodyOmission)
    }

    init(_ response: HTTPResponseData) {
        self.init(truncated: response.bodyTruncated, omission: response.bodyOmission)
    }

    // MARK: Internal

    var isUnknown: Bool {
        self == .unknown
    }

    /// Suffix for a connection-log body line. Empty when the body needs no note.
    var logNote: String {
        switch self {
        case .complete:
            ""
        case .knownTruncated:
            " (only the first part was kept)"
        case .unknown:
            " (may be incomplete: saved capture evidence could not be read)"
        }
    }

    /// Human wording for an omission reason. Known reasons keep their raw text.
    static func reasonDescription(_ reason: String) -> String {
        if reason == SessionStore.unreadableEvidenceOmissionReason {
            return String(
                localized: "Restored from a saved session whose capture evidence could not be read",
                bundle: RockxyLocalization.bundle
            )
        }
        return reason
    }

    static func detailsTitle(forRequest isRequest: Bool, completeness: BodyCompleteness) -> String {
        switch (completeness, isRequest) {
        case (.unknown, true):
            String(localized: "Request body may be incomplete", bundle: RockxyLocalization.bundle)
        case (.unknown, false):
            String(localized: "Response body may be incomplete", bundle: RockxyLocalization.bundle)
        case (_, true):
            String(
                localized: "Request body was omitted or truncated during capture",
                bundle: RockxyLocalization.bundle
            )
        case (_, false):
            String(
                localized: "Response body was omitted or truncated during capture",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    /// One-line note placed ahead of copied or exported text, only for unknown completeness.
    /// Known truncation deliberately adds nothing so existing output is unchanged.
    static func exportNote(request: BodyCompleteness, response: BodyCompleteness?) -> String? {
        let subject: String
        switch (request.isUnknown, response?.isUnknown == true) {
        case (true, true):
            subject = "the request and response bodies"
        case (true, false):
            subject = "the request body"
        case (false, true):
            subject = "the response body"
        case (false, false):
            return nil
        }
        return "Rockxy: \(subject) may be incomplete "
            + "(restored from a saved session whose capture evidence could not be read)."
    }
}
