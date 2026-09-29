import SwiftUI

// MARK: - MCPClientSetupCommand

/// One-line setup commands for MCP clients that register servers from their
/// own CLI. The bridge path is single-quoted so paths with spaces or quotes
/// survive the shell unchanged.
enum MCPClientSetupCommand: String, CaseIterable, Identifiable {
    case claudeCode
    case codex

    // MARK: Internal

    var id: String {
        rawValue
    }

    /// Client product names stay verbatim in every language.
    var clientName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    func command(bridgePath: String) -> String {
        let quotedPath = "'" + bridgePath.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        return switch self {
        case .claudeCode: "claude mcp add rockxy -- \(quotedPath)"
        case .codex: "codex mcp add rockxy -- \(quotedPath)"
        }
    }
}

// MARK: - MCPSettingsServerState

enum MCPSettingsServerState: Equatable {
    case disabled
    case starting
    case running(port: Int?)
    case failed(String)
    case stopped

    // MARK: Internal

    static func resolve(
        isEnabled: Bool,
        isStarting: Bool,
        isRunning: Bool,
        activePort: Int?,
        lastError: String?
    )
        -> Self
    {
        guard isEnabled else {
            return .disabled
        }
        if isStarting {
            return .starting
        }
        if isRunning {
            return .running(port: activePort)
        }
        if let lastError {
            return .failed(lastError)
        }
        return .stopped
    }
}

// Settings tab for the MCP (Model Context Protocol) server.
// Provides enable/disable toggle, connection configuration JSON,
// privacy controls, and status display.

// MARK: - MCPSettingsTab

struct MCPSettingsTab: View {
    // MARK: Internal

    var body: some View {
        SettingsPane {
            SettingsSection(String(localized: "MCP Server", bundle: RockxyLocalization.bundle)) {
                mcpServerSection
            }

            SettingsSection(String(localized: "Client Configuration", bundle: RockxyLocalization.bundle)) {
                mcpConfigurationSection
            }

            SettingsSection(String(localized: "Privacy", bundle: RockxyLocalization.bundle)) {
                privacySection
            }

            SettingsSection(String(localized: "Changes", bundle: RockxyLocalization.bundle)) {
                changesSection
            }

            SettingsSection(String(localized: "About MCP", bundle: RockxyLocalization.bundle)) {
                aboutSection
            }
        }
        .onChange(of: mcpEnabled) { _, newValue in
            AppSettingsManager.shared.updateMCPServerEnabled(newValue)
            Task {
                if newValue {
                    await mcpCoordinator.startIfEnabled()
                } else {
                    await mcpCoordinator.stop()
                }
            }
        }
        .onChange(of: mcpRedactSensitiveData) { _, newValue in
            AppSettingsManager.shared.updateMCPRedactSensitiveData(newValue)
            mcpCoordinator.updateRedactionSetting(newValue)
        }
    }

    // MARK: Private

    @AppStorage(RockxyIdentity.current.defaultsKey("mcp.serverEnabled")) private var mcpEnabled = false

    @AppStorage(RockxyIdentity.current.defaultsKey("mcp.redactSensitiveData")) private var mcpRedactSensitiveData = true
    @AppStorage(MCPChangePermission.defaultsKey) private var mcpAllowChanges = false
    @State private var didCopyConfig = false
    @State private var copyFeedbackGeneration = UUID()
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var mcpCoordinator: MCPServerCoordinator {
        MCPServerCoordinator.shared
    }

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var serverState: MCPSettingsServerState {
        MCPSettingsServerState.resolve(
            isEnabled: mcpEnabled,
            isStarting: mcpCoordinator.isStarting,
            isRunning: mcpCoordinator.isRunning,
            activePort: mcpCoordinator.activePort,
            lastError: mcpCoordinator.lastError
        )
    }

    // MARK: - Helpers

    private var configJSON: String {
        struct ServerEntry: Encodable {
            let command: String
            let args: [String]
            let env: [String: String]
        }
        struct Config: Encodable {
            let mcpServers: [String: ServerEntry]
        }

        let config = Config(mcpServers: [
            "rockxy": ServerEntry(command: binaryPath, args: [], env: [:]),
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(config),
              let text = String(data: data, encoding: .utf8) else
        {
            return "{\"mcpServers\":{\"rockxy\":{\"command\":\"rockxy-mcp\",\"args\":[],\"env\":{}}}}"
        }
        return text
    }

    private var binaryPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("rockxy-mcp")
            .path
    }

    // MARK: - MCP Server Section

    private var mcpServerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                String(localized: "Enable MCP Server", bundle: RockxyLocalization.bundle),
                isOn: $mcpEnabled
            )
            .toggleStyle(.checkbox)

            Text(
                String(
                    localized: "Start a local HTTP server for Model Context Protocol (MCP) communication with compatible tools.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            SettingsFieldRow(String(localized: "Status", bundle: RockxyLocalization.bundle)) {
                serverStatus
            }

            SettingsFieldRow(String(localized: "Client Activity", bundle: RockxyLocalization.bundle)) {
                clientActivityStatus
            }
        }
    }

    @ViewBuilder private var serverStatus: some View {
        switch serverState {
        case .disabled:
            Label(String(localized: "Disabled", bundle: RockxyLocalization.bundle), systemImage: "circle")
                .foregroundStyle(.secondary)
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Starting…", bundle: RockxyLocalization.bundle))
            }
            .foregroundStyle(.secondary)
        case let .running(port):
            Label {
                if let port {
                    Text(String(localized: "Running on port \(String(port))", bundle: RockxyLocalization.bundle))
                } else {
                    Text(String(localized: "Running", bundle: RockxyLocalization.bundle))
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(.green)
        case let .failed(error):
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .stopped:
            Label(String(localized: "Stopped", bundle: RockxyLocalization.bundle), systemImage: "pause.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var clientActivityStatus: some View {
        if let activity = mcpCoordinator.latestClientActivity {
            VStack(alignment: .leading, spacing: 3) {
                Label {
                    Text("\(activity.clientName) \(activity.clientVersion)")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .foregroundStyle(.green)

                Text(
                    String(
                        localized: "Last validated method: \(activity.lastMethod) · \(TimestampFormatter.string(activity.lastActivityAt, date: .abbreviated, time: .shortened))",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(settingsMetrics.metadataFont(monospaced: true))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        } else if case .running = serverState {
            Label(
                String(localized: "Waiting for a client to connect", bundle: RockxyLocalization.bundle),
                systemImage: "ellipsis.circle"
            )
            .foregroundStyle(.secondary)
        } else {
            Label(
                String(localized: "Start the MCP server to receive client activity", bundle: RockxyLocalization.bundle),
                systemImage: "bolt.horizontal.circle"
            )
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - MCP Configuration Section

    private var mcpConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        localized: "The MCP bridge is inside Rockxy.app on this Mac.",
                        bundle: RockxyLocalization.bundle
                    ))
                    Text(String(
                        localized: "Copy creates client-ready JSON with this Mac's absolute app path, which may include your account name.",
                        bundle: RockxyLocalization.bundle
                    ))
                }
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    copyConfigToClipboard()
                } label: {
                    Label(
                        didCopyConfig
                            ? String(localized: "Copied", bundle: RockxyLocalization.bundle)
                            : String(localized: "Copy", bundle: RockxyLocalization.bundle),
                        systemImage: didCopyConfig ? "checkmark" : "doc.on.doc"
                    )
                    .font(settingsMetrics.secondaryFont(weight: .medium))
                }
                .accessibilityHint(String(
                    localized: "Copies JSON with this Mac's absolute Rockxy app path.",
                    bundle: RockxyLocalization.bundle
                ))

                Menu {
                    ForEach(MCPClientSetupCommand.allCases) { client in
                        Button(client.clientName) {
                            copyToClipboard(client.command(bridgePath: binaryPath))
                        }
                    }
                } label: {
                    Text(String(localized: "Copy Command", bundle: RockxyLocalization.bundle))
                        .font(settingsMetrics.secondaryFont(weight: .medium))
                }
                .fixedSize()
                .help(String(
                    localized: "Copy a terminal command that registers Rockxy with an MCP client",
                    bundle: RockxyLocalization.bundle
                ))
            }

            ScrollView(.horizontal) {
                Text(verbatim: "Rockxy.app/Contents/MacOS/rockxy-mcp")
                    .font(settingsMetrics.secondaryFont(monospaced: true))
                    .lineSpacing(4)
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Label(
                String(
                    localized: "After saving the configuration, connect or relaunch the client. Its first validated handshake will appear in Client Activity above.",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "checkmark.circle"
            )
            .font(settingsMetrics.metadataFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                String(
                    localized: "Redact Sensitive Data Before Sending to MCP Clients",
                    bundle: RockxyLocalization.bundle
                ),
                isOn: $mcpRedactSensitiveData
            )
            .toggleStyle(.checkbox)

            Text(
                String(
                    localized: "Automatically redact sensitive information before sending to MCP clients.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Label(
                mcpRedactSensitiveData
                    ? String(localized: "Redaction is active for MCP tool results.", bundle: RockxyLocalization.bundle)
                    : String(
                        localized: "Warning: MCP tool results may include captured secrets.",
                        bundle: RockxyLocalization.bundle
                    ),
                systemImage: mcpRedactSensitiveData ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
            )
            .font(settingsMetrics.metadataFont(weight: .medium))
            .foregroundStyle(mcpRedactSensitiveData ? Color.green : Color.orange)
        }
    }

    // MARK: - Changes Section

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                String(
                    localized: "Allow MCP Clients to Change Rules and Capture",
                    bundle: RockxyLocalization.bundle
                ),
                isOn: $mcpAllowChanges
            )
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("mcp.allowChanges")

            Text(
                String(
                    localized: """
                    Lets MCP clients create Breakpoint, Map Local, Map Remote, and Block rules, turn \
                    rules on or off, enable HTTPS decryption for a domain, switch No Caching, pause \
                    recording, and clear the session. Rules they create appear in the matching tool \
                    windows and count toward the same active-rule limits.
                    """,
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Label(
                mcpAllowChanges
                    ? String(localized: "MCP clients can change Rockxy.", bundle: RockxyLocalization.bundle)
                    : String(localized: "MCP clients can only read.", bundle: RockxyLocalization.bundle),
                systemImage: mcpAllowChanges ? "pencil.circle.fill" : "eye.circle"
            )
            .font(settingsMetrics.metadataFont(weight: .medium))
            .foregroundStyle(mcpAllowChanges ? Color.orange : Color.secondary)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                String(
                    localized: """
                    MCP (Model Context Protocol) allows compatible tools to interact with \
                    Rockxy. MCP clients can read captured HTTP traffic, inspect request and \
                    response details, export requests as cURL, and view proxy rules and status.
                    """, bundle: RockxyLocalization.bundle
                )
            )
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.tertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyConfigToClipboard() {
        copyToClipboard(configJSON)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let generation = UUID()
        copyFeedbackGeneration = generation
        didCopyConfig = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard copyFeedbackGeneration == generation else {
                return
            }
            didCopyConfig = false
        }
    }
}
