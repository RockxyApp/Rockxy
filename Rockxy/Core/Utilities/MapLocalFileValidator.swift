import Foundation
import os

/// Validates and loads file content for Map Local rules.
/// Prevents path traversal, symlink abuse, and oversized file reads.
/// Uses fd-based approach to eliminate TOCTOU race between stat and read.
enum MapLocalFileValidator {
    // MARK: Internal

    /// Loads a Map Local file off the caller's thread and reports the result through
    /// `completion`, which runs on the Map Local file-I/O queue. The proxy handlers call this
    /// from a NIO event loop, where the synchronous variant below blocked every connection
    /// multiplexed onto that loop — including the channel closes a proxy stop depends on.
    static func loadFileData(at filePath: String, completion: @escaping @Sendable (Data?) -> Void) {
        MapLocalFileIO.perform {
            completion(loadFileData(at: filePath))
        }
    }

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

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "MapLocalFileValidator"
    )

    /// Maximum file size allowed for Map Local responses (10 MB).
    private static let maxFileSize: UInt64 = 10 * 1_024 * 1_024
}

// MARK: - MapLocalFileIO

/// Queue for the blocking filesystem work behind Map Local. A target on a stale network mount
/// or a spun-down external disk blocks in the kernel with no deadline, and the 10 MB cap bounds
/// the bytes read but not the wait, so that work must never run on a NIO event loop.
///
/// Serial on purpose: a hung mount then stalls only later Map Local reads instead of growing one
/// blocked thread per captured request.
enum MapLocalFileIO {
    // MARK: Internal

    static func perform(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    // MARK: Private

    private static let queue = DispatchQueue(
        label: "\(RockxyIdentity.current.logSubsystem).map-local-file-io",
        qos: .userInitiated
    )
}
