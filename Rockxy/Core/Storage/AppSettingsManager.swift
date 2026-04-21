import Foundation
import os

/// Singleton that holds the in-memory `AppSettings` state and persists changes
/// to `UserDefaults` via `AppSettingsStorage`. Marked `@Observable` so SwiftUI
/// views react to settings mutations without manual binding.
@MainActor @Observable
final class AppSettingsManager {
    // MARK: Lifecycle

    private init() {
        settings = AppSettingsStorage.load()
    }

    // MARK: Internal

    static let shared = AppSettingsManager()

    var settings: AppSettings

    func save() {
        AppSettingsStorage.save(settings)
    }

    func updateProxyPort(_ port: Int) {
        settings.proxyPort = port
        save()
    }

    func updateRecordOnLaunch(_ recordOnLaunch: Bool) {
        settings.recordOnLaunch = recordOnLaunch
        save()
    }

    func updateMCPServerEnabled(_ enabled: Bool) {
        settings.mcpServerEnabled = enabled
        save()
    }

    func updateMCPServerPort(_ port: Int) {
        let clampedPort = min(max(port, 1), 65_535)
        if clampedPort != port {
            Self.logger.warning("Clamped invalid MCP server port \(port) to \(clampedPort)")
        }
        settings.mcpServerPort = clampedPort
        save()
    }

    func updateMCPRedactSensitiveData(_ redact: Bool) {
        settings.mcpRedactSensitiveData = redact
        save()
    }

    func updateLastExportedRootCAPath(_ path: String?) {
        settings.lastExportedRootCAPath = path
        save()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "AppSettingsManager")
}
