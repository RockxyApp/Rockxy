import Crypto
import Foundation
import os

nonisolated private let developerApplicationRecoveryLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "DeveloperApplicationRecovery"
)

/// Durable transaction index for third-party settings temporarily prepared by Rockxy.
/// Record paths are derived from a relative Application Support path and bound to its digest;
/// the ledger never accepts an absolute or escaping recovery target.
enum DeveloperApplicationRecoveryLedger {
    // MARK: Internal

    nonisolated static let maximumRecordBytes: UInt64 = 16_384
    nonisolated static let maximumRecords = 256

    @discardableResult
    static func reconcileOutstandingPreparations(
        applicationSupportURL: URL,
        fileManager: FileManager,
        preparationRegistry: DeveloperApplicationPreparationRegistry,
        recordedProcessIsAlive: (Int32, String?) -> Bool
    ) -> Int {
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
                    if let processIdentifier = outstanding.record.processIdentifier,
                       recordedProcessIsAlive(
                           processIdentifier,
                           outstanding.record.processStartSignature
                       )
                    {
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
    ) throws {
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
        let record = RecoveryRecord(
            schemaVersion: outstanding.record.schemaVersion,
            settingsRelativePath: outstanding.record.settingsRelativePath,
            processIdentifier: processIdentifier,
            processStartSignature: processStartSignature?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try JSONEncoder().encode(record).write(to: preparation.recoveryRecordURL, options: .atomic)
    }

    static func recordURL(
        for settingsURL: URL,
        applicationSupportURL: URL,
        fileManager: FileManager
    ) throws -> URL {
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
        applicationSupportURL: URL,
        fileManager: FileManager
    ) throws {
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
        let record = RecoveryRecord(
            schemaVersion: 1,
            settingsRelativePath: try relativeSettingsPath(
                for: settingsURL,
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            ),
            processIdentifier: nil,
            processStartSignature: nil
        )
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
    }

    nonisolated static func processStartSignature(processIdentifier: Int32) -> String? {
        guard processIdentifier > 0 else {
            return nil
        }
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(processIdentifier), "-o", "lstart="]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let signature = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return signature?.isEmpty == false ? signature : nil
        } catch {
            return nil
        }
    }

    nonisolated static func isRecordedProcessAlive(
        processIdentifier: Int32,
        expectedStartSignature: String?
    ) -> Bool {
        guard let currentStartSignature = processStartSignature(processIdentifier: processIdentifier) else {
            return false
        }
        guard let expectedStartSignature, !expectedStartSignature.isEmpty else {
            return true
        }
        return currentStartSignature == expectedStartSignature
    }

    // MARK: Private

    private struct RecoveryRecord: Codable {
        let schemaVersion: Int
        let settingsRelativePath: String
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
    ) throws -> String {
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
              })
        else {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
        return relativePath
    }

    private static func outstandingPreparation(
        fromRecordAt recordURL: URL,
        applicationSupportURL: URL,
        recoveryDirectoryURL: URL,
        fileManager: FileManager
    ) throws -> OutstandingPreparation {
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
              ) <= maximumRecordBytes
        else {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
        let record = try JSONDecoder().decode(
            RecoveryRecord.self,
            from: Data(contentsOf: recordURL, options: [.mappedIfSafe])
        )
        guard record.schemaVersion == 1,
              !record.settingsRelativePath.hasPrefix("/"),
              record.settingsRelativePath.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              })
        else {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
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
        guard expectedRecordURL.standardizedFileURL == recordURL.standardizedFileURL else {
            throw DeveloperApplicationCaptureError.unsafeSettingsLocation
        }
        return OutstandingPreparation(
            preparation: DeveloperApplicationSettingsPreparation(
                settingsURL: settingsURL,
                backupURL: settingsURL.appendingPathExtension("rockxy-backup"),
                absenceMarkerURL: settingsURL.appendingPathExtension("rockxy-originally-absent"),
                preparedSnapshotURL: settingsURL.appendingPathExtension("rockxy-prepared"),
                recoveryRecordURL: recordURL
            ),
            record: record
        )
    }
}
