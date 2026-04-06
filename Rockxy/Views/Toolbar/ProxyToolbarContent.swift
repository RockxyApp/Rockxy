import SwiftUI

// Renders the proxy toolbar content interface for toolbar controls and filtering.

// MARK: - ProxyToolbarContent

/// Main window toolbar providing start/stop, command palette, clear, and inspector
/// layout toggle buttons, plus the central proxy status indicator.
struct ProxyToolbarContent: ToolbarContent {
    @Bindable var coordinator: MainContentCoordinator

    var body: some ToolbarContent {
        // Left: control buttons
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                if coordinator.isProxyRunning {
                    coordinator.stopProxy()
                } else {
                    coordinator.startProxy()
                }
            } label: {
                Label(
                    coordinator.isProxyRunning
                        ? String(localized: "Stop")
                        : String(localized: "Start"),
                    systemImage: coordinator.isProxyRunning ? "stop.fill" : "play.fill"
                )
            }
            .help(coordinator.isProxyRunning ? "Stop proxy" : "Start proxy")

            Button {
                let alert = NSAlert()
                alert.messageText = String(localized: "Command Palette")
                alert.informativeText = String(localized: "Coming soon!")
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            } label: {
                Label(String(localized: "Command Palette"), systemImage: "command")
            }
            .help("Open Command Palette")

            Button {
                coordinator.clearSession()
            } label: {
                Label(String(localized: "Clear"), systemImage: "trash")
            }
            .help("Clear all captured traffic")

            Divider()

            Button {
                coordinator.toggleInspectorBottom()
            } label: {
                Label(
                    String(localized: "Bottom Inspector"),
                    systemImage: "rectangle.split.1x2"
                )
            }
            .help(String(localized: "Show or hide the bottom inspector panel"))

            Button {
                coordinator.toggleInspectorRight()
            } label: {
                Label(
                    String(localized: "Right Inspector"),
                    systemImage: "sidebar.trailing"
                )
            }
            .help(String(localized: "Show or hide the right inspector panel"))
        }

        // Center: status indicator
        ToolbarItem(placement: .principal) {
            ProxyStatusIndicator(
                isRunning: coordinator.isProxyRunning,
                listenAddress: AppSettingsManager.shared.settings.effectiveListenAddress,
                port: coordinator.isProxyRunning
                    ? coordinator.activeProxyPort
                    : AppSettingsManager.shared.settings.proxyPort,
                showPopover: $coordinator.showProxyStatusPopover
            )
        }
    }
}
