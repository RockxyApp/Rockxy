import Foundation
import os

// Persists Compose history snapshots outside the active window lifecycle.

// MARK: - ComposeHistoryStore

/// Disk-backed storage for Compose history.
///
/// Request history can contain sensitive payloads. The live in-memory history keeps
/// exact request headers so same-session restore is lossless, but persisted entries
/// redact Authorization/Cookie-style headers before the JSON file is written.
final class ComposeHistoryStore {
    // MARK: Lifecycle

    init(
        fileURL: URL? = nil,
        maxEntries: Int = ComposeHistoryStore.defaultMaxEntries,
        bodySizeLimit: Int = ComposeHistoryStore.defaultBodySizeLimit,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.maxEntries = maxEntries
        self.bodySizeLimit = bodySizeLimit
        self.fileManager = fileManager
    }

    // MARK: Internal

    static var live: ComposeHistoryStore {
        ComposeHistoryStore()
    }
    static let defaultMaxEntries = 200
    static let defaultBodySizeLimit = 256 * 1_024

    let maxEntries: Int
    let bodySizeLimit: Int

    func load() -> [ComposeHistoryEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([ComposeHistoryEntry].self, from: data)
        } catch {
            Self.logger.error("Failed to load compose history: \(error.localizedDescription)")
            return []
        }
    }

    func save(_ entries: [ComposeHistoryEntry]) throws {
        let cappedEntries = Array(entries.prefix(maxEntries)).map(entryForPersistence)
        let data = try encoder.encode(cappedEntries)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ComposeHistoryStore")
    private static let sensitiveHeaderNames: Set<String> = [
        "authorization",
        "cookie",
        "proxy-authorization",
        "set-cookie",
    ]

    private let fileURL: URL
    private let fileManager: FileManager

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    private static func defaultFileURL() -> URL {
        if RockxyIdentity.isRunningTests {
            return RockxyIdentity.current.appSupportPath("compose-history-\(UUID().uuidString).json")
        }
        return RockxyIdentity.current.appSupportPath("compose-history.json")
    }

    private func entryForPersistence(_ entry: ComposeHistoryEntry) -> ComposeHistoryEntry {
        let bodySnapshot = capped(entry.body)
        let responseSnapshot = entry.responseBody.map(capped)
        return ComposeHistoryEntry(
            id: entry.id,
            method: entry.method,
            url: entry.url,
            headers: redacted(entry.headers),
            queryItems: entry.queryItems,
            body: bodySnapshot.value,
            bodyContentType: entry.bodyContentType,
            statusCode: entry.statusCode,
            responseHeaders: entry.responseHeaders.map(redacted),
            responseBody: responseSnapshot?.value,
            bodyTruncated: entry.bodyTruncated || bodySnapshot.truncated,
            responseBodyTruncated: entry.responseBodyTruncated || (responseSnapshot?.truncated ?? false),
            timestamp: entry.timestamp
        )
    }

    private func redacted(_ headers: [EditableReplayHeader]) -> [EditableReplayHeader] {
        headers.map { header in
            guard Self.sensitiveHeaderNames.contains(header.name.lowercased()) else {
                return header
            }
            return EditableReplayHeader(
                id: header.id,
                name: header.name,
                value: String(localized: "<redacted before saving>"),
                isEnabled: header.isEnabled
            )
        }
    }

    private func capped(_ text: String) -> (value: String, truncated: Bool) {
        guard text.utf8.count > bodySizeLimit else {
            return (text, false)
        }
        var result = ""
        var byteCount = 0
        for character in text {
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= bodySizeLimit else {
                break
            }
            result.append(character)
            byteCount += characterByteCount
        }
        return (result, true)
    }
}
