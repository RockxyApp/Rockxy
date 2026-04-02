import Foundation
import os

/// Reads and writes `AppSettings` values to `UserDefaults`.
/// Each setting uses a namespaced key (`com.amunx.Rockxy.*`) to avoid collisions.
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
        logger.info("Settings saved")
    }

    // MARK: Private

    private static let logger = Logger(subsystem: "com.amunx.Rockxy", category: "AppSettingsStorage")

    private static let proxyPortKey = "com.amunx.Rockxy.proxyPort"
    private static let autoStartKey = "com.amunx.Rockxy.autoStart"
    private static let recordOnLaunchKey = "com.amunx.Rockxy.recordOnLaunch"
    private static let onlyListenOnLocalhostKey = "com.amunx.Rockxy.onlyListenOnLocalhost"
    private static let listenIPv6Key = "com.amunx.Rockxy.listenIPv6"
    private static let autoSelectPortKey = "com.amunx.Rockxy.autoSelectPort"
}
