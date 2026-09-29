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

    // MARK: Internal

    static let defaultQuickTools: [Self] = [.breakpoint, .mapLocal, .scripting, .networkConditions]
}

// MARK: - FooterActionDescriptor

struct FooterActionDescriptor: Identifiable, Equatable {
    let id: FooterActionKind
    let title: String
    let systemImage: String
    let help: String
    let isActive: Bool
    let isEnabled: Bool

    static func toolingActions(
        isAllowListActive: Bool,
        isProxyOverridden: Bool = false,
        quickTools: [FooterActionKind] = FooterActionKind.defaultQuickTools
    )
        -> [Self]
    {
        let catalog: [Self] = [
            .init(
                id: .blockList,
                title: String(localized: "Block List", bundle: RockxyLocalization.bundle),
                systemImage: "hand.raised.slash",
                help: String(localized: "Open Block List", bundle: RockxyLocalization.bundle),
                isActive: false,
                isEnabled: true
            ),
            .init(
                id: .allowList,
                title: String(localized: "Allow List", bundle: RockxyLocalization.bundle),
                systemImage: "checkmark.shield",
                help: String(localized: "Open Allow List", bundle: RockxyLocalization.bundle),
                isActive: isAllowListActive,
                isEnabled: true
            ),
            .init(
                id: .mapLocal,
                title: String(localized: "Map Local", bundle: RockxyLocalization.bundle),
                systemImage: "folder.badge.gearshape",
                help: String(localized: "Open Map Local", bundle: RockxyLocalization.bundle),
                isActive: false,
                isEnabled: true
            ),
            .init(
                id: .scripting,
                title: String(localized: "Scripting", bundle: RockxyLocalization.bundle),
                systemImage: "curlybraces",
                help: String(localized: "Open Scripting", bundle: RockxyLocalization.bundle),
                isActive: false,
                isEnabled: true
            ),
            .init(
                id: .mapRemote,
                title: String(localized: "Map Remote", bundle: RockxyLocalization.bundle),
                systemImage: "arrow.triangle.branch",
                help: String(localized: "Open Map Remote", bundle: RockxyLocalization.bundle),
                isActive: false,
                isEnabled: true
            ),
            .init(
                id: .breakpoint,
                title: String(localized: "Breakpoint", bundle: RockxyLocalization.bundle),
                systemImage: "pause.circle",
                help: String(localized: "Open Breakpoint Rules", bundle: RockxyLocalization.bundle),
                isActive: false,
                isEnabled: true
            ),
            .init(
                id: .networkConditions,
                title: String(localized: "Network Conditions", bundle: RockxyLocalization.bundle),
                systemImage: "speedometer",
                help: String(localized: "Open Network Conditions", bundle: RockxyLocalization.bundle),
                isActive: false,
                isEnabled: true
            ),
        ]

        var actions = quickTools.compactMap { kind in catalog.first { $0.id == kind } }
        if isProxyOverridden {
            actions.append(.init(
                id: .proxyOverride,
                title: String(localized: "Proxy Overridden", bundle: RockxyLocalization.bundle),
                systemImage: "checkmark.circle.fill",
                help: String(
                    localized: "Show system proxy override details. Toggle by: ⌥⌘O",
                    bundle: RockxyLocalization.bundle
                ),
                isActive: true,
                isEnabled: true
            ))
        }

        return actions
    }
}

// MARK: - FooterMutationIndicator

/// A live active-mutation indicator for the footer: shows a rule tool category
/// (Map Local, Map Remote, Breakpoints) together with its enabled-rule count.
/// Purely derived from `[ProxyRule]` plus the tool-level master switches so the
/// footer can expose active mutation state without displacing traffic.
struct FooterMutationIndicator: Identifiable, Equatable {
    // MARK: Lifecycle

    init(category: Category, count: Int) {
        id = category
        self.count = count
    }

    // MARK: Internal

    enum Category: String, CaseIterable {
        case mapLocal
        case mapRemote
        case breakpoint
        case networkCondition

        // MARK: Internal

        /// The `RuleAction.toolCategory` value that maps to this indicator.
        var toolCategory: String {
            switch self {
            case .mapLocal: "mapLocal"
            case .mapRemote: "mapRemote"
            case .breakpoint: "breakpoint"
            case .networkCondition: "networkCondition"
            }
        }

        /// The tool-window ID opened when the indicator is activated.
        var windowID: String {
            switch self {
            case .mapLocal: "mapLocal"
            case .mapRemote: "mapRemote"
            case .breakpoint: "breakpointRules"
            case .networkCondition: "networkConditions"
            }
        }

        var title: String {
            switch self {
            case .mapLocal: String(localized: "Map Local", bundle: RockxyLocalization.bundle)
            case .mapRemote: String(localized: "Map Remote", bundle: RockxyLocalization.bundle)
            case .breakpoint: String(localized: "Breakpoints", bundle: RockxyLocalization.bundle)
            case .networkCondition: String(localized: "Network Conditions", bundle: RockxyLocalization.bundle)
            }
        }

        var systemImage: String {
            switch self {
            case .mapLocal: "folder.badge.gearshape"
            case .mapRemote: "arrow.triangle.branch"
            case .breakpoint: "pause.circle"
            case .networkCondition: "tortoise"
            }
        }
    }

    let id: Category
    let count: Int

    var title: String {
        id.title
    }

    var systemImage: String {
        id.systemImage
    }

    var windowID: String {
        id.windowID
    }

    var help: String {
        switch id {
        case .mapLocal:
            if count == 1 {
                return String(localized: "1 active Map Local rule. Open Map Local.", bundle: RockxyLocalization.bundle)
            }
            return String(
                localized: "\(count) active Map Local rules. Open Map Local.",
                bundle: RockxyLocalization.bundle
            )
        case .mapRemote:
            if count == 1 {
                return String(
                    localized: "1 active Map Remote rule. Open Map Remote.",
                    bundle: RockxyLocalization.bundle
                )
            }
            return String(
                localized: "\(count) active Map Remote rules. Open Map Remote.",
                bundle: RockxyLocalization.bundle
            )
        case .breakpoint:
            if count == 1 {
                return String(
                    localized: "1 active Breakpoint rule. Open Breakpoint Rules.",
                    bundle: RockxyLocalization.bundle
                )
            }
            return String(
                localized: "\(count) active Breakpoint rules. Open Breakpoint Rules.",
                bundle: RockxyLocalization.bundle
            )
        case .networkCondition:
            return String(
                localized: "A Network Conditions profile is slowing or blocking matching traffic. Open Network Conditions.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    var accessibilityLabel: String {
        String(AttributedString(
            localized: "\(id.title), ^[\(count) active rule](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }
}

// MARK: - FooterMutationIndicatorBuilder

/// Pure builder that derives the ordered footer mutation indicators from the
/// current rule set and the three tool-level master switches. A category is
/// surfaced only when its master switch is enabled AND it has at least one
/// enabled rule. Order is always Map Local, Map Remote, then Breakpoint.
enum FooterMutationIndicatorBuilder {
    static func indicators(
        rules: [ProxyRule],
        mapLocalToolEnabled: Bool,
        mapRemoteToolEnabled: Bool,
        breakpointToolEnabled: Bool,
        networkConditionsToolEnabled: Bool = true
    )
        -> [FooterMutationIndicator]
    {
        var counts: [String: Int] = [:]
        for rule in rules where rule.isEnabled {
            counts[rule.action.toolCategory, default: 0] += 1
        }

        let toolSwitches: [FooterMutationIndicator.Category: Bool] = [
            .mapLocal: mapLocalToolEnabled,
            .mapRemote: mapRemoteToolEnabled,
            .breakpoint: breakpointToolEnabled,
            .networkCondition: networkConditionsToolEnabled,
        ]

        let order: [FooterMutationIndicator.Category] = [.mapLocal, .mapRemote, .breakpoint, .networkCondition]
        return order.compactMap { category in
            guard toolSwitches[category] == true else {
                return nil
            }
            let count = counts[category.toolCategory, default: 0]
            guard count > 0 else {
                return nil
            }
            return FooterMutationIndicator(category: category, count: count)
        }
    }
}

// MARK: - FooterToolingButton

/// Shared native launcher for the top command bar and footer. Quick Tools are product-specific,
/// so their names remain visible instead of requiring new users to learn an icon vocabulary.
/// Native button styles still own bezel, hover, pressed, focused, disabled, and active treatment.
struct FooterToolingButton: View {
    // MARK: Internal

    let descriptor: FooterActionDescriptor
    var controlSize: ControlSize = .small
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(descriptor.title, systemImage: descriptor.systemImage)
                .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 2)
        }
        .controlSize(controlSize)
        .rockxyGlassButtonStyle(prominent: descriptor.isActive)
        .disabled(!descriptor.isEnabled)
        .help(descriptor.help)
        .accessibilityLabel(descriptor.title)
        .accessibilityValue(descriptor.isActive ? String(localized: "Active", bundle: RockxyLocalization.bundle) : "")
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - FooterMutationIndicatorButton

/// Compact active-mutation chip rendered in the footer. Shows the tool category
/// plus its live enabled-rule count, and opens the matching tool window when
/// activated. The parent group chooses the titled or compact form based on the
/// horizontal space available in the existing fixed-height footer.
private struct FooterMutationIndicatorButton: View {
    // MARK: Internal

    let indicator: FooterMutationIndicator
    let showsTitle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { label }
            .controlSize(.small)
            .rockxyGlassButtonStyle()
            .tint(indicatorColor)
            .help(indicator.help)
            .accessibilityLabel(indicator.accessibilityLabel)
            .accessibilityValue(String(AttributedString(
                localized: "^[\(indicator.count) active rule](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var indicatorColor: Color {
        switch indicator.id {
        case .mapLocal,
             .mapRemote:
            Color(nsColor: .systemOrange)
        case .breakpoint:
            Color(nsColor: .systemPurple)
        case .networkCondition:
            Color(nsColor: .systemRed)
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: indicator.systemImage)
            if showsTitle {
                Text(indicator.title)
            }
            Text(CountFormatter.format(indicator.count))
                .monospacedDigit()
        }
        .font(.system(size: metrics.badgeFontSize, weight: .semibold))
        .lineLimit(1)
    }
}

// MARK: - FooterProxyOverrideButton

private struct FooterProxyOverrideButton: View {
    // MARK: Internal

    let descriptor: FooterActionDescriptor
    let proxyHost: String
    let proxyPort: Int
    let onSwitchOff: () -> Void

    var body: some View {
        FooterToolingButton(descriptor: descriptor, controlSize: .regular) {
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
    // MARK: Internal

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

            Button(String(localized: "Switch Off", bundle: RockxyLocalization.bundle)) {
                isPresented = false
                onSwitchOff()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 660, alignment: .leading)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var statusText: String {
        String(
            localized: "System Proxy is Overridden by Rockxy (IP=\(proxyHost) Port=\(String(proxyPort))) (Toggle by: ⌥⌘O)",
            bundle: RockxyLocalization.bundle
        )
    }
}

// MARK: - StatusBarRequestSummary

enum StatusBarRequestSummary {
    static func text(
        visibleCount: Int,
        availableCount: Int,
        selectedCount: Int,
        activeFilterCount: Int
    )
        -> String
    {
        if activeFilterCount > 0, visibleCount != availableCount {
            if selectedCount > 0 {
                return String(
                    localized: "\(selectedCount) selected, \(visibleCount) of \(availableCount) shown",
                    bundle: RockxyLocalization.bundle
                )
            }
            return String(AttributedString(
                localized: "\(visibleCount) of ^[\(availableCount) request](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        }
        if visibleCount == 0 {
            return String(localized: "No requests", bundle: RockxyLocalization.bundle)
        }
        if selectedCount > 0 {
            return String(
                localized: "\(selectedCount)/\(visibleCount) rows selected",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(AttributedString(
            localized: "^[\(visibleCount) request](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }
}

// MARK: - StatusBarView

/// Bottom status bar showing request counts, bandwidth stats (upload/download speed), active
/// mutation indicators, quick tools, request status, and the proxy-override control. The primary
/// Clear Session and Follow Live workflows live in the top `TrafficCommandBar`, not here.
struct StatusBarView: View {
    // MARK: Internal

    let totalCount: Int
    let selectedCount: Int
    var availableCount: Int?
    var isProxyRunning: Bool = false
    var proxyHost: String = "127.0.0.1"
    var proxyPort: Int = 9_090
    var totalDataSize: Int64 = 0
    var uploadSpeed: Int64 = 0
    var downloadSpeed: Int64 = 0
    var isProxyOverridden: Bool = false
    var isAllowListActive: Bool = false
    var isNoCachingActive: Bool = false
    var activeFilterCount: Int = 0
    var errorCount: Int = 0
    var proxyStartedAt: Date?
    var selectedRequestInfo: String?
    var sessionProvenance: SessionProvenance?
    var activeRules: [ProxyRule] = []
    var mapLocalToolEnabled: Bool = true
    var mapRemoteToolEnabled: Bool = true
    var breakpointToolEnabled: Bool = true
    var networkConditionsToolEnabled: Bool = true
    var pausedBreakpointCount: Int = 0

    var onSwitchOffProxyOverride: () -> Void = {}
    var onOpenToolWindow: (String) -> Void = { _ in }

    var body: some View {
        WorkspaceFooterBar(horizontalPadding: 12) {
            HStack(spacing: 0) {
                breakpointQueueIndicator
                quickTools
                    .layoutPriority(0)
                mutationIndicators
                Spacer(minLength: 12)
                centerStatus
                    .layoutPriority(3)
                Spacer(minLength: 12)
                rightStats
                    .layoutPriority(3)
            }
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
    @AppStorage(QuickToolsLayout.storageKey) private var quickToolsLayoutRaw = ""
    @AppStorage(QuickToolsLayout.legacyFooterStorageKey) private var legacyFooterQuickToolOrder = ""
    @State private var isCustomizingQuickTools = false

    private var statusText: String {
        StatusBarRequestSummary.text(
            visibleCount: totalCount,
            availableCount: availableCount ?? totalCount,
            selectedCount: selectedCount,
            activeFilterCount: activeFilterCount
        )
    }

    private var formattedDataSize: String {
        SizeFormatter.format(bytes: totalDataSize)
    }

    private var mutationIndicatorList: [FooterMutationIndicator] {
        FooterMutationIndicatorBuilder.indicators(
            rules: activeRules,
            mapLocalToolEnabled: mapLocalToolEnabled,
            mapRemoteToolEnabled: mapRemoteToolEnabled,
            breakpointToolEnabled: breakpointToolEnabled,
            networkConditionsToolEnabled: networkConditionsToolEnabled
        )
    }

    private var quickToolsLayout: QuickToolsLayout {
        QuickToolsLayout.resolved(
            storageRaw: quickToolsLayoutRaw,
            legacyFooterRaw: legacyFooterQuickToolOrder
        )
    }

    private var breakpointQueueSummary: String {
        String(AttributedString(
            localized: "^[\(pausedBreakpointCount) item](inflect: true) waiting",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }

    @ViewBuilder private var breakpointQueueIndicator: some View {
        if pausedBreakpointCount > 0 {
            HStack(spacing: 6) {
                Button {
                    onOpenToolWindow("breakpoints")
                } label: {
                    Label(breakpointQueueSummary, systemImage: "pause.circle.fill")
                        .font(.system(size: metrics.badgeFontSize, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .controlSize(.small)
                .rockxyGlassButtonStyle(prominent: true)
                .tint(Color(nsColor: .systemOrange))
                .help(breakpointQueueSummary)
                .accessibilityLabel(String(localized: "Breakpoint Queue", bundle: RockxyLocalization.bundle))
                .accessibilityValue(breakpointQueueSummary)

                Divider()
                    .frame(height: 12)
            }
            .padding(.trailing, 8)
            .layoutPriority(4)
        }
    }

    @ViewBuilder private var mutationIndicators: some View {
        let indicators = mutationIndicatorList
        if !indicators.isEmpty {
            HStack(spacing: 6) {
                Divider()
                    .frame(height: 12)
                ViewThatFits(in: .horizontal) {
                    mutationIndicatorRow(indicators, showsTitles: true)
                    mutationIndicatorRow(indicators, showsTitles: false)
                    mutationIndicatorMenu(indicators)
                }
            }
            .padding(.leading, 8)
            .layoutPriority(1)
        }
    }

    @ViewBuilder private var centerStatus: some View {
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
                    Text(String(AttributedString(
                        localized: "^[\(errorCount) error](inflect: true)",
                        bundle: RockxyLocalization.bundle,
                        locale: RockxyLocalization.locale
                    ).characters))
                        .font(.system(size: metrics.secondaryFontSize))
                }
                .foregroundStyle(Color(nsColor: .systemRed))
            }

            if let proxyStartedAt {
                SessionDurationView(startedAt: proxyStartedAt)
            }

            Text(String(localized: "\(formattedDataSize) total", bundle: RockxyLocalization.bundle))
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .help(String(localized: "Total captured payload bytes", bundle: RockxyLocalization.bundle))

            Text("↑ \(formattedSpeed(uploadSpeed))")
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .help(String(localized: "Captured upload throughput", bundle: RockxyLocalization.bundle))

            Text("↓ \(formattedSpeed(downloadSpeed))")
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(Color.accentColor)
                .help(String(localized: "Captured download throughput", bundle: RockxyLocalization.bundle))

            if let proxyOverride = FooterActionDescriptor.toolingActions(
                isAllowListActive: isAllowListActive,
                isProxyOverridden: isProxyOverridden,
                quickTools: []
            ).first(where: { $0.id == .proxyOverride }) {
                FooterProxyOverrideButton(
                    descriptor: proxyOverride,
                    proxyHost: proxyHost,
                    proxyPort: proxyPort,
                    onSwitchOff: onSwitchOffProxyOverride
                )
            }

            if isAllowListActive {
                statusPill(String(localized: "Allow List", bundle: RockxyLocalization.bundle), color: Color.accentColor)
            }

            if isNoCachingActive {
                statusPill(
                    String(localized: "No Cache", bundle: RockxyLocalization.bundle),
                    color: Color(nsColor: .systemOrange)
                )
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var quickTools: some View {
        let descriptors = FooterActionDescriptor.toolingActions(
            isAllowListActive: isAllowListActive,
            quickTools: quickToolsLayout.footer
        )
        ViewThatFits(in: .horizontal) {
            labeledQuickToolsRow(descriptors)
            quickToolsMenu(descriptors)
        }
    }

    private func labeledQuickToolsRow(_ descriptors: [FooterActionDescriptor]) -> some View {
        HStack(spacing: 4) {
            ForEach(descriptors) { descriptor in
                FooterToolingButton(descriptor: descriptor, controlSize: .regular) {
                    performAction(descriptor.id)
                }
            }
            Button {
                isCustomizingQuickTools.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: metrics.chromeBadgeHeight, height: metrics.chromeBadgeHeight)
            }
            .font(.system(size: metrics.secondaryFontSize, weight: .medium))
            .controlSize(.regular)
            .rockxyGlassButtonStyle()
            .help(String(localized: "Customize Quick Tools", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Customize Quick Tools", bundle: RockxyLocalization.bundle))
            .popover(isPresented: $isCustomizingQuickTools, arrowEdge: .bottom) {
                QuickToolsEditor(
                    layout: quickToolsLayout,
                    onSave: { quickToolsLayoutRaw = $0.encoded },
                    onReset: { quickToolsLayoutRaw = QuickToolsLayout.default.encoded },
                    onDone: { isCustomizingQuickTools = false }
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func quickToolsMenu(_ descriptors: [FooterActionDescriptor]) -> some View {
        Menu {
            ForEach(descriptors) { descriptor in
                Button {
                    performAction(descriptor.id)
                } label: {
                    Label(descriptor.title, systemImage: descriptor.systemImage)
                }
            }
            Divider()
            Button(String(localized: "Customize Quick Tools…", bundle: RockxyLocalization.bundle)) {
                DispatchQueue.main.async {
                    isCustomizingQuickTools = true
                }
            }
        } label: {
            Label(String(localized: "Quick Tools", bundle: RockxyLocalization.bundle), systemImage: "hammer")
                .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 2)
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .controlSize(.regular)
        .rockxyGlassButtonStyle()
        .help(String(localized: "Open Quick Tools", bundle: RockxyLocalization.bundle))
        .accessibilityLabel(String(localized: "Quick Tools", bundle: RockxyLocalization.bundle))
        .popover(isPresented: $isCustomizingQuickTools, arrowEdge: .bottom) {
            QuickToolsEditor(
                layout: quickToolsLayout,
                onSave: { quickToolsLayoutRaw = $0.encoded },
                onReset: { quickToolsLayoutRaw = QuickToolsLayout.default.encoded },
                onDone: { isCustomizingQuickTools = false }
            )
        }
    }

    private func mutationIndicatorRow(
        _ indicators: [FooterMutationIndicator],
        showsTitles: Bool
    )
        -> some View
    {
        HStack(spacing: 6) {
            ForEach(indicators) { indicator in
                FooterMutationIndicatorButton(indicator: indicator, showsTitle: showsTitles) {
                    onOpenToolWindow(indicator.windowID)
                }
            }
        }
    }

    private func mutationIndicatorMenu(_ indicators: [FooterMutationIndicator]) -> some View {
        Menu {
            ForEach(indicators) { indicator in
                Button {
                    onOpenToolWindow(indicator.windowID)
                } label: {
                    Label(
                        "\(indicator.title)  \(CountFormatter.format(indicator.count))",
                        systemImage: indicator.systemImage
                    )
                }
            }
        } label: {
            Label(
                CountFormatter.format(indicators.reduce(0) { $0 + $1.count }),
                systemImage: "bolt.horizontal.circle"
            )
                .font(.system(size: metrics.badgeFontSize, weight: .semibold))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .rockxyGlassButtonStyle()
        .tint(Color(nsColor: .systemOrange))
        .fixedSize()
        .help(String(localized: "Active mutation rules", bundle: RockxyLocalization.bundle))
        .accessibilityLabel(String(localized: "Active mutation rules", bundle: RockxyLocalization.bundle))
    }

    private func statusPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: metrics.badgeFontSize, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .rockxyChipStyle(tint: color, isActive: true)
    }

    private func formattedSpeed(_ bytesPerSecond: Int64) -> String {
        // Shares the footer row with the total captured size, so both have to come from the same
        // formatter — a hand-rolled "%.1f MB/s" also ignores the locale's decimal separator.
        "\(SizeFormatter.format(bytes: bytesPerSecond))/s"
    }

    private func performAction(_ action: FooterActionKind) {
        guard let windowID = action.toolWindowID else {
            return
        }
        onOpenToolWindow(windowID)
    }
}

// MARK: - WorkspaceFooterBar

/// Shared bottom-edge chrome for the traffic workspace and its native inspector.
/// Keeping height and separator construction in one view guarantees both panes meet on one pixel row.
struct WorkspaceFooterBar<Content: View>: View {
    // MARK: Internal

    let horizontalPadding: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        RockxyGlassEffectGroup(spacing: Theme.Glass.footerOuterHorizontalPadding) {
            content()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding)
                .frame(height: metrics.statusBarHeight)
                .rockxyGlassEffect(
                    in: RoundedRectangle(
                        cornerRadius: Theme.Glass.footerCornerRadius,
                        style: .continuous
                    )
                )
        }
        .padding(.horizontal, Theme.Glass.footerOuterHorizontalPadding)
        .padding(.vertical, Theme.Glass.footerOuterVerticalPadding)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
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
