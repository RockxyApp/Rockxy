import Crypto
import Darwin
import Foundation
import os

nonisolated private let developerApplicationRecoveryLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "DeveloperApplicationRecovery"
)

// MARK: - DeveloperApplicationRecoveryLedger

/// Durable transaction index for third-party settings temporarily prepared by Rockxy.
/// Recovery targets are derived from a relative Application Support path and bound to its digest.
/// An absolute application-bundle path is retained only as process identity evidence and is never
/// used as a filesystem mutation target.
enum DeveloperApplicationRecoveryLedger {
    // MARK: Internal

    nonisolated static let maximumRecordBytes: UInt64 = 16_384
    nonisolated static let maximumRecords = 256

    @discardableResult
    static func reconcileOutstandingPreparations(
        applicationSupportURL: URL,
        fileManager: FileManager,
        preparationRegistry: DeveloperApplicationPreparationRegistry,
        recordedProcessIsAlive: (Int32, String?) -> Bool,
        recordedApplicationProcessIdentifier: ((String, String) -> Int32?)? = nil,
        livePreparationHandler: ((Int32, DeveloperApplicationSettingsPreparation) -> Void)? = nil
    )
        -> Int
    {
        let directoryURL = recoveryDirectoryURL(applicationSupportURL: applicationSupportURL)
        do {
            try DeveloperApplicationCaptureConfigurator.validateContainedPath(
                directoryURL,
                rootURL: applicationSupportURL,
                fileManager: fileManager
            )
            guard fileManager.fileExists(atPath: directoryURL.path) else {
                return 0
            }
            let allRecordURLs = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "json" }
            if allRecordURLs.count > maximumRecords {
                developerApplicationRecoveryLogger.warning(
                    "Recovery ledger contains \(allRecordURLs.count) records; processing the bounded first \(maximumRecords)"
                )
            }
            let recordURLs = allRecordURLs
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .prefix(maximumRecords)

            var reconciledCount = 0
            for recordURL in recordURLs {
                do {
                    let outstanding = try outstandingPreparation(
                        fromRecordAt: recordURL,
                        applicationSupportURL: applicationSupportURL,
                        recoveryDirectoryURL: directoryURL,
                        fileManager: fileManager
                    )
                    let preparation = outstanding.preparation
                    let key = preparation.settingsURL.standardizedFileURL.path
                    guard preparationRegistry.begin(key) else {
                        continue
                    }
                    defer { preparationRegistry.end(key) }
                    let recordedProcessIdentifier = outstanding.record.processIdentifier
                    let recordedProcessIsStillAlive = recordedProcessIdentifier.map {
                        recordedProcessIsAlive($0, outstanding.record.processStartSignature)
                    } ?? false
                    var relaunchedProcessIdentifier: Int32?
                    if !recordedProcessIsStillAlive,
                       let bundleIdentifier = outstanding.record.bundleIdentifier,
                       let applicationBundlePath = outstanding.record.applicationBundlePath
                    {
                        relaunchedProcessIdentifier = recordedApplicationProcessIdentifier?(
                            bundleIdentifier,
                            applicationBundlePath
                        )
                    }
                    if let liveProcessIdentifier = recordedProcessIsStillAlive
                        ? recordedProcessIdentifier
                        : relaunchedProcessIdentifier
                    {
                        if !recordedProcessIsStillAlive {
                            try associateRunningProcess(
                                processIdentifier: liveProcessIdentifier,
                                processStartSignature: processStartSignature(
                                    processIdentifier: liveProcessIdentifier
                                ),
                                with: preparation,
                                applicationSupportURL: applicationSupportURL,
                                fileManager: fileManager
                            )
                        }
                        livePreparationHandler?(liveProcessIdentifier, preparation)
                        continue
                    }
                    try DeveloperApplicationCaptureConfigurator.restoreRecognizedSettings(
                        preparation,
                        applicationSupportURL: applicationSupportURL,
                        fileManager: fileManager
                    )
                    reconciledCount += 1
                } catch {
                    developerApplicationRecoveryLogger.error(
                        "Could not reconcile a developer-application settings transaction: \(error.localizedDescription)"
                    )
                }
            }
            return reconciledCount
        } catch {
            developerApplicationRecoveryLogger.error(
                "Could not enumerate developer-application recovery records: \(error.localizedDescription)"
            )
            return 0
        }
    }

    static func associateRunningProcess(
        processIdentifier: Int32,
        processStartSignature: String?,
        with preparation: DeveloperApplicationSettingsPreparation,
        applicationSupportURL: URL,
        fileManager: FileManager
    )
        throws
    {
        guard processIdentifier > 0 else {
            return
        }
        let directoryURL = recoveryDirectoryURL(applicationSupportURL: applicationSupportURL)
        let outstanding = try outstandingPreparation(
            fromRecordAt: preparation.recoveryRecordURL,
            applicationSupportURL: applicationSupportURL,
            recoveryDirectoryURL: directoryURL,
            fileManager: fileManager
        )
        let normalizedStartSignature = processStartSignature?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasStableIdentity = normalizedStartSignature?.isEmpty == false
        let record = RecoveryRecord(
            schemaVersion: outstanding.record.schemaVersion,
            settingsRelativePath: outstanding.record.settingsRelativePath,
            bundleIdentifier: outstanding.record.bundleIdentifier,
            applicationBundlePath: outstanding.record.applicationBundlePath,
            processIdentifier: hasStableIdentity ? processIdentifier : nil,
            processStartSignature: hasStableIdentity ? normalizedStartSignature : nil
        )
        try JSONEncoder().encode(record).write(to: preparation.recoveryRecordURL, options: .atomic)
    }

    static func recordURL(
        for settingsURL: URL,
        applicationSupportURL: URL,
        fileManager: FileManager
    )
        throws -> URL
    {
        let relativePath = try relativeSettingsPath(
            for: settingsURL,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        let digest = SHA256.hash(data: Data(relativePath.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return recoveryDirectoryURL(applicationSupportURL: applicationSupportURL)
            .appendingPathComponent("\(digest).json", isDirectory: false)
    }

    static func writeRecord(
        settingsURL: URL,
        recordURL: URL,
        bundleIdentifier: String,
        applicationBundlePath: String,
        applicationSupportURL: URL,
        fileManager: FileManager
    )
        throws
    {
        let directoryURL = recoveryDirectoryURL(applicationSupportURL: applicationSupportURL)
        try DeveloperApplicationCaptureConfigurator.validateContainedPath(
            directoryURL,
            rootURL: applicationSupportURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try DeveloperApplicationCaptureConfigurator.validateContainedPath(
            directoryURL,
            rootURL: applicationSupportURL,
            fileManager: fileManager
        )
        try DeveloperApplicationCaptureConfigurator.validateContainedPath(
            recordURL,
            rootURL: directoryURL,
            fileManager: fileManager
        )
        let normalizedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBundleIdentifier.isEmpty else {
            throw DeveloperApplicationCaptureError.invalidApplicationMetadata
        }
        let normalizedApplicationBundlePath = URL(fileURLWithPath: applicationBundlePath)
            .standardizedFileURL.resolvingSymlinksInPath().path
        guard normalizedApplicationBundlePath.hasPrefix("/") else {
            throw DeveloperApplicationCaptureError.invalidApplicationMetadata
        }
        let record = try RecoveryRecord(
            schemaVersion: 3,
            settingsRelativePath: relativeSettingsPath(
                for: settingsURL,
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            ),
            bundleIdentifier: normalizedBundleIdentifier,
            applicationBundlePath: normalizedApplicationBundlePath,
            processIdentifier: nil,
            processStartSignature: nil
        )
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
    }

    nonisolated static func processStartSignature(processIdentifier: Int32) -> String? {
        guard processIdentifier > 0 else {
            return nil
        }
        var info = proc_bsdinfo()
        let expectedSize = MemoryLayout<proc_bsdinfo>.size
        let result = proc_pidinfo(
            processIdentifier,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(expectedSize)
        )
        guard result == expectedSize else {
            return nil
        }
        return "proc-v1:\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
    }

    nonisolated static func isRecordedProcessAlive(
        processIdentifier: Int32,
        expectedStartSignature: String?
    )
        -> Bool
    {
        guard let currentStartSignature = processStartSignature(processIdentifier: processIdentifier) else {
            return false
        }
        guard let expectedStartSignature else {
            return false
        }
        let normalizedExpected = expectedStartSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalizedExpected.isEmpty && currentStartSignature == normalizedExpected
    }

    // MARK: Private

    private struct RecoveryRecord: Codable {
        let schemaVersion: Int
        let settingsRelativePath: String
        let bundleIdentifier: String?
        let applicationBundlePath: String?
        let processIdentifier: Int32?
        let processStartSignature: String?
    }

    private struct OutstandingPreparation {
        let preparation: DeveloperApplicationSettingsPreparation
        let record: RecoveryRecord
    }

    private static func recoveryDirectoryURL(applicationSupportURL: URL) -> URL {
        applicationSupportURL
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("DeveloperApplicationPreparations", isDirectory: true)
    }

    private static func relativeSettingsPath(
        for settingsURL: URL,
        applicationSupportURL: URL,
        fileManager: FileManager
    )
        throws -> String
    {
        try DeveloperApplicationCaptureConfigurator.validateContainedPath(
            settingsURL,
            rootURL: applicationSupportURL,
            fileManager: fileManager
        )
        let rootPath = applicationSupportURL.standardizedFileURL.path
        let settingsPath = settingsURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard settingsPath.hasPrefix(prefix) else {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
        let relativePath = String(settingsPath.dropFirst(prefix.count))
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              relativePath.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }) else
        {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
        return relativePath
    }

    private static func outstandingPreparation(
        fromRecordAt recordURL: URL,
        applicationSupportURL: URL,
        recoveryDirectoryURL: URL,
        fileManager: FileManager
    )
        throws -> OutstandingPreparation
    {
        try DeveloperApplicationCaptureConfigurator.validateContainedPath(
            recordURL,
            rootURL: recoveryDirectoryURL,
            fileManager: fileManager
        )
        let resourceValues = try recordURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard resourceValues.isRegularFile == true,
              resourceValues.isSymbolicLink != true,
              try DeveloperApplicationCaptureConfigurator.fileSize(
                  at: recordURL,
                  fileManager: fileManager
              ) <= maximumRecordBytes else
        {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
        let record = try JSONDecoder().decode(
            RecoveryRecord.self,
            from: Data(contentsOf: recordURL, options: [.mappedIfSafe])
        )
        guard (1 ... 3).contains(record.schemaVersion),
              !record.settingsRelativePath.hasPrefix("/"),
              record.settingsRelativePath.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }) else
        {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
        if record.schemaVersion >= 2 {
            guard let bundleIdentifier = record.bundleIdentifier,
                  bundleIdentifier == bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                  !bundleIdentifier.isEmpty,
                  let applicationBundlePath = record.applicationBundlePath,
                  applicationBundlePath.hasPrefix("/"),
                  URL(fileURLWithPath: applicationBundlePath)
                  .standardizedFileURL.resolvingSymlinksInPath().path == applicationBundlePath else
            {
                throw DeveloperApplicationCaptureError.unsafeSettingsLocation
            }
        }
        let settingsURL = applicationSupportURL.appendingPathComponent(
            record.settingsRelativePath,
            isDirectory: false
        )
        try DeveloperApplicationCaptureConfigurator.validateContainedPath(
            settingsURL,
            rootURL: applicationSupportURL,
            fileManager: fileManager
        )
        let expectedRecordURL = try self.recordURL(
            for: settingsURL,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        guard expectedRecordURL.standardizedFileURL.resolvingSymlinksInPath()
            == recordURL.standardizedFileURL.resolvingSymlinksInPath() else
        {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
        let artifacts: (backupURL: URL, absenceMarkerURL: URL, preparedSnapshotURL: URL) = if record
            .schemaVersion >= 3
        {
            DeveloperApplicationCaptureConfigurator.recoveryArtifactURLs(for: recordURL)
        } else {
            (
                settingsURL.appendingPathExtension("rockxy-backup"),
                settingsURL.appendingPathExtension("rockxy-originally-absent"),
                settingsURL.appendingPathExtension("rockxy-prepared")
            )
        }
        return OutstandingPreparation(
            preparation: DeveloperApplicationSettingsPreparation(
                settingsURL: settingsURL,
                backupURL: artifacts.backupURL,
                absenceMarkerURL: artifacts.absenceMarkerURL,
                preparedSnapshotURL: artifacts.preparedSnapshotURL,
                recoveryRecordURL: recordURL,
                applicationBundlePath: record.applicationBundlePath
            ),
            record: record
        )
    }
}
