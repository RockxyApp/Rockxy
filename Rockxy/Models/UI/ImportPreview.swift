import Foundation

// Defines the UI model for imported session preview metadata.

// MARK: - ImportFileType

enum ImportFileType: String {
    case har
    case charlesJSON
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
}
