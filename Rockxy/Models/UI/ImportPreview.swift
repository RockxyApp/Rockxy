import Foundation

// Defines the UI model for imported session preview metadata.

// MARK: - ImportFileType

enum ImportFileType: String {
    case har
    case charlesJSON
    /// A binary Charles session (`.chls`) that Charles converted to HAR.
    case charlesSession
    case rockxysession
}

// MARK: - ImportPreview

/// Metadata about a file selected for import, displayed in the `ImportReviewSheet`
/// before any destructive session replacement occurs.
struct ImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let fileType: ImportFileType
    let transactionCount: Int
    let logEntryCount: Int
    let fileSize: Int64
    let captureStartDate: Date?
    let captureEndDate: Date?
    let rockxyVersion: String?
    let sourceURL: URL
    /// HAR entries that could not be read and would be left out of the import.
    var skippedEntryCount = 0
    /// Private directory holding a converted copy of the file; removed once the
    /// import finishes or is cancelled.
    var temporaryDirectory: URL?
}
