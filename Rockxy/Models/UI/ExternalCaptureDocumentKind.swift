import Foundation

// Classifies files handed to Rockxy from outside the app (Finder, Dock, drag and drop).

// MARK: - ExternalCaptureDocumentKind

/// Capture documents Rockxy can open from Finder, the Dock, or a drop onto
/// the main window. Classification is by file extension so a HAR saved with
/// a plain `.json` name (as some browsers do) is still accepted. Charles JSON sessions
/// (`.chlsj`) go through the same importer, which recognizes them by content.
enum ExternalCaptureDocumentKind: Equatable {
    case session
    case har

    // MARK: Lifecycle

    init?(url: URL) {
        guard url.isFileURL else {
            return nil
        }
        switch url.pathExtension.lowercased() {
        case "rockxysession":
            self = .session
        case "har",
             "json",
             "chlsj":
            self = .har
        default:
            return nil
        }
    }
}
