import Foundation
import os

/// Central registry for all inspector, exporter, and protocol handler plugins.
/// Thread-safe via per-collection `NSLock` guards — plugins can be registered
/// from any thread, and queries happen on the main thread during UI layout.
/// Built-in plugins are registered at startup via `loadPlugins()`.
final class PluginManager: Sendable {
    // MARK: Internal

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

    func loadPlugins() {
        registerBuiltIns()
        Task { await scriptManager.loadAllPlugins() }
        Self.logger.info("Plugin loading complete")
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
    private nonisolated(unsafe) var _inspectors: [any InspectorPlugin] = []

    private let _exporterLock: NSLock = .init()
    private nonisolated(unsafe) var _exporters: [any ExporterPlugin] = []

    private let _handlerLock: NSLock = .init()
    private nonisolated(unsafe) var _handlers: [any ProtocolHandler] = []

    // MARK: - Built-in Registration

    private func registerBuiltIns() {
        register(inspector: JSONInspector())
        register(exporter: HARExporter())
    }
}
