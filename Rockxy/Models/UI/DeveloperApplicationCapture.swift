import AppKit
import Foundation
import os

nonisolated private let developerApplicationCaptureLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "DeveloperApplicationCapture"
)

// MARK: - DeveloperApplicationInstallation

/// One user-selected macOS application and the safe preparation Rockxy can apply before launch.
struct DeveloperApplicationInstallation: Equatable, Identifiable, Sendable {
    let appURL: URL
    let bundleIdentifier: String
    let displayName: String
    let settingsAdapter: DeveloperApplicationSettingsAdapter?
    let launchAdapter: DeveloperApplicationLaunchAdapter?

    var id: String {
        "\(bundleIdentifier)|\(appURL.standardizedFileURL.path)"
    }
}

// MARK: - DeveloperApplicationLaunchAdapter

/// A runtime capability that can be prepared through documented launch arguments.
enum DeveloperApplicationLaunchAdapter: Equatable, Sendable {
    case chromiumProxy

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

// MARK: - DeveloperApplicationLaunching

@MainActor
protocol DeveloperApplicationLaunching {
    @discardableResult
    func launch(
        _ installation: DeveloperApplicationInstallation,
        arguments: [String],
        environment: [String: String],
        onTermination: (@MainActor @Sendable () -> Void)?
    ) async throws -> Int32
}

// MARK: - DeveloperApplicationWorkspaceLauncher

private final class DeveloperApplicationTerminationObserver: @unchecked Sendable {
    var token: NSObjectProtocol?
}

/// Launches a fresh application instance with a scoped environment via LaunchServices.
@MainActor
struct DeveloperApplicationWorkspaceLauncher: DeveloperApplicationLaunching {
    @discardableResult
    func launch(
        _ installation: DeveloperApplicationInstallation,
        arguments: [String],
        environment: [String: String],
        onTermination: (@MainActor @Sendable () -> Void)?
    ) async throws -> Int32 {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.arguments = arguments
        configuration.environment = environment

        let launchedApplication: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: installation.appURL,
                configuration: configuration
            ) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let application {
                    continuation.resume(returning: application)
                } else {
                    continuation.resume(
                        throwing: DeveloperSetupLaunchError.processFailed(
                            command: installation.displayName,
                            status: -1,
                            message: nil
                        )
                    )
                }
            }
        }

        let processIdentifier = launchedApplication.processIdentifier
        guard let onTermination else {
            return processIdentifier
        }
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let observer = DeveloperApplicationTerminationObserver()
        observer.token = notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let terminated = notification
                .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                terminated.processIdentifier == processIdentifier
            else {
                return
            }
            if let token = observer.token {
                notificationCenter.removeObserver(token)
                observer.token = nil
            }
            Task { @MainActor in
                onTermination()
            }
        }
        if launchedApplication.isTerminated {
            if let token = observer.token {
                notificationCenter.removeObserver(token)
                observer.token = nil
            }
            onTermination()
        }
        return processIdentifier
    }
}

// MARK: - DeveloperApplicationSettingsPreparation

/// A reversible settings transaction. The backup is stored beside the settings file so a later
/// setup attempt can recover it even if Rockxy stopped before observing application termination.
struct DeveloperApplicationSettingsPreparation: Equatable, Sendable {
    let settingsURL: URL
    let backupURL: URL
    let absenceMarkerURL: URL
    let preparedSnapshotURL: URL
    let recoveryRecordURL: URL
}

// MARK: - DeveloperApplicationPreparationRegistry

/// Prevents two setup windows from preparing the same third-party settings file concurrently.
final class DeveloperApplicationPreparationRegistry: @unchecked Sendable {
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

    private let lock = NSLock()
    private var activeKeys: Set<String> = []
}

// MARK: - DeveloperApplicationSettingsRestorationMonitoring

@MainActor
protocol DeveloperApplicationSettingsRestorationMonitoring {
    func startMonitoring(
        processIdentifier: Int32,
        preparation: DeveloperApplicationSettingsPreparation
    ) throws
}

/// Runs a bounded, exact-path restoration monitor outside Rockxy's process. This closes the gap
/// where Rockxy exits before the prepared application. The monitor restores only when the live
/// settings still match Rockxy's prepared snapshot, so user edits made during the session win.
@MainActor
final class DeveloperApplicationSettingsRestorationMonitor: DeveloperApplicationSettingsRestorationMonitoring {
    static let shared = DeveloperApplicationSettingsRestorationMonitor()

    nonisolated static let script = """
    remaining=120960
    started=$(/bin/ps -p "$1" -o lstart= 2>/dev/null)
    while [ -n "$started" ] && /bin/kill -0 "$1" 2>/dev/null && [ "$remaining" -gt 0 ]; do
      current=$(/bin/ps -p "$1" -o lstart= 2>/dev/null)
      if [ "$current" != "$started" ]; then
        break
      fi
      /bin/sleep 5
      remaining=$((remaining - 1))
    done
    current=$(/bin/ps -p "$1" -o lstart= 2>/dev/null)
    if [ -n "$started" ] && /bin/kill -0 "$1" 2>/dev/null && [ "$current" = "$started" ]; then
      exit 0
    fi
    settings=$2
    backup=$3
    absent=$4
    prepared=$5
    recovery_record=$6
    if [ ! -f "$prepared" ]; then
      exit 0
    fi
    if [ ! -f "$settings" ] || ! /usr/bin/cmp -s "$settings" "$prepared"; then
      # A byte-level mismatch may be an application rewrite that preserved Rockxy's proxy
      # selector while changing unrelated settings. Keep the recovery transaction for Rockxy's
      # semantic reconciler instead of deleting the user's original configuration.
      exit 0
    fi
    if [ -f "$absent" ]; then
      /bin/rm -f "$settings" "$backup" "$absent" "$prepared" "$recovery_record"
    elif [ -f "$backup" ]; then
      /bin/mv -f "$backup" "$settings"
      /bin/rm -f "$absent" "$prepared" "$recovery_record"
    else
      /bin/rm -f "$prepared" "$recovery_record"
    fi
    """

    func startMonitoring(
        processIdentifier: Int32,
        preparation: DeveloperApplicationSettingsPreparation
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            Self.script,
            "rockxy-settings-restoration-monitor",
            String(processIdentifier),
            preparation.settingsURL.path,
            preparation.backupURL.path,
            preparation.absenceMarkerURL.path,
            preparation.preparedSnapshotURL.path,
            preparation.recoveryRecordURL.path,
        ]
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
    }
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

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            String(localized: "Choose a valid macOS application.", bundle: RockxyLocalization.bundle)
        case .invalidApplicationMetadata:
            String(localized: "The selected application's proxy metadata could not be read safely.", bundle: RockxyLocalization.bundle)
        case .unsafeSettingsLocation:
            String(localized: "The selected application reported an unsafe settings location. Rockxy left it unchanged.", bundle: RockxyLocalization.bundle)
        case .malformedProxySettings:
            String(localized: "The application's HTTP Proxy settings file is malformed. Rockxy left it unchanged.", bundle: RockxyLocalization.bundle)
        case let .settingsRecoveryConflict(path):
            String(
                localized: "The application rewrote its temporary proxy settings into an unreadable form. Rockxy restored the original settings and preserved the unreadable copy at \(path). Review it, then try again.",
                bundle: RockxyLocalization.bundle
            )
        case let .applicationIsRunning(name):
            String(localized: "Quit \(name) completely, then try again so its proxy state and launch environment cannot be stale.", bundle: RockxyLocalization.bundle)
        case let .preparationInProgress(name):
            String(localized: "Rockxy is already preparing \(name). Wait for that launch to finish, then try again.", bundle: RockxyLocalization.bundle)
        case let .systemProxyRequired(name):
            String(localized: "Enable macOS System Proxy in Rockxy before opening \(name).", bundle: RockxyLocalization.bundle)
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
            .isRecordedProcessAlive
    ) -> Int {
        DeveloperApplicationRecoveryLedger.reconcileOutstandingPreparations(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager,
            preparationRegistry: preparationRegistry,
            recordedProcessIsAlive: recordedProcessIsAlive
        )
    }

    static func associateRunningProcess(
        processIdentifier: Int32,
        processStartSignature: String?,
        with preparation: DeveloperApplicationSettingsPreparation,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try DeveloperApplicationRecoveryLedger.associateRunningProcess(
            processIdentifier: processIdentifier,
            processStartSignature: processStartSignature,
            with: preparation,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
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
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw DeveloperApplicationCaptureError.invalidApplication
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? standardizedURL.deletingPathExtension().lastPathComponent

        return DeveloperApplicationInstallation(
            appURL: standardizedURL,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            settingsAdapter: try detectedSettingsAdapter(in: standardizedURL),
            launchAdapter: detectedLaunchAdapter(in: standardizedURL)
        )
    }

    static func proxySettingsURL(
        for adapter: DeveloperApplicationSettingsAdapter,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let vendorDirectory: String
        let dataDirectoryName: String
        switch adapter {
        case let .xmlHTTPProxyAutoDetect(vendor, dataDirectory):
            vendorDirectory = vendor
            dataDirectoryName = dataDirectory
        }

        guard isSafeDirectoryComponent(vendorDirectory),
              isSafeDirectoryComponent(dataDirectoryName)
        else {
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
    ) throws -> DeveloperApplicationSettingsPreparation? {
        guard let adapter = installation.settingsAdapter else {
            return nil
        }

        switch adapter {
        case .xmlHTTPProxyAutoDetect:
            return try configureXMLAutoDetect(
                adapter: adapter,
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            )
        }
    }

    static func restoreRecognizedSettings(
        _ preparation: DeveloperApplicationSettingsPreparation,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws {
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
            try removeIfPresent(preparation.recoveryRecordURL, fileManager: fileManager)
        } catch {
            // A malformed live file is preserved as a conflict while the original is restored.
            // Once no transaction artifacts remain, the record is settled even though the
            // caller still receives the conflict location for user-facing recovery guidance.
            if !hasRecoveryArtifacts(preparation, fileManager: fileManager) {
                try? removeIfPresent(preparation.recoveryRecordURL, fileManager: fileManager)
            }
            throw error
        }
    }

    @MainActor
    static func isRunning(
        _ installation: DeveloperApplicationInstallation,
        workspace: NSWorkspace = .shared
    ) -> Bool {
        workspace.runningApplications.contains { application in
            guard let bundleURL = application.bundleURL else {
                return false
            }
            return bundleURL.standardizedFileURL.resolvingSymlinksInPath()
                == installation.appURL.standardizedFileURL.resolvingSymlinksInPath()
        }
    }

    // MARK: Private

    private struct ApplicationProxyMetadata: Decodable {
        let productVendor: String
        let dataDirectoryName: String
    }

    /// Detects an application-level proxy schema from metadata shipped inside the app bundle.
    /// Absence is a supported outcome. A file that declares this schema but is malformed fails
    /// closed because silently launching would misrepresent the preparation Rockxy can perform.
    private static func detectedSettingsAdapter(
        in appURL: URL,
        fileManager: FileManager = .default
    ) throws -> DeveloperApplicationSettingsAdapter? {
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

        let metadata: ApplicationProxyMetadata
        do {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["productVendor"] != nil,
                  object["dataDirectoryName"] != nil
            else {
                // `product-info.json` is not a universal schema. An unrelated file with the
                // same basename is not evidence that this adapter applies.
                return nil
            }
            metadata = try JSONDecoder().decode(ApplicationProxyMetadata.self, from: data)
        } catch {
            throw DeveloperApplicationCaptureError.invalidApplicationMetadata
        }

        guard isSafeDirectoryComponent(metadata.productVendor),
              isSafeDirectoryComponent(metadata.dataDirectoryName)
        else {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }

        return .xmlHTTPProxyAutoDetect(
            vendorDirectory: metadata.productVendor,
            dataDirectoryName: metadata.dataDirectoryName
        )
    }

    private static func detectedLaunchAdapter(
        in appURL: URL,
        fileManager: FileManager = .default
    ) -> DeveloperApplicationLaunchAdapter? {
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
        applicationSupportURL: URL,
        fileManager: FileManager
    ) throws -> DeveloperApplicationSettingsPreparation {
        let settingsURL = try proxySettingsURL(
            for: adapter,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        let backupURL = settingsURL.appendingPathExtension("rockxy-backup")
        let absenceMarkerURL = settingsURL.appendingPathExtension("rockxy-originally-absent")
        let preparedSnapshotURL = settingsURL.appendingPathExtension("rockxy-prepared")
        let recoveryRecordURL = try DeveloperApplicationRecoveryLedger.recordURL(
            for: settingsURL,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        try validateContainedPath(backupURL, rootURL: applicationSupportURL, fileManager: fileManager)
        try validateContainedPath(absenceMarkerURL, rootURL: applicationSupportURL, fileManager: fileManager)
        try validateContainedPath(preparedSnapshotURL, rootURL: applicationSupportURL, fileManager: fileManager)

        if fileManager.fileExists(atPath: backupURL.path)
            || fileManager.fileExists(atPath: absenceMarkerURL.path)
            || fileManager.fileExists(atPath: preparedSnapshotURL.path)
        {
            try restoreBackup(
                settingsURL: settingsURL,
                backupURL: backupURL,
                absenceMarkerURL: absenceMarkerURL,
                preparedSnapshotURL: preparedSnapshotURL,
                fileManager: fileManager
            )
            try removeIfPresent(recoveryRecordURL, fileManager: fileManager)
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
        } else {
            try Data().write(to: absenceMarkerURL, options: .atomic)
        }
        let preparedData = document.xmlData(options: [.nodePrettyPrint])
        do {
            // Persist the recovery intent before mutating the live settings file. A crash after
            // this point leaves either a no-op record or a fully recoverable transaction.
            try DeveloperApplicationRecoveryLedger.writeRecord(
                settingsURL: settingsURL,
                recordURL: recoveryRecordURL,
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            )
            try preparedData.write(to: settingsURL, options: .atomic)
            try preparedData.write(to: preparedSnapshotURL, options: .atomic)
        } catch {
            // Once the backup marker exists, preparation is a transaction. A partial disk or
            // permission failure must not leave the selected application on Rockxy's settings.
            try? restoreBackup(
                settingsURL: settingsURL,
                backupURL: backupURL,
                absenceMarkerURL: absenceMarkerURL,
                preparedSnapshotURL: preparedSnapshotURL,
                fileManager: fileManager
            )
            try? removeIfPresent(recoveryRecordURL, fileManager: fileManager)
            throw error
        }
        return DeveloperApplicationSettingsPreparation(
            settingsURL: settingsURL,
            backupURL: backupURL,
            absenceMarkerURL: absenceMarkerURL,
            preparedSnapshotURL: preparedSnapshotURL,
            recoveryRecordURL: recoveryRecordURL
        )
    }

    private static func restoreBackup(
        settingsURL: URL,
        backupURL: URL,
        absenceMarkerURL: URL,
        preparedSnapshotURL: URL,
        fileManager: FileManager
    ) throws {
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

            let preparedDocument = try readProxySettingsDocument(at: preparedSnapshotURL, fileManager: fileManager)
            let liveDocument: XMLDocument
            do {
                liveDocument = try readProxySettingsDocument(at: settingsURL, fileManager: fileManager)
            } catch {
                let conflictURL = try recoverMalformedLiveSettings(
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
        }
        try removeIfPresent(preparedSnapshotURL, fileManager: fileManager)
    }

    private static func removeIfPresent(_ url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    /// Resolves a stale transaction whose live file is no longer parseable. The newer bytes are
    /// never discarded: they are moved beside the settings file under a unique conflict name.
    /// Rockxy then restores the exact original (or its original absence) and stops the current
    /// preparation so the user can inspect the conflict before explicitly trying again.
    private static func recoverMalformedLiveSettings(
        settingsURL: URL,
        backupURL: URL,
        absenceMarkerURL: URL,
        preparedSnapshotURL: URL,
        fileManager: FileManager
    ) throws -> URL {
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

    private static let proxySelectionOptionNames: Set<String> = [
        "USE_PROXY_PAC",
        "USE_HTTP_PROXY",
        "USE_PAC_URL",
        "PROXY_TYPE_IS_SOCKS",
    ]

    private static func readProxySettingsDocument(
        at url: URL,
        fileManager: FileManager
    ) throws -> XMLDocument {
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
                  proxySelectionOptionNames.contains(name)
            else {
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
    ) throws {
        try removeProxySelectionOptions(from: liveDocument)
        guard let originalComponent = proxyComponent(in: originalDocument) else {
            return
        }
        let liveComponent = proxyComponent(in: liveDocument, createIfMissing: true)
        for option in originalComponent.elements(forName: "option") {
            guard let name = option.attribute(forName: "name")?.stringValue,
                  proxySelectionOptionNames.contains(name),
                  let copy = option.copy() as? XMLNode
            else {
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
                  proxySelectionOptionNames.contains(name)
            else {
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
    ) -> XMLElement? {
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
    ) throws {
        try removeIfPresent(backupURL, fileManager: fileManager)
        try removeIfPresent(absenceMarkerURL, fileManager: fileManager)
        try removeIfPresent(preparedSnapshotURL, fileManager: fileManager)
    }

    private static func hasRecoveryArtifacts(
        _ preparation: DeveloperApplicationSettingsPreparation,
        fileManager: FileManager
    ) -> Bool {
        [
            preparation.backupURL,
            preparation.absenceMarkerURL,
            preparation.preparedSnapshotURL,
        ].contains { fileManager.fileExists(atPath: $0.path) }
    }

    static func validateContainedPath(
        _ candidateURL: URL,
        rootURL: URL,
        fileManager: FileManager
    ) throws {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = candidateURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPath), candidate.path != root.path else {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }

        var existingAncestor = candidateURL.deletingLastPathComponent()
        while existingAncestor.path != rootURL.path,
              !fileManager.fileExists(atPath: existingAncestor.path)
        {
            existingAncestor.deleteLastPathComponent()
        }
        let resolvedAncestor = existingAncestor.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedAncestor.path == root.path || resolvedAncestor.path.hasPrefix(rootPath) else {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
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

    static func fileSize(at url: URL, fileManager: FileManager) throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw DeveloperApplicationCaptureError.invalidApplicationMetadata
        }
        return size.uint64Value
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

// MARK: - DeveloperApplicationCaptureWorkflow

enum DeveloperApplicationCaptureOutcome: Equatable {
    case prepared(displayName: String, restorationMonitorActive: Bool)
    case explicitProxyLaunch(displayName: String)
    case environmentOnly(displayName: String)
}

/// Coordinates one reversible application preparation and launch. Keeping this workflow outside
/// the setup view model makes the capability boundary independently testable and keeps UI state
/// updates separate from filesystem and process lifecycle work.
@MainActor
struct DeveloperApplicationCaptureWorkflow {
    let launcher: DeveloperApplicationLaunching
    let restorationMonitor: DeveloperApplicationSettingsRestorationMonitoring
    let preparationRegistry: DeveloperApplicationPreparationRegistry
    let applicationIsRunning: @MainActor (DeveloperApplicationInstallation) -> Bool
    let applicationSupportURL: URL

    func open(
        appURL: URL,
        context: RockxySetupScriptContext,
        systemProxyConfigured: Bool
    ) async throws -> DeveloperApplicationCaptureOutcome {
        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: appURL)
        try validate(installation, systemProxyConfigured: systemProxyConfigured)

        let preparationKey = try settingsURL(for: installation)?.standardizedFileURL.path
        if let preparationKey, !preparationRegistry.begin(preparationKey) {
            throw DeveloperApplicationCaptureError.preparationInProgress(installation.displayName)
        }
        defer {
            if let preparationKey {
                preparationRegistry.end(preparationKey)
            }
        }

        let preparation = try await prepareSettings(for: installation)
        return try await launch(installation, preparation: preparation, context: context)
    }

    private func validate(
        _ installation: DeveloperApplicationInstallation,
        systemProxyConfigured: Bool
    ) throws {
        guard !applicationIsRunning(installation) else {
            throw DeveloperApplicationCaptureError.applicationIsRunning(installation.displayName)
        }
        if installation.settingsAdapter?.requiresSystemProxy == true, !systemProxyConfigured {
            throw DeveloperApplicationCaptureError.systemProxyRequired(installation.displayName)
        }
    }

    private func settingsURL(for installation: DeveloperApplicationInstallation) throws -> URL? {
        try installation.settingsAdapter.map {
            try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
                for: $0,
                applicationSupportURL: applicationSupportURL
            )
        }
    }

    private func prepareSettings(
        for installation: DeveloperApplicationInstallation
    ) async throws -> DeveloperApplicationSettingsPreparation? {
        let applicationSupportURL = self.applicationSupportURL
        return try await Task.detached {
            try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
                for: installation,
                applicationSupportURL: applicationSupportURL
            )
        }.value
    }

    private func launch(
        _ installation: DeveloperApplicationInstallation,
        preparation: DeveloperApplicationSettingsPreparation?,
        context: RockxySetupScriptContext
    ) async throws -> DeveloperApplicationCaptureOutcome {
        let arguments = installation.launchAdapter?.arguments(context: context) ?? []
        let environment = DeveloperCaptureEnvironmentBuilder.environment(
            context: context,
            baseEnvironment: DeveloperCaptureEnvironmentBuilder.safeInheritedEnvironment(),
            includeJavaProxyProperties: installation.settingsAdapter?.requiresJavaProxyProperties
        )
        let applicationSupportURL = self.applicationSupportURL
        let terminationCallback = preparation.map {
            Self.settingsRestorationCallback(
                $0,
                applicationSupportURL: applicationSupportURL
            )
        }

        do {
            let processIdentifier = try await launcher.launch(
                installation,
                arguments: arguments,
                environment: environment,
                onTermination: terminationCallback
            )
            guard let preparation else {
                if installation.launchAdapter != nil {
                    return .explicitProxyLaunch(displayName: installation.displayName)
                }
                return .environmentOnly(displayName: installation.displayName)
            }
            await associateRunningProcess(
                processIdentifier: processIdentifier,
                preparation: preparation
            )
            let monitorActive = startRestorationMonitor(
                processIdentifier: processIdentifier,
                preparation: preparation
            )
            return .prepared(
                displayName: installation.displayName,
                restorationMonitorActive: monitorActive
            )
        } catch {
            if let preparation {
                await Task.detached(priority: .utility) {
                    Self.restoreSettings(preparation, applicationSupportURL: applicationSupportURL)
                }.value
            }
            throw error
        }
    }

    private func startRestorationMonitor(
        processIdentifier: Int32,
        preparation: DeveloperApplicationSettingsPreparation
    ) -> Bool {
        do {
            try restorationMonitor.startMonitoring(
                processIdentifier: processIdentifier,
                preparation: preparation
            )
            return true
        } catch {
            developerApplicationCaptureLogger.error(
                "Could not start the developer-application settings restoration monitor: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func associateRunningProcess(
        processIdentifier: Int32,
        preparation: DeveloperApplicationSettingsPreparation
    ) async {
        let applicationSupportURL = self.applicationSupportURL
        do {
            try await Task.detached(priority: .utility) {
                let startSignature = DeveloperApplicationCaptureConfigurator.processStartSignature(
                    processIdentifier: processIdentifier
                )
                try DeveloperApplicationCaptureConfigurator.associateRunningProcess(
                    processIdentifier: processIdentifier,
                    processStartSignature: startSignature,
                    with: preparation,
                    applicationSupportURL: applicationSupportURL
                )
            }.value
        } catch {
            developerApplicationCaptureLogger.error(
                "Could not associate the launched application with its recovery record: \(error.localizedDescription)"
            )
        }
    }

    nonisolated private static func settingsRestorationCallback(
        _ preparation: DeveloperApplicationSettingsPreparation,
        applicationSupportURL: URL
    ) -> @MainActor @Sendable () -> Void {
        {
            Task.detached {
                restoreSettings(preparation, applicationSupportURL: applicationSupportURL)
            }
        }
    }

    nonisolated private static func restoreSettings(
        _ preparation: DeveloperApplicationSettingsPreparation,
        applicationSupportURL: URL
    ) {
        do {
            try DeveloperApplicationCaptureConfigurator.restoreRecognizedSettings(
                preparation,
                applicationSupportURL: applicationSupportURL
            )
        } catch {
            developerApplicationCaptureLogger.error(
                "Could not restore temporary developer-application proxy settings: \(error.localizedDescription)"
            )
        }
    }
}
