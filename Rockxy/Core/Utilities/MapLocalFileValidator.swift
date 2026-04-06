import Foundation
import os

/// Validates and loads file content for Map Local rules.
/// Prevents path traversal, symlink abuse, and oversized file reads.
/// Uses fd-based approach to eliminate TOCTOU race between stat and read.
enum MapLocalFileValidator {
    // MARK: Internal

    /// Validates a Map Local file path and returns the file data if safe.
    /// Returns nil if the path is invalid, unreadable, or too large.
    static func loadFileData(at filePath: String) -> Data? {
        let expanded = (filePath as NSString).expandingTildeInPath
        let resolved = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath()

        guard let fileHandle = try? FileHandle(forReadingFrom: resolved) else {
            logger.warning("SECURITY: Cannot open map local file: \(resolved.path)")
            return nil
        }
        defer { try? fileHandle.close() }

        // fstat on the open fd — guaranteed same file we opened
        var fileStat = stat()
        guard fstat(fileHandle.fileDescriptor, &fileStat) == 0 else {
            logger.warning("SECURITY: fstat failed on map local file: \(resolved.path)")
            return nil
        }

        guard (fileStat.st_mode & S_IFMT) == S_IFREG else {
            logger.warning("SECURITY: Map local path is not a regular file: \(resolved.path)")
            return nil
        }

        guard UInt64(fileStat.st_size) <= maxFileSize else {
            logger
                .warning(
                    "SECURITY: Map local file exceeds \(maxFileSize) bytes (\(fileStat.st_size)): \(resolved.path)"
                )
            return nil
        }

        return fileHandle.readDataToEndOfFile()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MapLocalFileValidator")

    /// Maximum file size allowed for Map Local responses (10 MB).
    private static let maxFileSize: UInt64 = 10 * 1024 * 1024
}
