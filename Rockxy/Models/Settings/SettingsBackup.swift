import Foundation

// One-file backup of every debugging tool's rules and switches, and the pure merge that turns
// a backup plus the current settings into the settings to apply.

// MARK: - SettingsBackupDocument

/// A settings backup file. Every section is optional when decoding so a file written by a
/// newer or older version still imports what it can.
struct SettingsBackupDocument: Codable {
    // MARK: Lifecycle

    init(
        exportedAt: Date = Date(),
        appVersion: String? = nil,
        onlyEnabledRules: Bool = false,
        settings: SettingsBackupSnapshot,
        mapLocalFiles: [SettingsBackupFile] = [],
        scripts: [SettingsBackupScript] = []
    ) {
        format = Self.formatIdentifier
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.onlyEnabledRules = onlyEnabledRules
        self.settings = settings
        self.mapLocalFiles = mapLocalFiles
        self.scripts = scripts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        guard format == Self.formatIdentifier else {
            throw SettingsBackupError.notABackup
        }
        version = try container.decode(Int.self, forKey: .version)
        guard version <= Self.currentVersion else {
            throw SettingsBackupError.newerVersion(version)
        }
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        onlyEnabledRules = try container.decodeIfPresent(Bool.self, forKey: .onlyEnabledRules) ?? false
        settings = try container
            .decodeIfPresent(SettingsBackupSnapshot.self, forKey: .settings) ?? SettingsBackupSnapshot()
        mapLocalFiles = try container.decodeIfPresent([SettingsBackupFile].self, forKey: .mapLocalFiles) ?? []
        scripts = try container.decodeIfPresent([SettingsBackupScript].self, forKey: .scripts) ?? []
    }

    // MARK: Internal

    static let formatIdentifier = "rockxy-settings-backup"
    static let currentVersion = 1
    /// Largest backup file Rockxy reads.
    static let maxFileSize = 32 * 1_024 * 1_024

    let format: String
    let version: Int
    let exportedAt: Date
    let appVersion: String?
    let onlyEnabledRules: Bool
    var settings: SettingsBackupSnapshot
    /// Response bodies of Map Local rules that live in Rockxy's own Map Local folder.
    var mapLocalFiles: [SettingsBackupFile]
    var scripts: [SettingsBackupScript]

    static func decode(_ data: Data) throws -> SettingsBackupDocument {
        guard data.count <= maxFileSize else {
            throw SettingsBackupError.tooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(SettingsBackupDocument.self, from: data)
        } catch let error as SettingsBackupError {
            throw error
        } catch {
            throw SettingsBackupError.unreadable
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

// MARK: - SettingsBackupSnapshot

/// Rules and switches of every debugging tool, as saved in a backup or read from the app.
struct SettingsBackupSnapshot: Codable {
    // MARK: Lifecycle

    init(
        rules: [ProxyRule] = [],
        toolsEnabled: [String: Bool] = [:],
        sslProxying: SSLProxyingBackup? = nil,
        allowList: AllowListBackup? = nil,
        bypassDomains: [BypassDomain] = [],
        reverseProxies: [ReverseProxyRule] = [],
        dnsSpoofing: [DNSSpoofingRule] = [],
        noCaching: Bool? = nil,
        ruleFolders: [String: [RuleFolder]] = [:]
    ) {
        self.ruleFolders = ruleFolders
        self.rules = rules
        self.toolsEnabled = toolsEnabled
        self.sslProxying = sslProxying
        self.allowList = allowList
        self.bypassDomains = bypassDomains
        self.reverseProxies = reverseProxies
        self.dnsSpoofing = dnsSpoofing
        self.noCaching = noCaching
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decodeIfPresent([ProxyRule].self, forKey: .rules) ?? []
        toolsEnabled = try container.decodeIfPresent([String: Bool].self, forKey: .toolsEnabled) ?? [:]
        sslProxying = try container.decodeIfPresent(SSLProxyingBackup.self, forKey: .sslProxying)
        allowList = try container.decodeIfPresent(AllowListBackup.self, forKey: .allowList)
        bypassDomains = try container.decodeIfPresent([BypassDomain].self, forKey: .bypassDomains) ?? []
        reverseProxies = try container.decodeIfPresent([ReverseProxyRule].self, forKey: .reverseProxies) ?? []
        dnsSpoofing = try container.decodeIfPresent([DNSSpoofingRule].self, forKey: .dnsSpoofing) ?? []
        noCaching = try container.decodeIfPresent(Bool.self, forKey: .noCaching)
        ruleFolders = try container.decodeIfPresent([String: [RuleFolder]].self, forKey: .ruleFolders) ?? [:]
    }

    // MARK: Internal

    /// The on/off switch of each rule-based tool, keyed like the app's own settings.
    static let toolSwitchKeys = [
        "breakpointToolEnabled", "mapLocalToolEnabled", "mapRemoteToolEnabled", "blockListToolEnabled",
        "networkConditionsToolEnabled", "modifyHeaderToolEnabled",
    ]

    var rules: [ProxyRule]
    var toolsEnabled: [String: Bool]
    var sslProxying: SSLProxyingBackup?
    var allowList: AllowListBackup?
    var bypassDomains: [BypassDomain]
    var reverseProxies: [ReverseProxyRule]
    var dnsSpoofing: [DNSSpoofingRule]
    var noCaching: Bool?
    /// Rule folders per tool (`mapLocal`, `breakpoint`), so the list structure survives a restore.
    var ruleFolders: [String: [RuleFolder]]

    /// The same settings keeping only rules that are turned on.
    func enabledOnly() -> SettingsBackupSnapshot {
        var copy = self
        copy.rules = rules.filter(\.isEnabled)
        copy.sslProxying = sslProxying.map { backup in
            var filtered = backup
            filtered.rules = backup.rules.filter(\.isEnabled)
            filtered.applicationRules = backup.applicationRules.filter(\.isEnabled)
            return filtered
        }
        copy.allowList = allowList.map { backup in
            var filtered = backup
            filtered.rules = backup.rules.filter(\.isEnabled)
            return filtered
        }
        copy.bypassDomains = bypassDomains.filter(\.isEnabled)
        copy.reverseProxies = reverseProxies.filter(\.isEnabled)
        copy.dnsSpoofing = dnsSpoofing.filter(\.isEnabled)
        return copy
    }
}

// MARK: - SSLProxyingBackup

struct SSLProxyingBackup: Codable {
    var isEnabled: Bool
    var bypassDomains: String
    var rules: [SSLProxyingRule]
    var applicationRules: [ApplicationSSLProxyingRule]
}

// MARK: - AllowListBackup

struct AllowListBackup: Codable {
    var isActive: Bool
    var rules: [AllowListRule]
}

// MARK: - SettingsBackupFile

/// A file carried inside a backup, named relative to the folder it belongs in.
struct SettingsBackupFile: Codable, Equatable {
    let name: String
    let data: Data
}

// MARK: - SettingsBackupScript

struct SettingsBackupScript: Codable, Equatable {
    let name: String
    let source: String
    let behavior: ScriptBehavior?
}

// MARK: - SettingsBackupImportMode

enum SettingsBackupImportMode {
    /// Keep current settings and add the backup's rules next to them.
    case append
    /// Make every tool match the backup.
    case replace
}

// MARK: - SettingsBackupError

enum SettingsBackupError: LocalizedError, Equatable {
    case notABackup
    case newerVersion(Int)
    case tooLarge
    case unreadable

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notABackup:
            String(localized: "This file is not a Rockxy settings backup.", bundle: RockxyLocalization.bundle)
        case .newerVersion:
            String(
                localized: "This backup was made by a newer version of Rockxy. Update Rockxy to import it.",
                bundle: RockxyLocalization.bundle
            )
        case .tooLarge:
            String(localized: "The backup file is too large to import.", bundle: RockxyLocalization.bundle)
        case .unreadable:
            String(localized: "The backup file is damaged or incomplete.", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - SettingsBackupMergeResult

struct SettingsBackupMergeResult {
    var settings: SettingsBackupSnapshot
    /// Rules the import adds; an identical rule that is already there is not added again.
    var addedRuleCount: Int
    /// Entries left out because they were invalid or conflicted with current settings.
    var skippedCount: Int
    /// Reverse proxy and DNS Spoofing entries the import adds (they are not tool rules).
    var addedReverseProxyCount = 0
    var addedDNSSpoofingCount = 0
}

// MARK: - SettingsBackupMerger

/// Combines a backup with the current settings. Pure, so it can be tested without touching
/// the app's stores.
enum SettingsBackupMerger {
    // MARK: Internal

    /// Merges `backup` into `current`. `proxyPort` is the listener port reverse proxies must
    /// avoid. Appended entries that would collide with an existing identifier get a new one.
    static func merge(
        _ backup: SettingsBackupSnapshot,
        into current: SettingsBackupSnapshot,
        mode: SettingsBackupImportMode,
        proxyPort: Int
    )
        -> SettingsBackupMergeResult
    {
        var skipped = 0
        var result = current

        // Rules: invalid regular expressions never reach the rule engine.
        let validRules = backup.rules.filter { rule in
            guard let pattern = rule.matchCondition.urlPattern else {
                return true
            }
            if case .failure = RegexValidator.compile(pattern) {
                skipped += 1
                return false
            }
            return true
        }
        switch mode {
        case .replace:
            result.rules = keepOneNetworkCondition(validRules)
            result.toolsEnabled = backup.toolsEnabled.filter { SettingsBackupSnapshot.toolSwitchKeys.contains($0.key) }
            if let noCaching = backup.noCaching {
                result.noCaching = noCaching
            }
        case .append:
            let existingIDs = Set(current.rules.map(\.id))
            var fingerprints = Set(current.rules.compactMap(fingerprint))
            let appended = validRules
                .filter { rule in fingerprint(rule).map { fingerprints.insert($0).inserted } ?? true }
                .map { existingIDs.contains($0.id) ? reidentified($0) : $0 }
            result.rules = keepOneNetworkCondition(current.rules + appended)
        }
        let addedRuleCount = mode == .replace ? result.rules.count : result.rules.count - current.rules.count

        if let ssl = backup.sslProxying {
            result.sslProxying = mergeSSL(ssl, into: current.sslProxying, mode: mode)
        }
        if let allowList = backup.allowList {
            result.allowList = mergeAllowList(allowList, into: current.allowList, mode: mode)
        }

        let validBypass = backup.bypassDomains.filter { ProxyBypassDomainValidator.isValid($0.domain) }
        skipped += backup.bypassDomains.count - validBypass.count
        var alreadyPresent = 0
        result.bypassDomains = mergeUnique(
            validBypass,
            into: mode == .replace ? [] : current.bypassDomains,
            key: { $0.domain.lowercased() },
            skipped: &alreadyPresent
        )

        var reverseProxies = mode == .replace ? [] : current.reverseProxies
        for rule in backup.reverseProxies {
            var candidate = rule
            if reverseProxies.contains(where: { $0.id == candidate.id }) {
                candidate.id = UUID()
            }
            guard ReverseProxyRuleValidator
                .problem(with: candidate, among: reverseProxies, proxyPort: proxyPort) == nil else
            {
                skipped += 1
                continue
            }
            reverseProxies.append(candidate)
        }
        result.reverseProxies = reverseProxies

        var dnsRules = mode == .replace ? [] : current.dnsSpoofing
        for rule in backup.dnsSpoofing {
            var candidate = rule
            if dnsRules.contains(where: { $0.id == candidate.id }) {
                candidate.id = UUID()
            }
            guard DNSSpoofingRuleValidator.problem(with: candidate, among: dnsRules) == nil else {
                skipped += 1
                continue
            }
            dnsRules.append(candidate)
        }
        result.dnsSpoofing = dnsRules

        return SettingsBackupMergeResult(
            settings: result,
            addedRuleCount: addedRuleCount,
            skippedCount: skipped,
            addedReverseProxyCount: reverseProxies.count - (mode == .replace ? 0 : current.reverseProxies.count),
            addedDNSSpoofingCount: dnsRules.count - (mode == .replace ? 0 : current.dnsSpoofing.count)
        )
    }

    /// Returns `value` with a fresh `id`, for models whose identifier is immutable.
    static func reidentified<T: Codable>(_ value: T) -> T {
        guard let data = try? JSONEncoder().encode(value),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            return value
        }
        object["id"] = UUID().uuidString
        guard let updated = try? JSONSerialization.data(withJSONObject: object),
              let decoded = try? JSONDecoder().decode(T.self, from: updated) else
        {
            return value
        }
        return decoded
    }

    // MARK: Private

    /// A rule's content without its identifier and on/off state, to recognize a rule that is
    /// already present.
    private static func fingerprint(_ rule: ProxyRule) -> String? {
        guard let data = try? JSONEncoder().encode(rule),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            return nil
        }
        object["id"] = nil
        object["isEnabled"] = nil
        guard let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(bytes: normalized, encoding: .utf8)
    }

    /// Only one network condition can shape traffic at a time; later enabled ones are turned off.
    private static func keepOneNetworkCondition(_ rules: [ProxyRule]) -> [ProxyRule] {
        var sawEnabled = false
        return rules.map { rule in
            guard case .networkCondition = rule.action, rule.isEnabled else {
                return rule
            }
            if sawEnabled {
                var disabled = rule
                disabled.isEnabled = false
                return disabled
            }
            sawEnabled = true
            return rule
        }
    }

    private static func mergeSSL(
        _ backup: SSLProxyingBackup,
        into current: SSLProxyingBackup?,
        mode: SettingsBackupImportMode
    )
        -> SSLProxyingBackup
    {
        guard mode == .append, var merged = current else {
            return backup
        }
        var ignored = 0
        merged.rules = mergeUnique(
            backup.rules,
            into: merged.rules,
            key: { "\($0.listType)|\($0.domain.lowercased())" },
            skipped: &ignored
        )
        merged.applicationRules = mergeUnique(
            backup.applicationRules,
            into: merged.applicationRules,
            key: { "\($0.listType)|\($0.applicationIdentifier.lowercased())" },
            skipped: &ignored
        )
        return merged
    }

    private static func mergeAllowList(
        _ backup: AllowListBackup,
        into current: AllowListBackup?,
        mode: SettingsBackupImportMode
    )
        -> AllowListBackup
    {
        guard mode == .append, var merged = current else {
            return backup
        }
        var ignored = 0
        merged.rules = mergeUnique(
            backup.rules,
            into: merged.rules,
            key: { "\($0.rawPattern)|\($0.method ?? "")|\($0.matchType)|\($0.graphQLOperationName ?? "")" },
            skipped: &ignored
        )
        return merged
    }

    /// Appends items whose `key` is not already present, giving colliding identifiers a new one.
    private static func mergeUnique<T: Codable & Identifiable>(
        _ incoming: [T],
        into existing: [T],
        key: (T) -> String,
        skipped: inout Int
    )
        -> [T] where T.ID == UUID
    {
        var result = existing
        var keys = Set(existing.map(key))
        var ids = Set(existing.map(\.id))
        for item in incoming {
            guard keys.insert(key(item)).inserted else {
                skipped += 1
                continue
            }
            let placed = ids.contains(item.id) ? reidentified(item) : item
            ids.insert(placed.id)
            result.append(placed)
        }
        return result
    }
}
