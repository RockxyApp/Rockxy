import Foundation
import os

/// Central registry for all inspector, exporter, and protocol handler plugins.
/// Thread-safe via per-collection `NSLock` guards — plugins can be registered
/// from any thread, and queries happen on the main thread during UI layout.
///
/// Startup readiness is served by `ensureLoadedOnce()`, which is called from
/// `AppDelegate.applicationDidFinishLaunching(_:)` and awaited before
/// `ProxyServer.init` on the capture-start path. Both call sites are safe to
/// invoke concurrently — the second caller observes the same single load.
final class PluginManager: @unchecked Sendable {
    // MARK: Internal

    static let shared = PluginManager()

    let scriptManager = ScriptPluginManager()

    // MARK: - Registration

    func register(inspector plugin: any InspectorPlugin) {
        _inspectorPlugins.lock()
        defer { _inspectorPlugins.unlock() }
        _inspectors.append(plugin)
        Self.logger.debug("Registered inspector plugin: \(plugin.name)")
    }

    func register(exporter plugin: any ExporterPlugin) {
        _exporterLock.lock()
        defer { _exporterLock.unlock() }
        _exporters.append(plugin)
        Self.logger.debug("Registered exporter plugin: \(plugin.name)")
    }

    func register(handler plugin: any ProtocolHandler) {
        _handlerLock.lock()
        defer { _handlerLock.unlock() }
        _handlers.append(plugin)
        Self.logger.debug("Registered protocol handler: \(plugin.protocolName)")
    }

    // MARK: - Loading

    /// Authoritative startup entry point. Registers built-in inspector/exporter
    /// plugins exactly once and awaits the script manager's one-shot script load.
    /// Safe to call from multiple sites (AppDelegate, capture-start coordinator).
    func ensureLoadedOnce() async {
        registerBuiltInsIfNeeded()
        await scriptManager.ensureLoadedOnce()
    }

    /// Fire-and-forget shim for legacy synchronous call sites. Registers built-in
    /// inspectors/exporters synchronously (so callers that `allExporters()` right
    /// afterwards see them) and dispatches the async script load to a background
    /// Task. Prefer `ensureLoadedOnce()` in new code.
    func loadPlugins() {
        registerBuiltInsIfNeeded()
        Task { await scriptManager.ensureLoadedOnce() }
    }

    // MARK: - Queries

    func inspectorPlugin(for contentType: ContentType) -> (any InspectorPlugin)? {
        _inspectorPlugins.lock()
        defer { _inspectorPlugins.unlock() }
        return _inspectors.first { plugin in
            plugin.supportedContentTypes.contains(contentType)
        }
    }

    func allExporters() -> [any ExporterPlugin] {
        _exporterLock.lock()
        defer { _exporterLock.unlock() }
        return _exporters
    }

    func protocolHandler(for request: HTTPRequestData) -> (any ProtocolHandler)? {
        _handlerLock.lock()
        defer { _handlerLock.unlock() }
        return _handlers.first { $0.canHandle(request: request) }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "PluginManager"
    )

    private let _inspectorPlugins: NSLock = .init()
    nonisolated(unsafe) private var _inspectors: [any InspectorPlugin] = []

    private let _exporterLock: NSLock = .init()
    nonisolated(unsafe) private var _exporters: [any ExporterPlugin] = []

    private let _handlerLock: NSLock = .init()
    nonisolated(unsafe) private var _handlers: [any ProtocolHandler] = []

    private let _builtInsLock: NSLock = .init()
    nonisolated(unsafe) private var _didRegisterBuiltIns: Bool = false

    // MARK: - Built-in Registration

    private func registerBuiltInsIfNeeded() {
        _builtInsLock.lock()
        if _didRegisterBuiltIns {
            _builtInsLock.unlock()
            return
        }
        _didRegisterBuiltIns = true
        _builtInsLock.unlock()
        register(inspector: JSONInspector())
        register(exporter: HARExporter())
    }
}
