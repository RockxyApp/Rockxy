import AppKit
import SwiftUI

// MARK: - AppUIDisplayMetrics

struct AppUIDisplayMetrics: Equatable {
    let settings: AppUISettings

    init(settings: AppUISettings = .default) {
        self.settings = settings
    }

    var fontSize: CGFloat {
        CGFloat(settings.fontSize)
    }

    var primaryFontSize: CGFloat {
        fontSize
    }

    var controlFontSize: CGFloat {
        max(11, fontSize - 1)
    }

    var secondaryFontSize: CGFloat {
        max(9, fontSize - 1)
    }

    var metadataFontSize: CGFloat {
        max(10, fontSize - 2)
    }

    var badgeFontSize: CGFloat {
        max(10, fontSize - 3)
    }

    var monospacedContentFontSize: CGFloat {
        fontSize
    }

    var sidebarNavigationFontSize: CGFloat {
        max(11, fontSize)
    }

    var sidebarSecondaryFontSize: CGFloat {
        max(10, fontSize - 1)
    }

    var sidebarSectionHeaderFontSize: CGFloat {
        max(10, fontSize - 2)
    }

    var sidebarBadgeFontSize: CGFloat {
        max(10, fontSize - 2)
    }

    var sidebarIconFontSize: CGFloat {
        max(12, fontSize)
    }

    var sidebarAppIconSize: CGFloat {
        max(20, min(fontSize + 7, 32))
    }

    var sidebarRowHeight: CGFloat {
        max(24, fontSize + 12)
    }

    var tableStatusDotSize: CGFloat {
        max(8, min(fontSize - 3, 12))
    }

    var tableSSLIconSize: CGFloat {
        max(10, min(fontSize - 1, 16))
    }

    var tableClientIconSize: CGFloat {
        max(14, min(fontSize + 3, 18))
    }

    var chromeFontSize: CGFloat {
        controlFontSize
    }

    var chromeSecondaryFontSize: CGFloat {
        secondaryFontSize
    }

    var chromeIconFontSize: CGFloat {
        max(11, controlFontSize)
    }

    var chromeBadgeFontSize: CGFloat {
        max(10, controlFontSize)
    }

    var chromeStatusDotSize: CGFloat {
        max(8, min(controlFontSize - 2, 14))
    }

    var chromeControlHeight: CGFloat {
        max(32, controlFontSize + 16)
    }

    var chromeBadgeHeight: CGFloat {
        max(24, controlFontSize + 11)
    }

    var workspaceTabFontSize: CGFloat {
        max(13, min(controlFontSize, 18))
    }

    var tableRowHeight: CGFloat {
        if fontSize <= 12 {
            return max(24, fontSize + 16)
        }
        if fontSize <= 13 {
            return 28
        }
        return fontSize + 16
    }

    var tableTextHeight: CGFloat {
        max(17, fontSize + 5)
    }

    var statusBarHeight: CGFloat {
        max(34, fontSize + 22)
    }

    var filterBarHeight: CGFloat {
        max(26, fontSize + 14)
    }

    var inspectorTabHeight: CGFloat {
        max(22, fontSize + 10)
    }

    var inspectorTextEditorSettings: InspectorTextEditorSettings {
        InspectorTextEditorSettings(appUI: settings)
    }

    var appKitBodyFont: NSFont {
        settings.useMonospacedFont
            ? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : .systemFont(ofSize: fontSize, weight: .regular)
    }

    var appKitMonospacedFont: NSFont {
        .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    func appKitFont(weight: NSFont.Weight = .regular, monospaced: Bool = false) -> NSFont {
        if monospaced || settings.useMonospacedFont {
            return .monospacedSystemFont(ofSize: fontSize, weight: weight)
        }
        return .systemFont(ofSize: fontSize, weight: weight)
    }

    func swiftUIFont(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced || settings.useMonospacedFont {
            return .system(size: fontSize, weight: weight, design: .monospaced)
        }
        return .system(size: fontSize, weight: weight)
    }
}

// MARK: - DeveloperSetupDisplayMetrics

struct DeveloperSetupDisplayMetrics: Equatable {
    let appMetrics: AppUIDisplayMetrics

    init(appMetrics: AppUIDisplayMetrics = AppUIDisplayMetrics()) {
        self.appMetrics = appMetrics
    }

    var titleFontSize: CGFloat {
        max(15, appMetrics.primaryFontSize + 5)
    }

    var sectionTitleFontSize: CGFloat {
        max(13, appMetrics.primaryFontSize + 1)
    }

    var bodyFontSize: CGFloat {
        appMetrics.primaryFontSize
    }

    var controlFontSize: CGFloat {
        appMetrics.controlFontSize
    }

    var secondaryFontSize: CGFloat {
        max(11, appMetrics.primaryFontSize - 1)
    }

    var metadataFontSize: CGFloat {
        appMetrics.metadataFontSize
    }

    var badgeFontSize: CGFloat {
        appMetrics.badgeFontSize
    }

    var iconFontSize: CGFloat {
        max(13, appMetrics.controlFontSize + 1)
    }

    var prominentIconFontSize: CGFloat {
        max(20, appMetrics.primaryFontSize + 9)
    }

    var snippetFontSize: CGFloat {
        appMetrics.monospacedContentFontSize
    }

    var sidebarRowHeight: CGFloat {
        max(36, appMetrics.primaryFontSize + 24)
    }

    var cardMinimumHeight: CGFloat {
        max(82, appMetrics.primaryFontSize + 68)
    }

    func font(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced || appMetrics.settings.useMonospacedFont {
            return .system(size: bodyFontSize, weight: weight, design: .monospaced)
        }
        return .system(size: bodyFontSize, weight: weight)
    }

    func secondaryFont(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced || appMetrics.settings.useMonospacedFont {
            return .system(size: secondaryFontSize, weight: weight, design: .monospaced)
        }
        return .system(size: secondaryFontSize, weight: weight)
    }
}

// MARK: - InspectorTextEditorSettings

struct InspectorTextEditorSettings: Equatable, Sendable {
    var fontSize: Int = AppUISettings.defaultFontSize
    var tabWidth: Int = AppUISettings.defaultTabWidth
    var useMonospacedFont = false
    var wordWrap = true
    var showInvisibles = false
    var showMinimap = false
    var scrollBeyondLastLine = false

    init(
        fontSize: Int = AppUISettings.defaultFontSize,
        tabWidth: Int = AppUISettings.defaultTabWidth,
        useMonospacedFont: Bool = false,
        wordWrap: Bool = true,
        showInvisibles: Bool = false,
        showMinimap: Bool = false,
        scrollBeyondLastLine: Bool = false
    ) {
        self.fontSize = AppUISettings.validFontSize(fontSize)
        self.tabWidth = AppUISettings.validTabWidth(tabWidth)
        self.useMonospacedFont = useMonospacedFont
        self.wordWrap = wordWrap
        self.showInvisibles = showInvisibles
        self.showMinimap = showMinimap
        self.scrollBeyondLastLine = scrollBeyondLastLine
    }

    init(appUI: AppUISettings) {
        self.init(
            fontSize: appUI.fontSize,
            tabWidth: appUI.tabWidth,
            useMonospacedFont: appUI.useMonospacedFont,
            wordWrap: appUI.bodyWordWrap,
            showInvisibles: appUI.bodyShowInvisibles,
            showMinimap: appUI.bodyShowMinimap,
            scrollBeyondLastLine: appUI.bodyScrollBeyondLastLine
        )
    }

    var cgFontSize: CGFloat {
        CGFloat(fontSize)
    }

    var appKitFont: NSFont {
        useMonospacedFont
            ? .monospacedSystemFont(ofSize: cgFontSize, weight: .regular)
            : .systemFont(ofSize: cgFontSize, weight: .regular)
    }

    var tabInterval: CGFloat {
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: appKitFont]).width
        return max(1, spaceWidth * CGFloat(tabWidth))
    }
}

// MARK: - AppUIDisplayMetricsKey

private struct AppUIDisplayMetricsKey: EnvironmentKey {
    static let defaultValue = AppUIDisplayMetrics()
}

extension EnvironmentValues {
    var appUIDisplayMetrics: AppUIDisplayMetrics {
        get { self[AppUIDisplayMetricsKey.self] }
        set { self[AppUIDisplayMetricsKey.self] = newValue }
    }
}

extension View {
    func appUIDisplayMetrics(_ metrics: AppUIDisplayMetrics) -> some View {
        environment(\.appUIDisplayMetrics, metrics)
    }
}

// MARK: - AppUIDisplayMetricsProvider

struct AppUIDisplayMetricsProvider<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .appUIDisplayMetrics(AppUIDisplayMetrics(settings: settingsManager.appUI))
    }

    private let settingsManager = AppSettingsManager.shared
}
