import Foundation
import os

// Saves captured responses as local files for Map Local rule creation.

// MARK: - MapLocalSnapshotService

/// Saves a captured response body as a local file for use with Map Local rules.
/// Files are written to ~/Library/Application Support/com.amunx.rockxy.community/snapshots/.
enum MapLocalSnapshotService {
    // MARK: Internal

    struct SnapshotResult {
        let path: String
        let mimeType: String
    }

    /// Saves the response body to a snapshot file. Returns the file path and inferred MIME type.
    /// Returns nil if the body is nil or empty.
    static func saveSnapshot(
        responseBody: Data?,
        contentType: String?,
        requestURL: URL?
    )
        -> SnapshotResult?
    {
        guard let body = responseBody, !body.isEmpty else {
            return nil
        }

        let ext = MimeTypeResolver.inferExtension(fromContentType: contentType)
            ?? requestURL?.pathExtension.lowercased().nilIfEmpty
            ?? "bin"

        let filename = sanitizeFilename(from: requestURL) + ".\(ext)"
        let directory = snapshotsDirectory()

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(filename)
            try body.write(to: fileURL)

            let mimeType = MimeTypeResolver.mimeType(for: fileURL)
            logger.info("Saved Map Local snapshot: \(fileURL.path)")
            return SnapshotResult(path: fileURL.path, mimeType: mimeType)
        } catch {
            logger.error("Failed to save Map Local snapshot: \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns the expected snapshot path without writing a file. Used for editor preview.
    static func expectedSnapshotPath(
        contentType: String?,
        requestURL: URL?
    )
        -> String
    {
        let ext = MimeTypeResolver.inferExtension(fromContentType: contentType)
            ?? requestURL?.pathExtension.lowercased().nilIfEmpty
            ?? "bin"
        let filename = sanitizeFilename(from: requestURL) + ".\(ext)"
        return snapshotsDirectory().appendingPathComponent(filename).path
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MapLocalSnapshotService")

    private static func snapshotsDirectory() -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
                RockxyIdentity.current.appSupportDirectoryName,
                isDirectory: true
            ).appendingPathComponent("snapshots", isDirectory: true)
        }
        return appSupport
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
    }

    private static func sanitizeFilename(from url: URL?) -> String {
        guard let url else {
            return "snapshot-\(UUID().uuidString.prefix(8))"
        }

        var name = url.lastPathComponent
        if name.isEmpty || name == "/" {
            name = url.host ?? "snapshot"
        }

        let ext = (name as NSString).pathExtension
        if !ext.isEmpty {
            name = (name as NSString).deletingPathExtension
        }

        name = name.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "-", options: .regularExpression)
        if name.isEmpty {
            name = "snapshot"
        }

        let timestamp = Int(Date().timeIntervalSince1970) % 100_000
        return "\(name)-\(timestamp)"
    }
}

// MARK: - String + NilIfEmpty

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
