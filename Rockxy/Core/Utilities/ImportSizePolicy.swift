import Foundation
import os

// Validates imported files against the app's session size limits.

// MARK: - ImportSizePolicy

enum ImportSizePolicy {
    // MARK: Internal

    // Conservative MVP safety bounds to prevent OOM/hangs from accidental huge-file imports.
    // Not permanent product limits — values can be tuned based on real-world usage.
    static let maxHARFileSize: UInt64 = 100 * 1024 * 1024 // 100 MB
    static let maxSessionFileSize: UInt64 = 200 * 1024 * 1024 // 200 MB

    static func validateFileSize(at url: URL, maxSize: UInt64) -> Result<Void, ImportSizeError> {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let fileSize = attributes[.size] as? UInt64 else {
                return .success(())
            }
            if fileSize > maxSize {
                let sizeMB = Double(fileSize) / (1024 * 1024)
                let limitMB = Double(maxSize) / (1024 * 1024)
                logger.warning(
                    "File too large: \(sizeMB, format: .fixed(precision: 1)) MB (limit: \(limitMB, format: .fixed(precision: 0)) MB)"
                )
                return .failure(.fileTooLarge(
                    actualBytes: fileSize,
                    limitBytes: maxSize
                ))
            }
            return .success(())
        } catch {
            logger.error("Failed to check file size: \(error.localizedDescription)")
            return .failure(.attributeError(error))
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ImportSizePolicy")
}

// MARK: - ImportSizeError

enum ImportSizeError: Error, LocalizedError {
    case fileTooLarge(actualBytes: UInt64, limitBytes: UInt64)
    case attributeError(Error)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .fileTooLarge(actual, limit):
            let actualMB = Double(actual) / (1024 * 1024)
            let limitMB = Double(limit) / (1024 * 1024)
            return String(
                localized: "File is too large (\(String(format: "%.1f", actualMB)) MB). Maximum supported size is \(String(format: "%.0f", limitMB)) MB."
            )
        case let .attributeError(error):
            return String(localized: "Could not read file: \(error.localizedDescription)")
        }
    }
}
