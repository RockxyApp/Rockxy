import AppKit
import SwiftUI

// Defines the app-wide theme tokens and appearance helpers used across Rockxy.

// MARK: - AppThemeApplier

/// Applies the user's theme preference (system / light / dark) to all app windows.
@MainActor
enum AppThemeApplier {
    static func apply(_ theme: String) {
        let appearance: NSAppearance? = switch theme {
        case "light":
            NSAppearance(named: .aqua)
        case "dark":
            NSAppearance(named: .darkAqua)
        default:
            nil
        }

        NSApp.appearance = appearance
        refreshExistingWindowChrome(with: appearance)

        // SwiftUI owns the views hosted by NSToolbarItems and can finish its update after this
        // settings action returns. Refresh once more on the next main-loop turn so an existing
        // Light toolbar cannot survive inside a window whose content has already changed to Dark
        // (or vice versa).
        DispatchQueue.main.async {
            refreshExistingWindowChrome(with: appearance)
        }
    }

    /// Rebinds AppKit chrome that is hosted outside the SwiftUI content hierarchy. SwiftUI toolbar
    /// hosts can retain their previous explicit appearance even after the window changes theme, so
    /// app-selected themes must be applied directly to every hosted toolbar view. `nil` keeps the
    /// System setting live and inherited.
    static func refreshWindowChrome(_ window: NSWindow, appearance: NSAppearance?) {
        window.appearance = appearance
        window.contentView?.appearance = nil
        window.contentView?.needsLayout = true
        window.contentView?.needsDisplay = true

        guard let toolbar = window.toolbar else {
            return
        }

        let itemViews = (toolbar.items + (toolbar.visibleItems ?? [])).compactMap(\.view)
        for view in itemViews {
            refreshToolbarView(view, appearance: appearance)
        }
        toolbar.validateVisibleItems()
    }

    private static func refreshExistingWindowChrome(with appearance: NSAppearance?) {
        for window in NSApp.windows {
            refreshWindowChrome(window, appearance: appearance)
        }
    }

    static func refreshToolbarView(_ view: NSView, appearance: NSAppearance?) {
        view.appearance = appearance
        view.needsLayout = true
        view.needsDisplay = true
        for subview in view.subviews {
            refreshToolbarView(subview, appearance: appearance)
        }
    }
}

// MARK: - AppTheme SwiftUI Presentation

extension AppTheme {
    /// Resolves the app override without consulting the process-wide system setting from a
    /// toolbar host. SwiftUI may create that host outside the scene's presentation boundary, so
    /// the resolved scheme is injected as a normal environment value by every scene provider.
    func resolvedColorScheme(inheriting colorScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .system:
            colorScheme
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

// MARK: - Theme

/// Centralized color and styling constants for the Rockxy UI.
/// Organized by UI region (StatusCode, Method, Sidebar, Table, Inspector, etc.)
/// to keep color definitions consistent across views.
enum Theme {
    /// HTTP status code badge colors: 2xx green, 3xx blue, 4xx orange, 5xx red.
    enum StatusCode {
        static let success = Color.green
        static let redirect = Color.blue
        static let clientError = Color.orange
        static let serverError = Color.red
    }

    /// HTTP method badge colors matching common developer tool conventions.
    enum Method {
        static let get = Color.blue
        static let post = Color.green
        static let put = Color.orange
        static let patch = Color.yellow
        static let delete = Color.red
    }

    enum LogLevel {
        static let debug = Color.gray
        static let info = Color.blue
        static let notice = Color.cyan
        static let warning = Color.orange
        static let error = Color.red
        static let fault = Color.purple
    }

    // MARK: - Sidebar

    /// Sidebar section header colors and app icon gradient palette.
    enum Sidebar {
        static let favoritesHeader = Color(red: 0.77, green: 0.47, blue: 0.23) // #C4793A
        static let sectionHeader = Color.gray

        static let appIconGradients: [(Color, Color)] = [
            (.blue, .cyan),
            (.purple, .pink),
            (.orange, .yellow),
            (.green, .mint),
            (.red, .orange),
            (.indigo, .purple),
            (.teal, .green),
            (.brown, .orange),
        ]

        /// Deterministically maps an app name to a gradient pair using hash-based indexing.
        static func appIconGradient(for name: String) -> (Color, Color) {
            let index = abs(name.hashValue) % appIconGradients.count
            return appIconGradients[index]
        }
    }

    // MARK: - Table

    enum Table {
        static let alternatingRowEven = Color(nsColor: .controlBackgroundColor)
        static let alternatingRowOdd = Color(nsColor: .alternatingContentBackgroundColors[1])
        static let selectionHighlight = Color.accentColor.opacity(0.2)
        static let headerBackground = Color(nsColor: .windowBackgroundColor)
        static let headerBorder = Color(nsColor: .separatorColor)
    }

    // MARK: - JSON Syntax

    enum DropTarget {
        static let cornerRadius: CGFloat = 10
        static let inset: CGFloat = 8
        static let lineWidth: CGFloat = 2
        static let dash: [CGFloat] = [8, 5]
        static let fillOpacity = 0.08
    }

    enum JSON {
        static let key = Color(nsColor: keyNS)
        static let string = Color(nsColor: stringNS)
        static let number = Color(nsColor: numberNS)
        static let bool = Color(nsColor: boolNS)
        static let null = Color(nsColor: nullNS)
        static let bracket = Color(nsColor: bracketNS)

        static let keyNS = NSColor.systemRed
        static let stringNS = NSColor.systemBlue
        static let numberNS = NSColor.systemGreen
        static let boolNS = NSColor.systemPurple
        static let nullNS = NSColor.secondaryLabelColor
        static let bracketNS = NSColor.systemGreen
        static let headerNS = NSColor.systemBlue
        static let statusNS = NSColor.systemRed
    }

    // MARK: - Filter Pills

    enum FilterPill {
        static let activeBackground = Color.accentColor.opacity(0.15)
        static let activeForeground = Color.primary
        static let inactiveBackground = Color.clear
        static let inactiveForeground = Color.secondary
    }

    // MARK: - Liquid Glass

    /// Shared geometry and fallback treatments for the top-level functional layer.
    /// Keep these values centralized so custom glass surfaces remain visually related
    /// and their macOS 14/accessibility fallbacks don't drift apart.
    enum Glass {
        static let shelfCornerRadius: CGFloat = 16
        static let shelfInset: CGFloat = 6
        static let shelfOuterPadding: CGFloat = 10
        static let shelfSectionSpacing: CGFloat = 7
        static let footerCornerRadius: CGFloat = 13
        static let footerOuterHorizontalPadding: CGFloat = 8
        static let footerOuterVerticalPadding: CGFloat = 6
        static let functionalBarCornerRadius: CGFloat = 12
        static let functionalBarHorizontalInset: CGFloat = 7
        static let functionalBarVerticalInset: CGFloat = 5
        static let fallbackTintOpacity = 0.15
        static let fallbackStrokeOpacity = 0.28
        static let neutralStrokeOpacity = 0.10
        static let activeStrokeOpacity = 0.55
        static let activeFillOpacity = 0.13
        static let neutralFillOpacity = 0.06
        static let hoverFillOpacity = 0.10
        static let semanticFillOpacity = 0.14
        static let semanticHoverFillOpacity = 0.20
        static let semanticStrokeOpacity = 0.34
        static let semanticHoverStrokeOpacity = 0.52
        static let ambientAccentOpacity = 0.20
        static let ambientSecondaryOpacity = 0.08
        static let separatorOpacity = 0.55
        static let toastCornerRadius: CGFloat = 14
        static let toastHorizontalPadding: CGFloat = 16
        static let toastVerticalPadding: CGFloat = 10
    }

    // MARK: - Status Bar

    enum StatusBar {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let border = Color(nsColor: .separatorColor)
        static let text = Color.secondary
    }

    // MARK: - Inspector

    enum Inspector {
        static let urlBarBackground = Color(nsColor: .controlBackgroundColor)
        static let tabActive = Color.primary
        static let tabInactive = Color.secondary
        static let matchHighlight = Color(nsColor: matchHighlightNS)
        static let matchHighlightText = Color(nsColor: matchHighlightTextNS)

        static let matchHighlightNS = NSColor.systemYellow.withAlphaComponent(0.36)
        static let matchHighlightTextNS = NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return bestMatch == .darkAqua
                ? NSColor(calibratedWhite: 1.0, alpha: 1.0)
                : NSColor(calibratedWhite: 0.0, alpha: 1.0)
        }
    }

    // MARK: - Plugin

    enum Plugin {
        static let scriptBadge = Color.green
        static let inspectorBadge = Color.blue
        static let exporterBadge = Color.orange
        static let detectorBadge = Color.purple
        static let capabilityBadge = Color(nsColor: .tertiaryLabelColor)
        static let statusActive = Color.green
        static let statusDisabled = Color.gray
        static let statusError = Color.red

        static func badgeColor(for type: PluginType) -> Color {
            switch type {
            case .script:
                scriptBadge
            case .inspector:
                inspectorBadge
            case .exporter:
                exporterBadge
            case .detector:
                detectorBadge
            }
        }

        static func sfSymbol(for type: PluginType) -> String {
            switch type {
            case .script:
                "scroll"
            case .inspector:
                "eye"
            case .exporter:
                "square.and.arrow.up"
            case .detector:
                "sensor"
            }
        }
    }

    // MARK: - Timing Phase Colors

    enum Timing {
        static let dns = Color.cyan
        static let tcp = Color.green
        static let tls = Color.purple
        static let ttfb = Color.orange
        static let transfer = Color.blue
    }

    // MARK: - Traffic Insights

    /// Chart and breakdown colors for the Traffic Insights report. Series colors follow the
    /// entity they represent (a protocol keeps its hue no matter how many others are visible),
    /// and status classes reuse the request-list status palette so both surfaces agree.
    enum Insights {
        static let received = Color.blue
        static let sent = Color.teal
        static let latencyMedian = Color.indigo
        static let latencyTail = Color.orange
        static let neutralBar = Color(nsColor: .quaternaryLabelColor)
        static let cardBackground = Color(nsColor: .controlBackgroundColor)
        static let cardStroke = Color(nsColor: .separatorColor)
        static let findingInfo = Color.blue
        static let findingNotice = Color.orange
        static let findingWarning = Color.red

        static let cardCornerRadius: CGFloat = 12
        static let cardPadding: CGFloat = 14
        static let cardSpacing: CGFloat = 12
        static let chartHeight: CGFloat = 200
        /// Report row layout: minimum widths decide how many cards share a row, so every row
        /// fills the workspace and cards wrap instead of squeezing.
        static let tileMinimumWidth: CGFloat = 168
        static let breakdownMinimumWidth: CGFloat = 210
        static let listMinimumWidth: CGFloat = 400
        static let protocolsCardWidth: CGFloat = 400
        static let timelineMinimumWidth: CGFloat = 440
        static let rankBarHeight: CGFloat = 3
        static let donutInnerRadiusRatio: CGFloat = 0.64

        /// Fixed hue order for protocol shares. Never cycled or re-assigned by rank.
        static func protocolColor(_ kind: TrafficInsightsProtocol) -> Color {
            switch kind {
            case .https: .blue
            case .http: .orange
            case .tunneled: Color(nsColor: .systemGray)
            case .webSocket: .cyan
            case .graphQL: .pink
            case .grpc: .green
            case .aiAPI: .purple
            case .web3RPC: .mint
            }
        }

        static func statusClassColor(_ statusClass: TrafficInsightsStatusClass) -> Color {
            switch statusClass {
            case .success: Theme.StatusCode.success
            case .redirect: Theme.StatusCode.redirect
            case .clientError: Theme.StatusCode.clientError
            case .serverError: Theme.StatusCode.serverError
            case .failed: .red
            case .blocked: .gray
            case .pending: Color(nsColor: .tertiaryLabelColor)
            case .other: Color(nsColor: .secondaryLabelColor)
            }
        }
    }

    // MARK: - Highlight Colors

    enum Highlight {
        static let red = Color(nsColor: .systemRed)
        static let orange = Color(nsColor: .systemOrange)
        static let yellow = Color(nsColor: .systemYellow)
        static let green = Color(nsColor: .systemGreen)
        static let blue = Color(nsColor: .systemBlue)
        static let purple = Color(nsColor: .systemPurple)

        static let redNS: NSColor = .systemRed
        static let orangeNS: NSColor = .systemOrange
        static let yellowNS: NSColor = .systemYellow
        static let greenNS: NSColor = .systemGreen
        static let blueNS: NSColor = .systemBlue
        static let purpleNS: NSColor = .systemPurple
    }

    // MARK: - Layout Tokens

    enum Layout {
        static let compactRowHeight: CGFloat = 22
        static let standardRowHeight: CGFloat = 28
        static let toolbarHeight: CGFloat = 38
        static let sidebarMinWidth: CGFloat = 200
        static let inspectorMinWidth: CGFloat = 300
        static let intercellSpacingH: CGFloat = 4
        static let intercellSpacingV: CGFloat = 0
        static let contentPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = 12
        static let controlSpacing: CGFloat = 6
        static let iconSize: CGFloat = 14
        static let badgeCornerRadius: CGFloat = 4
        static let windowCornerRadius: CGFloat = 10
    }

    // MARK: - Typography Tokens

    enum Typography {
        enum AppKit {
            static let tableBody: NSFont = .systemFont(ofSize: 12)
            static let tableHeader: NSFont = .systemFont(ofSize: 11, weight: .medium)
            static let monoData: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
            static let sectionTitle: NSFont = .systemFont(ofSize: 13, weight: .semibold)
            static let caption: NSFont = .systemFont(ofSize: 10)
        }

        static let tableBody = Font.system(size: 12)
        static let tableHeader = Font.system(size: 11, weight: .medium)
        static let monoData = Font.system(size: 11, design: .monospaced)
        static let sectionTitle = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 10)
        static let badge = Font.system(size: 9, weight: .medium)
    }
}
