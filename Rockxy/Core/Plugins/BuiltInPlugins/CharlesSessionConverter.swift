import AppKit
import Foundation
import os

// Converts Charles's binary session files (.chls) to HAR with the Charles app's own
// command-line converter, so Rockxy never parses the closed format itself.

// MARK: - CharlesSessionConverterError

enum CharlesSessionConverterError: LocalizedError, Equatable {
    case charlesNotInstalled
    case conversionFailed(String?)
    case timedOut

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .charlesNotInstalled:
            String(
                localized: """
                Rockxy opens .chls files with Charles's converter, and Charles is not installed. In Charles, \
                choose File > Export Session… and save a JSON Session File (.chlsj) or HTTP Archive (.har), \
                then open that file in Rockxy.
                """,
                bundle: RockxyLocalization.bundle
            )
        case let .conversionFailed(detail):
            detail.map {
                String(localized: "Charles could not convert the session: \($0)", bundle: RockxyLocalization.bundle)
            } ?? String(localized: "Charles could not convert the session.", bundle: RockxyLocalization.bundle)
        case .timedOut:
            String(
                localized: "Charles did not finish converting the session in time.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

// MARK: - CharlesSessionConverter

/// Runs `Charles convert <session.chls> <out.har>` into a private temporary
/// directory. Charles converts headlessly: it opens no window and leaves the
/// system proxy alone. The caller owns and removes the returned directory.
struct CharlesSessionConverter: Sendable {
    // MARK: Lifecycle

    init(
        runner: SimulatorCommandRunning = SimulatorProcessRunner(timeout: .seconds(120)),
        locateCharles: @escaping @Sendable () -> URL? = CharlesSessionConverter.installedCharlesExecutable
    ) {
        self.runner = runner
        self.locateCharles = locateCharles
    }

    // MARK: Internal

    static let bundleIdentifier = "com.xk72.Charles"

    var isCharlesInstalled: Bool {
        locateCharles() != nil
    }

    /// The `Charles` executable inside an installed Charles.app, if any.
    static func installedCharlesExecutable() -> URL? {
        var bundles: [URL] = []
        if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            bundles.append(registered)
        }
        bundles.append(URL(fileURLWithPath: "/Applications/Charles.app"))
        bundles
            .append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Charles.app"))
        return bundles
            .map { $0.appendingPathComponent("Contents/MacOS/Charles") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Converts `session` and returns the HAR file. Its parent directory is private
    /// to this conversion; remove it once the import no longer needs the file.
    func convertToHAR(_ session: URL) async throws -> URL {
        guard let charles = locateCharles() else {
            throw CharlesSessionConverterError.charlesNotInstalled
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-charles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let output = directory.appendingPathComponent(
            session.deletingPathExtension().lastPathComponent + ".har"
        )
        let result: SimulatorCommandOutput
        do {
            result = try await runner.run(executable: charles, arguments: ["convert", session.path, output.path])
        } catch SimulatorCertificateInstallerError.timedOut {
            try? FileManager.default.removeItem(at: directory)
            throw CharlesSessionConverterError.timedOut
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw CharlesSessionConverterError.conversionFailed(error.localizedDescription)
        }
        guard result.status == 0, FileManager.default.fileExists(atPath: output.path) else {
            try? FileManager.default.removeItem(at: directory)
            Self.logger.error("Charles convert exited with status \(result.status)")
            throw CharlesSessionConverterError.conversionFailed(Self.lastErrorLine(result))
        }
        return output
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "CharlesConvert")

    private let runner: SimulatorCommandRunning
    private let locateCharles: @Sendable () -> URL?

    /// Charles logs progress at INFO; the last non-INFO line carries the reason.
    private static func lastErrorLine(_ output: SimulatorCommandOutput) -> String? {
        let text = (String(data: output.standardError.suffix(4_096), encoding: .utf8) ?? "")
            + (String(data: output.standardOutput.suffix(4_096), encoding: .utf8) ?? "")
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty && !$0.hasPrefix("INFO") }
            .map { String($0.prefix(300)) }
    }
}
