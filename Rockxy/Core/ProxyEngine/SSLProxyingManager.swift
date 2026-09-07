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

    /// Application-scoped rules. Include = Decrypt, Exclude = Tunnel, mirroring host rules but
    /// matched against a resolved `ClientApplicationIdentity`.
    private(set) var applicationRules: [ApplicationSSLProxyingRule] = [] {
        didSet {
            rebuildApplicationCache()
        }
    }

    var includeRules: [SSLProxyingRule] {
        rules.filter { $0.listType == .include }
    }

    var excludeRules: [SSLProxyingRule] {
        rules.filter { $0.listType == .exclude }
    }

    var applicationIncludeRules: [ApplicationSSLProxyingRule] {
        applicationRules.filter { $0.listType == .include }
    }

    var applicationExcludeRules: [ApplicationSSLProxyingRule] {
        applicationRules.filter { $0.listType == .exclude }
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
            let oldValue = _forceGlobalPassthrough
            guard oldValue != newValue else {
                passthroughLock.unlock()
                return
            }
            _forceGlobalPassthrough = newValue
            passthroughLock.unlock()
            Self.logger.info("Global TLS passthrough \(newValue ? "enabled" : "disabled")")
            NotificationCenter.default.post(name: .sslProxyingStateDidChange, object: nil)
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

    // MARK: - Application Rule CRUD

    func addApplicationRule(_ rule: ApplicationSSLProxyingRule) {
        applicationRules.append(rule)
        clearAutoPassthroughIfNeeded(for: [rule])
        save()
    }

    func addApplicationRules(_ newRules: [ApplicationSSLProxyingRule]) {
        applicationRules.append(contentsOf: newRules)
        clearAutoPassthroughIfNeeded(for: newRules)
        save()
    }

    func removeApplicationRule(id: UUID) {
        applicationRules.removeAll { $0.id == id }
        save()
    }

    func removeApplicationRules(ids: Set<UUID>) {
        applicationRules.removeAll { ids.contains($0.id) }
        save()
    }

    func toggleApplicationRule(id: UUID) {
        guard let index = applicationRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        let previous = applicationRules[index]
        applicationRules[index].isEnabled.toggle()
        clearAutoPassthroughIfNeeded(for: [applicationRules[index]], previousRules: [previous])
        save()
    }

    func setApplicationRuleEnabled(id: UUID, enabled: Bool) {
        guard let index = applicationRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard applicationRules[index].isEnabled != enabled else {
            return
        }
        let previous = applicationRules[index]
        applicationRules[index].isEnabled = enabled
        clearAutoPassthroughIfNeeded(for: [applicationRules[index]], previousRules: [previous])
        save()
    }

    func updateApplicationRule(_ rule: ApplicationSSLProxyingRule) {
        guard let index = applicationRules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        let previous = applicationRules[index]
        applicationRules[index] = rule
        clearAutoPassthroughIfNeeded(for: [rule], previousRules: [previous])
        save()
    }

    func replaceAllApplicationRules(_ newRules: [ApplicationSSLProxyingRule]) {
        applicationRules = newRules
        clearAutoPassthroughForActiveApplicationIncludeRules()
        save()
        Self.logger.info("Replaced all application SSL proxying rules (\(newRules.count) rules)")
    }

    /// Thread-safe check usable from NIO event loops.
    /// Decision chain: enabled → global passthrough → bypass → exclude → include.
    nonisolated func shouldIntercept(_ host: String) -> Bool {
        shouldIntercept(host: host, application: nil)
    }

    /// Whether the host is covered by the TLS-only bypass patterns configured in HTTPS
    /// Decryption. Exposed separately from `shouldIntercept` so quick actions can explain why a
    /// Decrypt request cannot take effect instead of silently adding an overridden rule.
    nonisolated func isHostInTLSBypassList(_ host: String) -> Bool {
        passthroughLock.lock()
        let patterns = cachedBypassPatterns
        passthroughLock.unlock()
        return matchesBypassPattern(host, patterns: patterns)
    }

    /// Combined host + application interception decision, table-order independent.
    ///
    /// Deterministic order: global disabled/passthrough/bypass ⇒ tunnel; any matching enabled
    /// host **or** application Tunnel (exclude) ⇒ tunnel; any matching enabled host **or**
    /// application Decrypt (include) ⇒ intercept; otherwise tunnel. Application rules
    /// participate only for a non-nil resolved identity — a nil (remote/unresolved) identity
    /// can never enable application decryption.
    nonisolated func shouldIntercept(host: String, application: ClientApplicationIdentity?) -> Bool {
        guard isDecryptionConfigured(host: host, application: application) else {
            return false
        }

        passthroughLock.lock()
        let globalPassthrough = _forceGlobalPassthrough
        passthroughLock.unlock()

        return !globalPassthrough
    }

    /// Whether the persisted HTTPS policy selects Decrypt for this host/application pair.
    ///
    /// This intentionally excludes the temporary certificate-readiness fallback
    /// (`forceGlobalPassthrough`) and per-host auto-passthrough state. Settings, sidebar menus,
    /// and inspectors use it to present the configured rule accurately even while Rockxy is
    /// temporarily unable to intercept. The proxy pipeline must continue to call
    /// `shouldIntercept(host:application:)`, which layers runtime readiness on top.
    nonisolated func isDecryptionConfigured(
        host: String,
        application: ClientApplicationIdentity? = nil
    ) -> Bool {
        lock.lock()
        let enabled = cachedIsEnabled
        let includeSnapshot = cachedEnabledIncludeRules
        let excludeSnapshot = cachedEnabledExcludeRules
        let appIncludeSnapshot = cachedEnabledAppIncludeRules
        let appExcludeSnapshot = cachedEnabledAppExcludeRules
        lock.unlock()

        if !enabled {
            return false
        }

        passthroughLock.lock()
        let bypassPatterns = cachedBypassPatterns
        passthroughLock.unlock()

        if matchesBypassPattern(host, patterns: bypassPatterns) {
            return false
        }

        // Tunnel (exclude) wins across both host and application scopes.
        if excludeSnapshot.contains(where: { $0.matches(host) }) {
            return false
        }
        if let application, appExcludeSnapshot.contains(where: { $0.matches(application) }) {
            return false
        }

        // Decrypt (include) enables interception, including for never-before-seen hosts.
        if includeSnapshot.contains(where: { $0.matches(host) }) {
            return true
        }
        if let application, appIncludeSnapshot.contains(where: { $0.matches(application) }) {
            return true
        }

        return false
    }

    /// Whether resolving a per-connection application identity could change any TLS decision.
    /// Nonisolated + thread-safe so the proxy accept path can consult it without hopping actors.
    nonisolated func hasEnabledApplicationRules() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedIsEnabled && (!cachedEnabledAppIncludeRules.isEmpty || !cachedEnabledAppExcludeRules.isEmpty)
    }

    /// Whether the current policy contains any enabled host or application Decrypt rule.
    /// A trusted Root CA alone does not decrypt HTTPS; without one of these rules every
    /// HTTPS connection is intentionally recorded as an opaque CONNECT tunnel.
    nonisolated func hasEnabledDecryptRules() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedIsEnabled
            && (!cachedEnabledIncludeRules.isEmpty || !cachedEnabledAppIncludeRules.isEmpty)
    }

    /// Whether an unresolved local application must remain tunneled. A host Decrypt rule cannot
    /// safely override an application Tunnel rule until the connection owner is known.
    nonisolated func hasEnabledApplicationTunnelRules() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedIsEnabled && !cachedEnabledAppExcludeRules.isEmpty
    }

    /// Called from PostHandshakeHandler when a client rejects our intercepted certificate.
    nonisolated func markHostForPassthrough(
        _ host: String,
        application: ClientApplicationIdentity? = nil
    ) {
        markHostForPassthrough(host, clientIdentifier: application?.identifier)
    }

    /// Client-scoped variant used when the caller is a remote device rather than a local app.
    /// The identifier is already privacy-preserving and stable only for the capture boundary.
    nonisolated func markHostForPassthrough(
        _ host: String,
        clientIdentifier: String?
    ) {
        let scope = AutoPassthroughScope(
            host: host,
            clientIdentifier: clientIdentifier
        )
        passthroughLock.lock()
        autoPassthroughHosts[scope] = Date()
        passthroughLock.unlock()
        Self.logger.info("Scoped auto-passthrough enabled for \(host) after TLS failure")
        persistPassthroughHosts()
    }

    nonisolated func clearAutoPassthrough() {
        passthroughLock.lock()
        let hadEntries = !autoPassthroughHosts.isEmpty
        autoPassthroughHosts.removeAll()
        passthroughLock.unlock()
        persistPassthroughHosts()
        Self.logger.info("Cleared all auto-passthrough hosts")

        guard hadEntries else {
            return
        }

        // Certificate readiness clears `forceGlobalPassthrough` before it clears these per-host
        // fallbacks. The first state notification therefore still sees the hosts as passthrough.
        // Notify again after the fallback state is actually gone so any live raw tunnel whose
        // host is now interceptable is reset before the browser reuses it.
        NotificationCenter.default.post(name: .sslProxyingStateDidChange, object: nil)
    }

    /// Clears the protection fallback for one host so its next connection can retry TLS interception.
    /// Returns `true` when a recent TLS rejection was present and cleared.
    @discardableResult
    nonisolated func retryInterception(for host: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            return false
        }

        passthroughLock.lock()
        let matchingScopes = autoPassthroughHosts.keys.filter {
            $0.host.caseInsensitiveCompare(normalizedHost) == .orderedSame
        }
        for scope in matchingScopes {
            autoPassthroughHosts.removeValue(forKey: scope)
        }
        passthroughLock.unlock()

        guard !matchingScopes.isEmpty else {
            return false
        }

        persistPassthroughHosts()
        // Clearing the auto-passthrough fallback can make this host interceptable again while a
        // raw `.autoPassthrough` tunnel is still live (the inspector retry path may not touch any
        // rule, so `save()` never fires). Post the policy-change notification so the live-tunnel
        // observer resets that tunnel and the next request enters interception. Posted only on a
        // real state change — the no-match early return above never reaches here.
        NotificationCenter.default.post(name: .sslProxyingStateDidChange, object: nil)
        return true
    }

    /// Thread-safe check for hosts that should skip interception due to recent TLS failure.
    nonisolated func isAutoPassthrough(
        _ host: String,
        application: ClientApplicationIdentity? = nil
    ) -> Bool {
        isAutoPassthrough(host, clientIdentifier: application?.identifier)
    }

    nonisolated func isAutoPassthrough(
        _ host: String,
        clientIdentifier: String?
    ) -> Bool {
        let scope = AutoPassthroughScope(
            host: host,
            clientIdentifier: clientIdentifier
        )
        passthroughLock.lock()
        defer { passthroughLock.unlock() }
        guard let timestamp = autoPassthroughHosts[scope] else {
            return false
        }
        if Date().timeIntervalSince(timestamp) > Self.passthroughTTLSeconds {
            autoPassthroughHosts.removeValue(forKey: scope)
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
                    applicationRules = storage.applicationRules ?? []
                    rebuildCache()
                    Self.logger
                        .info("Loaded v\(storage.schemaVersion) SSL proxying settings (\(self.rules.count) rules)")
                } else {
                    let legacyRules = try JSONDecoder().decode([SSLProxyingRule].self, from: data)
                    isEnabled = true
                    bypassDomains = Self.defaultBypassDomains
                    rules = legacyRules
                    applicationRules = []
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
                schemaVersion: 3,
                isEnabled: isEnabled,
                bypassDomains: bypassDomains,
                rules: rules,
                applicationRules: applicationRules
            )
            let data = try JSONEncoder().encode(storage)
            try data.write(to: url, options: .atomic)
            Self.logger.debug("Saved \(self.rules.count) SSL proxying rules")
        } catch {
            Self.logger.error("Failed to save SSL proxying rules: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: .sslProxyingStateDidChange, object: nil)
    }

    func exportRules() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let storage = SSLProxyingStorage(
            schemaVersion: 3,
            isEnabled: isEnabled,
            bypassDomains: bypassDomains,
            rules: rules,
            applicationRules: applicationRules
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
            replaceAllApplicationRules(storage.applicationRules ?? [])
            replaceAllRules(storage.rules)
        } else {
            let decoded = try JSONDecoder().decode([SSLProxyingRule].self, from: data)
            isEnabled = true
            bypassDomains = Self.defaultBypassDomains
            rebuildBypassCache()
            replaceAllApplicationRules([])
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
    nonisolated(unsafe) private var cachedEnabledAppIncludeRules: [ApplicationSSLProxyingRule] = []
    nonisolated(unsafe) private var cachedEnabledAppExcludeRules: [ApplicationSSLProxyingRule] = []
    nonisolated(unsafe) private var cachedIsEnabled: Bool = true

    private let passthroughLock = NSLock()
    nonisolated(unsafe) private var autoPassthroughHosts: [AutoPassthroughScope: Date] = [:]
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

    private func rebuildApplicationCache() {
        let enabledInclude = applicationRules.filter { $0.isEnabled && $0.listType == .include }
        let enabledExclude = applicationRules.filter { $0.isEnabled && $0.listType == .exclude }
        lock.lock()
        cachedEnabledAppIncludeRules = enabledInclude
        cachedEnabledAppExcludeRules = enabledExclude
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

    private func clearAutoPassthroughIfNeeded(
        for rules: [ApplicationSSLProxyingRule],
        previousRules: [ApplicationSSLProxyingRule] = []
    ) {
        guard isEnabled else {
            return
        }
        let previousByID = Dictionary(uniqueKeysWithValues: previousRules.map { ($0.id, $0) })
        let identifiersToRetry = Set(rules.compactMap { rule -> String? in
            guard rule.listType == .include, rule.isEnabled else {
                return nil
            }
            guard let previous = previousByID[rule.id] else {
                return rule.applicationIdentifier
            }
            if previous.listType != .include || !previous.isEnabled
                || previous.applicationIdentifier != rule.applicationIdentifier
            {
                return rule.applicationIdentifier
            }
            return nil
        })
        clearAutoPassthrough(clientIdentifiers: identifiersToRetry)
    }

    private func clearAutoPassthroughForActiveApplicationIncludeRules() {
        clearAutoPassthrough(clientIdentifiers: Set(
            applicationRules
                .filter { $0.listType == .include && $0.isEnabled }
                .map(\.applicationIdentifier)
        ))
    }

    private func clearAutoPassthrough(clientIdentifiers: Set<String>) {
        let normalizedIdentifiers = Set(clientIdentifiers.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        guard !normalizedIdentifiers.isEmpty else {
            return
        }

        passthroughLock.lock()
        let scopesToRemove = autoPassthroughHosts.keys.filter { scope in
            scope.clientIdentifier.map(normalizedIdentifiers.contains) == true
        }
        for scope in scopesToRemove {
            autoPassthroughHosts.removeValue(forKey: scope)
        }
        passthroughLock.unlock()

        guard !scopesToRemove.isEmpty else {
            return
        }
        persistPassthroughHosts()
        Self.logger.info(
            "Cleared \(scopesToRemove.count) auto-passthrough host(s) after application Decrypt scope change"
        )
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
            let scopesToRemove = autoPassthroughHosts.keys.filter { scope in
                rules.contains { $0.matches(scope.host) }
            }
            removedCount = scopesToRemove.count
            for scope in scopesToRemove {
                autoPassthroughHosts.removeValue(forKey: scope)
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
            let decoded = try JSONDecoder().decode(AutoPassthroughStorage.self, from: data)
            guard decoded.schemaVersion == AutoPassthroughStorage.currentSchemaVersion else {
                Self.logger.info("Discarding legacy global auto-passthrough state")
                return
            }
            let now = Date()
            var loaded = 0
            passthroughLock.lock()
            for record in decoded.records where
                record.scope.clientIdentifier != nil
                && now.timeIntervalSince(record.timestamp) <= Self.passthroughTTLSeconds
            {
                autoPassthroughHosts[record.scope] = record.timestamp
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
        let snapshot = AutoPassthroughStorage(
            schemaVersion: AutoPassthroughStorage.currentSchemaVersion,
            records: autoPassthroughHosts.map {
                AutoPassthroughRecord(scope: $0.key, timestamp: $0.value)
            }
        )
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

// MARK: - AutoPassthroughStorage

private struct AutoPassthroughScope: Codable, Hashable {
    let host: String
    let clientIdentifier: String?

    init(host: String, clientIdentifier: String?) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.clientIdentifier = clientIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct AutoPassthroughRecord: Codable {
    let scope: AutoPassthroughScope
    let timestamp: Date
}

private struct AutoPassthroughStorage: Codable {
    static let currentSchemaVersion = 3

    let schemaVersion: Int
    let records: [AutoPassthroughRecord]
}

// MARK: - SSLProxyingStorage

/// Versioned envelope for persisting SSL proxying settings.
///
/// `applicationRules` is an optional sibling introduced in schema v3. It is omitted from
/// older payloads (v2), and older builds — whose model lacks the key — decode v3 by ignoring
/// it while preserving host `rules`, so the format degrades gracefully in both directions.
private struct SSLProxyingStorage: Codable {
    let schemaVersion: Int
    let isEnabled: Bool
    let bypassDomains: String
    let rules: [SSLProxyingRule]
    let applicationRules: [ApplicationSSLProxyingRule]?
}
