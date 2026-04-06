import Foundation

/// Bundle-driven identity and namespace values shared across the app, tests, and helper.
struct RockxyIdentity {
    let familyNamespace: String
    let appBundleIdentifier: String
    let helperBundleIdentifier: String
    let helperMachServiceName: String
    let helperPlistName: String
    let allowedCallerIdentifiers: [String]
    let defaultsPrefix: String
    let notificationPrefix: String
    let logSubsystem: String
    let appSupportDirectoryName: String
    let sharedSupportDirectoryName: String
    let sharedCertificateLabelPrefix: String
    let sharedUTTypePrefix: String

    static let current = RockxyIdentity(bundle: .main)

    init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]

        familyNamespace = Self.string(
            named: "RockxyFamilyNamespace",
            in: info,
            fallback: "com.amunx.rockxy"
        )
        appBundleIdentifier = Self.string(
            named: "CFBundleIdentifier",
            in: info,
            fallback: "com.amunx.rockxy.community"
        )
        helperBundleIdentifier = Self.string(
            named: "RockxyHelperBundleIdentifier",
            in: info,
            fallback: "com.amunx.rockxy.helper"
        )
        helperMachServiceName = Self.string(
            named: "RockxyHelperMachServiceName",
            in: info,
            fallback: "com.amunx.rockxy.helper"
        )
        helperPlistName = Self.string(
            named: "RockxyHelperPlistName",
            in: info,
            fallback: "com.amunx.rockxy.helper.plist"
        )
        defaultsPrefix = Self.string(
            named: "RockxyDefaultsPrefix",
            in: info,
            fallback: "com.amunx.rockxy.community"
        )
        notificationPrefix = Self.string(
            named: "RockxyNotificationPrefix",
            in: info,
            fallback: defaultsPrefix
        )
        logSubsystem = Self.string(
            named: "RockxyLogSubsystem",
            in: info,
            fallback: appBundleIdentifier
        )
        appSupportDirectoryName = Self.string(
            named: "RockxyAppSupportDirectoryName",
            in: info,
            fallback: "com.amunx.rockxy.community"
        )
        sharedSupportDirectoryName = Self.string(
            named: "RockxySharedSupportDirectoryName",
            in: info,
            fallback: "com.amunx.rockxy"
        )
        sharedCertificateLabelPrefix = Self.string(
            named: "RockxySharedCertificateLabelPrefix",
            in: info,
            fallback: "com.amunx.rockxy.rootCA"
        )
        sharedUTTypePrefix = Self.string(
            named: "RockxySharedUTTypePrefix",
            in: info,
            fallback: "com.amunx.rockxy"
        )

        let callers = Self.string(
            named: "RockxyAllowedCallerIdentifiers",
            in: info,
            fallback: appBundleIdentifier
        )
        allowedCallerIdentifiers = callers
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    var rootCACertificateLabel: String { sharedCertificateLabelPrefix }
    var rootCAKeyLabel: String { "\(sharedCertificateLabelPrefix).key" }
    var sessionUTTypeIdentifier: String { "\(sharedUTTypePrefix).session" }
    var harUTTypeIdentifier: String { "\(sharedUTTypePrefix).har" }

    func defaultsKey(_ suffix: String) -> String {
        "\(defaultsPrefix).\(suffix)"
    }

    func notificationName(_ suffix: String) -> Notification.Name {
        Notification.Name("\(notificationPrefix).\(suffix)")
    }

    func pluginStoragePrefix(pluginID: String) -> String {
        "\(defaultsPrefix).plugin.\(pluginID).storage."
    }

    func pluginRuntimePrefix(pluginID: String) -> String {
        "\(defaultsPrefix).plugin.\(pluginID)"
    }

    func pluginConfigPrefix(pluginID: String) -> String {
        "\(defaultsPrefix).plugin.\(pluginID).config."
    }

    func pluginEnabledKey(pluginID: String) -> String {
        defaultsKey("plugin.\(pluginID).enabled")
    }

    func appSupportDirectory(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
    }

    func appSupportPath(_ relativePath: String, fileManager: FileManager = .default) -> URL {
        appSupportDirectory(fileManager: fileManager).appendingPathComponent(relativePath)
    }

    func temporaryAppSupportDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
    }

    func sharedSupportDirectory(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(sharedSupportDirectoryName, isDirectory: true)
    }

    func sharedSupportPath(_ relativePath: String, fileManager: FileManager = .default) -> URL {
        sharedSupportDirectory(fileManager: fileManager).appendingPathComponent(relativePath)
    }

    private static func string(
        named key: String,
        in info: [String: Any],
        fallback: String
    ) -> String {
        let value = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            return value
        }
        return fallback
    }
}
