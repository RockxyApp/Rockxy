import AppKit
import SwiftUI

// Defines the app-wide theme tokens and appearance helpers used across Rockxy.

// MARK: - AppThemeApplier

/// Applies the user's theme preference (system / light / dark) to all app windows.
enum AppThemeApplier {
    static func apply(_ theme: String) {
        switch theme {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
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

    enum JSON {
        static let key = Color.primary
        static let string = Color(red: 0.76, green: 0.24, blue: 0.16)
        static let number = Color.blue
        static let bool = Color.orange
        static let null = Color.gray
        static let bracket = Color.secondary
    }

    // MARK: - Filter Pills

    enum FilterPill {
        static let activeBackground = Color.accentColor.opacity(0.15)
        static let activeForeground = Color.accentColor
        static let inactiveBackground = Color.clear
        static let inactiveForeground = Color.secondary
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
