import Foundation

enum TestIdentity {
    static let familyNamespace = "com.amunx.rockxy"
    static let communityBundleIdentifier = "com.amunx.rockxy.community"
    static let helperBundleIdentifier = "com.amunx.rockxy.helper"
    static let helperMachServiceName = "com.amunx.rockxy.helper"
    static let helperPlistName = "com.amunx.rockxy.helper.plist"
    static let defaultsPrefix = communityBundleIdentifier
    static let notificationPrefix = communityBundleIdentifier
    static let logSubsystem = communityBundleIdentifier
    static let appSupportDirectoryName = communityBundleIdentifier
    static let sharedSupportDirectoryName = familyNamespace
    static let sharedCertificateLabelPrefix = "\(familyNamespace).rootCA"
    static let sharedUTTypePrefix = familyNamespace
    static let keychainProbeLabel = "\(familyNamespace).test.probe"

    static let appSettingsKeys = [
        "proxyPort",
        "autoStart",
        "recordOnLaunch",
        "onlyListenOnLocalhost",
        "listenIPv6",
        "autoSelectPort",
    ].map { "\(defaultsPrefix).\($0)" }

    static let previewTabStorageKey = "\(defaultsPrefix).previewTabs"
    static let previewTabBeautifyKey = "\(defaultsPrefix).previewAutoBeautify"
    static let headerColumnStorageKey = "\(defaultsPrefix).headerColumns"
    static let discoveredRequestHeadersKey = "\(defaultsPrefix).discoveredReqHeaders"
    static let discoveredResponseHeadersKey = "\(defaultsPrefix).discoveredResHeaders"
    static let hiddenBuiltInColumnsKey = "\(defaultsPrefix).hiddenBuiltInColumns"
    static let showAlertOnQuitKey = "\(defaultsPrefix).showAlertOnQuit"
    static let recordOnLaunchKey = "\(defaultsPrefix).recordOnLaunch"
    static let autoSelectPortKey = "\(defaultsPrefix).autoSelectPort"
    static let pluginStoragePrefix = "\(defaultsPrefix).plugin"

    static let helperBackupDirectory = "/Library/Application Support/\(sharedSupportDirectoryName)"
    static let applicationSupportDirectory = "Application Support/\(appSupportDirectoryName)"
    static let rulesPathComponent = "rules.json"
    static let rootCAKeyFilename = "rootCA-key.pem"
    static let rootCABackupFilename = "rootCA-key.pem.bak"
}
