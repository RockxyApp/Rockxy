import Foundation
import os

/// Persists proxy rules as a JSON file in Application Support.
/// Each save overwrites the entire file — rules are small enough
/// that atomic writes are simpler than incremental updates.
struct RuleStore {
    // MARK: Lifecycle

    init() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            Self.logger.error("Application Support directory not found, using temporary directory")
            let tempDir = RockxyIdentity.current.temporaryAppSupportDirectory()
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            fileURL = tempDir.appendingPathComponent("rules.json")
            return
        }
        fileURL = appSupport
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("rules.json")
    }

    // MARK: Internal

    // MARK: - Errors

    enum RuleStoreError: LocalizedError {
        case importFileTooLarge(UInt64)
        case invalidRegexInImport(pattern: String, reason: String)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case let .importFileTooLarge(size):
                "Import file is too large (\(size / 1024 / 1024) MB). Maximum allowed is 5 MB."
            case let .invalidRegexInImport(pattern, reason):
                "Invalid regex pattern '\(pattern)': \(reason)"
            }
        }
    }

    func loadRules() throws -> [ProxyRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([ProxyRule].self, from: data)
    }

    func saveRules(_ rules: [ProxyRule]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(rules)
        try data.write(to: fileURL)
        Self.logger.info("Saved \(rules.count) rules")
    }

    func exportRules(to url: URL) throws {
        let data = try JSONEncoder().encode(loadRules())
        try data.write(to: url, options: .atomic)
    }

    func importRules(from url: URL) throws -> [ProxyRule] {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = attrs[.size] as? UInt64, fileSize > Self.maxImportSize {
            throw RuleStoreError.importFileTooLarge(fileSize)
        }
        let data = try Data(contentsOf: url)
        let rules = try JSONDecoder().decode([ProxyRule].self, from: data)
        for rule in rules {
            if let pattern = rule.matchCondition.urlPattern {
                if case let .failure(error) = RegexValidator.compile(pattern) {
                    throw RuleStoreError.invalidRegexInImport(pattern: pattern, reason: error.localizedDescription)
                }
            }
        }
        return rules
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "RuleStore")

    /// Maximum import file size: 5 MB.
    private static let maxImportSize: UInt64 = 5 * 1024 * 1024

    private let fileURL: URL
}
