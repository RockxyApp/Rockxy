import Foundation

/// Bundle-driven identity and namespace values shared across the app, tests, and helper.
struct RockxyIdentity {
    // MARK: Lifecycle

    init(bundle: Bundle) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init(infoDictionary info: [String: Any]) {
        let fallbackFamilyNamespace = Self.string(
            named: "RockxyFamilyNamespace",
            in: info,
            fallback: "com.amunx.rockxy"
        )
        let fallbackAppBundleIdentifier = Self.string(
            named: "CFBundleIdentifier",
            in: info,
            fallback: fallbackFamilyNamespace
        )

        displayName = Self.string(
            named: "CFBundleDisplayName",
            in: info,
            fallback: Self.string(named: "CFBundleName", in: info, fallback: "Rockxy")
        )
        familyNamespace = fallbackFamilyNamespace
        appBundleIdentifier = fallbackAppBundleIdentifier
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
            fallback: fallbackAppBundleIdentifier
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
            fallback: fallbackAppBundleIdentifier
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

    // MARK: Internal

    static let current = RockxyIdentity(bundle: .main)

    /// Whether this process is a test host, decided solely by whether a test framework image is loaded.
    ///
    /// This is the one definition of "test host" in the codebase; `HelperRegistrationGuard` delegates
    /// here (the app target depends on `Shared/`, never the reverse). A loaded framework image is the
    /// one signal here that another process cannot set: it requires loading that framework, which a
    /// hardened-runtime build with library validation refuses. The scan is anchored and skips the main
    /// executable so the path of the app bundle itself — the one path an outsider can choose — cannot
    /// stand in for a framework. `XCTestConfigurationFilePath`, any `XCTest*` environment key,
    /// and argv are deliberately NOT consulted: any process running as the user can plant environment
    /// keys for every future app launch with `launchctl setenv` (it survives logout), and a user can
    /// open a file whose name contains "XCTest" or ".xctest". Trusting them made a shipped Rockxy read
    /// as a test host and redirect its persistent state to throwaway test locations.
    ///
    /// A real test run always loads the framework before app code runs: the host is launched with
    /// `libXCTestBundleInject.dylib`, which links `XCTest.framework`. A hardened-runtime app with
    /// library validation does not load a foreign framework and has `DYLD_INSERT_LIBRARIES` stripped.
    ///
    /// Latched once per process so every call site agrees for the life of the process.
    static let isRunningTests: Bool = isTestHost(imagePaths: loadedImagePaths())

    let displayName: String
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

    var rootCACertificateLabel: String {
        sharedCertificateLabelPrefix
    }

    var rootCAKeyLabel: String {
        "\(sharedCertificateLabelPrefix).key"
    }

    var sessionUTTypeIdentifier: String {
        "\(sharedUTTypePrefix).session"
    }

    var projectUTTypeIdentifier: String {
        "\(sharedUTTypePrefix).project"
    }

    var harUTTypeIdentifier: String {
        "\(sharedUTTypePrefix).har"
    }

    /// Whether a loaded Mach-O image path belongs to XCTest or Swift Testing.
    ///
    /// Anchored on the framework's own binary rather than on the name appearing anywhere in the
    /// path, because the main executable's path is itself in the image list. Measured on macOS:
    /// a copy of a binary into a directory named `Testing.framework` makes
    /// `_dyld_get_image_name(0)` report that path, so a bare `contains` check would let anyone
    /// who can place a copy of Rockxy decide it is a test host. A symlink does not do it — dyld
    /// reports the resolved path — but a copy is enough. `loadedImagePaths()` also drops image 0
    /// for the same reason; this stays correct on its own so the decision does not depend on it.
    ///
    /// macOS frameworks are versioned (`XCTest.framework/Versions/A/XCTest`) and the other
    /// platforms are flat (`XCTest.framework/XCTest`), so match the trailing binary name and
    /// require the matching framework directory above it.
    static func isTestFrameworkImagePath(_ path: String) -> Bool {
        ["XCTest", "Testing"].contains { name in
            path.hasSuffix("/" + name) && path.contains("/\(name).framework/")
        }
    }

    /// Pure decision over an injected image list, so the contract is testable without a real process.
    static func isTestHost(imagePaths: [String]) -> Bool {
        imagePaths.contains(where: isTestFrameworkImagePath)
    }

    /// Paths of every loaded Mach-O image except the main executable.
    ///
    /// Index 0 is the main executable, whose path is chosen by whoever placed the bundle. It can
    /// never be a test framework, so dropping it removes the one image in the list an outsider
    /// has any say over.
    static func loadedImagePaths() -> [String] {
        (1 ..< _dyld_image_count()).compactMap { index in
            _dyld_get_image_name(index).map { String(cString: $0) }
        }
    }

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
        if Self.isRunningTests {
            return Self.temporaryDirectory(
                named: appSupportDirectoryName,
                fileManager: fileManager
            )
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
    }

    func appSupportPath(_ relativePath: String, fileManager: FileManager = .default) -> URL {
        appSupportDirectory(fileManager: fileManager).appendingPathComponent(relativePath)
    }

    func temporaryAppSupportDirectory(fileManager: FileManager = .default) -> URL {
        Self.temporaryDirectory(
            named: appSupportDirectoryName,
            fileManager: fileManager
        )
    }

    func sharedSupportDirectory(fileManager: FileManager = .default) -> URL {
        if Self.isRunningTests {
            return Self.temporaryDirectory(
                named: sharedSupportDirectoryName,
                fileManager: fileManager
            )
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(sharedSupportDirectoryName, isDirectory: true)
    }

    func sharedSupportPath(_ relativePath: String, fileManager: FileManager = .default) -> URL {
        sharedSupportDirectory(fileManager: fileManager).appendingPathComponent(relativePath)
    }

    // MARK: Private

    private static let testRunToken: String = {
        let environment = ProcessInfo.processInfo.environment
        if let explicit = environment["ROCKXY_TEST_RUN_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !explicit.isEmpty
        {
            return explicit
        }

        if let configurationPath = environment["XCTestConfigurationFilePath"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !configurationPath.isEmpty
        {
            return "xc-\(stableHash(configurationPath))"
        }

        return UUID().uuidString
    }()

    private static func string(
        named key: String,
        in info: [String: Any],
        fallback: String
    )
        -> String
    {
        let value = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            return value
        }
        return fallback
    }

    private static func temporaryDirectory(
        named directoryName: String,
        fileManager: FileManager
    )
        -> URL
    {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("rockxy-tests-\(testRunToken)", isDirectory: true)
        return root.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16, uppercase: false)
    }
}
