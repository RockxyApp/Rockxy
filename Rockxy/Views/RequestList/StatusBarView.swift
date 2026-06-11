import Combine
import SwiftUI

// Renders the status bar interface for traffic list presentation.

// MARK: - FooterActionKind

enum FooterActionKind: String, CaseIterable {
    case blockList
    case allowList
    case mapLocal
    case scripting
    case mapRemote
    case breakpoint
    case networkConditions
    case proxyOverride
}

// MARK: - FooterActionDescriptor

struct FooterActionDescriptor: Identifiable, Equatable {
    let id: FooterActionKind
    let title: String
    let systemImage: String
    let help: String
    let isActive: Bool
    let isEnabled: Bool

    static func toolingActions(isAllowListActive: Bool, isProxyOverridden: Bool = false) -> [Self] {
        var actions: [Self] = [
            .init(
                id: .blockList,
                title: String(localized: "Block List"),
                systemImage: "hand.raised.slash",
                help: String(localized: "Open Block List"),
                isActive: false,
                isEnabled: true
            ),
            .init(
                id: .allowList,
                title: String(localized: "Allow List"),
                systemImage: "checkmark.shield",
                help: String(localized: "Open Allow List"),
                isActive: isAllowListActive,
                isEnabled: true
            ),
            .init(
                id: .mapLocal,
                title: String(localized: "Map Local"),
                systemImage: "folder.badge.gearshape",
                help: String(localized: "Open Map Local"),
                isActive: false,
                isEnabled: true
            ),
            .init(
                id: .scripting,
                title: String(localized: "Scripting"),
                systemImage: "curlybraces",
                help: String(localized: "Open Scripting"),
                isActive: false,
                isEnabled: true
            ),
            .init(
                id: .mapRemote,
                title: String(localized: "Map Remote"),
                systemImage: "arrow.triangle.branch",
                help: String(localized: "Open Map Remote"),
                isActive: false,
                isEnabled: true
            ),
            .init(
                id: .breakpoint,
                title: String(localized: "Breakpoint"),
                systemImage: "pause.circle",
                help: String(localized: "Open Breakpoint Rules"),
                isActive: false,
                isEnabled: true
            ),
            .init(
                id: .networkConditions,
                title: String(localized: "Network Conditions"),
                systemImage: "speedometer",
                help: String(localized: "Open Network Conditions"),
                isActive: false,
                isEnabled: true
            ),
        ]

        if isProxyOverridden {
            actions.append(.init(
                id: .proxyOverride,
                title: String(localized: "Proxy Overridden"),
                systemImage: "checkmark.circle.fill",
                help: String(localized: "Show system proxy override details. Toggle by: ⌥⌘O"),
                isActive: true,
                isEnabled: true
            ))
        }

        return actions
    }
}

// MARK: - FooterToolingButton

private struct FooterToolingButton: View {
    let descriptor: FooterActionDescriptor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(descriptor.title)
                .modifier(FooterToolingChrome(
                    isActive: descriptor.isActive,
                    isEnabled: descriptor.isEnabled,
                    isHovered: isHovered
                ))
        }
        .buttonStyle(.plain)
        .disabled(!descriptor.isEnabled)
        .help(descriptor.help)
        .onHover { isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
}

// MARK: - FooterProxyOverrideButton

private struct FooterProxyOverrideButton: View {
    let descriptor: FooterActionDescriptor
    let proxyHost: String
    let proxyPort: Int
    let onSwitchOff: () -> Void

    var body: some View {
        FooterToolingButton(descriptor: descriptor) {
            showPopover.toggle()
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            FooterProxyOverridePopover(
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                isPresented: $showPopover,
                onSwitchOff: onSwitchOff
            )
        }
    }

    // MARK: Private

    @State private var showPopover = false
}

// MARK: - FooterProxyOverridePopover

private struct FooterProxyOverridePopover: View {
    let proxyHost: String
    let proxyPort: Int
    @Binding var isPresented: Bool
    let onSwitchOff: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: metrics.chromeIconFontSize, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemGreen))

            Text(statusText)
                .font(.system(size: metrics.chromeFontSize))
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(1)
                .truncationMode(.middle)

            Button(String(localized: "Switch Off")) {
                isPresented = false
                onSwitchOff()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 660, alignment: .leading)
    }

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var statusText: String {
        String(localized: "System Proxy is Overridden by Rockxy (IP=\(proxyHost) Port=\(proxyPort)) (Toggle by: ⌥⌘O)")
    }
}

// MARK: - FooterToolingChrome

private struct FooterToolingChrome: ViewModifier {
    let isActive: Bool
    let isEnabled: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: metrics.badgeFontSize, weight: .semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(backgroundColor, in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
    }

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor
        }
        if isHovered, isEnabled {
            return Color(nsColor: .secondaryLabelColor)
        }
        return Color(nsColor: .tertiaryLabelColor)
    }
}

// MARK: - FooterPrimaryButton

private struct FooterPrimaryButton: View {
    let title: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(metrics.swiftUIFont())
                .foregroundStyle(isActive ? Color.accentColor : Color(nsColor: .labelColor))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.12)
        }
        if isHovered {
            return Color(nsColor: .controlBackgroundColor)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.72)
    }
}

// MARK: - StatusBarView

/// Bottom status bar showing request counts, bandwidth stats (upload/download speed),
/// and quick-action buttons for clearing, toggling filters, and auto-select mode.
struct StatusBarView: View {
    // MARK: Internal

    let totalCount: Int
    let selectedCount: Int
    var isProxyRunning: Bool = false
    var proxyHost: String = "127.0.0.1"
    var proxyPort: Int = 9_090
    var totalDataSize: Int64 = 0
    var uploadSpeed: Int64 = 0
    var downloadSpeed: Int64 = 0
    var isProxyOverridden: Bool = false
    var isAllowListActive: Bool = false
    var isNoCachingActive: Bool = false
    var isAutoSelectEnabled: Bool = true
    var isFilterBarVisible: Bool = false
    var activeFilterCount: Int = 0
    var errorCount: Int = 0
    var proxyStartedAt: Date?
    var selectedRequestInfo: String?
    var sessionProvenance: SessionProvenance?

    var onClear: () -> Void = {}
    var onFilter: () -> Void = {}
    var onAutoSelect: () -> Void = {}
    var onSwitchOffProxyOverride: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            leftButtons
            Spacer(minLength: 24)
            centerStatus
            Spacer(minLength: 24)
            rightStats
        }
        .padding(.horizontal, 12)
        .frame(height: metrics.statusBarHeight)
        .background(Theme.StatusBar.background)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: Private

    private var statusText: String {
        if totalCount == 0 {
            return String(localized: "No requests")
        }
        if selectedCount > 0 {
            return String(localized: "\(selectedCount)/\(totalCount) rows selected")
        }
        return String(localized: "\(totalCount) requests")
    }

    private var formattedDataSize: String {
        ByteCountFormatter.string(fromByteCount: totalDataSize, countStyle: .file)
    }

    private var leftButtons: some View {
        HStack(spacing: 8) {
            FooterPrimaryButton(title: String(localized: "Clear"), action: onClear)
            FooterPrimaryButton(
                title: activeFilterCount > 0
                    ? String(localized: "Filter (\(activeFilterCount))")
                    : String(localized: "Filter"),
                isActive: isFilterBarVisible || activeFilterCount > 0,
                action: onFilter
            )
            FooterPrimaryButton(
                title: String(localized: "Auto Select"),
                isActive: isAutoSelectEnabled,
                action: onAutoSelect
            )
        }
    }

    private var centerStatus: some View {
        Group {
            if let provenance = sessionProvenance {
                Text(provenance.displayText)
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(statusText)
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
    }

    private var rightStats: some View {
        HStack(spacing: 8) {
            if let selectedRequestInfo {
                Text(selectedRequestInfo)
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)

                Divider()
                    .frame(height: 12)
            }

            if errorCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: metrics.badgeFontSize))
                    Text(String(localized: "\(errorCount) errors"))
                        .font(.system(size: metrics.secondaryFontSize))
                }
                .foregroundStyle(Color(nsColor: .systemRed))
            }

            if let proxyStartedAt {
                SessionDurationView(startedAt: proxyStartedAt)
            }

            Text("\(formattedDataSize) total")
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .help("Total captured payload bytes")

            Text("↑ \(formattedSpeed(uploadSpeed))")
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .help("Captured upload throughput")

            Text("↓ \(formattedSpeed(downloadSpeed))")
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(Color.accentColor)
                .help("Captured download throughput")

            toolingButtons

            if isAllowListActive {
                statusPill(String(localized: "Allow List"), color: Color.accentColor)
            }

            if isNoCachingActive {
                statusPill(String(localized: "No Cache"), color: Color(nsColor: .systemOrange))
            }
        }
        .lineLimit(1)
    }

    private func formattedSpeed(_ bytesPerSecond: Int64) -> String {
        if bytesPerSecond < 1_024 {
            return "\(bytesPerSecond) B/s"
        } else if bytesPerSecond < 1_048_576 {
            return "\(bytesPerSecond / 1_024) KB/s"
        } else {
            let mb = Double(bytesPerSecond) / 1_048_576
            return String(format: "%.1f MB/s", mb)
        }
    }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var metrics

    @ViewBuilder
    private var toolingButtons: some View {
        ForEach(FooterActionDescriptor.toolingActions(
            isAllowListActive: isAllowListActive,
            isProxyOverridden: isProxyOverridden
        )) { descriptor in
            if descriptor.id == .proxyOverride {
                FooterProxyOverrideButton(
                    descriptor: descriptor,
                    proxyHost: proxyHost,
                    proxyPort: proxyPort,
                    onSwitchOff: onSwitchOffProxyOverride
                )
            } else {
                FooterToolingButton(descriptor: descriptor) {
                    performAction(descriptor.id)
                }
            }
        }
    }

    private func statusPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: metrics.badgeFontSize, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }

    private func performAction(_ action: FooterActionKind) {
        switch action {
        case .blockList:
            openWindow(id: "blockList")
        case .allowList:
            openWindow(id: "allowList")
        case .mapLocal:
            openWindow(id: "mapLocal")
        case .scripting:
            openWindow(id: "scriptingList")
        case .mapRemote:
            openWindow(id: "mapRemote")
        case .breakpoint:
            openWindow(id: "breakpointRules")
        case .networkConditions:
            openWindow(id: "networkConditions")
        case .proxyOverride:
            break
        }
    }
}

// MARK: - SessionDurationView

/// Displays elapsed time since the proxy session started, updating every second.
private struct SessionDurationView: View {
    // MARK: Internal

    let startedAt: Date

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: metrics.badgeFontSize))
            Text(formattedDuration)
                .font(.system(size: metrics.secondaryFontSize).monospacedDigit())
        }
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .onReceive(timer) { tick in
            now = tick
        }
    }

    // MARK: Private

    @State private var now = Date()
    @Environment(\.appUIDisplayMetrics) private var metrics

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var formattedDuration: String {
        let interval = Int(now.timeIntervalSince(startedAt))
        let hours = interval / 3_600
        let minutes = (interval % 3_600) / 60
        let seconds = interval % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
