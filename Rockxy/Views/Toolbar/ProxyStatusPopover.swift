import SwiftUI

// Presents capture readiness and listener context from the main toolbar.

// MARK: - CaptureReadinessLevel

enum CaptureReadinessLevel: Equatable {
    case ready
    case attention
    case neutral
}

// MARK: - CaptureReadinessItem

struct CaptureReadinessItem: Equatable {
    let value: String
    let systemImage: String
    let level: CaptureReadinessLevel
}

// MARK: - CaptureStatusPresentation

/// Pure presentation decisions for the capture-status popover. Keeping listener scope and
/// readiness wording outside the SwiftUI layout makes the security-sensitive state easy to test.
struct CaptureStatusPresentation: Equatable {
    // MARK: Lifecycle

    init(
        displayState: ProxyDisplayState,
        listenAddress: String,
        port: Int,
        certReadiness: CertReadiness,
        helperReadiness: HelperManager.HelperStatus,
        isSystemProxyConfigured: Bool,
        isSystemRoutingExpected: Bool = true,
        captureHealth: CaptureHealthState = .verified
    ) {
        let header = Self.captureHeader(
            displayState: displayState,
            isSystemProxyConfigured: isSystemProxyConfigured,
            isSystemRoutingExpected: isSystemRoutingExpected,
            certReadiness: certReadiness,
            captureHealth: captureHealth
        )
        title = header.title
        description = header.description
        systemImage = header.systemImage
        actionTitle = displayState.captureActionTitle
        isActionEnabled = displayState != .starting && displayState != .stopping
        listener = Self.listener(address: listenAddress, port: port)
        listenerLabel = Self.listenerLabel(displayState: displayState)
        listenerScope = Self.listenerScope(address: listenAddress)
        listenerScopeLabel = Self.listenerScopeLabel(displayState: displayState)
        https = Self.httpsItem(certReadiness)
        systemRouting = Self.systemRoutingItem(
            displayState: displayState,
            helperReadiness: helperReadiness,
            isConfigured: isSystemProxyConfigured
        )
        capturePath = Self.capturePathItem(displayState: displayState, captureHealth: captureHealth)
    }

    // MARK: Internal

    let title: String
    let description: String
    let systemImage: String
    let actionTitle: String
    let isActionEnabled: Bool
    let listener: String
    let listenerLabel: String
    let listenerScope: String
    let listenerScopeLabel: String
    let https: CaptureReadinessItem
    let systemRouting: CaptureReadinessItem
    let capturePath: CaptureReadinessItem

    static func listener(address: String, port: Int) -> String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }

    static func listenerScope(address: String) -> String {
        switch address.lowercased() {
        case "0.0.0.0",
             "::":
            String(localized: "This Mac and local network", bundle: RockxyLocalization.bundle)
        case "127.0.0.1",
             "::1",
             "localhost":
            String(localized: "This Mac only", bundle: RockxyLocalization.bundle)
        default:
            String(localized: "Selected network interface", bundle: RockxyLocalization.bundle)
        }
    }

    static func listenerLabel(displayState: ProxyDisplayState) -> String {
        switch displayState {
        case .stopped,
             .starting:
            String(localized: "Configured endpoint", bundle: RockxyLocalization.bundle)
        case .running,
             .paused,
             .stopping:
            String(localized: "Listening", bundle: RockxyLocalization.bundle)
        }
    }

    static func listenerScopeLabel(displayState: ProxyDisplayState) -> String {
        switch displayState {
        case .stopped,
             .starting:
            String(localized: "Configured access", bundle: RockxyLocalization.bundle)
        case .running,
             .paused,
             .stopping:
            String(localized: "Reachable from", bundle: RockxyLocalization.bundle)
        }
    }

    // MARK: Private

    private static func captureHeader(
        displayState: ProxyDisplayState,
        isSystemProxyConfigured: Bool,
        isSystemRoutingExpected: Bool,
        certReadiness: CertReadiness,
        captureHealth: CaptureHealthState
    ) -> (title: String, description: String, systemImage: String) {
        guard displayState == .running else {
            return (displayState.captureTitle, displayState.captureDescription, displayState.captureSystemImage)
        }
        if captureHealth == .checking {
            return (
                String(localized: "Checking Capture", bundle: RockxyLocalization.bundle),
                String(localized: "Verifying the live listener with a private loopback request.", bundle: RockxyLocalization.bundle),
                "checkmark.arrow.trianglehead.counterclockwise"
            )
        }
        if captureHealth == .failed
            || (isSystemRoutingExpected && !isSystemProxyConfigured)
            || certReadiness != .trusted
        {
            return (
                String(localized: "Capture Needs Attention", bundle: RockxyLocalization.bundle),
                String(localized: "The listener is running, but automatic capture is not fully verified.", bundle: RockxyLocalization.bundle),
                "exclamationmark.triangle.fill"
            )
        }
        return (displayState.captureTitle, displayState.captureDescription, displayState.captureSystemImage)
    }

    private static func capturePathItem(
        displayState: ProxyDisplayState,
        captureHealth: CaptureHealthState
    ) -> CaptureReadinessItem {
        guard displayState != .stopped else {
            return CaptureReadinessItem(
                value: String(localized: "Runs on start", bundle: RockxyLocalization.bundle),
                systemImage: "checkmark.circle",
                level: .neutral
            )
        }
        switch captureHealth {
        case .idle:
            return CaptureReadinessItem(
                value: String(localized: "Not checked", bundle: RockxyLocalization.bundle),
                systemImage: "minus.circle",
                level: .neutral
            )
        case .checking:
            return CaptureReadinessItem(
                value: String(localized: "Checking…", bundle: RockxyLocalization.bundle),
                systemImage: "arrow.triangle.2.circlepath",
                level: .neutral
            )
        case .verified:
            return CaptureReadinessItem(
                value: String(localized: "Local path verified", bundle: RockxyLocalization.bundle),
                systemImage: "checkmark.circle.fill",
                level: .ready
            )
        case .failed:
            return CaptureReadinessItem(
                value: String(localized: "Check failed", bundle: RockxyLocalization.bundle),
                systemImage: "exclamationmark.triangle.fill",
                level: .attention
            )
        }
    }

    private static func httpsItem(_ readiness: CertReadiness) -> CaptureReadinessItem {
        if readiness == .trusted {
            return CaptureReadinessItem(
                value: String(localized: "Ready", bundle: RockxyLocalization.bundle),
                systemImage: "checkmark.circle.fill",
                level: .ready
            )
        }
        return CaptureReadinessItem(
            value: readiness.localizedDescription,
            systemImage: "exclamationmark.triangle.fill",
            level: .attention
        )
    }

    private static func systemRoutingItem(
        displayState: ProxyDisplayState,
        helperReadiness: HelperManager.HelperStatus,
        isConfigured: Bool
    )
        -> CaptureReadinessItem
    {
        if isConfigured {
            return CaptureReadinessItem(
                value: String(localized: "Routing active", bundle: RockxyLocalization.bundle),
                systemImage: "checkmark.circle.fill",
                level: .ready
            )
        }
        if displayState == .stopping {
            return CaptureReadinessItem(
                value: String(localized: "Restoring routing", bundle: RockxyLocalization.bundle),
                systemImage: "arrow.triangle.2.circlepath",
                level: .neutral
            )
        }
        if displayState != .stopped {
            return CaptureReadinessItem(
                value: String(localized: "Manual app setup", bundle: RockxyLocalization.bundle),
                systemImage: "arrow.triangle.branch",
                level: .attention
            )
        }
        if helperReadiness == .installedCompatible {
            return CaptureReadinessItem(
                value: String(localized: "Ready on start", bundle: RockxyLocalization.bundle),
                systemImage: "checkmark.circle",
                level: .ready
            )
        }
        let value = switch helperReadiness {
        case .requiresApproval:
            String(localized: "Approval needed", bundle: RockxyLocalization.bundle)
        case .installedOutdated,
             .installedIncompatible:
            String(localized: "Update needed", bundle: RockxyLocalization.bundle)
        case .unreachable,
             .signingMismatch:
            String(localized: "Needs attention", bundle: RockxyLocalization.bundle)
        case .notInstalled:
            String(localized: "Developer setup needed", bundle: RockxyLocalization.bundle)
        case .installedCompatible:
            String(localized: "Ready on start", bundle: RockxyLocalization.bundle)
        }
        return CaptureReadinessItem(
            value: value,
            systemImage: "wrench.and.screwdriver.fill",
            level: .attention
        )
    }
}

// MARK: - ProxyStatusPopover

/// A capture-focused status surface. It explains readiness and listener reachability instead
/// of repeating low-level address fields without telling the user whether capture will work.
struct ProxyStatusPopover: View {
    // MARK: Internal

    let displayState: ProxyDisplayState
    let listenAddress: String
    let port: Int
    let readiness: ReadinessCoordinator
    let isSystemProxyConfigured: Bool
    let onToggleCapture: () -> Void

    @Binding var showPopover: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            captureHeader

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                valueRow(
                    label: presentation.listenerLabel,
                    value: presentation.listener,
                    systemImage: "network",
                    level: .neutral,
                    isMonospaced: true
                )
                valueRow(
                    label: presentation.listenerScopeLabel,
                    value: presentation.listenerScope,
                    systemImage: "macbook.and.iphone",
                    level: .neutral
                )
                valueRow(
                    label: String(localized: "HTTPS decryption", bundle: RockxyLocalization.bundle),
                    item: presentation.https
                )
                valueRow(
                    label: String(localized: "System routing", bundle: RockxyLocalization.bundle),
                    item: presentation.systemRouting
                )
                valueRow(
                    label: String(localized: "Capture path", bundle: RockxyLocalization.bundle),
                    item: presentation.capturePath
                )
            }

            Divider()

            HStack(spacing: 8) {
                Button(String(localized: "Developer Setup…", bundle: RockxyLocalization.bundle)) {
                    openWindow(id: "developerSetupHub")
                    showPopover = false
                }

                Spacer()

                Button(String(localized: "Advanced Settings…", bundle: RockxyLocalization.bundle)) {
                    openWindow(id: "advancedProxySettings")
                    showPopover = false
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var presentation: CaptureStatusPresentation {
        CaptureStatusPresentation(
            displayState: displayState,
            listenAddress: listenAddress,
            port: port,
            certReadiness: readiness.certReadiness,
            helperReadiness: readiness.helperReadiness,
            isSystemProxyConfigured: isSystemProxyConfigured,
            isSystemRoutingExpected: readiness.systemRoutingExpected,
            captureHealth: readiness.captureHealth
        )
    }

    private var headerColor: Color {
        switch displayState {
        case .running:
            if readiness.captureHealth == .checking {
                Color.accentColor
            } else if readiness.hasBlockingReadinessIssue {
                Color(nsColor: .systemOrange)
            } else {
                Color(nsColor: .systemGreen)
            }
        case .paused:
            Color(nsColor: .systemOrange)
        case .starting,
             .stopping:
            Color.accentColor
        case .stopped:
            Color(nsColor: .secondaryLabelColor)
        }
    }

    private var captureHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(headerColor)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.headline)
                Text(presentation.description)
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if displayState == .starting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(presentation.actionTitle)
            } else {
                Button(presentation.actionTitle) {
                    onToggleCapture()
                    showPopover = false
                }
                .controlSize(.small)
                .disabled(!presentation.isActionEnabled)
            }
        }
    }

    private func valueRow(
        label: String,
        item: CaptureReadinessItem
    )
        -> some View
    {
        valueRow(
            label: label,
            value: item.value,
            systemImage: item.systemImage,
            level: item.level
        )
    }

    private func valueRow(
        label: String,
        value: String,
        systemImage: String,
        level: CaptureReadinessLevel,
        isMonospaced: Bool = false
    )
        -> some View
    {
        GridRow {
            Text(label)
                .font(.system(size: metrics.chromeFontSize))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.badgeFontSize, weight: .semibold))
                    .foregroundStyle(color(for: level))
                    .accessibilityHidden(true)
                Text(value)
                    .font(isMonospaced
                        ? .system(size: metrics.chromeFontSize, weight: .medium, design: .monospaced)
                        : .system(size: metrics.chromeFontSize, weight: .medium))
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    private func color(for level: CaptureReadinessLevel) -> Color {
        switch level {
        case .ready:
            Color(nsColor: .systemGreen)
        case .attention:
            Color(nsColor: .systemOrange)
        case .neutral:
            Color(nsColor: .secondaryLabelColor)
        }
    }
}
