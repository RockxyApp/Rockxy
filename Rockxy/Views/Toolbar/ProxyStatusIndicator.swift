import SwiftUI

// Renders the proxy status indicator interface for toolbar controls and filtering.

// MARK: - ProxyStatusIndicator

/// Toolbar capsule showing the proxy server's running state with a colored dot indicator
/// and the listen address. Clicking opens a popover with connection details and an
/// "Advanced Settings..." button.
struct ProxyStatusIndicator: View {
    // MARK: Internal

    let displayState: ProxyDisplayState
    let listenAddress: String
    let port: Int
    let updateStatusSummary: AppUpdater.UpdateStatusSummary?
    let openUpdates: () -> Void
    let readiness: ReadinessCoordinator
    let isSystemProxyConfigured: Bool
    let onToggleCapture: () -> Void

    @Binding var showPopover: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 7) {
                    statusDot

                    Text(statusText)
                        .font(.system(size: metrics.chromeFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Divider()
                        .frame(height: 12)
                        .accessibilityHidden(true)

                    Text(listenerText)
                        .font(.system(size: metrics.chromeFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, ProxyStatusChromeMetrics.horizontalPadding)
                .padding(.trailing, updateStatusSummary == nil ? ProxyStatusChromeMetrics.horizontalPadding : 8)
                .frame(height: metrics.chromeControlHeight)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(statusHelpText)
            .accessibilityLabel(statusText)
            .accessibilityValue(listenerStatusText)

            if let updateStatusSummary {
                Divider()
                    .frame(height: 13)
                    .padding(.horizontal, 2)
                    .accessibilityHidden(true)

                updateStatus(updateStatusSummary)
                    .padding(.trailing, ProxyStatusChromeMetrics.horizontalPadding)
                    .frame(height: metrics.chromeControlHeight)
            }
        }
        .frame(height: metrics.chromeControlHeight)
        .contentShape(Capsule(style: .continuous))
        .popover(isPresented: $showPopover) {
            ProxyStatusPopover(
                displayState: displayState,
                listenAddress: listenAddress,
                port: port,
                readiness: readiness,
                isSystemProxyConfigured: isSystemProxyConfigured,
                onToggleCapture: onToggleCapture,
                showPopover: $showPopover
            )
        }
    }

    // MARK: Private

    private enum ProxyStatusChromeMetrics {
        static let horizontalPadding: CGFloat = 14
    }

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var statusColor: Color {
        switch displayState {
        case .starting,
             .stopping:
            Color.accentColor
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
        case .stopped:
            Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var statusShadowColor: Color {
        switch displayState {
        case .running:
            if readiness.captureHealth == .checking {
                Color.accentColor.opacity(0.35)
            } else if readiness.hasBlockingReadinessIssue {
                Color(nsColor: .systemOrange).opacity(0.35)
            } else {
                Color(nsColor: .systemGreen).opacity(0.45)
            }
        case .starting,
             .stopping:
            Color.accentColor.opacity(0.35)
        default:
            Color.clear
        }
    }

    private var statusText: String {
        let needsAttention = readiness.hasBlockingReadinessIssue
        if displayState == .running, readiness.captureHealth == .checking {
            return String(localized: "Checking Capture", bundle: RockxyLocalization.bundle)
        }
        if displayState == .running, needsAttention {
            return String(localized: "Capture Needs Attention", bundle: RockxyLocalization.bundle)
        }
        return displayState.captureTitle
    }

    private var listenerText: String {
        CaptureStatusPresentation.listener(address: listenAddress, port: port)
    }

    private var listenerStatusText: String {
        switch displayState {
        case .stopped:
            String(localized: "Configured endpoint: \(listenerText)", bundle: RockxyLocalization.bundle)
        case .starting:
            String(localized: "Starting on \(listenerText)", bundle: RockxyLocalization.bundle)
        case .running,
             .paused,
             .stopping:
            String(localized: "Listening on \(listenerText)", bundle: RockxyLocalization.bundle)
        }
    }

    private var statusHelpText: String {
        let captureContext = [
            statusText,
            listenerStatusText,
        ]
        if let updateStatusSummary {
            return (captureContext + [
                updateStatusSummary.title,
                updateStatusSummary.versionLine,
                updateStatusSummary.countLine,
            ])
            .compactMap { $0 }
            .joined(separator: "\n")
        }
        return captureContext.joined(separator: "\n")
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: metrics.chromeStatusDotSize, height: metrics.chromeStatusDotSize)
            .shadow(
                color: statusShadowColor,
                radius: 4,
                x: 0,
                y: 0
            )
    }

    private func updateStatus(_ summary: AppUpdater.UpdateStatusSummary) -> some View {
        Button(action: openUpdates) {
            ViewThatFits(in: .horizontal) {
                updateBadge(summary.badgeTitle)
                updateBadge(String(localized: "Update", bundle: RockxyLocalization.bundle))
            }
        }
        .buttonStyle(.plain)
        .help([
            summary.title,
            summary.versionLine,
            summary.countLine,
        ]
        .compactMap { $0 }
        .joined(separator: "\n"))
    }

    private func updateBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: metrics.chromeBadgeFontSize, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: metrics.chromeBadgeHeight)
            .rockxyChipStyle(isActive: true)
    }
}
