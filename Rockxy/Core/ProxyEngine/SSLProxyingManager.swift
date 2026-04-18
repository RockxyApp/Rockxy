import Foundation
import os

// MARK: - SSLProxyingManager

/// Manages the list of domains for which Rockxy will perform TLS interception.
/// Supports Include and Exclude lists, a global enable toggle, and bypass domains.
///
/// The `shouldIntercept(_:)` method is `nonisolated` and thread-safe so it can be
/// called directly from NIO event loops without hopping to the main actor.
@MainActor @Observable
final class SSLProxyingManager {
    // MARK: Lifecycle

    private init() {
        customStorageURL = nil
        customPassthroughStorageURL = nil
        cachedEnabledIncludeRules = []
        cachedEnabledExcludeRules = []
        load()
    }

    /// Test-only initializer with injectable storage path.
    init(storageURL: URL, passthroughStorageURL: URL? = nil) {
        customStorageURL = storageURL
        customPassthroughStorageURL = passthroughStorageURL
        cachedEnabledIncludeRules = []
        cachedEnabledExcludeRules = []
        load()
    }

    // MARK: Internal

    static let shared = SSLProxyingManager()

    static let defaultBypassDomains =
        "dns.google,one.one.one.one,ocsp.digicert.com,ocsp.apple.com,ocsp2.apple.com"

    private(set) var isEnabled: Bool = true
    private(set) var bypassDomains: String = SSLProxyingManager.defaultBypassDomains

    private(set) var rules: [SSLProxyingRule] = [] {
        didSet {
            rebuildCache()
        }
    }

    var includeRules: [SSLProxyingRule] {
        rules.filter { $0.listType == .include }
    }

    var excludeRules: [SSLProxyingRule] {
        rules.filter { $0.listType == .exclude }
    }

    /// When true, all CONNECT requests pass through as raw tunnels without interception.
    /// Set when the root CA is not trusted, preventing invalid certificate errors.
    nonisolated var forceGlobalPassthrough: Bool {
        get {
            passthroughLock.lock()
            defer { passthroughLock.unlock() }
            return _forceGlobalPassthrough
        }
        set {
            passthroughLock.lock()
            _forceGlobalPassthrough = newValue
            passthroughLock.unlock()
            Self.logger.info("Global TLS passthrough \(newValue ? "enabled" : "disabled")")
        }
    }

    func setEnabled(_ enabled: Bool) {
        let wasEnabled = isEnabled
        isEnabled = enabled
        rebuildCache()
        if enabled, !wasEnabled {
            clearAutoPassthroughForActiveIncludeRules()
        }
        save()
        Self.logger.info("SSL proxying tool \(enabled ? "enabled" : "disabled")")
    }

    func setBypassDomains(_ text: String) {
        bypassDomains = text
        rebuildBypassCache()
        save()
    }

    func resetBypassToDefault() {
        bypassDomains = Self.defaultBypassDomains
        rebuildBypassCache()
        save()
    }

    func addRule(_ rule: SSLProxyingRule) {
        rules.append(rule)
        clearAutoPassthroughIfNeeded(for: [rule])
        save()
    }

    func addRules(_ newRules: [SSLProxyingRule]) {
        rules.append(contentsOf: newRules)
        clearAutoPassthroughIfNeeded(for: newRules)
        save()
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func removeRules(ids: Set<UUID>) {
        rules.removeAll { ids.contains($0.id) }
        save()
    }

    func toggleRule(id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        let previous = rules[index]
        rules[index].isEnabled.toggle()
        clearAutoPassthroughIfNeeded(for: [rules[index]], previousRules: [previous])
        save()
    }

    func setRuleEnabled(id: UUID, enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard rules[index].isEnabled != enabled else {
            return
        }
        let previous = rules[index]
        rules[index].isEnabled = enabled
        clearAutoPassthroughIfNeeded(for: [rules[index]], previousRules: [previous])
        save()
    }

    func updateRule(_ rule: SSLProxyingRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        let previous = rules[index]
        rules[index] = rule
        clearAutoPassthroughIfNeeded(for: [rule], previousRules: [previous])
        save()
    }

    func replaceAllRules(_ newRules: [SSLProxyingRule]) {
        rules = newRules
        clearAutoPassthroughForActiveIncludeRules()
        save()
        Self.logger.info("Replaced all SSL proxying rules (\(newRules.count) rules)")
    }

    /// Thread-safe check usable from NIO event loops.
    /// Decision chain: enabled → global passthrough → bypass → exclude → include.
    nonisolated func shouldIntercept(_ host: String) -> Bool {
        lock.lock()
        let enabled = cachedIsEnabled
        let includeSnapshot = cachedEnabledIncludeRules
        let excludeSnapshot = cachedEnabledExcludeRules
        lock.unlock()

        if !enabled {
            return false
        }

        passthroughLock.lock()
        let globalPassthrough = _forceGlobalPassthrough
        let bypassPatterns = cachedBypassPatterns
        passthroughLock.unlock()

        if globalPassthrough {
            return false
        }

        if matchesBypassPattern(host, patterns: bypassPatterns) {
            return false
        }

        if excludeSnapshot.contains(where: { $0.matches(host) }) {
            return false
        }

        if includeSnapshot.isEmpty {
            return false
        }

        return includeSnapshot.contains { $0.matches(host) }
    }

    /// Called from PostHandshakeHandler when a client rejects our intercepted certificate.
    nonisolated func markHostForPassthrough(_ host: String) {
        passthroughLock.lock()
        autoPassthroughHosts[host] = Date()
        passthroughLock.unlock()
        Self.logger.info("Auto-passthrough enabled for \(host) after TLS failure")
        persistPassthroughHosts()
    }

    nonisolated func clearAutoPassthrough() {
        passthroughLock.lock()
        autoPassthroughHosts.removeAll()
        passthroughLock.unlock()
        persistPassthroughHosts()
        Self.logger.info("Cleared all auto-passthrough hosts")
    }

    /// Thread-safe check for hosts that should skip interception due to recent TLS failure.
    nonisolated func isAutoPassthrough(_ host: String) -> Bool {
        passthroughLock.lock()
        defer { passthroughLock.unlock() }
        guard let timestamp = autoPassthroughHosts[host] else {
            return false
        }
        if Date().timeIntervalSince(timestamp) > Self.passthroughTTLSeconds {
            autoPassthroughHosts.removeValue(forKey: host)
            return false
        }
        return true
    }

    func load() {
        let url = resolvedStorageURL
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                if let storage = try? JSONDecoder().decode(SSLProxyingStorage.self, from: data),
                   storage.schemaVersion >= 2
                {
                    isEnabled = storage.isEnabled
                    bypassDomains = storage.bypassDomains
                    rules = storage.rules
                    rebuildCache()
                    Self.logger
                        .info("Loaded v\(storage.schemaVersion) SSL proxying settings (\(self.rules.count) rules)")
                } else {
                    let legacyRules = try JSONDecoder().decode([SSLProxyingRule].self, from: data)
                    isEnabled = true
                    bypassDomains = Self.defaultBypassDomains
                    rules = legacyRules
                    rebuildCache()
                    Self.logger.info("Migrated \(legacyRules.count) legacy SSL proxying rules to v2")
                    save()
                }
            } catch {
                Self.logger.error("Failed to load SSL proxying rules: \(error.localizedDescription)")
            }
        } else {
            Self.logger.info("No SSL proxying rules file found, starting with defaults")
        }
        rebuildBypassCache()
        loadPassthroughHosts()
    }

    func save() {
        let url = resolvedStorageURL
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let storage = SSLProxyingStorage(
                schemaVersion: 2,
                isEnabled: isEnabled,
                bypassDomains: bypassDomains,
                rules: rules
            )
            let data = try JSONEncoder().encode(storage)
            try data.write(to: url, options: .atomic)
            Self.logger.debug("Saved \(self.rules.count) SSL proxying rules")
        } catch {
            Self.logger.error("Failed to save SSL proxying rules: \(error.localizedDescription)")
        }
    }

    func exportRules() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let storage = SSLProxyingStorage(
            schemaVersion: 2,
            isEnabled: isEnabled,
            bypassDomains: bypassDomains,
            rules: rules
        )
        return try? encoder.encode(storage)
    }

    func importRules(from data: Data) throws {
        if let storage = try? JSONDecoder().decode(SSLProxyingStorage.self, from: data),
           storage.schemaVersion >= 2
        {
            isEnabled = storage.isEnabled
            bypassDomains = storage.bypassDomains
            rebuildBypassCache()
            replaceAllRules(storage.rules)
        } else {
            let decoded = try JSONDecoder().decode([SSLProxyingRule].self, from: data)
            isEnabled = true
            bypassDomains = Self.defaultBypassDomains
            rebuildBypassCache()
            replaceAllRules(decoded)
        }
    }

    func addPresets() {
        let presetDomains = [
            "*.googleapis.com",
            "*.github.com",
            "*.githubusercontent.com",
            "*.stripe.com",
            "*.sentry.io",
            "*.firebase.io",
            "*.cloudflare.com",
        ]
        let existingDomains = Set(rules.map { $0.domain.lowercased() })
        var added = 0
        var addedRules: [SSLProxyingRule] = []
        for domain in presetDomains {
            guard !existingDomains.contains(domain.lowercased()) else {
                continue
            }
            let rule = SSLProxyingRule(domain: domain)
            addedRules.append(rule)
            added += 1
        }
        if added > 0 {
            rules.append(contentsOf: addedRules)
            clearAutoPassthroughIfNeeded(for: addedRules)
            save()
            Self.logger.info("Added \(added) preset SSL proxying rules")
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "SSLProxyingManager")
    private static let passthroughTTLSeconds: TimeInterval = 86_400

    private static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("ssl-proxying-rules.json")
    }

    nonisolated private static var passthroughStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("auto-passthrough-hosts.json")
    }

    private let customStorageURL: URL?
    private let customPassthroughStorageURL: URL?

    private let lock = NSLock()
    nonisolated(unsafe) private var cachedEnabledIncludeRules: [SSLProxyingRule]
    nonisolated(unsafe) private var cachedEnabledExcludeRules: [SSLProxyingRule]
    nonisolated(unsafe) private var cachedIsEnabled: Bool = true

    private let passthroughLock = NSLock()
    nonisolated(unsafe) private var autoPassthroughHosts: [String: Date] = [:]
    nonisolated(unsafe) private var _forceGlobalPassthrough = false
    nonisolated(unsafe) private var cachedBypassPatterns: [String] = []

    private var resolvedStorageURL: URL {
        customStorageURL ?? Self.defaultStorageURL
    }

    nonisolated private var resolvedPassthroughStorageURL: URL {
        customPassthroughStorageURL ?? Self.passthroughStorageURL
    }

    private func rebuildCache() {
        let enabledInclude = rules.filter { $0.isEnabled && $0.listType == .include }
        let enabledExclude = rules.filter { $0.isEnabled && $0.listType == .exclude }
        lock.lock()
        cachedEnabledIncludeRules = enabledInclude
        cachedEnabledExcludeRules = enabledExclude
        cachedIsEnabled = isEnabled
        lock.unlock()
    }

    private func rebuildBypassCache() {
        let patterns = bypassDomains
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        passthroughLock.lock()
        cachedBypassPatterns = patterns
        passthroughLock.unlock()
    }

    nonisolated private func matchesBypassPattern(_ host: String, patterns: [String]) -> Bool {
        let lowerHost = host.lowercased()
        for pattern in patterns {
            if pattern == "*" {
                return true
            } else if pattern.hasPrefix("*.") {
                let suffix = String(pattern.dropFirst(1))
                if lowerHost.hasSuffix(suffix), lowerHost.count > suffix.count {
                    return true
                }
            } else if lowerHost == pattern {
                return true
            }
        }
        return false
    }

    private func clearAutoPassthroughIfNeeded(
        for rules: [SSLProxyingRule],
        previousRules: [SSLProxyingRule] = []
    ) {
        guard isEnabled else {
            return
        }

        let previousByID = Dictionary(uniqueKeysWithValues: previousRules.map { ($0.id, $0) })
        let rulesToRetry = rules.filter { rule in
            guard rule.listType == .include, rule.isEnabled else {
                return false
            }
            guard let previous = previousByID[rule.id] else {
                return true
            }
            if previous.listType != .include || !previous.isEnabled {
                return true
            }
            return previous.domain.caseInsensitiveCompare(rule.domain) != .orderedSame
        }

        clearAutoPassthrough(matching: rulesToRetry)
    }

    private func clearAutoPassthroughForActiveIncludeRules() {
        clearAutoPassthrough(matching: rules.filter { $0.listType == .include && $0.isEnabled })
    }

    private func clearAutoPassthrough(matching rules: [SSLProxyingRule]) {
        guard !rules.isEmpty else {
            return
        }

        passthroughLock.lock()
        let removedCount: Int

        if rules.contains(where: { $0.domain == "*" }) {
            removedCount = autoPassthroughHosts.count
            autoPassthroughHosts.removeAll()
        } else {
            let hostsToRemove = autoPassthroughHosts.keys.filter { host in
                rules.contains { $0.matches(host) }
            }
            removedCount = hostsToRemove.count
            for host in hostsToRemove {
                autoPassthroughHosts.removeValue(forKey: host)
            }
        }

        passthroughLock.unlock()

        guard removedCount > 0 else {
            return
        }

        persistPassthroughHosts()
        Self.logger.info("Cleared \(removedCount) auto-passthrough host(s) after SSL intercept scope change")
    }

    private func loadPassthroughHosts() {
        let url = resolvedPassthroughStorageURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: Date].self, from: data)
            let now = Date()
            var loaded = 0
            passthroughLock.lock()
            for (host, timestamp) in decoded where now.timeIntervalSince(timestamp) <= Self.passthroughTTLSeconds {
                autoPassthroughHosts[host] = timestamp
                loaded += 1
            }
            passthroughLock.unlock()
            if loaded > 0 {
                Self.logger.info("Loaded \(loaded) persisted auto-passthrough hosts")
            }
        } catch {
            Self.logger.error("Failed to load auto-passthrough hosts: \(error.localizedDescription)")
        }
    }

    nonisolated private func persistPassthroughHosts() {
        let url = resolvedPassthroughStorageURL
        passthroughLock.lock()
        let snapshot = autoPassthroughHosts
        passthroughLock.unlock()

        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Failed to persist auto-passthrough hosts: \(error.localizedDescription)")
        }
    }
}

// MARK: - SSLProxyingStorage

/// Versioned envelope for persisting SSL proxying settings.
private struct SSLProxyingStorage: Codable {
    let schemaVersion: Int
    let isEnabled: Bool
    let bypassDomains: String
    let rules: [SSLProxyingRule]
}
