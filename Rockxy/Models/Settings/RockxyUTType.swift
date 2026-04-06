import UniformTypeIdentifiers

// Declares the Uniform Type Identifiers for Rockxy session and HAR files.

extension UTType {
    /// Native Rockxy session file format (`.rockxysession`).
    /// Conforms to `public.json` since the underlying format is JSON.
    static let rockxySession = UTType(
        exportedAs: RockxyIdentity.current.sessionUTTypeIdentifier,
        conformingTo: .json
    )

    /// HTTP Archive format (`.har`).
    /// Conforms to `public.json` since HAR files are JSON documents.
    static let har = UTType(
        importedAs: RockxyIdentity.current.harUTTypeIdentifier,
        conformingTo: .json
    )
}
