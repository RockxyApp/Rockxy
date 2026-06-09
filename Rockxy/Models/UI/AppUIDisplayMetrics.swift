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

    var secondaryFontSize: CGFloat {
        max(9, fontSize - 1)
    }

    var badgeFontSize: CGFloat {
        max(9, fontSize - 3)
    }

    var tableRowHeight: CGFloat {
        max(24, fontSize + 16)
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
