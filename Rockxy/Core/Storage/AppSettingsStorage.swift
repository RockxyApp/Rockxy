import Foundation
import os

/// Reads and writes `AppSettings` values to `UserDefaults`.
/// Each setting uses a namespaced key to avoid collisions.
enum AppSettingsStorage {
    // MARK: Internal

    static func load() -> AppSettings {
        var settings = AppSettings()
        let defaults = UserDefaults.standard
        if defaults.object(forKey: proxyPortKey) != nil {
            settings.proxyPort = defaults.integer(forKey: proxyPortKey)
        }
        settings.autoStartProxy = defaults.bool(forKey: autoStartKey)
        settings.recordOnLaunch = defaults.object(forKey: recordOnLaunchKey) != nil
            ? defaults.bool(forKey: recordOnLaunchKey) : true
        settings.onlyListenOnLocalhost = defaults.object(forKey: onlyListenOnLocalhostKey) != nil
            ? defaults.bool(forKey: onlyListenOnLocalhostKey) : true
        settings.listenIPv6 = defaults.bool(forKey: listenIPv6Key)
        settings.autoSelectPort = defaults.object(forKey: autoSelectPortKey) != nil
            ? defaults.bool(forKey: autoSelectPortKey) : true
        if let theme = defaults.string(forKey: appThemeKey).flatMap(AppTheme.init(rawValue:)) {
            settings.appTheme = theme
        }
        if defaults.object(forKey: appUIFontSizeKey) != nil {
            settings.appUI.fontSize = AppUISettings.validFontSize(defaults.integer(forKey: appUIFontSizeKey))
        }
        if defaults.object(forKey: appUITabWidthKey) != nil {
            settings.appUI.tabWidth = AppUISettings.validTabWidth(defaults.integer(forKey: appUITabWidthKey))
        }
        settings.appUI.useMonospacedFont = defaults.bool(forKey: appUIUseMonospacedFontKey)
        settings.appUI.bodyWordWrap = defaults.object(forKey: appUIBodyWordWrapKey) != nil
            ? defaults.bool(forKey: appUIBodyWordWrapKey) : true
        settings.appUI.bodyShowInvisibles = defaults.bool(forKey: appUIBodyShowInvisiblesKey)
        settings.appUI.bodyShowMinimap = defaults.bool(forKey: appUIBodyShowMinimapKey)
        settings.appUI.bodyScrollBeyondLastLine = defaults.bool(forKey: appUIBodyScrollBeyondLastLineKey)
        settings.appUI.useAlternatingRowBackgroundColors = defaults
            .object(forKey: appUIUseAlternatingRowBackgroundColorsKey) != nil
            ? defaults.bool(forKey: appUIUseAlternatingRowBackgroundColorsKey) : true
        settings.scriptingToolEnabled = defaults.object(forKey: scriptingToolEnabledKey) != nil
            ? defaults.bool(forKey: scriptingToolEnabledKey) : true
        settings.allowSystemEnvVars = defaults.bool(forKey: allowSystemEnvVarsKey)
        settings.allowMultipleScriptsPerRequest = defaults.bool(forKey: allowMultipleScriptsPerRequestKey)
        settings.mcpServerEnabled = defaults.bool(forKey: mcpServerEnabledKey)
        if defaults.object(forKey: mcpServerPortKey) != nil {
            let stored = defaults.integer(forKey: mcpServerPortKey)
            let clamped = min(max(stored, 1), 65_535)
            if clamped != stored {
                logger.warning("Clamped out-of-range stored MCP port \(stored) to \(clamped)")
            }
            settings.mcpServerPort = clamped
        }
        settings.mcpRedactSensitiveData = defaults.object(forKey: mcpRedactSensitiveDataKey) != nil
            ? defaults.bool(forKey: mcpRedactSensitiveDataKey) : true
        if let visibility = defaults.string(forKey: githubGistVisibilityKey)
            .flatMap(GitHubGistVisibility.init(rawValue:)) {
            settings.githubGistVisibility = visibility
        }
        settings.githubGistRedactSensitiveData = defaults.object(forKey: githubGistRedactSensitiveDataKey) != nil
            ? defaults.bool(forKey: githubGistRedactSensitiveDataKey) : true
        settings.githubGistAskBeforePublishing = defaults.object(forKey: githubGistAskBeforePublishingKey) != nil
            ? defaults.bool(forKey: githubGistAskBeforePublishingKey) : true
        settings.githubGistOpenInBrowser = defaults.object(forKey: githubGistOpenInBrowserKey) != nil
            ? defaults.bool(forKey: githubGistOpenInBrowserKey) : true
        settings.githubGistCopyURLToClipboard = defaults.bool(forKey: githubGistCopyURLToClipboardKey)
        settings.lastExportedRootCAPath = defaults.string(forKey: lastExportedRootCAPathKey)
        return settings
    }

    static func save(_ settings: AppSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.proxyPort, forKey: proxyPortKey)
        defaults.set(settings.autoStartProxy, forKey: autoStartKey)
        defaults.set(settings.recordOnLaunch, forKey: recordOnLaunchKey)
        defaults.set(settings.onlyListenOnLocalhost, forKey: onlyListenOnLocalhostKey)
        defaults.set(settings.listenIPv6, forKey: listenIPv6Key)
        defaults.set(settings.autoSelectPort, forKey: autoSelectPortKey)
        defaults.set(settings.appTheme.rawValue, forKey: appThemeKey)
        defaults.set(settings.appUI.fontSize, forKey: appUIFontSizeKey)
        defaults.set(settings.appUI.tabWidth, forKey: appUITabWidthKey)
        defaults.set(settings.appUI.useMonospacedFont, forKey: appUIUseMonospacedFontKey)
        defaults.set(settings.appUI.bodyWordWrap, forKey: appUIBodyWordWrapKey)
        defaults.set(settings.appUI.bodyShowInvisibles, forKey: appUIBodyShowInvisiblesKey)
        defaults.set(settings.appUI.bodyShowMinimap, forKey: appUIBodyShowMinimapKey)
        defaults.set(settings.appUI.bodyScrollBeyondLastLine, forKey: appUIBodyScrollBeyondLastLineKey)
        defaults.set(
            settings.appUI.useAlternatingRowBackgroundColors,
            forKey: appUIUseAlternatingRowBackgroundColorsKey
        )
        defaults.set(settings.scriptingToolEnabled, forKey: scriptingToolEnabledKey)
        defaults.set(settings.allowSystemEnvVars, forKey: allowSystemEnvVarsKey)
        defaults.set(settings.allowMultipleScriptsPerRequest, forKey: allowMultipleScriptsPerRequestKey)
        defaults.set(settings.mcpServerEnabled, forKey: mcpServerEnabledKey)
        defaults.set(settings.mcpServerPort, forKey: mcpServerPortKey)
        defaults.set(settings.mcpRedactSensitiveData, forKey: mcpRedactSensitiveDataKey)
        defaults.set(settings.githubGistVisibility.rawValue, forKey: githubGistVisibilityKey)
        defaults.set(settings.githubGistRedactSensitiveData, forKey: githubGistRedactSensitiveDataKey)
        defaults.set(settings.githubGistAskBeforePublishing, forKey: githubGistAskBeforePublishingKey)
        defaults.set(settings.githubGistOpenInBrowser, forKey: githubGistOpenInBrowserKey)
        defaults.set(settings.githubGistCopyURLToClipboard, forKey: githubGistCopyURLToClipboardKey)
        defaults.set(settings.lastExportedRootCAPath, forKey: lastExportedRootCAPathKey)
        logger.info("Settings saved")
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "AppSettingsStorage")

    private static let proxyPortKey = RockxyIdentity.current.defaultsKey("proxyPort")
    private static let autoStartKey = RockxyIdentity.current.defaultsKey("autoStart")
    private static let recordOnLaunchKey = RockxyIdentity.current.defaultsKey("recordOnLaunch")
    private static let onlyListenOnLocalhostKey = RockxyIdentity.current.defaultsKey("onlyListenOnLocalhost")
    private static let listenIPv6Key = RockxyIdentity.current.defaultsKey("listenIPv6")
    private static let autoSelectPortKey = RockxyIdentity.current.defaultsKey("autoSelectPort")
    private static let appThemeKey = RockxyIdentity.current.defaultsKey("appTheme")
    private static let appUIFontSizeKey = RockxyIdentity.current.defaultsKey("appearance.fontSize")
    private static let appUITabWidthKey = RockxyIdentity.current.defaultsKey("appearance.tabWidth")
    private static let appUIUseMonospacedFontKey = RockxyIdentity.current.defaultsKey("appearance.useMonospacedFont")
    private static let appUIBodyWordWrapKey = RockxyIdentity.current.defaultsKey("appearance.bodyWordWrap")
    private static let appUIBodyShowInvisiblesKey = RockxyIdentity.current.defaultsKey("appearance.bodyShowInvisibles")
    private static let appUIBodyShowMinimapKey = RockxyIdentity.current.defaultsKey("appearance.bodyShowMinimap")
    private static let appUIBodyScrollBeyondLastLineKey = RockxyIdentity.current
        .defaultsKey("appearance.bodyScrollBeyondLastLine")
    private static let appUIUseAlternatingRowBackgroundColorsKey = RockxyIdentity.current
        .defaultsKey("appearance.useAlternatingRowBackgroundColors")
    private static let scriptingToolEnabledKey = RockxyIdentity.current.defaultsKey("scripting.toolEnabled")
    private static let allowSystemEnvVarsKey = RockxyIdentity.current.defaultsKey("scripting.allowSystemEnvVars")
    private static let allowMultipleScriptsPerRequestKey = RockxyIdentity.current
        .defaultsKey("scripting.allowMultipleScriptsPerRequest")
    private static let mcpServerEnabledKey = RockxyIdentity.current.defaultsKey("mcp.serverEnabled")
    private static let mcpServerPortKey = RockxyIdentity.current.defaultsKey("mcp.serverPort")
    private static let mcpRedactSensitiveDataKey = RockxyIdentity.current.defaultsKey("mcp.redactSensitiveData")
    private static let githubGistVisibilityKey = RockxyIdentity.current.defaultsKey("github.gist.visibility")
    private static let githubGistRedactSensitiveDataKey = RockxyIdentity.current
        .defaultsKey("github.gist.redactSensitiveData")
    private static let githubGistAskBeforePublishingKey = RockxyIdentity.current
        .defaultsKey("github.gist.askBeforePublishing")
    private static let githubGistOpenInBrowserKey = RockxyIdentity.current.defaultsKey("github.gist.openInBrowser")
    private static let githubGistCopyURLToClipboardKey = RockxyIdentity.current
        .defaultsKey("github.gist.copyURLToClipboard")
    private static let lastExportedRootCAPathKey = RockxyIdentity.current.defaultsKey("certificate.lastExportedRootCAPath")
}
