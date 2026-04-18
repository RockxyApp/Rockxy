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
        settings.scriptingToolEnabled = defaults.object(forKey: scriptingToolEnabledKey) != nil
            ? defaults.bool(forKey: scriptingToolEnabledKey) : true
        settings.allowSystemEnvVars = defaults.bool(forKey: allowSystemEnvVarsKey)
        settings.allowMultipleScriptsPerRequest = defaults.bool(forKey: allowMultipleScriptsPerRequestKey)
        settings.mcpServerEnabled = defaults.bool(forKey: mcpServerEnabledKey)
        if defaults.object(forKey: mcpServerPortKey) != nil {
            settings.mcpServerPort = defaults.integer(forKey: mcpServerPortKey)
        }
        settings.mcpRedactSensitiveData = defaults.object(forKey: mcpRedactSensitiveDataKey) != nil
            ? defaults.bool(forKey: mcpRedactSensitiveDataKey) : true
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
        defaults.set(settings.scriptingToolEnabled, forKey: scriptingToolEnabledKey)
        defaults.set(settings.allowSystemEnvVars, forKey: allowSystemEnvVarsKey)
        defaults.set(settings.allowMultipleScriptsPerRequest, forKey: allowMultipleScriptsPerRequestKey)
        defaults.set(settings.mcpServerEnabled, forKey: mcpServerEnabledKey)
        defaults.set(settings.mcpServerPort, forKey: mcpServerPortKey)
        defaults.set(settings.mcpRedactSensitiveData, forKey: mcpRedactSensitiveDataKey)
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
    private static let scriptingToolEnabledKey = RockxyIdentity.current.defaultsKey("scripting.toolEnabled")
    private static let allowSystemEnvVarsKey = RockxyIdentity.current.defaultsKey("scripting.allowSystemEnvVars")
    private static let allowMultipleScriptsPerRequestKey = RockxyIdentity.current
        .defaultsKey("scripting.allowMultipleScriptsPerRequest")
    private static let mcpServerEnabledKey = RockxyIdentity.current.defaultsKey("mcp.serverEnabled")
    private static let mcpServerPortKey = RockxyIdentity.current.defaultsKey("mcp.serverPort")
    private static let mcpRedactSensitiveDataKey = RockxyIdentity.current.defaultsKey("mcp.redactSensitiveData")
}
