import SwiftUI

// Renders the proxy toolbar content interface for toolbar controls and filtering.

// MARK: - ProxyToolbarContent

/// Main window toolbar providing start/stop, Developer Setup access, and inspector
/// layout toggle buttons, plus the central proxy status indicator.
struct ProxyToolbarContent: ToolbarContent {
    // MARK: Internal

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
                    coordinator.isProxyStopping
                        ? String(localized: "Stopping…", bundle: RockxyLocalization.bundle)
                        : coordinator.isProxyRunning
                        ? String(localized: "Stop", bundle: RockxyLocalization.bundle)
                        : String(localized: "Start", bundle: RockxyLocalization.bundle),
                    systemImage: coordinator.isProxyRunning || coordinator.isProxyStopping
                        ? "stop.fill"
                        : "play.fill"
                )
            }
            .help(
                coordinator.isProxyStopping
                    ? String(localized: "Proxy shutdown is in progress", bundle: RockxyLocalization.bundle)
                    : coordinator.isProxyRunning ? "Stop proxy" : "Start proxy"
            )
            .disabled(coordinator.isProxyStarting || coordinator.isProxyStopping)

            Button {
                openWindow(id: "developerSetupHub")
            } label: {
                Label(String(localized: "Dev Hub", bundle: RockxyLocalization.bundle), systemImage: "command")
            }
            .help(String(localized: "Open Developer Setup", bundle: RockxyLocalization.bundle))

            Divider()

            Button {
                coordinator.toggleInspectorBottom()
            } label: {
                Label(
                    String(localized: "Bottom Inspector", bundle: RockxyLocalization.bundle),
                    systemImage: "rectangle.split.1x2"
                )
            }
            .help(
                coordinator.canToggleBottomInspector
                    ? String(localized: "Show or hide the bottom inspector panel", bundle: RockxyLocalization.bundle)
                    : String(
                        localized: "Select a request to use the bottom inspector",
                        bundle: RockxyLocalization.bundle
                    )
            )
            .disabled(!coordinator.canToggleBottomInspector)

            Button {
                coordinator.toggleTrafficSplitView()
            } label: {
                Label(
                    coordinator.isTrafficSplitViewVisible
                        ? String(localized: "Hide Split View", bundle: RockxyLocalization.bundle)
                        : String(localized: "Show Split View", bundle: RockxyLocalization.bundle),
                    systemImage: "rectangle.split.2x1"
                )
            }
            .help(String(
                localized: "Show a second traffic pane with its own filters and selection",
                bundle: RockxyLocalization.bundle
            ))

            Button {
                coordinator.toggleInspectorRight()
            } label: {
                Label(
                    String(localized: "Context Dock", bundle: RockxyLocalization.bundle),
                    systemImage: "sidebar.trailing"
                )
            }
            .help(String(localized: "Show or hide the Context Dock", bundle: RockxyLocalization.bundle))
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
                readiness: coordinator.readiness,
                isSystemProxyConfigured: coordinator.isSystemProxyConfigured,
                onToggleCapture: {
                    if coordinator.isProxyRunning {
                        coordinator.stopProxy()
                    } else {
                        coordinator.startProxy()
                    }
                },
                showPopover: $coordinator.showProxyStatusPopover
            )
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var updater = AppUpdater.shared
}

// MARK: - ProxyToolbarStatusView

/// Reusable status content for the AppKit-owned main toolbar.
struct ProxyToolbarStatusView: View {
    // MARK: Internal

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
            readiness: coordinator.readiness,
            isSystemProxyConfigured: coordinator.isSystemProxyConfigured,
            onToggleCapture: {
                if coordinator.isProxyRunning {
                    coordinator.stopProxy()
                } else {
                    coordinator.startProxy()
                }
            },
            showPopover: $coordinator.showProxyStatusPopover
        )
    }

    // MARK: Private

    @ObservedObject private var updater = AppUpdater.shared
}
