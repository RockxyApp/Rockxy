import SwiftUI

// Settings tab for the MCP (Model Context Protocol) server.
// Provides enable/disable toggle, connection configuration JSON,
// privacy controls, and status display.

// MARK: - MCPSettingsTab

struct MCPSettingsTab: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                mcpServerSection
                mcpConfigurationSection
                sectionDivider
                privacySection
                sectionDivider
                aboutSection
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 24)
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

    private var mcpCoordinator: MCPServerCoordinator {
        MCPServerCoordinator.shared
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

    private var sectionDivider: some View {
        Divider().padding(.horizontal, 0)
    }

    // MARK: - MCP Server Section

    private var mcpServerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "MCP Server"))
                .font(.system(size: 15, weight: .bold))

            Toggle(
                String(localized: "Enable MCP Server"),
                isOn: $mcpEnabled
            )
            .toggleStyle(.checkbox)

            Text(
                String(
                    localized: "Start a local HTTP server for Model Context Protocol (MCP) communication with compatible tools."
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if mcpCoordinator.isRunning, let port = mcpCoordinator.activePort {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                    Text(String(localized: "Running on port \(port)"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }
                .padding(.leading, 4)
            }

            if let error = mcpCoordinator.lastError {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - MCP Configuration Section

    private var mcpConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "MCP Configuration"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyConfigToClipboard()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text(String(localized: "Copy"))
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }

            Text(configJSON)
                .font(.system(size: 11.5, design: .monospaced))
                .lineSpacing(4)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            Text(
                String(
                    localized: "Add this to your MCP-compatible tool configuration file."
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Privacy"))
                .font(.system(size: 15, weight: .bold))

            Toggle(
                String(localized: "Redact Sensitive Data Before Sending to AI"),
                isOn: $mcpRedactSensitiveData
            )
            .toggleStyle(.checkbox)

            Text(
                String(
                    localized: "Automatically redact sensitive information before sending to MCP clients."
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "About MCP Integration"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)

            Text(
                String(
                    localized: """
                    MCP (Model Context Protocol) allows compatible tools to interact with \
                    Rockxy. The AI can read captured HTTP traffic, inspect request and \
                    response details, export requests as cURL, and view proxy rules and status.
                    """
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .lineSpacing(2)
        }
    }

    private func copyConfigToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(configJSON, forType: .string)
    }
}
