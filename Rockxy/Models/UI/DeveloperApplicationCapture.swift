import AppKit
import Darwin
import Foundation

// MARK: - DeveloperApplicationInstallation

/// One user-selected macOS application and the safe preparation Rockxy can apply before launch.
struct DeveloperApplicationInstallation: Equatable, Identifiable, Sendable {
    let appURL: URL
    let bundleIdentifier: String
    let displayName: String
    let settingsAdapter: DeveloperApplicationSettingsAdapter?
    let launchAdapter: DeveloperApplicationLaunchAdapter?
    let runtimeCapabilities: Set<DeveloperApplicationRuntimeCapability>

    var id: String {
        "\(bundleIdentifier)|\(appURL.standardizedFileURL.path)"
    }
}

// MARK: - DeveloperApplicationLaunchAdapter

/// A runtime capability that can be prepared through documented launch arguments.
enum DeveloperApplicationLaunchAdapter: Equatable, Sendable {
    case chromiumProxy

    // MARK: Internal

    func arguments(context: RockxySetupScriptContext) -> [String] {
        switch self {
        case .chromiumProxy:
            [
                "--proxy-server=http://\(context.proxyHost):\(context.proxyPort)",
            ]
        }
    }
}

// MARK: - DeveloperApplicationSettingsAdapter

/// A detected, declarative application-settings format that Rockxy knows how to update safely.
///
/// The type is intentionally capability-based rather than product-based. Applications that ship
/// the same settings schema receive the same behavior without maintaining a vendor/product list.
enum DeveloperApplicationSettingsAdapter: Equatable, Sendable {
    case xmlHTTPProxyAutoDetect(vendorDirectory: String, dataDirectoryName: String)

    // MARK: Internal

    var requiresSystemProxy: Bool {
        switch self {
        case .xmlHTTPProxyAutoDetect:
            true
        }
    }

    var requiresJavaProxyProperties: Bool {
        switch self {
        case .xmlHTTPProxyAutoDetect:
            true
        }
    }
}

// MARK: - DeveloperApplicationSettingsPreparation

/// A reversible settings transaction. Recovery artifacts are stored in Rockxy's Application
/// Support ledger directory so an IDE update cannot remove the only copy of the original settings.
struct DeveloperApplicationSettingsPreparation: Equatable, Sendable {
    let settingsURL: URL
    let backupURL: URL
    let absenceMarkerURL: URL
    let preparedSnapshotURL: URL
    let recoveryRecordURL: URL
    /// Resolved application bundle path retained only as generic process-identity evidence for
    /// restart detection. It is never used as a filesystem mutation target.
    let applicationBundlePath: String?
}

// MARK: - DeveloperApplicationPreparationRegistry

/// Prevents two setup windows from preparing the same third-party settings file concurrently.
final class DeveloperApplicationPreparationRegistry: @unchecked Sendable {
    // MARK: Internal

    static let shared = DeveloperApplicationPreparationRegistry()

    func begin(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !activeKeys.contains(key) else {
            return false
        }
        activeKeys.insert(key)
        return true
    }

    func end(_ key: String) {
        lock.lock()
        activeKeys.remove(key)
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var activeKeys: Set<String> = []
}

// MARK: - DeveloperApplicationCaptureError

enum DeveloperApplicationCaptureError: LocalizedError, Equatable {
    case invalidApplication
    case invalidApplicationMetadata
    case unsafeSettingsLocation
    case malformedProxySettings
    case settingsRecoveryConflict(String)
    case applicationIsRunning(String)
    case preparationInProgress(String)
    case systemProxyRequired(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            String(localized: "Choose a valid macOS application.", bundle: RockxyLocalization.bundle)
        case .invalidApplicationMetadata:
            String(
                localized: "The selected application's proxy metadata could not be read safely.",
                bundle: RockxyLocalization.bundle
            )
        case .unsafeSettingsLocation:
            String(
                localized: "The selected application reported an unsafe settings location. Rockxy left it unchanged.",
                bundle: RockxyLocalization.bundle
            )
        case .malformedProxySettings:
            String(
                localized: "The application's HTTP Proxy settings file is malformed. Rockxy left it unchanged.",
                bundle: RockxyLocalization.bundle
            )
        case let .settingsRecoveryConflict(path):
            String(
                localized: "Rockxy could not safely compare the application's current proxy settings with its recovery snapshot. Rockxy restored the original settings and preserved the current file at \(path). Review it, then try again.",
                bundle: RockxyLocalization.bundle
            )
        case let .applicationIsRunning(name):
            String(
                localized: "Quit \(name) completely, then try again so its proxy state and launch environment cannot be stale.",
                bundle: RockxyLocalization.bundle
            )
        case let .preparationInProgress(name):
            String(
                localized: "Rockxy is already preparing \(name). Wait for that launch to finish, then try again.",
                bundle: RockxyLocalization.bundle
            )
        case let .systemProxyRequired(name):
            String(
                localized: "Enable macOS System Proxy in Rockxy before opening \(name).",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

// MARK: - DeveloperApplicationCaptureConfigurator

/// Inspects a selected app, applies only recognized settings adapters, and otherwise leaves the
/// app bundle and preferences untouched. Unknown apps can still be launched with Rockxy's scoped
/// environment; that is an explicit best-effort capability, not a claim of universal capture.
enum DeveloperApplicationCaptureConfigurator {
    // MARK: Internal

    nonisolated static let maximumMetadataBytes: UInt64 = 1_048_576
    nonisolated static let maximumProxySettingsBytes: UInt64 = 1_048_576

    /// Reconciles settings transactions that survived a reboot, logout, app crash, or a monitor
    /// lifetime limit. Records contain only a validated path relative to Application Support;
    /// malformed or tampered records are ignored without following them outside that boundary.
    @discardableResult
    static func reconcileOutstandingPreparations(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        preparationRegistry: DeveloperApplicationPreparationRegistry = .shared,
        recordedProcessIsAlive: (Int32, String?) -> Bool = DeveloperApplicationRecoveryLedger
            .isRecordedProcessAlive,
        recordedApplicationProcessIdentifier: ((String, String) -> Int32?)? = nil,
        livePreparationHandler: ((Int32, DeveloperApplicationSettingsPreparation) -> Void)? = nil
    )
        -> Int
    {
        DeveloperApplicationRecoveryLedger.reconcileOutstandingPreparations(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager,
            preparationRegistry: preparationRegistry,
            recordedProcessIsAlive: recordedProcessIsAlive,
            recordedApplicationProcessIdentifier: recordedApplicationProcessIdentifier,
            livePreparationHandler: livePreparationHandler
        )
    }

    static func associateRunningProcess(
        processIdentifier: Int32,
        processStartSignature: String?,
        with preparation: DeveloperApplicationSettingsPreparation,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    )
        throws
    {
        try DeveloperApplicationRecoveryLedger.associateRunningProcess(
            processIdentifier: processIdentifier,
            processStartSignature: processStartSignature,
            with: preparation,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
    }

    static func recoveryArtifactURLs(for recoveryRecordURL: URL) -> (
        backupURL: URL,
        absenceMarkerURL: URL,
        preparedSnapshotURL: URL
    ) {
        let artifactBaseURL = recoveryRecordURL.deletingPathExtension()
        return (
            artifactBaseURL.appendingPathExtension("backup"),
            artifactBaseURL.appendingPathExtension("absent"),
            artifactBaseURL.appendingPathExtension("prepared")
        )
    }

    nonisolated static func processStartSignature(processIdentifier: Int32) -> String? {
        DeveloperApplicationRecoveryLedger.processStartSignature(processIdentifier: processIdentifier)
    }

    static func installation(at appURL: URL) throws -> DeveloperApplicationInstallation {
        let standardizedURL = appURL.standardizedFileURL
        guard standardizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              let bundle = Bundle(url: standardizedURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else
        {
            throw DeveloperApplicationCaptureError.invalidApplication
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? standardizedURL.deletingPathExtension().lastPathComponent

        return try DeveloperApplicationInstallation(
            appURL: standardizedURL,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            settingsAdapter: detectedSettingsAdapter(in: standardizedURL),
            launchAdapter: detectedLaunchAdapter(in: standardizedURL),
            runtimeCapabilities: DeveloperApplicationRuntimeDetector.capabilities(
                in: standardizedURL,
                bundle: bundle
            )
        )
    }

    static func proxySettingsURL(
        for adapter: DeveloperApplicationSettingsAdapter,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    )
        throws -> URL
    {
        let vendorDirectory: String
        let dataDirectoryName: String
        switch adapter {
        case let .xmlHTTPProxyAutoDetect(vendor, dataDirectory):
            vendorDirectory = vendor
            dataDirectoryName = dataDirectory
        }

        guard isSafeDirectoryComponent(vendorDirectory),
              isSafeDirectoryComponent(dataDirectoryName) else
        {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }

        let settingsURL = applicationSupportURL
            .appendingPathComponent(vendorDirectory, isDirectory: true)
            .appendingPathComponent(dataDirectoryName, isDirectory: true)
            .appendingPathComponent("options", isDirectory: true)
            .appendingPathComponent("proxy.settings.xml", isDirectory: false)
        try validateContainedPath(settingsURL, rootURL: applicationSupportURL, fileManager: fileManager)
        return settingsURL
    }

    @discardableResult
    static func prepareRecognizedSettings(
        for installation: DeveloperApplicationInstallation,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    )
        throws -> DeveloperApplicationSettingsPreparation?
    {
        guard let adapter = installation.settingsAdapter else {
            return nil
        }

        switch adapter {
        case .xmlHTTPProxyAutoDetect:
            return try configureXMLAutoDetect(
                adapter: adapter,
                installation: installation,
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            )
        }
    }

    static func restoreRecognizedSettings(
        _ preparation: DeveloperApplicationSettingsPreparation,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    )
        throws
    {
        try validateContainedPath(
            preparation.settingsURL,
            rootURL: applicationSupportURL,
            fileManager: fileManager
        )
        try validateContainedPath(
            preparation.backupURL,
            rootURL: applicationSupportURL,
            fileManager: fileManager
        )
        try validateContainedPath(
            preparation.absenceMarkerURL,
            rootURL: applicationSupportURL,
            fileManager: fileManager
        )
        try validateContainedPath(
            preparation.preparedSnapshotURL,
            rootURL: applicationSupportURL,
            fileManager: fileManager
        )
        try validateContainedPath(
            preparation.recoveryRecordURL,
            rootURL: applicationSupportURL,
            fileManager: fileManager
        )
        do {
            try restoreBackup(
                settingsURL: preparation.settingsURL,
                backupURL: preparation.backupURL,
                absenceMarkerURL: preparation.absenceMarkerURL,
                preparedSnapshotURL: preparation.preparedSnapshotURL,
                fileManager: fileManager
            )
            try settleRecoveryRecord(preparation.recoveryRecordURL, fileManager: fileManager)
        } catch {
            // A malformed live file is preserved as a conflict while the original is restored.
            // Once no transaction artifacts remain, the record is settled even though the
            // caller still receives the conflict location for user-facing recovery guidance.
            if case DeveloperApplicationCaptureError.settingsRecoveryConflict = error {
                try? settleRecoveryRecord(preparation.recoveryRecordURL, fileManager: fileManager)
            }
            throw error
        }
    }

    /// Identity of one installed application and the settings scope Rockxy would prepare for it.
    static func scopeIdentity(
        for installation: DeveloperApplicationInstallation
    )
        -> DeveloperApplicationScopeIdentity
    {
        DeveloperApplicationScopeIdentity(
            bundlePath: installation.appURL.standardizedFileURL.resolvingSymlinksInPath().path,
            settingsAdapter: installation.settingsAdapter
        )
    }

    /// Resolves the same identity for an arbitrary installed bundle, such as one reported by a
    /// running application. Adapter detection is skipped when the caller only needs path identity.
    static func scopeIdentity(
        forBundleAt bundleURL: URL,
        resolvingSettingsAdapter: Bool = true,
        fileManager: FileManager = .default
    )
        -> DeveloperApplicationScopeIdentity
    {
        let standardizedURL = bundleURL.standardizedFileURL
        let adapter: DeveloperApplicationSettingsAdapter? = resolvingSettingsAdapter
            ? ((try? detectedSettingsAdapter(in: standardizedURL, fileManager: fileManager)) ?? nil)
            : nil
        return DeveloperApplicationScopeIdentity(
            bundlePath: standardizedURL.resolvingSymlinksInPath().path,
            settingsAdapter: adapter
        )
    }

    /// Rejects preparation while any running installation owns the same settings scope. Two
    /// installations of one application family share a single settings directory, so an
    /// exact bundle-path comparison alone would let Rockxy mutate settings underneath a
    /// running process. Applications without a recognized adapter keep exact-path behavior.
    @MainActor
    static func isRunning(
        _ installation: DeveloperApplicationInstallation,
        workspace: NSWorkspace = .shared
    )
        -> Bool
    {
        let candidate = scopeIdentity(for: installation)
        let runningInstances = DeveloperApplicationWorkspaceScopeProvider.runningInstances(
            resolvingSettingsAdapters: candidate.settingsAdapter != nil,
            workspace: workspace
        )
        return DeveloperApplicationScopeResolution.blockingInstance(
            candidate: candidate,
            runningInstances: runningInstances
        ) != nil
    }

    static func validateContainedPath(
        _ candidateURL: URL,
        rootURL: URL,
        fileManager: FileManager
    )
        throws
    {
        let root = try canonicalizedURLPreservingMissingSuffix(rootURL, fileManager: fileManager)
        let candidate = try canonicalizedURLPreservingMissingSuffix(candidateURL, fileManager: fileManager)
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPath), candidate.path != root.path else {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
    }

    static func fileSize(at url: URL, fileManager: FileManager) throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw DeveloperApplicationCaptureError.invalidApplicationMetadata
        }
        return size.uint64Value
    }

    // MARK: Private

    private static let proxySelectionOptionNames: Set<String> = [
        "USE_PROXY_PAC",
        "USE_HTTP_PROXY",
        "USE_PAC_URL",
        "PROXY_TYPE_IS_SOCKS",
    ]

    /// Detects an application-level proxy schema from metadata shipped inside the app bundle.
    /// Absence and partial metadata are supported outcomes: they fall back to the scoped launch
    /// environment rather than preventing an otherwise valid application from opening.
    private static func detectedSettingsAdapter(
        in appURL: URL,
        fileManager: FileManager = .default
    )
        throws -> DeveloperApplicationSettingsAdapter?
    {
        let metadataURL = appURL
            .appendingPathComponent("Contents/Resources/product-info.json", isDirectory: false)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        let data: Data
        do {
            guard try fileSize(at: metadataURL, fileManager: fileManager) <= maximumMetadataBytes else {
                return nil
            }
            data = try Data(contentsOf: metadataURL, options: [.mappedIfSafe])
        } catch {
            return nil
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let productVendor = object["productVendor"] as? String,
              let dataDirectoryName = object["dataDirectoryName"] as? String,
              let launchEntries = object["launch"] as? [[String: Any]] else
        {
            // `product-info.json` is not a universal or version-stable schema. Entries that do
            // not prove this adapter applies must not block the generic environment-only path.
            return nil
        }

        guard isSafeDirectoryComponent(productVendor),
              isSafeDirectoryComponent(dataDirectoryName) else
        {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
        guard launchEntries.contains(where: { entry in
            guard entry["os"] as? String == "macOS",
                  let javaExecutablePath = entry["javaExecutablePath"] as? String else
            {
                return false
            }
            return DeveloperApplicationRuntimeDetector.isContainedExecutable(
                relativePath: javaExecutablePath,
                relativeTo: metadataURL.deletingLastPathComponent(),
                bundleURL: appURL,
                fileManager: fileManager
            )
        }) else {
            return nil
        }

        return .xmlHTTPProxyAutoDetect(
            vendorDirectory: productVendor,
            dataDirectoryName: dataDirectoryName
        )
    }

    private static func detectedLaunchAdapter(
        in appURL: URL,
        fileManager: FileManager = .default
    )
        -> DeveloperApplicationLaunchAdapter?
    {
        let frameworksURL = appURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let knownRuntimeFrameworks = [
            "Electron Framework.framework",
            "Chromium Embedded Framework.framework",
        ]
        guard knownRuntimeFrameworks.contains(where: {
            fileManager.fileExists(atPath: frameworksURL.appendingPathComponent($0).path)
        }) else {
            return nil
        }
        return .chromiumProxy
    }

    private static func configureXMLAutoDetect(
        adapter: DeveloperApplicationSettingsAdapter,
        installation: DeveloperApplicationInstallation,
        applicationSupportURL: URL,
        fileManager: FileManager
    )
        throws -> DeveloperApplicationSettingsPreparation
    {
        let settingsURL = try proxySettingsURL(
            for: adapter,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        let recoveryRecordURL = try DeveloperApplicationRecoveryLedger.recordURL(
            for: settingsURL,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        let recoveryArtifactURLs = recoveryArtifactURLs(for: recoveryRecordURL)
        let backupURL = recoveryArtifactURLs.backupURL
        let absenceMarkerURL = recoveryArtifactURLs.absenceMarkerURL
        let preparedSnapshotURL = recoveryArtifactURLs.preparedSnapshotURL
        let recoveryDirectoryURL = recoveryRecordURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
        try validateContainedPath(backupURL, rootURL: applicationSupportURL, fileManager: fileManager)
        try validateContainedPath(absenceMarkerURL, rootURL: applicationSupportURL, fileManager: fileManager)
        try validateContainedPath(preparedSnapshotURL, rootURL: applicationSupportURL, fileManager: fileManager)

        // Migrate a transaction created by Rockxy 0.38.x, whose artifacts lived beside the
        // third-party settings file. New transactions keep their only recovery copy under Rockxy.
        let legacyBackupURL = settingsURL.appendingPathExtension("rockxy-backup")
        let legacyAbsenceMarkerURL = settingsURL.appendingPathExtension("rockxy-originally-absent")
        let legacyPreparedSnapshotURL = settingsURL.appendingPathExtension("rockxy-prepared")
        if fileManager.fileExists(atPath: legacyBackupURL.path)
            || fileManager.fileExists(atPath: legacyAbsenceMarkerURL.path)
            || fileManager.fileExists(atPath: legacyPreparedSnapshotURL.path)
        {
            try restoreBackup(
                settingsURL: settingsURL,
                backupURL: legacyBackupURL,
                absenceMarkerURL: legacyAbsenceMarkerURL,
                preparedSnapshotURL: legacyPreparedSnapshotURL,
                fileManager: fileManager
            )
            try settleRecoveryRecord(recoveryRecordURL, fileManager: fileManager)
        }

        if fileManager.fileExists(atPath: backupURL.path)
            || fileManager.fileExists(atPath: absenceMarkerURL.path)
            || fileManager.fileExists(atPath: preparedSnapshotURL.path)
            || fileManager.fileExists(atPath: recoveryRecordURL.path)
        {
            // A record can outlive its artifacts when a completed restore was interrupted before
            // the ledger entry was removed. `restoreBackup` settles that case without touching
            // the live settings file, so preparation continues instead of failing permanently.
            try restoreBackup(
                settingsURL: settingsURL,
                backupURL: backupURL,
                absenceMarkerURL: absenceMarkerURL,
                preparedSnapshotURL: preparedSnapshotURL,
                fileManager: fileManager
            )
            try settleRecoveryRecord(recoveryRecordURL, fileManager: fileManager)
        }

        let document: XMLDocument
        let originalData: Data?

        if fileManager.fileExists(atPath: settingsURL.path) {
            do {
                guard try fileSize(at: settingsURL, fileManager: fileManager) <= maximumProxySettingsBytes else {
                    throw DeveloperApplicationCaptureError.malformedProxySettings
                }
                let data = try Data(contentsOf: settingsURL, options: [.mappedIfSafe])
                originalData = data
                document = try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
            } catch {
                throw DeveloperApplicationCaptureError.malformedProxySettings
            }
        } else {
            originalData = nil
            document = XMLDocument(rootElement: XMLElement(name: "application"))
        }

        guard let application = document.rootElement(), application.name == "application" else {
            throw DeveloperApplicationCaptureError.malformedProxySettings
        }

        let component: XMLElement
        if let existing = application.elements(forName: "component").first(where: {
            $0.attribute(forName: "name")?.stringValue == "HttpConfigurable"
        }) {
            component = existing
        } else {
            component = XMLElement(name: "component")
            component.addAttribute(attribute(name: "name", value: "HttpConfigurable"))
            application.addChild(component)
        }

        setOption(name: "USE_PROXY_PAC", value: "true", in: component)
        removeOption(name: "USE_HTTP_PROXY", from: component)
        removeOption(name: "USE_PAC_URL", from: component)
        removeOption(name: "PROXY_TYPE_IS_SOCKS", from: component)

        let directory = settingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try validateContainedPath(settingsURL, rootURL: applicationSupportURL, fileManager: fileManager)
        if let originalData {
            try originalData.write(to: backupURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        } else {
            try Data().write(to: absenceMarkerURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: absenceMarkerURL.path)
        }
        let preparedData = document.xmlData(options: [.nodePrettyPrint])
        do {
            // Persist the recovery intent before mutating the live settings file. A crash after
            // this point leaves either a no-op record or a fully recoverable transaction.
            try DeveloperApplicationRecoveryLedger.writeRecord(
                settingsURL: settingsURL,
                recordURL: recoveryRecordURL,
                bundleIdentifier: installation.bundleIdentifier,
                applicationBundlePath: installation.appURL.path,
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            )
            try preparedData.write(to: settingsURL, options: .atomic)
            try preparedData.write(to: preparedSnapshotURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: preparedSnapshotURL.path)
        } catch {
            // Once the backup marker exists, preparation is a transaction. A partial disk or
            // permission failure must not leave the selected application on Rockxy's settings.
            do {
                try restoreBackup(
                    settingsURL: settingsURL,
                    backupURL: backupURL,
                    absenceMarkerURL: absenceMarkerURL,
                    preparedSnapshotURL: preparedSnapshotURL,
                    fileManager: fileManager
                )
                try settleRecoveryRecord(recoveryRecordURL, fileManager: fileManager)
            } catch {
                // Keep every remaining artifact and the durable record for startup recovery.
            }
            throw error
        }
        return DeveloperApplicationSettingsPreparation(
            settingsURL: settingsURL,
            backupURL: backupURL,
            absenceMarkerURL: absenceMarkerURL,
            preparedSnapshotURL: preparedSnapshotURL,
            recoveryRecordURL: recoveryRecordURL,
            applicationBundlePath: installation.appURL.standardizedFileURL
                .resolvingSymlinksInPath().path
        )
    }

    private static func restoreBackup(
        settingsURL: URL,
        backupURL: URL,
        absenceMarkerURL: URL,
        preparedSnapshotURL: URL,
        fileManager: FileManager
    )
        throws
    {
        guard hasAnyRecoveryArtifact(
            backupURL: backupURL,
            absenceMarkerURL: absenceMarkerURL,
            preparedSnapshotURL: preparedSnapshotURL,
            fileManager: fileManager
        ) else {
            // A completed restore already removed every recovery artifact and only the ledger
            // entry survived, typically because Rockxy was terminated between the two steps.
            // That entry owns nothing: the caller settles it and the live settings file stays
            // exactly as the application and the user left it.
            return
        }

        if fileManager.fileExists(atPath: preparedSnapshotURL.path) {
            guard fileManager.fileExists(atPath: settingsURL.path) else {
                // The application or user removed the file. That newer choice wins.
                try removeRecoveryArtifacts(
                    backupURL: backupURL,
                    absenceMarkerURL: absenceMarkerURL,
                    preparedSnapshotURL: preparedSnapshotURL,
                    fileManager: fileManager
                )
                return
            }

            let preparedDocument: XMLDocument
            do {
                preparedDocument = try readProxySettingsDocument(
                    at: preparedSnapshotURL,
                    fileManager: fileManager
                )
            } catch {
                let conflictURL = try recoverConflictingLiveSettings(
                    settingsURL: settingsURL,
                    backupURL: backupURL,
                    absenceMarkerURL: absenceMarkerURL,
                    preparedSnapshotURL: preparedSnapshotURL,
                    fileManager: fileManager
                )
                throw DeveloperApplicationCaptureError.settingsRecoveryConflict(conflictURL.path)
            }
            let liveDocument: XMLDocument
            do {
                liveDocument = try readProxySettingsDocument(at: settingsURL, fileManager: fileManager)
            } catch {
                let conflictURL = try recoverConflictingLiveSettings(
                    settingsURL: settingsURL,
                    backupURL: backupURL,
                    absenceMarkerURL: absenceMarkerURL,
                    preparedSnapshotURL: preparedSnapshotURL,
                    fileManager: fileManager
                )
                throw DeveloperApplicationCaptureError.settingsRecoveryConflict(conflictURL.path)
            }
            guard proxySelectionFingerprint(in: liveDocument) == proxySelectionFingerprint(in: preparedDocument) else {
                // Only an actual proxy-selector change wins. Reformatting or unrelated settings
                // written by the application do not erase the user's recoverable proxy state.
                try removeRecoveryArtifacts(
                    backupURL: backupURL,
                    absenceMarkerURL: absenceMarkerURL,
                    preparedSnapshotURL: preparedSnapshotURL,
                    fileManager: fileManager
                )
                return
            }

            if fileManager.fileExists(atPath: absenceMarkerURL.path) {
                try removeProxySelectionOptions(from: liveDocument)
                if isEffectivelyEmptyProxySettingsDocument(liveDocument) {
                    try removeIfPresent(settingsURL, fileManager: fileManager)
                } else {
                    try liveDocument.xmlData(options: [.nodePrettyPrint]).write(to: settingsURL, options: .atomic)
                }
                try removeRecoveryArtifacts(
                    backupURL: backupURL,
                    absenceMarkerURL: absenceMarkerURL,
                    preparedSnapshotURL: preparedSnapshotURL,
                    fileManager: fileManager
                )
                return
            }

            if fileManager.fileExists(atPath: backupURL.path) {
                let originalDocument = try readProxySettingsDocument(at: backupURL, fileManager: fileManager)
                try restoreProxySelection(from: originalDocument, into: liveDocument)
                try liveDocument.xmlData(options: [.nodePrettyPrint]).write(to: settingsURL, options: .atomic)
                try removeRecoveryArtifacts(
                    backupURL: backupURL,
                    absenceMarkerURL: absenceMarkerURL,
                    preparedSnapshotURL: preparedSnapshotURL,
                    fileManager: fileManager
                )
                return
            }
        }

        if fileManager.fileExists(atPath: absenceMarkerURL.path) {
            try removeIfPresent(settingsURL, fileManager: fileManager)
            try removeIfPresent(backupURL, fileManager: fileManager)
            try removeIfPresent(absenceMarkerURL, fileManager: fileManager)
            try removeIfPresent(preparedSnapshotURL, fileManager: fileManager)
            return
        }

        if fileManager.fileExists(atPath: backupURL.path) {
            guard try fileSize(at: backupURL, fileManager: fileManager) <= maximumProxySettingsBytes else {
                throw DeveloperApplicationCaptureError.malformedProxySettings
            }
            let originalData = try Data(contentsOf: backupURL, options: [.mappedIfSafe])
            try originalData.write(to: settingsURL, options: .atomic)
            try fileManager.removeItem(at: backupURL)
            return
        }
        // A transaction that still owns artifacts but has lost its original/absence artifact
        // cannot be settled safely. Keep the record and the live settings intact so a later
        // repair or diagnostic can recover them.
        throw DeveloperApplicationCaptureError.malformedProxySettings
    }

    private static func removeIfPresent(_ url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    /// Resolves a stale transaction whose snapshots can no longer be compared safely. The live
    /// bytes are
    /// never discarded: they are moved beside the settings file under a unique conflict name.
    /// Rockxy then restores the exact original (or its original absence) and stops the current
    /// preparation so the user can inspect the conflict before explicitly trying again.
    private static func recoverConflictingLiveSettings(
        settingsURL: URL,
        backupURL: URL,
        absenceMarkerURL: URL,
        preparedSnapshotURL: URL,
        fileManager: FileManager
    )
        throws -> URL
    {
        let originalData: Data?
        if fileManager.fileExists(atPath: backupURL.path) {
            // Validate the recovery source before moving the only live copy out of place.
            _ = try readProxySettingsDocument(at: backupURL, fileManager: fileManager)
            originalData = try Data(contentsOf: backupURL, options: [.mappedIfSafe])
        } else if fileManager.fileExists(atPath: absenceMarkerURL.path) {
            originalData = nil
        } else {
            throw DeveloperApplicationCaptureError.malformedProxySettings
        }

        let conflictURL = settingsURL.appendingPathExtension("rockxy-conflict-\(UUID().uuidString)")
        try fileManager.moveItem(at: settingsURL, to: conflictURL)
        do {
            if let originalData {
                try originalData.write(to: settingsURL, options: .atomic)
            }
            try removeRecoveryArtifacts(
                backupURL: backupURL,
                absenceMarkerURL: absenceMarkerURL,
                preparedSnapshotURL: preparedSnapshotURL,
                fileManager: fileManager
            )
            return conflictURL
        } catch {
            if !fileManager.fileExists(atPath: settingsURL.path) {
                try? fileManager.moveItem(at: conflictURL, to: settingsURL)
            }
            throw error
        }
    }

    private static func readProxySettingsDocument(
        at url: URL,
        fileManager: FileManager
    )
        throws -> XMLDocument
    {
        do {
            guard try fileSize(at: url, fileManager: fileManager) <= maximumProxySettingsBytes else {
                throw DeveloperApplicationCaptureError.malformedProxySettings
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let document = try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
            guard document.rootElement()?.name == "application" else {
                throw DeveloperApplicationCaptureError.malformedProxySettings
            }
            return document
        } catch {
            if let captureError = error as? DeveloperApplicationCaptureError {
                throw captureError
            }
            throw DeveloperApplicationCaptureError.malformedProxySettings
        }
    }

    /// Compares only the selector Rockxy owns. False values are equivalent to absence because
    /// applications commonly materialize default false options while rewriting the file.
    private static func proxySelectionFingerprint(in document: XMLDocument) -> [String: Set<String>] {
        guard let component = proxyComponent(in: document) else {
            return [:]
        }
        var result: [String: Set<String>] = [:]
        for option in component.elements(forName: "option") {
            guard let name = option.attribute(forName: "name")?.stringValue,
                  proxySelectionOptionNames.contains(name) else
            {
                continue
            }
            let value = option.attribute(forName: "value")?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if value == "false" {
                continue
            }
            result[name, default: []].insert(value)
        }
        return result
    }

    private static func restoreProxySelection(
        from originalDocument: XMLDocument,
        into liveDocument: XMLDocument
    )
        throws
    {
        try removeProxySelectionOptions(from: liveDocument)
        guard let originalComponent = proxyComponent(in: originalDocument) else {
            return
        }
        let liveComponent = proxyComponent(in: liveDocument, createIfMissing: true)
        for option in originalComponent.elements(forName: "option") {
            guard let name = option.attribute(forName: "name")?.stringValue,
                  proxySelectionOptionNames.contains(name),
                  let copy = option.copy() as? XMLNode else
            {
                continue
            }
            liveComponent?.addChild(copy)
        }
    }

    private static func removeProxySelectionOptions(from document: XMLDocument) throws {
        guard let component = proxyComponent(in: document) else {
            return
        }
        for option in component.elements(forName: "option") {
            guard let name = option.attribute(forName: "name")?.stringValue,
                  proxySelectionOptionNames.contains(name) else
            {
                continue
            }
            option.detach()
        }
        let hasMeaningfulChildren = component.children?.contains { node in
            node.kind != .text
                || !(node.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        if !hasMeaningfulChildren {
            component.detach()
        }
    }

    private static func proxyComponent(
        in document: XMLDocument,
        createIfMissing: Bool = false
    )
        -> XMLElement?
    {
        guard let application = document.rootElement() else {
            return nil
        }
        if let component = application.elements(forName: "component").first(where: {
            $0.attribute(forName: "name")?.stringValue == "HttpConfigurable"
        }) {
            return component
        }
        guard createIfMissing else {
            return nil
        }
        let component = XMLElement(name: "component")
        component.addAttribute(attribute(name: "name", value: "HttpConfigurable"))
        application.addChild(component)
        return component
    }

    private static func isEffectivelyEmptyProxySettingsDocument(_ document: XMLDocument) -> Bool {
        guard let root = document.rootElement() else {
            return true
        }
        return root.children?.allSatisfy { node in
            node.kind == .text && (node.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
    }

    private static func removeRecoveryArtifacts(
        backupURL: URL,
        absenceMarkerURL: URL,
        preparedSnapshotURL: URL,
        fileManager: FileManager
    )
        throws
    {
        try removeIfPresent(backupURL, fileManager: fileManager)
        try removeIfPresent(absenceMarkerURL, fileManager: fileManager)
        try removeIfPresent(preparedSnapshotURL, fileManager: fileManager)
    }

    private static func hasAnyRecoveryArtifact(
        backupURL: URL,
        absenceMarkerURL: URL,
        preparedSnapshotURL: URL,
        fileManager: FileManager
    )
        -> Bool
    {
        [backupURL, absenceMarkerURL, preparedSnapshotURL]
            .contains { fileManager.fileExists(atPath: $0.path) }
    }

    /// Removes a ledger entry that no longer owns any recovery artifact, together with the
    /// bounded restoration-monitor marker derived from it.
    private static func settleRecoveryRecord(
        _ recoveryRecordURL: URL,
        fileManager: FileManager
    )
        throws
    {
        try removeIfPresent(recoveryRecordURL, fileManager: fileManager)
        DeveloperApplicationRestorationMonitorLedger.removeMarker(
            for: recoveryRecordURL,
            fileManager: fileManager
        )
    }

    /// Canonicalizes every existing path component while retaining a not-yet-created suffix.
    /// Foundation can return `/private/var` URLs from directory enumeration but leave a missing
    /// sibling under `/var`; treating those aliases lexically would reject a valid recovery file.
    /// Broken symbolic links remain unsafe because a later target could escape the trusted root.
    private static func canonicalizedURLPreservingMissingSuffix(
        _ url: URL,
        fileManager: FileManager
    )
        throws -> URL
    {
        var existingURL = url.standardizedFileURL
        var missingComponents: [String] = []

        while !fileManager.fileExists(atPath: existingURL.path) {
            var information = stat()
            if lstat(existingURL.path, &information) == 0,
               information.st_mode & S_IFMT == S_IFLNK
            {
                throw DeveloperApplicationCaptureError.unsafeSettingsLocation
            }
            guard existingURL.path != "/" else {
                break
            }
            missingComponents.append(existingURL.lastPathComponent)
            existingURL.deleteLastPathComponent()
        }

        var canonicalURL = existingURL.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents.reversed() {
            canonicalURL.appendPathComponent(component, isDirectory: false)
        }
        return canonicalURL.standardizedFileURL
    }

    private static func isSafeDirectoryComponent(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && value.utf8.count <= 255
            && trimmed == value
            && trimmed != "."
            && trimmed != ".."
            && !trimmed.contains("/")
            && !trimmed.contains(":")
            && !trimmed.contains("\0")
            && trimmed.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func setOption(name: String, value: String, in component: XMLElement) {
        let matchingOptions = component.elements(forName: "option").filter {
            $0.attribute(forName: "name")?.stringValue == name
        }
        if let option = matchingOptions.first {
            option.removeAttribute(forName: "value")
            option.addAttribute(attribute(name: "value", value: value))
            for duplicate in matchingOptions.dropFirst() {
                duplicate.detach()
            }
            return
        }

        let option = XMLElement(name: "option")
        option.addAttribute(attribute(name: "name", value: name))
        option.addAttribute(attribute(name: "value", value: value))
        component.addChild(option)
    }

    private static func attribute(name: String, value: String) -> XMLNode {
        let attribute = XMLNode(kind: .attribute)
        attribute.name = name
        attribute.stringValue = value
        return attribute
    }

    private static func removeOption(name: String, from component: XMLElement) {
        for option in component.elements(forName: "option") where
            option.attribute(forName: "name")?.stringValue == name
        {
            option.detach()
        }
    }
}
