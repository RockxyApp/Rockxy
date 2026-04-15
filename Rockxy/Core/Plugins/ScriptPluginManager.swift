import Foundation
import os

// Defines `ScriptPluginManager`, which coordinates script plugin behavior in the plugin
// and scripting subsystem.

// MARK: - ScriptPluginError

enum ScriptPluginError: Error, LocalizedError {
    case pluginNotFound(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .pluginNotFound(id):
            "Plugin not found: \(id)"
        }
    }
}

// MARK: - ScriptPluginManager

actor ScriptPluginManager {
    // MARK: Lifecycle

    init(
        discovery: PluginDiscovery = PluginDiscovery(),
        defaults: UserDefaults = .standard,
        settingsProvider: (@Sendable () -> AppSettings)? = nil
    ) {
        self.discovery = discovery
        self.defaults = defaults
        self.runtime = ScriptRuntime(defaults: defaults)
        if let settingsProvider {
            self.settingsProviderOverride = settingsProvider
        } else {
            self.settingsProviderOverride = nil
        }
    }

    // MARK: Internal

    /// Snapshot of `plugins` updated by the actor after every mutation so that
    /// NIO event-loop threads can make pre-hook decisions without awaiting.
    nonisolated static let pluginSnapshot = OSAllocatedUnfairLock<[PluginInfo]>(initialState: [])

    private(set) var plugins: [PluginInfo] = []

    nonisolated let defaults: UserDefaults

    nonisolated let settingsProviderOverride: (@Sendable () -> AppSettings)?

    nonisolated var identity: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    var pluginsDirectoryURL: URL {
        get async { await discovery.pluginsDirectoryURL }
    }

    /// Whether the one-shot startup load has completed.
    var isReady: Bool {
        isLoadedOnce
    }

    /// Startup-readiness entry point. Runs the discovery + reconcile pass exactly
    /// once per process. Concurrent callers share the same in-flight task and all
    /// observe the same completion. Safe to call from multiple launch/capture sites.
    func ensureLoadedOnce() async {
        if isLoadedOnce {
            return
        }
        if let existing = loadOnceTask {
            await existing.value
            if isLoadedOnce {
                loadOnceTask = nil
            }
            return
        }
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.performInitialLoad()
        }
        loadOnceTask = task
        await task.value
        loadOnceTask = nil
    }

    /// Re-scan-able discovery path. Always runs a fresh discovery pass so that
    /// plugin create/install/delete/reload flows see new filesystem state. When
    /// a discovery is already in flight, the second caller awaits the same
    /// result rather than spawning a duplicate pass.
    func loadAllPlugins() async {
        if let existing = inFlightDiscoveryTask {
            await existing.value
            return
        }
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.performDiscoveryAndReconcile()
        }
        inFlightDiscoveryTask = task
        await task.value
        inFlightDiscoveryTask = nil
    }

    /// Atomically check quota, claim the enabled slot, load the runtime, and
    /// commit or roll back. The count check + isEnabled = true happen before
    /// the first await, so concurrent callers see the claimed slot.
    ///
    /// If the plugin is already enabled, returns `true` immediately as a
    /// no-op — no runtime reload, no quota consumption.
    func enablePluginIfAllowed(id: String, maxEnabled: Int) async throws -> Bool {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            throw ScriptPluginError.pluginNotFound(id)
        }

        if plugins[index].isEnabled {
            return true
        }

        let enabledCount = plugins.filter(\.isEnabled).count
        guard enabledCount < maxEnabled else {
            return false
        }

        plugins[index].isEnabled = true

        do {
            try await runtime.loadPlugin(plugins[index])
            guard let j = plugins.firstIndex(where: { $0.id == id }),
                  plugins[j].isEnabled else
            {
                await runtime.unloadPlugin(id: id)
                Self.logger.info("Plugin \(id) removed or disabled during enable — unloaded")
                return false
            }
            plugins[j].status = .active
            defaults.set(true, forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
            publishSnapshot()
            Self.logger.info("Enabled plugin: \(id)")
            return true
        } catch {
            if let j = plugins.firstIndex(where: { $0.id == id }) {
                plugins[j].isEnabled = false
                plugins[j].status = .error(error.localizedDescription)
            }
            throw error
        }
    }

    func disablePlugin(id: String) async {
        guard plugins.contains(where: { $0.id == id }) else {
            return
        }
        await runtime.unloadPlugin(id: id)
        if let index = plugins.firstIndex(where: { $0.id == id }) {
            plugins[index].isEnabled = false
            plugins[index].status = .disabled
        }
        defaults.set(false, forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
        publishSnapshot()
        Self.logger.info("Disabled plugin: \(id)")
    }

    func reloadPlugin(id: String) async throws {
        guard plugins.contains(where: { $0.id == id }) else {
            return
        }
        await runtime.unloadPlugin(id: id)
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        try await runtime.loadPlugin(plugins[index])
        if let j = plugins.firstIndex(where: { $0.id == id }) {
            plugins[j].status = .active
        }
        publishSnapshot()
        Self.logger.info("Reloaded plugin: \(id)")
    }

    func uninstallPlugin(id: String) async throws {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        let bundlePath = plugins[index].bundlePath
        await runtime.unloadPlugin(id: id)
        try await discovery.uninstallPlugin(bundlePath: bundlePath)
        if let j = plugins.firstIndex(where: { $0.id == id }) {
            plugins.remove(at: j)
        }
        defaults.removeObject(forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
        publishSnapshot()
        Self.logger.info("Uninstalled plugin: \(id)")
    }

    func installPlugin(from sourceURL: URL) async throws {
        try await discovery.installPlugin(from: sourceURL)
    }

    func updateConfig(pluginID: String, key: String, value: Any) async {
        let configKey = RockxyIdentity.current.pluginConfigPrefix(pluginID: pluginID) + key
        defaults.set(value, forKey: configKey)
    }

    func configValue(pluginID: String, key: String) async -> Any? {
        let configKey = RockxyIdentity.current.pluginConfigPrefix(pluginID: pluginID) + key
        return defaults.object(forKey: configKey)
    }

    // MARK: - Pipeline Hooks

    /// Request-side entry point called from the proxy handlers after rule evaluation
    /// has run and no rule action consumed the request. Iterates id-sorted enabled
    /// scripts whose behavior matches + has `runOnRequest` true. First plugin that
    /// returns a non-forward outcome wins; first forward also wins (no chaining this
    /// milestone).
    func runRequestHook(on request: HTTPRequestData) async -> RequestHookOutcome {
        let settings = currentSettings()
        // Master switch: when the user disables the Scripting tool, hooks are
        // bypassed entirely — even for currently-enabled scripts. The list of
        // enabled plugins is preserved so the user can flip the toggle back on.
        guard settings.scriptingToolEnabled else {
            return .forward(request)
        }
        let chain = settings.allowMultipleScriptsPerRequest
        var current = request
        for plugin in plugins where plugin.isEnabled && plugin.status == .active {
            guard plugin.manifest.entryPoints["script"] != nil else {
                continue
            }
            let behavior = plugin.manifest.scriptBehavior ?? ScriptBehavior.defaults()
            guard behavior.runOnRequest else {
                continue
            }
            guard Self.matches(behavior: behavior, request: current) else {
                continue
            }
            let context = ScriptRequestContext(from: current)
            let outcome: RequestHookOutcome
            do {
                outcome = try await runtime.callOnRequest(
                    pluginID: plugin.id,
                    context: context,
                    behavior: behavior,
                    originalRequest: current
                )
            } catch {
                Self.logger.error("Plugin \(plugin.id) onRequest failed: \(error.localizedDescription)")
                continue
            }
            switch outcome {
            case let .forward(modified):
                if chain {
                    current = modified
                    continue
                }
                return .forward(modified)
            case .blockLocally,
                 .mock,
                 .mockFailure:
                return outcome
            }
        }
        return .forward(current)
    }

    /// Response-side entry point. Same matching + first-match semantics as request
    /// side. If a matching plugin mutates the response, the mutated response is
    /// returned. Otherwise the original response is returned unchanged.
    func runResponseHook(
        request: HTTPRequestData,
        response: HTTPResponseData
    )
        async -> HTTPResponseData
    {
        guard currentSettings().scriptingToolEnabled else {
            return response
        }
        for plugin in plugins where plugin.isEnabled && plugin.status == .active {
            guard plugin.manifest.entryPoints["script"] != nil else {
                continue
            }
            let behavior = plugin.manifest.scriptBehavior ?? ScriptBehavior.defaults()
            guard behavior.runOnResponse else {
                continue
            }
            guard Self.matches(behavior: behavior, request: request) else {
                continue
            }
            let context = ScriptResponseContext(request: request, response: response)
            do {
                return try await runtime.callOnResponse(
                    pluginID: plugin.id,
                    context: context,
                    originalRequest: request,
                    originalResponse: response
                )
            } catch {
                Self.logger.error("Plugin \(plugin.id) onResponse failed: \(error.localizedDescription)")
                continue
            }
        }
        return response
    }

    /// Nonisolated snapshot used by proxy handlers (NIO event-loop threads) to
    /// decide, without awaiting the actor, whether response-side buffering needs
    /// to be activated for an incoming request. Based on a last-known plugin
    /// snapshot that the actor refreshes after every mutation.
    nonisolated func hasResponseHookForSnapshot(request: HTTPRequestData) -> Bool {
        // Honor the master toggle from the NIO event loop without awaiting the actor.
        guard currentSettings().scriptingToolEnabled else {
            return false
        }
        let snapshot = Self.pluginSnapshot.withLock { $0 }
        for plugin in snapshot where plugin.isEnabled && plugin.status == .active {
            guard plugin.manifest.entryPoints["script"] != nil else {
                continue
            }
            let behavior = plugin.manifest.scriptBehavior ?? ScriptBehavior.defaults()
            guard behavior.runOnResponse else {
                continue
            }
            if Self.matches(behavior: behavior, request: request) {
                return true
            }
        }
        return false
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptPluginManager")

    private let discovery: PluginDiscovery
    private let runtime: ScriptRuntime

    private var isLoadedOnce: Bool = false
    private var loadOnceTask: Task<Void, Never>?
    private var inFlightDiscoveryTask: Task<Void, Never>?

    private static func matches(behavior: ScriptBehavior, request: HTTPRequestData) -> Bool {
        guard let condition = behavior.matchCondition else {
            return true
        }
        return condition.matches(
            method: request.method,
            url: request.url,
            headers: request.headers
        )
    }

    nonisolated private func currentSettings() -> AppSettings {
        if let override = settingsProviderOverride {
            return override()
        }
        return AppSettingsStorage.load()
    }

    private func performInitialLoad() async {
        await performDiscoveryAndReconcile()
        isLoadedOnce = true
    }

    private func performDiscoveryAndReconcile() async {
        var discovered = await discovery.discoverPlugins()
        discovered.sort(by: { $0.id < $1.id })
        plugins = discovered

        let enabledSnapshots = plugins.filter(\.isEnabled).map { (id: $0.id, info: $0) }

        for snapshot in enabledSnapshots {
            do {
                try await runtime.loadPlugin(snapshot.info)
                guard let j = plugins.firstIndex(where: { $0.id == snapshot.id }),
                      plugins[j].isEnabled else
                {
                    await runtime.unloadPlugin(id: snapshot.id)
                    Self.logger.info("Plugin \(snapshot.id) removed or disabled during load — unloaded")
                    continue
                }
                plugins[j].status = .active
            } catch {
                if let j = plugins.firstIndex(where: { $0.id == snapshot.id }),
                   plugins[j].isEnabled
                {
                    plugins[j].status = .error(error.localizedDescription)
                }
                Self.logger.error("Failed to load plugin \(snapshot.id): \(error.localizedDescription)")
            }
        }
        publishSnapshot()
        Self.logger.info("Loaded \(self.plugins.count) plugins")
    }

    private func publishSnapshot() {
        let current = plugins
        Self.pluginSnapshot.withLock { $0 = current }
    }
}
