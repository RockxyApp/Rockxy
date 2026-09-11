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
        migrationStorageURLs = Self.defaultMigrationStorageURLs
        passthroughNowProvider = Date.init
        cachedEnabledIncludeRules = []
        cachedEnabledExcludeRules = []
        load()
    }

    /// Test-only initializer with injectable storage path.
    init(
        storageURL: URL,
        passthroughStorageURL: URL? = nil,
        migrationStorageURLs: [URL] = [],
        passthroughNowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        customStorageURL = storageURL
        customPassthroughStorageURL = passthroughStorageURL
        self.migrationStorageURLs = migrationStorageURLs
        self.passthroughNowProvider = passthroughNowProvider
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
        let now = passthroughNowProvider()
        passthroughLock.lock()
        autoPassthroughHosts = autoPassthroughHosts.filter {
            now.timeIntervalSince($0.value) <= Self.passthroughTTLSeconds
        }
        if autoPassthroughHosts[scope] == nil,
           autoPassthroughHosts.count >= Self.maximumAutoPassthroughEntries,
           let oldestScope = autoPassthroughHosts.min(by: { $0.value < $1.value })?.key
        {
            autoPassthroughHosts.removeValue(forKey: oldestScope)
        }
        autoPassthroughHosts[scope] = now
        passthroughLock.unlock()
        Self.logger.info("Scoped auto-passthrough enabled for \(host) after TLS failure")
        persistPassthroughHosts()
    }

    /// Gives a client a brief raw-tunnel retry after an unclassified TLS failure. A nil identity
    /// is scoped to unresolved clients for this host and remains memory-only.
    /// Unlike certificate rejection and known compatibility fallbacks, this state is memory-only
    /// so a transient network error cannot silently disable decryption across app launches.
    nonisolated func markHostForTransientPassthrough(
        _ host: String,
        clientIdentifier: String?
    ) {
        let scope = AutoPassthroughScope(host: host, clientIdentifier: clientIdentifier)
        let now = passthroughNowProvider()
        passthroughLock.lock()
        transientPassthroughHosts = transientPassthroughHosts.filter {
            now.timeIntervalSince($0.value) <= Self.transientPassthroughTTLSeconds
        }
        if transientPassthroughHosts[scope] == nil,
           transientPassthroughHosts.count >= Self.maximumAutoPassthroughEntries,
           let oldestScope = transientPassthroughHosts.min(by: { $0.value < $1.value })?.key
        {
            transientPassthroughHosts.removeValue(forKey: oldestScope)
        }
        transientPassthroughHosts[scope] = now
        passthroughLock.unlock()
        Self.logger.info("Temporary scoped passthrough enabled for \(host) after an unclassified TLS failure")
    }

    nonisolated func clearAutoPassthrough() {
        passthroughLock.lock()
        let hadEntries = !autoPassthroughHosts.isEmpty || !transientPassthroughHosts.isEmpty
        autoPassthroughHosts.removeAll()
        transientPassthroughHosts.removeAll()
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

    /// Waits for every fallback-state snapshot queued before this call to reach disk.
    /// Capture-time writes remain asynchronous; app termination uses this barrier so a
    /// recently cleared fallback cannot reappear on the next launch.
    @discardableResult
    nonisolated func flushPassthroughPersistence(timeout: DispatchTimeInterval = .seconds(2)) -> Bool {
        let drained = DispatchSemaphore(value: 0)
        passthroughLock.lock()
        enqueuePassthroughSnapshotLocked()
        Self.passthroughPersistenceQueue.async {
            drained.signal()
        }
        passthroughLock.unlock()
        return drained.wait(timeout: .now() + timeout) == .success
    }

    /// Retries every protected host for the selected client scopes while preserving fallback
    /// state for unrelated applications and remote devices. Returns the number of host/client
    /// entries removed.
    @discardableResult
    nonisolated func retryInterception(clientIdentifiers: Set<String>) -> Int {
        let normalizedIdentifiers = Set(clientIdentifiers.compactMap { identifier -> String? in
            let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty ? nil : normalized
        })
        guard !normalizedIdentifiers.isEmpty else {
            return 0
        }

        passthroughLock.lock()
        let matchingScopes = autoPassthroughHosts.keys.filter { scope in
            scope.clientIdentifier.map(normalizedIdentifiers.contains) == true
        }
        let transientMatchingScopes = transientPassthroughHosts.keys.filter { scope in
            scope.clientIdentifier.map(normalizedIdentifiers.contains) == true
        }
        for scope in matchingScopes {
            autoPassthroughHosts.removeValue(forKey: scope)
        }
        for scope in transientMatchingScopes {
            transientPassthroughHosts.removeValue(forKey: scope)
        }
        passthroughLock.unlock()

        let removedCount = matchingScopes.count + transientMatchingScopes.count
        guard removedCount > 0 else {
            return 0
        }

        if !matchingScopes.isEmpty {
            persistPassthroughHosts()
        }
        Self.logger.info(
            "Cleared \(removedCount) scoped auto-passthrough host(s) for explicit HTTPS retry"
        )
        NotificationCenter.default.post(name: .sslProxyingStateDidChange, object: nil)
        return removedCount
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
        let transientMatchingScopes = transientPassthroughHosts.keys.filter {
            $0.host.caseInsensitiveCompare(normalizedHost) == .orderedSame
        }
        for scope in matchingScopes {
            autoPassthroughHosts.removeValue(forKey: scope)
        }
        for scope in transientMatchingScopes {
            transientPassthroughHosts.removeValue(forKey: scope)
        }
        passthroughLock.unlock()

        guard !matchingScopes.isEmpty || !transientMatchingScopes.isEmpty else {
            return false
        }

        if !matchingScopes.isEmpty {
            persistPassthroughHosts()
        }
        RecentFailureTracker.certificateRejections.reset(host: normalizedHost)
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
        let now = passthroughNowProvider()
        if let timestamp = autoPassthroughHosts[scope] {
            if now.timeIntervalSince(timestamp) <= Self.passthroughTTLSeconds {
                return true
            }
            autoPassthroughHosts.removeValue(forKey: scope)
        }
        if let timestamp = transientPassthroughHosts[scope] {
            if now.timeIntervalSince(timestamp) <= Self.transientPassthroughTTLSeconds {
                return true
            }
            transientPassthroughHosts.removeValue(forKey: scope)
        }
        return false
    }

    func load() {
        let url = resolvedStorageURL
        if let (data, sourceURL) = settingsDataToLoad(primaryURL: url) {
            do {
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
                    if sourceURL != url {
                        Self.logger.info("Recovered HTTPS decryption settings from an earlier Rockxy namespace")
                        save()
                    }
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

    nonisolated private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "SSLProxyingManager"
    )
    nonisolated private static let passthroughTTLSeconds: TimeInterval = 86_400
    nonisolated private static let transientPassthroughTTLSeconds: TimeInterval = 60
    nonisolated private static let maximumAutoPassthroughEntries = 2_048
    nonisolated private static let passthroughPersistenceQueue = DispatchQueue(
        label: "\(RockxyIdentity.current.logSubsystem).ssl-passthrough-persistence",
        qos: .utility
    )

    nonisolated private static var defaultMigrationStorageURLs: [URL] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let activeDirectory = RockxyIdentity.current.appSupportDirectoryName
        let legacyDirectories = [
            "com.amunx.Rockxy",
            RockxyIdentity.current.familyNamespace,
            "\(RockxyIdentity.current.familyNamespace).community",
        ]
        return Array(Set(legacyDirectories))
            .filter { $0 != activeDirectory }
            .map {
                appSupport
                    .appendingPathComponent($0, isDirectory: true)
                    .appendingPathComponent("ssl-proxying-rules.json")
            }
    }

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
    private let migrationStorageURLs: [URL]
    private let passthroughNowProvider: @Sendable () -> Date

    private let lock = NSLock()
    nonisolated(unsafe) private var cachedEnabledIncludeRules: [SSLProxyingRule]
    nonisolated(unsafe) private var cachedEnabledExcludeRules: [SSLProxyingRule]
    nonisolated(unsafe) private var cachedEnabledAppIncludeRules: [ApplicationSSLProxyingRule] = []
    nonisolated(unsafe) private var cachedEnabledAppExcludeRules: [ApplicationSSLProxyingRule] = []
    nonisolated(unsafe) private var cachedIsEnabled: Bool = true

    private let passthroughLock = NSLock()
    nonisolated(unsafe) private var autoPassthroughHosts: [AutoPassthroughScope: Date] = [:]
    nonisolated(unsafe) private var transientPassthroughHosts: [AutoPassthroughScope: Date] = [:]
    nonisolated(unsafe) private var _forceGlobalPassthrough = false
    nonisolated(unsafe) private var cachedBypassPatterns: [String] = []
    nonisolated(unsafe) private var passthroughPersistenceDirty = false
    nonisolated(unsafe) private var passthroughPersistenceScheduled = false

    private var resolvedStorageURL: URL {
        customStorageURL ?? Self.defaultStorageURL
    }

    private func settingsDataToLoad(primaryURL: URL) -> (Data, URL)? {
        if let data = try? Data(contentsOf: primaryURL) {
            if Self.isValidSettingsData(data) {
                return (data, primaryURL)
            }
            Self.logger.error("Active HTTPS decryption settings are unreadable; checking earlier Rockxy namespaces")
        }

        let candidates = migrationStorageURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { lhs, rhs in
                let leftDate = try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let rightDate = try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if leftDate == rightDate {
                    return lhs.path < rhs.path
                }
                return (leftDate ?? .distantPast) > (rightDate ?? .distantPast)
            }
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate) else {
                continue
            }
            if Self.isValidSettingsData(data) {
                return (data, candidate)
            }
        }
        return nil
    }

    private static func isValidSettingsData(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(SSLProxyingStorage.self, from: data)) != nil
            || (try? JSONDecoder().decode([SSLProxyingRule].self, from: data)) != nil
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
        let transientScopesToRemove = transientPassthroughHosts.keys.filter { scope in
            scope.clientIdentifier.map(normalizedIdentifiers.contains) == true
        }
        for scope in scopesToRemove {
            autoPassthroughHosts.removeValue(forKey: scope)
        }
        for scope in transientScopesToRemove {
            transientPassthroughHosts.removeValue(forKey: scope)
        }
        passthroughLock.unlock()

        let removedCount = scopesToRemove.count + transientScopesToRemove.count
        guard removedCount > 0 else {
            return
        }
        if !scopesToRemove.isEmpty {
            persistPassthroughHosts()
        }
        Self.logger.info(
            "Cleared \(removedCount) auto-passthrough host(s) after application Decrypt scope change"
        )
    }

    private func clearAutoPassthrough(matching rules: [SSLProxyingRule]) {
        guard !rules.isEmpty else {
            return
        }

        passthroughLock.lock()
        let removedCount: Int
        let removedPersistentCount: Int

        if rules.contains(where: { $0.domain == "*" }) {
            removedPersistentCount = autoPassthroughHosts.count
            removedCount = removedPersistentCount + transientPassthroughHosts.count
            autoPassthroughHosts.removeAll()
            transientPassthroughHosts.removeAll()
        } else {
            let scopesToRemove = autoPassthroughHosts.keys.filter { scope in
                rules.contains { $0.matches(scope.host) }
            }
            let transientScopesToRemove = transientPassthroughHosts.keys.filter { scope in
                rules.contains { $0.matches(scope.host) }
            }
            removedPersistentCount = scopesToRemove.count
            removedCount = removedPersistentCount + transientScopesToRemove.count
            for scope in scopesToRemove {
                autoPassthroughHosts.removeValue(forKey: scope)
            }
            for scope in transientScopesToRemove {
                transientPassthroughHosts.removeValue(forKey: scope)
            }
        }

        passthroughLock.unlock()

        guard removedCount > 0 else {
            return
        }

        if removedPersistentCount > 0 {
            persistPassthroughHosts()
        }
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
            let now = passthroughNowProvider()
            let validRecords = decoded.records
                .filter {
                    $0.scope.clientIdentifier != nil
                        && now.timeIntervalSince($0.timestamp) <= Self.passthroughTTLSeconds
                }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(Self.maximumAutoPassthroughEntries)
            passthroughLock.lock()
            for record in validRecords {
                autoPassthroughHosts[record.scope] = record.timestamp
            }
            passthroughLock.unlock()
            let loaded = validRecords.count
            if loaded > 0 {
                Self.logger.info("Loaded \(loaded) persisted auto-passthrough hosts")
            }
        } catch {
            Self.logger.error("Failed to load auto-passthrough hosts: \(error.localizedDescription)")
        }
    }

    nonisolated private func persistPassthroughHosts() {
        passthroughLock.lock()
        enqueuePassthroughSnapshotLocked()
        passthroughLock.unlock()
    }

    /// Must be called while `passthroughLock` is held so a mutation marks the latest state dirty
    /// before the coalesced writer is scheduled on the serial utility queue.
    nonisolated private func enqueuePassthroughSnapshotLocked() {
        passthroughPersistenceDirty = true
        guard !passthroughPersistenceScheduled else {
            return
        }
        passthroughPersistenceScheduled = true
        Self.passthroughPersistenceQueue.async { [self] in
            drainPassthroughPersistence()
        }
    }

    /// Coalesces rejection bursts while preserving ordered, latest-state persistence. The serial
    /// queue keeps writing until no mutation arrived during the preceding atomic write.
    nonisolated private func drainPassthroughPersistence() {
        while true {
            passthroughLock.lock()
            guard passthroughPersistenceDirty else {
                passthroughPersistenceScheduled = false
                passthroughLock.unlock()
                return
            }
            passthroughPersistenceDirty = false
            let url = resolvedPassthroughStorageURL
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
}

// MARK: - AutoPassthroughStorage

private struct AutoPassthroughScope: Codable, Hashable, Sendable {
    let host: String
    let clientIdentifier: String?

    init(host: String, clientIdentifier: String?) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.clientIdentifier = clientIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct AutoPassthroughRecord: Codable, Sendable {
    let scope: AutoPassthroughScope
    let timestamp: Date
}

private struct AutoPassthroughStorage: Codable, Sendable {
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
