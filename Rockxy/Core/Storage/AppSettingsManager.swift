import Foundation
import os

/// Singleton that holds the in-memory `AppSettings` state and persists changes
/// to `UserDefaults` via `AppSettingsStorage`. Marked `@Observable` so SwiftUI
/// views react to settings mutations without manual binding.
@MainActor @Observable
final class AppSettingsManager {
    // MARK: Lifecycle

    private init() {
        let loadedSettings = AppSettingsStorage.load()
        settings = loadedSettings
        appUI = loadedSettings.appUI
        appTheme = loadedSettings.appTheme
    }

    // MARK: Internal

    static let shared = AppSettingsManager()

    var settings: AppSettings {
        didSet {
            syncAppearanceStateFromSettings()
        }
    }

    var appUI: AppUISettings
    var appTheme: AppTheme

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

    func updateAppTheme(_ theme: AppTheme) {
        guard theme != appTheme else {
            return
        }
        appTheme = theme
        settings.appTheme = theme
        AppSettingsStorage.saveAppearance(appTheme: appTheme, appUI: appUI)
        AppThemeApplier.apply(theme.rawValue)
        notifyAppearanceDidChange()
    }

    func updateAppUI(_ appUI: AppUISettings) {
        var validated = appUI
        validated.fontSize = AppUISettings.validFontSize(appUI.fontSize)
        validated.tabWidth = AppUISettings.validTabWidth(appUI.tabWidth)
        guard validated != self.appUI else {
            return
        }
        self.appUI = validated
        settings.appUI = validated
        AppSettingsStorage.saveAppearance(appTheme: appTheme, appUI: validated)
        notifyAppearanceDidChange()
    }

    func updateAppUI(_ update: (inout AppUISettings) -> Void) {
        var appUI = appUI
        update(&appUI)
        updateAppUI(appUI)
    }

    func restoreAppearanceDefaults() {
        let defaultTheme = AppTheme.system
        let defaultUI = AppUISettings.default
        guard appTheme != defaultTheme || appUI != defaultUI else {
            return
        }
        appTheme = defaultTheme
        appUI = defaultUI
        settings.appTheme = .system
        settings.appUI = .default
        AppSettingsStorage.saveAppearance(appTheme: defaultTheme, appUI: defaultUI)
        AppThemeApplier.apply(AppTheme.system.rawValue)
        notifyAppearanceDidChange()
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

    func updateGitHubGistVisibility(_ visibility: GitHubGistVisibility) {
        settings.githubGistVisibility = visibility
        save()
    }

    func updateGitHubGistRedactSensitiveData(_ redact: Bool) {
        settings.githubGistRedactSensitiveData = redact
        save()
    }

    func updateGitHubGistAskBeforePublishing(_ ask: Bool) {
        settings.githubGistAskBeforePublishing = ask
        save()
    }

    func updateGitHubGistOpenInBrowser(_ openInBrowser: Bool) {
        settings.githubGistOpenInBrowser = openInBrowser
        save()
    }

    func updateGitHubGistCopyURLToClipboard(_ copyURL: Bool) {
        settings.githubGistCopyURLToClipboard = copyURL
        save()
    }

    func updateLastExportedRootCAPath(_ path: String?) {
        settings.lastExportedRootCAPath = path
        save()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "AppSettingsManager")

    private func syncAppearanceStateFromSettings() {
        if appUI != settings.appUI {
            appUI = settings.appUI
        }
        if appTheme != settings.appTheme {
            appTheme = settings.appTheme
        }
    }

    private func notifyAppearanceDidChange() {
        NotificationCenter.default.post(
            name: .appearanceDidChange,
            object: self,
            userInfo: [
                "fontSize": appUI.fontSize,
                "theme": appTheme.rawValue,
            ]
        )
    }
}
