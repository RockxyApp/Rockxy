import SwiftUI

// Inbound SOCKS5 listener settings shown in Advanced Proxy Settings.

// MARK: - SOCKSListenerSettings

/// Persisted on/off state and port of the inbound SOCKS5 listener, plus the status
/// the running proxy last reported. Changes post `socksListenerSettingsDidChange`
/// so a running proxy applies them immediately.
@MainActor @Observable
final class SOCKSListenerSettings {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        let storedPort = defaults.integer(forKey: Self.portKey)
        port = storedPort == 0 ? Self.defaultPort : storedPort
    }

    // MARK: Internal

    static let shared = SOCKSListenerSettings()
    static let defaultPort = 8_889
    static let portRange = 1_024 ... 65_535

    private(set) var isEnabled: Bool
    private(set) var port: Int
    private(set) var status: ReverseProxyRuleStatus = .proxyStopped

    /// The port the proxy should listen on, or `nil` when the listener is off.
    var requestedPort: Int? {
        isEnabled && Self.portRange.contains(port) ? port : nil
    }

    func update(isEnabled: Bool, port: Int) {
        guard isEnabled != self.isEnabled || port != self.port else {
            return
        }
        self.isEnabled = isEnabled
        self.port = port
        defaults.set(isEnabled, forKey: Self.enabledKey)
        defaults.set(port, forKey: Self.portKey)
        NotificationCenter.default.post(name: .socksListenerSettingsDidChange, object: nil)
    }

    func applyListenerResult(_ failure: ReverseProxyBindFailure?) {
        guard requestedPort != nil else {
            status = .disabled
            return
        }
        status = switch failure {
        case nil: .listening
        case .proxyNotRunning: .proxyStopped
        case .portInUse: .portInUse
        case let .bindFailed(message): .failed(message)
        }
    }

    func markProxyStopped() {
        status = isEnabled ? .proxyStopped : .disabled
    }

    // MARK: Private

    private static let enabledKey = RockxyIdentity.current.defaultsKey("socksListenerEnabled")
    private static let portKey = RockxyIdentity.current.defaultsKey("socksListenerPort")

    private let defaults: UserDefaults
}

// MARK: - SOCKSListenerSettingsSection

struct SOCKSListenerSettingsSection: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            Text(String(localized: "SOCKS5 Listener", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.tableHeaderFont())

            Toggle(isOn: Binding(
                get: { settings.isEnabled },
                set: { settings.update(isEnabled: $0, port: portValue ?? settings.port) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Accept SOCKS5 connections", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font())
                    Text(String(
                        localized: """
                        For clients that ignore HTTP proxy settings, such as URLSessionWebSocketTask or \
                        NWConnection configured with a SOCKS proxy. Uses the same address as the HTTP listener.
                        """,
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)

            HStack(spacing: toolMetrics.controlSpacing) {
                Text(String(localized: "Port Number", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))
                TextField("", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .frame(width: toolMetrics.fieldWidth(110))
                    .onSubmit(applyPort)
                    .accessibilityLabel(String(
                        localized: "SOCKS5 listener port number",
                        bundle: RockxyLocalization.bundle
                    ))
                Button(String(localized: "Apply", bundle: RockxyLocalization.bundle), action: applyPort)
                    .controlSize(.small)
                    .disabled(portValue == nil || portValue == settings.port)
                Spacer(minLength: 0)
                Label(settings.status.title, systemImage: statusImage)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(settings.status == .listening ? .green : .secondary)
                    .lineLimit(1)
            }

            if portValue == nil {
                Text(String(localized: "Choose a local port from 1024 to 65535.", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
            }
        }
        .padding(toolMetrics.formHorizontalPadding)
        .advancedProxyPanelStyle()
        .onAppear {
            portText = String(settings.port)
        }
    }

    // MARK: Private

    @State private var settings = SOCKSListenerSettings.shared
    @State private var portText = ""
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var portValue: Int? {
        Int(portText.trimmingCharacters(in: .whitespaces)).flatMap {
            SOCKSListenerSettings.portRange.contains($0) ? $0 : nil
        }
    }

    private var statusImage: String {
        switch settings.status {
        case .listening: "circle.fill"
        case .portInUse,
             .failed: "exclamationmark.triangle.fill"
        case .disabled,
             .proxyStopped: "circle"
        }
    }

    private func applyPort() {
        guard let portValue else {
            return
        }
        settings.update(isEnabled: settings.isEnabled, port: portValue)
    }
}
