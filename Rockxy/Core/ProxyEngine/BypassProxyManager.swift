import Foundation
import os

/// Manages the list of domains that bypass Rockxy's proxy entirely.
/// Traffic to these domains goes directly to the network without interception.
///
/// The `isHostBypassed(_:)` method is `nonisolated` and thread-safe so it can be
/// called directly from NIO event loops without hopping to the main actor.
@MainActor @Observable
final class BypassProxyManager {
    // MARK: Lifecycle

    private init() {
        storageURLOverride = nil
        cachedEnabledDomains = []
        load()
    }

    /// Test-only initializer with isolated storage path.
    init(storageURL: URL) {
        storageURLOverride = storageURL
        cachedEnabledDomains = []
        load()
    }

    // MARK: Internal

    static let shared = BypassProxyManager()

    private(set) var domains: [BypassDomain] = [] {
        didSet {
            rebuildCache()
        }
    }

    func addDomain(_ domainString: String) {
        let trimmed = domainString.trimmingCharacters(in: .whitespaces).lowercased()
        guard ProxyBypassDomainValidator.isValid(trimmed) else {
            Self.logger.warning("Rejected invalid bypass domain")
            return
        }

        // Deduplicate
        guard !domains.contains(where: { $0.domain.lowercased() == trimmed }) else {
            Self.logger.debug("Bypass domain already exists: \(trimmed)")
            return
        }

        domains.append(BypassDomain(domain: trimmed))
        save()
        postChangeNotification()
        Self.logger.info("Added bypass domain: \(trimmed)")
    }

    func removeDomain(id: UUID) {
        domains.removeAll { $0.id == id }
        save()
        postChangeNotification()
    }

    func removeDomains(ids: Set<UUID>) {
        domains.removeAll { ids.contains($0.id) }
        save()
        postChangeNotification()
    }

    func toggleDomain(id: UUID) {
        guard let index = domains.firstIndex(where: { $0.id == id }) else {
            return
        }
        if !domains[index].isEnabled,
           !ProxyBypassDomainValidator.isValid(domains[index].domain)
        {
            Self.logger.warning("Refused to enable an invalid persisted bypass domain")
            return
        }
        domains[index].isEnabled.toggle()
        save()
        postChangeNotification()
    }

    /// Thread-safe check usable from NIO event loops.
    /// Uses a lock-protected snapshot of enabled domains to avoid main-actor hop.
    nonisolated func isHostBypassed(_ host: String) -> Bool {
        let snapshot: [BypassDomain]
        lock.lock()
        snapshot = cachedEnabledDomains
        lock.unlock()

        return snapshot.contains { $0.matches(host) }
    }

    /// Returns the list of enabled domain strings for system proxy configuration.
    func enabledDomainStrings() -> [String] {
        domains.filter(\.isEnabled).map(\.domain)
    }

    /// Returns enabled patterns expanded for macOS system proxy exceptions.
    func enabledDomainStringsForSystemProxy() -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for domain in domains where domain.isEnabled {
            for pattern in BypassDomain.systemProxyPatterns(for: domain.domain) {
                let key = pattern.lowercased()
                guard !seen.contains(key) else {
                    continue
                }
                seen.insert(key)
                result.append(pattern)
            }
        }

        return result
    }

    func load() {
        let url = resolvedStorageURL
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                var decoded = try JSONDecoder().decode([BypassDomain].self, from: data)
                var disabledInvalidEntries = 0
                for index in decoded.indices
                    where decoded[index].isEnabled
                    && !ProxyBypassDomainValidator.isValid(decoded[index].domain)
                {
                    decoded[index].isEnabled = false
                    disabledInvalidEntries += 1
                }
                domains = decoded
                if disabledInvalidEntries > 0 {
                    save()
                    Self.logger.warning(
                        "Disabled \(disabledInvalidEntries) invalid persisted bypass domain(s)"
                    )
                }
                Self.logger.info("Loaded \(self.domains.count) bypass proxy domains")
            } catch {
                Self.logger.error("Failed to load bypass proxy domains: \(error.localizedDescription)")
            }
        } else {
            Self.logger.info("No bypass proxy domains file found, starting with empty list")
        }
    }

    func save() {
        let url = resolvedStorageURL
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(domains)
            try data.write(to: url, options: .atomic)
            Self.logger.debug("Saved \(self.domains.count) bypass proxy domains")
        } catch {
            Self.logger.error("Failed to save bypass proxy domains: \(error.localizedDescription)")
        }
    }

    func exportDomains() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(domains)
    }

    func importDomains(from data: Data) throws {
        let decoded = try JSONDecoder().decode([BypassDomain].self, from: data)
        let normalizedPatterns = decoded.map { $0.domain.lowercased() }
        guard decoded.allSatisfy({ ProxyBypassDomainValidator.isValid($0.domain) }),
              Set(decoded.map(\.id)).count == decoded.count,
              Set(normalizedPatterns).count == decoded.count
        else {
            throw BypassProxyManagerError.invalidEntries
        }
        domains = decoded
        save()
        postChangeNotification()
        Self.logger.info("Imported \(decoded.count) bypass proxy domains")
    }

    func addPresets() {
        let presetDomains = [
            "localhost",
            "*.local",
            "127.0.0.1",
            "::1",
            "169.254.*",
        ]
        let existingDomains = Set(domains.map { $0.domain.lowercased() })
        var added = 0
        for domain in presetDomains {
            guard !existingDomains.contains(domain.lowercased()) else {
                continue
            }
            domains.append(BypassDomain(domain: domain))
            added += 1
        }
        if added > 0 {
            save()
            postChangeNotification()
            Self.logger.info("Added \(added) preset bypass domains")
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "BypassProxyManager")

    private static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("bypass-proxy-domains.json")
    }

    private let storageURLOverride: URL?

    private let lock = NSLock()
    nonisolated(unsafe) private var cachedEnabledDomains: [BypassDomain]

    private var resolvedStorageURL: URL {
        storageURLOverride ?? Self.defaultStorageURL
    }

    private func rebuildCache() {
        let enabled = domains.filter(\.isEnabled)
        lock.lock()
        cachedEnabledDomains = enabled
        lock.unlock()
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(name: .bypassProxyListDidChange, object: nil)
    }
}

enum BypassProxyManagerError: LocalizedError {
    case invalidEntries

    var errorDescription: String? {
        "The bypass list contains invalid or duplicate entries."
    }
}
