import AppKit
import SwiftUI

// Tools > TLS Key Log: write TLS session secrets to a file for Wireshark.

// MARK: - TLSKeyLogSettings

/// Persisted TLS key log state. Turning it on opens the file right away, so a running proxy
/// logs the next handshake without a restart.
@MainActor @Observable
final class TLSKeyLogSettings {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard, writer: TLSKeyLogWriter = .shared) {
        self.defaults = defaults
        self.writer = writer
        fileURL = defaults.string(forKey: Self.pathKey).map { URL(fileURLWithPath: $0) }
            ?? Self.defaultFileURL
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        applyToWriter()
    }

    // MARK: Internal

    static let shared = TLSKeyLogSettings()

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("rockxy-tls-keys.log")
    }

    private(set) var isEnabled: Bool
    private(set) var fileURL: URL
    private(set) var errorMessage: String?

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        applyToWriter()
    }

    func setFileURL(_ url: URL) {
        fileURL = url
        defaults.set(url.path, forKey: Self.pathKey)
        applyToWriter()
    }

    // MARK: Private

    private static let enabledKey = RockxyIdentity.current.defaultsKey("tlsKeyLogEnabled")
    private static let pathKey = RockxyIdentity.current.defaultsKey("tlsKeyLogPath")

    private let defaults: UserDefaults
    private let writer: TLSKeyLogWriter

    private func applyToWriter() {
        do {
            try writer.setDestination(isEnabled ? fileURL : nil)
            errorMessage = nil
        } catch {
            try? writer.setDestination(nil)
            errorMessage = String(
                localized: "Rockxy can't write to \(fileURL.path). Choose another file.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

// MARK: - TLSKeyLogWindowScene

struct TLSKeyLogWindowScene: Scene {
    var body: some Scene {
        Window(String(localized: "TLS Key Log", bundle: RockxyLocalization.bundle), id: "tlsKeyLog") {
            ToolWindowDisplayMetricsProvider {
                TLSKeyLogWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - TLSKeyLogWindowView

struct TLSKeyLogWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(
                localized: """
                Write the secrets of every TLS connection Rockxy decrypts to a key log file. \
                Wireshark and other packet analyzers use it to decrypt a capture of the same traffic.
                """,
                bundle: RockxyLocalization.bundle
            ))
            .font(toolMetrics.font())
            .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(get: { settings.isEnabled }, set: { settings.setEnabled($0) })) {
                Text(String(localized: "Write TLS keys to a file", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font())
            }
            .toggleStyle(.checkbox)

            HStack(spacing: toolMetrics.controlSpacing) {
                Text(verbatim: settings.fileURL.path)
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(settings.fileURL.path)
                Spacer(minLength: 0)
                Button(String(localized: "Choose…", bundle: RockxyLocalization.bundle), action: chooseFile)
                Button(String(localized: "Show in Finder", bundle: RockxyLocalization.bundle)) {
                    NSWorkspace.shared.activateFileViewerSelecting([settings.fileURL])
                }
                .disabled(!FileManager.default.fileExists(atPath: settings.fileURL.path))
            }

            if let errorMessage = settings.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label {
                Text(String(
                    localized: """
                    Anyone with this file and a packet capture can read the decrypted traffic. \
                    Turn logging off when you finish, and delete the file when you no longer need it.
                    """,
                    bundle: RockxyLocalization.bundle
                ))
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(.orange)
            }
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)

            Text(String(
                localized: "In Wireshark, open Settings > Protocols > TLS and set (Pre)-Master-Secret log filename to this file.",
                bundle: RockxyLocalization.bundle
            ))
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 520)
    }

    // MARK: Private

    @State private var settings = TLSKeyLogSettings.shared
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private func chooseFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = settings.fileURL.lastPathComponent
        panel.directoryURL = settings.fileURL.deletingLastPathComponent()
        panel.canCreateDirectories = true
        panel.message = String(
            localized: "Choose where Rockxy appends TLS keys. An existing file is kept and added to.",
            bundle: RockxyLocalization.bundle
        )
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        settings.setFileURL(url)
    }
}
