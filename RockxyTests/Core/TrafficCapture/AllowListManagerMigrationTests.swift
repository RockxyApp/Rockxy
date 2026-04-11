import Foundation
@testable import Rockxy
import Testing

/// Legacy-to-v2 migration semantics: preserve the old `AllowListEntry.matches(_:)`
/// host-matching behavior exactly through anchored regex rules with inline `(?i)`.
@MainActor
struct AllowListManagerMigrationTests {
    // MARK: Internal

    // MARK: - Exact Host Migration

    @Test
    func legacyExactHostMigratesToAnchoredRegex() throws {
        let (dir, storage) = tempDirAndURL()
        defer { cleanup(dir) }

        try writeLegacyStorage(
            isActive: true,
            entries: [(UUID(), "example.com", true)],
            to: storage
        )

        let manager = AllowListManager(storageURL: storage)
        #expect(manager.rules.count == 1)
        #expect(manager.rules[0].matchType == .regex)
        #expect(manager.rules[0].rawPattern.hasPrefix("(?i)"))
        #expect(manager.isActive)

        // Matches exact host including case variations, ports, path, query, fragment.
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("http://example.com/path")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://EXAMPLE.com")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://Example.COM/PATH")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com:8080/api")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com?x=1")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://example.com#frag")))

        // Rejects substring hosts and subdomains.
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://notexample.com")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://api.example.com")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://example.com.evil.com")))
    }

    // MARK: - Subdomain Wildcard Migration

    @Test
    func legacySubdomainWildcardMigratesToAnchoredRegex() throws {
        let (dir, storage) = tempDirAndURL()
        defer { cleanup(dir) }

        try writeLegacyStorage(
            isActive: true,
            entries: [(UUID(), "*.example.com", true)],
            to: storage
        )

        let manager = AllowListManager(storageURL: storage)
        #expect(manager.rules.count == 1)
        #expect(manager.rules[0].matchType == .regex)
        #expect(manager.rules[0].rawPattern.hasPrefix("(?i)"))

        // Matches subdomains (with case variations, ports, path, query, fragment).
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://api.example.com")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://a.b.example.com/path")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://API.EXAMPLE.com")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://api.example.com:8443/")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://api.example.com?x=1")))
        #expect(manager.isRequestAllowed(method: "GET", url: self.url("https://api.example.com#frag")))

        // Rejects bare root, substring hosts, and suffix-injection attacks.
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://example.com")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://notexample.com")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://fakeexample.com")))
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://api.example.com.evil.com")))
    }

    // MARK: - Mixed / Disabled Entries

    @Test
    func migrationPreservesIsEnabledFlag() throws {
        let (dir, storage) = tempDirAndURL()
        defer { cleanup(dir) }

        try writeLegacyStorage(
            isActive: true,
            entries: [
                (UUID(), "a.com", true),
                (UUID(), "b.com", false),
                (UUID(), "*.c.com", true),
            ],
            to: storage
        )

        let manager = AllowListManager(storageURL: storage)
        #expect(manager.rules.count == 3)
        #expect(manager.rules[0].isEnabled)
        #expect(!manager.rules[1].isEnabled)
        #expect(manager.rules[2].isEnabled)

        // Disabled rule should not match.
        #expect(!manager.isRequestAllowed(method: "GET", url: self.url("https://b.com")))
    }

    // MARK: - Legacy Snapshot

    @Test
    func legacySnapshotFileWrittenOnFirstMigration() throws {
        let (dir, storage) = tempDirAndURL()
        defer { cleanup(dir) }

        try writeLegacyStorage(
            isActive: false,
            entries: [(UUID(), "example.com", true)],
            to: storage
        )

        _ = AllowListManager(storageURL: storage)

        let snapshot = dir.appendingPathComponent("allow-list.legacy.json")
        #expect(FileManager.default.fileExists(atPath: snapshot.path))

        // Verify snapshot contents are the original legacy JSON (decodable as LegacyStorage).
        let data = try Data(contentsOf: snapshot)
        let decoded = try JSONDecoder().decode(LegacyStorage.self, from: data)
        #expect(decoded.entries.count == 1)
        #expect(decoded.entries[0].domain == "example.com")
    }

    // MARK: - New Schema Written on Next Save

    @Test
    func migrationRewritesToV2SchemaOnNextSave() throws {
        let (dir, storage) = tempDirAndURL()
        defer { cleanup(dir) }

        try writeLegacyStorage(
            isActive: true,
            entries: [(UUID(), "a.com", true)],
            to: storage
        )

        _ = AllowListManager(storageURL: storage)

        // Re-read raw JSON and verify it matches new schema, not legacy.
        let data = try Data(contentsOf: storage)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["schemaVersion"] as? Int == 2)
        #expect(decoded?["entries"] == nil)
        #expect(decoded?["rules"] != nil)
    }

    // MARK: - New vs Legacy Case Sensitivity Contract

    @Test
    func newUserRegexRemainsCaseSensitive() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("allow-list-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let manager = AllowListManager(storageURL: tempURL)
        // New user-authored regex without inline (?i) — must be case-sensitive.
        manager.addRule(
            AllowListRule(
                name: "x",
                rawPattern: "^https://example\\.com/.*$",
                method: nil,
                matchType: .regex,
                includeSubpaths: true
            )
        )
        manager.setActive(true)

        #expect(try manager.isRequestAllowed(method: "GET", url: #require(URL(string: "https://example.com/a"))))
        #expect(try !manager.isRequestAllowed(method: "GET", url: #require(URL(string: "https://EXAMPLE.COM/a"))))
    }

    @Test
    func degenerateLegacyEntriesAreSkipped() throws {
        let (dir, storage) = tempDirAndURL()
        defer { cleanup(dir) }

        try writeLegacyStorage(
            isActive: true,
            entries: [
                (UUID(), "", true), // empty domain
                (UUID(), "*.", true), // wildcard with empty root
                (UUID(), "   ", true), // whitespace only
                (UUID(), "valid.com", true), // one valid entry so the list is non-empty
            ],
            to: storage
        )

        let manager = AllowListManager(storageURL: storage)
        // Only the single valid entry should survive migration.
        #expect(manager.rules.count == 1)
        #expect(manager.rules[0].name == "valid.com")
    }

    @Test
    func bothDecodesFailKeepsEmptyState() throws {
        let (dir, storage) = tempDirAndURL()
        defer { cleanup(dir) }

        try Data("garbage".utf8).write(to: storage, options: .atomic)

        let manager = AllowListManager(storageURL: storage)
        #expect(manager.rules.isEmpty)
        #expect(!manager.isActive)

        // The original corrupt file must NOT be overwritten.
        let data = try Data(contentsOf: storage)
        #expect(String(data: data, encoding: .utf8) == "garbage")
    }

    // MARK: - load() clears existing in-memory state

    @Test
    func reloadingMissingFileClearsExistingState() throws {
        let (dir, storage) = tempDirAndURL()
        defer { cleanup(dir) }

        // Seed the manager with real state via its public API.
        let manager = AllowListManager(storageURL: storage)
        manager.addRule(
            AllowListRule(
                name: "api",
                rawPattern: "*example.com*",
                method: nil,
                matchType: .wildcard,
                includeSubpaths: true
            )
        )
        manager.setActive(true)
        #expect(manager.rules.count == 1)
        #expect(manager.isActive)
        #expect(try !manager.isRequestAllowed(method: "GET", url: #require(URL(string: "https://other.com"))))

        // Delete the persisted file out from under the manager.
        try FileManager.default.removeItem(at: storage)

        // Re-calling load() must clear the in-memory state AND the cache.
        manager.load()
        #expect(manager.rules.isEmpty)
        #expect(!manager.isActive)
        // Cache reflects cleared state — inactive => every request is allowed.
        #expect(try manager.isRequestAllowed(method: "GET", url: #require(URL(string: "https://other.com"))))
        #expect(try manager.isRequestAllowed(method: "GET", url: #require(URL(string: "https://example.com"))))
    }

    @Test
    func reloadingCorruptFileClearsExistingState() throws {
        let (dir, storage) = tempDirAndURL()
        defer { cleanup(dir) }

        // Seed the manager with real state via its public API.
        let manager = AllowListManager(storageURL: storage)
        manager.addRule(
            AllowListRule(
                name: "api",
                rawPattern: "*example.com*",
                method: nil,
                matchType: .wildcard,
                includeSubpaths: true
            )
        )
        manager.setActive(true)
        #expect(manager.rules.count == 1)

        // Corrupt the persisted file.
        try Data("{not json}".utf8).write(to: storage, options: .atomic)

        // Re-calling load() must clear in-memory state without overwriting the corrupt file.
        manager.load()
        #expect(manager.rules.isEmpty)
        #expect(!manager.isActive)
        #expect(try manager.isRequestAllowed(method: "GET", url: #require(URL(string: "https://anything.com"))))

        let onDisk = try Data(contentsOf: storage)
        #expect(String(data: onDisk, encoding: .utf8) == "{not json}")
    }

    // MARK: Private

    // MARK: - Helpers

    private func tempDirAndURL() -> (dir: URL, storage: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("allowlist-migration-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storage = dir.appendingPathComponent("allow-list.json")
        return (dir, storage)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeLegacyStorage(
        isActive: Bool,
        entries: [(id: UUID, domain: String, isEnabled: Bool)],
        to url: URL
    )
        throws
    {
        let legacy = LegacyStorage(
            isActive: isActive,
            entries: entries.map { LegacyEntry(id: $0.id, domain: $0.domain, isEnabled: $0.isEnabled) }
        )
        let data = try JSONEncoder().encode(legacy)
        try data.write(to: url, options: .atomic)
    }

    private func url(_ s: String) -> URL {
        URL(string: s)!
    }
}
