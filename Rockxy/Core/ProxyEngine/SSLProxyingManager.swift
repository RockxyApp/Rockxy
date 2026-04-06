import Foundation
import os

/// Manages the list of domains for which Rockxy will perform TLS interception.
/// Domains not in this list pass through as raw encrypted tunnels.
///
/// The `shouldIntercept(_:)` method is `nonisolated` and thread-safe so it can be
/// called directly from NIO event loops without hopping to the main actor.
@MainActor @Observable
final class SSLProxyingManager {
    // MARK: Lifecycle

    private init() {
        cachedEnabledRules = []
        load()
    }

    // MARK: Internal

    static let shared = SSLProxyingManager()

    private(set) var rules: [SSLProxyingRule] = [] {
        didSet {
            rebuildCache()
        }
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

    func addRule(_ rule: SSLProxyingRule) {
        rules.append(rule)
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
        rules[index].isEnabled.toggle()
        save()
    }

    /// Thread-safe check usable from NIO event loops.
    /// Uses a lock-protected snapshot of enabled rules to avoid main-actor hop.
    nonisolated func shouldIntercept(_ host: String) -> Bool {
        passthroughLock.lock()
        let globalPassthrough = _forceGlobalPassthrough
        passthroughLock.unlock()

        if globalPassthrough {
            return false
        }

        let snapshot: [SSLProxyingRule]
        lock.lock()
        snapshot = cachedEnabledRules
        lock.unlock()

        if snapshot.isEmpty {
            return true
        }

        return snapshot.contains { $0.matches(host) }
    }

    /// Called from PostHandshakeHandler when a client rejects our intercepted certificate.
    /// Marks the host for raw passthrough so subsequent connections skip interception.
    /// Persists to disk so passthrough survives app restarts.
    nonisolated func markHostForPassthrough(_ host: String) {
        passthroughLock.lock()
        autoPassthroughHosts[host] = Date()
        passthroughLock.unlock()
        Self.logger.info("Auto-passthrough enabled for \(host) after TLS failure")
        persistPassthroughHosts()
    }

    /// Removes all persisted auto-passthrough hosts, allowing interception to be retried.
    nonisolated func clearAutoPassthrough() {
        passthroughLock.lock()
        autoPassthroughHosts.removeAll()
        passthroughLock.unlock()
        persistPassthroughHosts()
        Self.logger.info("Cleared all auto-passthrough hosts")
    }

    /// Thread-safe check for hosts that should skip interception due to recent TLS failure.
    /// Uses a 24-hour TTL for persisted entries before retrying interception.
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
        let url = Self.storageURL
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                rules = try JSONDecoder().decode([SSLProxyingRule].self, from: data)
                Self.logger.info("Loaded \(self.rules.count) SSL proxying rules")
            } catch {
                Self.logger.error("Failed to load SSL proxying rules: \(error.localizedDescription)")
            }
        } else {
            Self.logger.info("No SSL proxying rules file found, starting with empty list")
        }
        loadPassthroughHosts()
    }

    func save() {
        let url = Self.storageURL
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(rules)
            try data.write(to: url, options: .atomic)
            Self.logger.debug("Saved \(self.rules.count) SSL proxying rules")
        } catch {
            Self.logger.error("Failed to save SSL proxying rules: \(error.localizedDescription)")
        }
    }

    func exportRules() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(rules)
    }

    func importRules(from data: Data) throws {
        let decoded = try JSONDecoder().decode([SSLProxyingRule].self, from: data)
        rules = decoded
        save()
        Self.logger.info("Imported \(decoded.count) SSL proxying rules")
    }

    func addPresets() {
        let presetDomains = [
            "*.googleapis.com",
            "*.github.com",
            "*.githubusercontent.com",
            "*.api.openai.com",
            "*.stripe.com",
            "*.sentry.io",
            "*.firebase.io",
            "*.cloudflare.com",
        ]
        let existingDomains = Set(rules.map { $0.domain.lowercased() })
        var added = 0
        for domain in presetDomains {
            guard !existingDomains.contains(domain.lowercased()) else {
                continue
            }
            rules.append(SSLProxyingRule(domain: domain))
            added += 1
        }
        if added > 0 {
            save()
            Self.logger.info("Added \(added) preset SSL proxying rules")
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "SSLProxyingManager")
    private static let passthroughTTLSeconds: TimeInterval = 86400 // 24 hours

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("ssl-proxying-rules.json")
    }

    private nonisolated static var passthroughStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("auto-passthrough-hosts.json")
    }

    private let lock = NSLock()
    private nonisolated(unsafe) var cachedEnabledRules: [SSLProxyingRule]

    private let passthroughLock = NSLock()
    private nonisolated(unsafe) var autoPassthroughHosts: [String: Date] = [:]
    private nonisolated(unsafe) var _forceGlobalPassthrough = false

    private func rebuildCache() {
        let enabled = rules.filter(\.isEnabled)
        lock.lock()
        cachedEnabledRules = enabled
        lock.unlock()
    }

    private func loadPassthroughHosts() {
        let url = Self.passthroughStorageURL
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

    private nonisolated func persistPassthroughHosts() {
        let url = Self.passthroughStorageURL
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
