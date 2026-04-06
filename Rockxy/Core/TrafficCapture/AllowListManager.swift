import Foundation
import os

// Defines `AllowListManager`, which coordinates allow list behavior in traffic capture and
// system proxy coordination.

// MARK: - AllowListManager

/// Manages the Allow List — a capture-level filter that restricts which traffic
/// is recorded in the session. When active, only traffic matching enabled entries
/// appears in the UI. Non-matching traffic is still proxied (forwarded) but not
/// displayed or stored.
///
/// The `isHostAllowed(_:)` method is `nonisolated` and thread-safe so it can be
/// called directly from NIO event loops without hopping to the main actor.
@MainActor @Observable
final class AllowListManager {
    // MARK: Lifecycle

    private init() {
        storageURLOverride = nil
        cachedEnabledEntries = []
        cachedIsActive = false
        load()
    }

    /// Test-only initializer with isolated storage path.
    init(storageURL: URL) {
        storageURLOverride = storageURL
        cachedEnabledEntries = []
        cachedIsActive = false
        load()
    }

    // MARK: Internal

    static let shared = AllowListManager()

    /// Master toggle. When false, all traffic passes through (allow list is ignored).
    /// When true, only hosts matching enabled entries are captured.
    var isActive: Bool = false {
        didSet {
            rebuildCache()
            save()
            postChangeNotification()
        }
    }

    private(set) var entries: [AllowListEntry] = [] {
        didSet {
            rebuildCache()
        }
    }

    func addEntry(_ domainString: String) {
        let trimmed = domainString.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            return
        }

        guard !entries.contains(where: { $0.domain.lowercased() == trimmed }) else {
            Self.logger.debug("Allow list entry already exists: \(trimmed)")
            return
        }

        entries.append(AllowListEntry(domain: trimmed))
        save()
        postChangeNotification()
        Self.logger.info("Added allow list entry: \(trimmed)")
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
        postChangeNotification()
    }

    func removeEntries(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
        postChangeNotification()
    }

    func toggleEntry(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        entries[index].isEnabled.toggle()
        save()
        postChangeNotification()
    }

    /// Thread-safe check usable from NIO event loops.
    /// Returns `true` if the host should be captured (recorded in session).
    ///
    /// - When allow list is inactive: always returns `true` (all traffic captured).
    /// - When allow list is active: returns `true` only if host matches an enabled entry.
    nonisolated func isHostAllowed(_ host: String) -> Bool {
        let snapshot: [AllowListEntry]
        let active: Bool
        lock.lock()
        snapshot = cachedEnabledEntries
        active = cachedIsActive
        lock.unlock()

        guard active else {
            return true
        }
        return snapshot.contains { $0.matches(host) }
    }

    func load() {
        let url = resolvedStorageURL
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let container = try JSONDecoder().decode(AllowListStorage.self, from: data)
                isActive = container.isActive
                entries = container.entries
                Self.logger.info("Loaded \(self.entries.count) allow list entries (active: \(self.isActive))")
            } catch {
                Self.logger.error("Failed to load allow list: \(error.localizedDescription)")
            }
        } else {
            Self.logger.info("No allow list file found, starting with empty list")
        }
    }

    func save() {
        let url = resolvedStorageURL
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let container = AllowListStorage(isActive: isActive, entries: entries)
            let data = try JSONEncoder().encode(container)
            try data.write(to: url, options: .atomic)
            Self.logger.debug("Saved \(self.entries.count) allow list entries")
        } catch {
            Self.logger.error("Failed to save allow list: \(error.localizedDescription)")
        }
    }

    func exportEntries() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let container = AllowListStorage(isActive: isActive, entries: entries)
        return try? encoder.encode(container)
    }

    func importEntries(from data: Data) throws {
        let container = try JSONDecoder().decode(AllowListStorage.self, from: data)
        isActive = container.isActive
        entries = container.entries
        save()
        postChangeNotification()
        Self.logger.info("Imported \(container.entries.count) allow list entries")
    }

    /// Check whether a specific domain is in the allow list (regardless of active state).
    func containsDomain(_ domain: String) -> Bool {
        entries.contains { $0.matches(domain) }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "AllowListManager")

    private static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("allow-list.json")
    }

    private let storageURLOverride: URL?

    private let lock = NSLock()
    private nonisolated(unsafe) var cachedEnabledEntries: [AllowListEntry]
    private nonisolated(unsafe) var cachedIsActive: Bool

    private var resolvedStorageURL: URL {
        storageURLOverride ?? Self.defaultStorageURL
    }

    private func rebuildCache() {
        let enabled = entries.filter(\.isEnabled)
        let active = isActive
        lock.lock()
        cachedEnabledEntries = enabled
        cachedIsActive = active
        lock.unlock()
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(name: .allowListDidChange, object: nil)
    }
}

// MARK: - AllowListStorage

/// Container for JSON persistence including both the master toggle and entries.
private struct AllowListStorage: Codable {
    let isActive: Bool
    let entries: [AllowListEntry]
}
