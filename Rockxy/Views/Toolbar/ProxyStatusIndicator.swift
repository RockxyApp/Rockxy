import SwiftUI

// Renders the proxy status indicator interface for toolbar controls and filtering.

// MARK: - ProxyStatusIndicator

/// Toolbar capsule showing the proxy server's running state with a colored dot indicator
/// and the listen address. Clicking opens a popover with connection details and an
/// "Advanced Settings..." button.
struct ProxyStatusIndicator: View {
    // MARK: Internal

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appUIDisplayMetrics) private var metrics

    let displayState: ProxyDisplayState
    let listenAddress: String
    let port: Int
    let updateStatusSummary: AppUpdater.UpdateStatusSummary?
    let openUpdates: () -> Void

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

                    if updateStatusSummary != nil {
                        Text("|")
                            .font(.system(size: metrics.badgeFontSize))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
                .padding(.leading, ProxyStatusChromeMetrics.horizontalPadding)
                .padding(.trailing, updateStatusSummary == nil ? ProxyStatusChromeMetrics.horizontalPadding : 7)
                .frame(height: metrics.chromeControlHeight)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(statusHelpText)

            if let updateStatusSummary {
                updateStatus(updateStatusSummary)
                    .padding(.trailing, ProxyStatusChromeMetrics.horizontalPadding)
                    .frame(height: metrics.chromeControlHeight)
            }
        }
        .frame(height: metrics.chromeControlHeight)
        .contentShape(Rectangle())
        .popover(isPresented: $showPopover) {
            ProxyStatusPopover(
                listenAddress: listenAddress,
                port: port,
                loopbackAddress: AppSettingsManager.shared.settings.loopbackAddress,
                showPopover: $showPopover
            )
        }
    }

    // MARK: Private

    private enum ProxyStatusChromeMetrics {
        static let horizontalPadding: CGFloat = 14
        static let strokeWidth: CGFloat = 0.75
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

    private var statusColor: Color {
        switch displayState {
        case .starting:
            Color.accentColor
        case .running:
            Color(nsColor: .systemGreen)
        case .paused:
            Color(nsColor: .systemOrange)
        case .stopped:
            Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var statusShadowColor: Color {
        switch displayState {
        case .running:
            Color(nsColor: .systemGreen).opacity(0.45)
        case .starting:
            Color.accentColor.opacity(0.35)
        default:
            Color.clear
        }
    }

    private var statusText: String {
        "Rockxy | \(listenAddress):\(port) | \(displayState.title)"
    }

    private var statusHelpText: String {
        if let updateStatusSummary {
            [
                statusText,
                updateStatusSummary.title,
                updateStatusSummary.versionLine,
                updateStatusSummary.countLine,
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        } else {
            statusText
        }
    }

    @ViewBuilder
    private func updateStatus(_ summary: AppUpdater.UpdateStatusSummary) -> some View {
        Button(action: openUpdates) {
            ViewThatFits(in: .horizontal) {
                updateBadge(summary.badgeTitle)
                updateBadge(String(localized: "Update"))
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
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: metrics.chromeBadgeHeight)
            .background {
                Capsule(style: .continuous).fill(updateBadgeBackground)
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(updateBadgeStroke, lineWidth: ProxyStatusChromeMetrics.strokeWidth)
            }
            .contentShape(Capsule(style: .continuous))
    }

    private var updateBadgeBackground: Color {
        Color(nsColor: .systemGray).opacity(colorScheme == .dark ? 0.62 : 0.82)
    }

    private var updateBadgeStroke: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06)
    }
}
