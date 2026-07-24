import SwiftUI

// Renders the proxy toolbar content interface for toolbar controls and filtering.

// MARK: - ProxyToolbarContent

/// Main window toolbar providing start/stop, Dev Hub access, and inspector
/// layout toggle buttons, plus the central proxy status indicator.
struct ProxyToolbarContent: ToolbarContent {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var updater = AppUpdater.shared

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
                openWindow(id: "developerSetupHub")
            } label: {
                Label(String(localized: "Dev Hub"), systemImage: "command")
            }
            .help(String(localized: "Open Developer Setup Hub"))

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
                    String(localized: "Context Dock"),
                    systemImage: "sidebar.trailing"
                )
            }
            .help(String(localized: "Show or hide the Context Dock"))
        }

        // Center: status indicator
        ToolbarItem(placement: .principal) {
            ProxyStatusIndicator(
                displayState: coordinator.proxyDisplayState,
                listenAddress: AppSettingsManager.shared.settings.effectiveListenAddress,
                port: coordinator.isProxyRunning
                    ? coordinator.activeProxyPort
                    : AppSettingsManager.shared.settings.proxyPort,
                updateStatusSummary: updater.updateStatusSummary,
                openUpdates: {
                    updater.showUpdatesFromStatusBadge()
                },
                showPopover: $coordinator.showProxyStatusPopover
            )
        }
    }
}

// MARK: - ProxyToolbarStatusView

/// Reusable status content for the AppKit-owned main toolbar.
struct ProxyToolbarStatusView: View {
    @ObservedObject private var updater = AppUpdater.shared

    @Bindable var coordinator: MainContentCoordinator

    var body: some View {
        ProxyStatusIndicator(
            displayState: coordinator.proxyDisplayState,
            listenAddress: AppSettingsManager.shared.settings.effectiveListenAddress,
            port: coordinator.isProxyRunning
                ? coordinator.activeProxyPort
                : AppSettingsManager.shared.settings.proxyPort,
            updateStatusSummary: updater.updateStatusSummary,
            openUpdates: {
                updater.showUpdatesFromStatusBadge()
            },
            showPopover: $coordinator.showProxyStatusPopover
        )
    }
}
