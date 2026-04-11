import Foundation
import os

// Defines `AllowListManager`, which coordinates allow list behavior in traffic capture.

// MARK: - AllowListManager

/// Manages the Allow List — a capture-level filter that restricts which traffic
/// is recorded in the session. When active, only traffic matching an enabled rule
/// appears in the UI. Non-matching traffic is still proxied (forwarded) but not
/// displayed or stored.
///
/// The `isRequestAllowed(method:url:)` method is `nonisolated` and thread-safe so
/// it can be called directly from NIO event loops without hopping to the main actor.
/// Runtime regex compilation happens in exactly one place: `rebuildCache()`.
@MainActor @Observable
final class AllowListManager {
    // MARK: Lifecycle

    private init() {
        storageURLOverride = nil
        cachedCompiled = []
        cachedIsActive = false
        load()
    }

    /// Test-only initializer with isolated storage path.
    init(storageURL: URL) {
        storageURLOverride = storageURL
        cachedCompiled = []
        cachedIsActive = false
        load()
    }

    // MARK: Internal

    static let shared = AllowListManager()

    /// Master toggle. When false, all traffic passes through (allow list is ignored).
    /// When true, only requests matching enabled rules are captured.
    private(set) var isActive: Bool = false

    /// Current allow list rules. Mutated only through the public API
    /// (`addRule`, `updateRule`, `removeRule`, `toggleRule`, `replaceAll`, `importRulesJSON`).
    private(set) var rules: [AllowListRule] = []

    // MARK: - Legacy Migration

    /// Maps a legacy `AllowListEntry` (host-only) to an anchored regex rule that
    /// preserves the old matching semantics exactly:
    /// - Exact `example.com` matches only that host (never substrings or subdomains)
    /// - Wildcard `*.example.com` matches subdomains only (never the bare root)
    /// - Inline `(?i)` preserves legacy case-insensitive host matching
    /// - The tail `(:\d+)?(?:[/?#].*)?$` allows port, path, query, and fragment
    ///
    /// Returns `nil` for degenerate legacy entries (empty host, or `*.` with empty
    /// root) that would produce an overbroad rule. The caller drops the entry.
    static func migrateLegacyEntry(_ entry: LegacyEntry) -> AllowListRule? {
        let domain = entry.domain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else {
            logger.warning("Skipping legacy Allow List entry with empty domain")
            return nil
        }
        let name = domain
        let rawPattern: String
        if domain.hasPrefix("*.") {
            let root = String(domain.dropFirst(2))
            guard !root.isEmpty else {
                logger.warning("Skipping legacy Allow List entry with empty subdomain root")
                return nil
            }
            let escapedRoot = NSRegularExpression.escapedPattern(for: root)
            rawPattern = "(?i)^https?://[^/]+\\.\(escapedRoot)(:\\d+)?(?:[/?#].*)?$"
        } else {
            let escapedHost = NSRegularExpression.escapedPattern(for: domain)
            rawPattern = "(?i)^https?://\(escapedHost)(:\\d+)?(?:[/?#].*)?$"
        }
        return AllowListRule(
            id: entry.id,
            name: name,
            isEnabled: entry.isEnabled,
            rawPattern: rawPattern,
            method: nil,
            matchType: .regex,
            includeSubpaths: true
        )
    }

    // MARK: - Master Toggle

    func setActive(_ active: Bool) {
        isActive = active
        rebuildCache()
        save()
    }

    // MARK: - Rule CRUD

    func addRule(_ rule: AllowListRule) {
        rules.append(rule)
        rebuildCache()
        save()
        Self.logger.info("Added allow list rule: \(rule.name, privacy: .private)")
    }

    func updateRule(_ rule: AllowListRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        rules[index] = rule
        rebuildCache()
        save()
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        rebuildCache()
        save()
    }

    func toggleRule(id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        rules[index].isEnabled.toggle()
        rebuildCache()
        save()
    }

    func replaceAll(_ newRules: [AllowListRule]) {
        rules = newRules
        rebuildCache()
        save()
        Self.logger.info("Replaced allow list with \(newRules.count) rules")
    }

    // MARK: - Runtime Matching (nonisolated)

    /// Thread-safe request check usable from NIO event loops.
    /// Returns `true` if the request should be captured (recorded in session).
    ///
    /// - When allow list is inactive: always returns `true`.
    /// - When allow list is active: returns `true` only if the request matches
    ///   at least one enabled rule (method + URL pattern).
    nonisolated func isRequestAllowed(method: String, url: URL) -> Bool {
        let snapshot: [CompiledRule]
        let active: Bool
        lock.lock()
        snapshot = cachedCompiled
        active = cachedIsActive
        lock.unlock()

        guard active else {
            return true
        }

        let upperMethod = method.uppercased()
        let urlString = String(url.absoluteString.prefix(ProxyLimits.maxURILength))
        let range = NSRange(urlString.startIndex..., in: urlString)

        for compiled in snapshot {
            if let ruleMethod = compiled.method, ruleMethod != upperMethod {
                continue
            }
            if compiled.regex.firstMatch(in: urlString, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Persistence

    func load() {
        let url = resolvedStorageURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            Self.logger.info("No allow list file found, clearing to empty state")
            applyState(isActive: false, rules: [], persist: false)
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Self.logger.error(
                "Failed to read allow list file: \(error.localizedDescription) — clearing to empty state"
            )
            applyState(isActive: false, rules: [], persist: false)
            return
        }

        // Attempt new schema first.
        if let storage = try? JSONDecoder().decode(AllowListStorage.self, from: data) {
            applyState(isActive: storage.isActive, rules: storage.rules, persist: false)
            Self.logger.info("Loaded \(self.rules.count) allow list rules (active: \(self.isActive))")
            return
        }

        // Fallback: legacy schema.
        if let legacy = try? JSONDecoder().decode(LegacyStorage.self, from: data) {
            let migrated = legacy.entries.compactMap(Self.migrateLegacyEntry(_:))
            writeLegacySnapshot(data)
            applyState(isActive: legacy.isActive, rules: migrated, persist: true)
            Self.logger.info("Migrated \(migrated.count) legacy Allow List entries to new schema")
            return
        }

        Self.logger.warning("Failed to decode allow list storage — clearing to empty state")
        applyState(isActive: false, rules: [], persist: false)
    }

    func save() {
        let url = resolvedStorageURL
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let storage = AllowListStorage(schemaVersion: Self.currentSchemaVersion, isActive: isActive, rules: rules)
            let data = try JSONEncoder().encode(storage)
            try data.write(to: url, options: .atomic)
            Self.logger.debug("Saved \(self.rules.count) allow list rules")
        } catch {
            Self.logger.error("Failed to save allow list: \(error.localizedDescription)")
        }
    }

    // MARK: - Import / Export

    func exportRulesJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let storage = AllowListStorage(schemaVersion: Self.currentSchemaVersion, isActive: isActive, rules: rules)
        return try? encoder.encode(storage)
    }

    func importRulesJSON(_ data: Data) throws {
        // Try new schema first.
        if let storage = try? JSONDecoder().decode(AllowListStorage.self, from: data) {
            applyState(isActive: storage.isActive, rules: storage.rules, persist: true)
            Self.logger.info("Imported \(storage.rules.count) allow list rules (schema v\(storage.schemaVersion))")
            return
        }

        // Fallback: legacy schema (supports importing older export files).
        let legacy = try JSONDecoder().decode(LegacyStorage.self, from: data)
        let migrated = legacy.entries.compactMap(Self.migrateLegacyEntry(_:))
        applyState(isActive: legacy.isActive, rules: migrated, persist: true)
        Self.logger.info("Imported \(migrated.count) legacy allow list entries (auto-migrated)")
    }

    // MARK: Private

    // MARK: - Private Types

    /// In-memory snapshot of a compiled rule. Never persisted.
    private struct CompiledRule {
        let id: UUID
        let regex: NSRegularExpression
        let method: String?
    }

    private enum CompileError: Error, LocalizedError {
        case patternTooLong(limit: Int)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case let .patternTooLong(limit):
                "Regex pattern exceeds \(limit) characters."
            }
        }
    }

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "AllowListManager")

    private static let currentSchemaVersion = 2

    // MARK: - Pattern Compilation (single call site)

    /// Maximum length of a user-authored regex pattern. Bounds the worst case
    /// for regex compilation / matching as defense-in-depth against accidentally
    /// pasted catastrophic-backtracking patterns.
    private static let maxUserRegexLength = 2_048

    private static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("allow-list.json")
    }

    private let storageURLOverride: URL?

    private let lock = NSLock()
    nonisolated(unsafe) private var cachedCompiled: [CompiledRule]
    nonisolated(unsafe) private var cachedIsActive: Bool

    private var resolvedStorageURL: URL {
        storageURLOverride ?? Self.defaultStorageURL
    }

    private var legacySnapshotURL: URL {
        resolvedStorageURL
            .deletingLastPathComponent()
            .appendingPathComponent("allow-list.legacy.json")
    }

    /// Compiles a user-facing raw pattern into an `NSRegularExpression` using
    /// **default case-sensitive** options. Called only from `rebuildCache()`.
    /// User-authored rules that want case-insensitive matching should include
    /// inline `(?i)` in their regex pattern. Legacy migrated rules automatically
    /// include `(?i)` to preserve pre-refactor host-insensitive semantics.
    ///
    /// Mirrors the Block List / Breakpoint wildcard semantics exactly.
    private static func compilePattern(
        rawPattern: String,
        matchType: RuleMatchType,
        includeSubpaths: Bool
    )
        throws -> NSRegularExpression
    {
        let source: String
        switch matchType {
        case .wildcard:
            var pattern = NSRegularExpression.escapedPattern(for: rawPattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            if includeSubpaths {
                if !pattern.hasSuffix(".*") {
                    pattern += ".*"
                }
            } else {
                pattern += "($|[?#])"
            }
            source = pattern
        case .regex:
            guard rawPattern.count <= maxUserRegexLength else {
                throw CompileError.patternTooLong(limit: maxUserRegexLength)
            }
            source = rawPattern
        }
        return try NSRegularExpression(pattern: source, options: [])
    }

    /// Atomically applies a loaded/imported state (`isActive` + `rules`) and
    /// rebuilds the nonisolated cache. If `persist` is true, writes the new
    /// schema to disk in a single `save()` call.
    private func applyState(isActive: Bool, rules: [AllowListRule], persist: Bool) {
        self.isActive = isActive
        self.rules = rules
        rebuildCache()
        if persist {
            save()
        }
    }

    /// Compiles the pattern and rebuilds the nonisolated cache snapshot.
    /// Invalid regex rules are skipped with a warning — other rules still evaluate.
    /// This is the sole call site for `compilePattern`.
    private func rebuildCache() {
        var compiled: [CompiledRule] = []
        compiled.reserveCapacity(rules.count)
        for rule in rules where rule.isEnabled {
            do {
                let regex = try Self.compilePattern(
                    rawPattern: rule.rawPattern,
                    matchType: rule.matchType,
                    includeSubpaths: rule.includeSubpaths
                )
                compiled.append(
                    CompiledRule(
                        id: rule.id,
                        regex: regex,
                        method: rule.method?.uppercased()
                    )
                )
            } catch {
                Self.logger.warning(
                    "Skipped invalid Allow List rule '\(rule.name, privacy: .private)': \(error.localizedDescription)"
                )
            }
        }

        let compiledSnapshot = compiled
        let active = isActive
        lock.lock()
        cachedCompiled = compiledSnapshot
        cachedIsActive = active
        lock.unlock()
    }

    /// Writes a one-time legacy snapshot file so users can recover pre-migration data.
    /// Only writes if the snapshot does not already exist.
    private func writeLegacySnapshot(_ data: Data) {
        let url = legacySnapshotURL
        guard !FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            Self.logger.info("Wrote legacy Allow List snapshot at \(url.path, privacy: .private)")
        } catch {
            Self.logger.warning("Failed to write legacy snapshot: \(error.localizedDescription)")
        }
    }
}

// MARK: - AllowListStorage

/// Versioned container for JSON persistence. Schema version `2` is the current format.
private struct AllowListStorage: Codable {
    let schemaVersion: Int
    let isActive: Bool
    let rules: [AllowListRule]
}

// MARK: - LegacyStorage

/// Legacy container from schema v1 (host-only entries). Read-only; written back as v2.
struct LegacyStorage: Codable {
    let isActive: Bool
    let entries: [LegacyEntry]
}

// MARK: - LegacyEntry

/// Legacy `AllowListEntry` shape preserved only for migration and import fallback.
struct LegacyEntry: Codable {
    let id: UUID
    let domain: String
    let isEnabled: Bool
}
