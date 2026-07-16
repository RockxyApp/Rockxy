import AppKit

// Resolves the app icon used in alerts and other AppKit surfaces.

// MARK: - AppIconProvider

@MainActor
enum AppIconProvider {
    // MARK: Internal

    static var appIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.isTemplate = false
        return icon
    }

    static func applicationIcon(named name: String, size: CGFloat) -> NSImage? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            return nil
        }

        let cacheKey = ApplicationIconCacheKey(name: normalizedName, size: Int(size.rounded()))
        if let cached = resizedApplicationIcons[cacheKey] {
            return cached
        }
        guard let source = applicationIconSource(named: normalizedName),
              let icon = source.copy() as? NSImage else
        {
            return nil
        }
        icon.size = NSSize(width: size, height: size)
        resizedApplicationIcons[cacheKey] = icon
        return icon
    }

    // MARK: Private

    private struct ApplicationIconCacheKey: Hashable {
        let name: String
        let size: Int
    }

    private static var applicationIcons: [String: NSImage] = [:]
    private static var resizedApplicationIcons: [ApplicationIconCacheKey: NSImage] = [:]
    private static var missingApplicationIconNames: Set<String> = []

    private static let bundleIDByApplicationName: [String: String] = [
        "Arc": "company.thebrowser.Browser",
        "Brave Browser": "com.brave.Browser",
        "Chrome": "com.google.Chrome",
        "Code Helper": "com.microsoft.VSCode",
        "Discord": "com.hnc.Discord",
        "Figma": "com.figma.Desktop",
        "Firefox": "org.mozilla.firefox",
        "Google Chrome": "com.google.Chrome",
        "Google Drive": "com.google.drivefs",
        "Microsoft Edge": "com.microsoft.edgemac",
        "Opera": "com.operasoftware.Opera",
        "Postman": "com.postmanlabs.mac",
        "Safari": "com.apple.Safari",
        "Slack": "com.tinyspeck.slackmacgap",
        "Spotify": "com.spotify.client",
        "Telegram": "ru.keepcoder.Telegram",
        "WhatsApp": "net.whatsapp.WhatsApp",
        "Xcode": "com.apple.dt.Xcode",
    ]

    private static func applicationIconSource(named name: String) -> NSImage? {
        guard !missingApplicationIconNames.contains(name) else {
            return nil
        }
        if let cached = applicationIcons[name] {
            return cached
        }

        if let bundleID = bundleIdentifier(for: name),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            return cacheApplicationIcon(NSWorkspace.shared.icon(forFile: appURL.path), named: name)
        }

        for runningApplication in NSWorkspace.shared.runningApplications {
            guard runningApplication.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame,
                  let icon = runningApplication.icon else
            {
                continue
            }
            return cacheApplicationIcon(icon, named: name)
        }

        for directory in ["/Applications", "/System/Applications", "/Applications/Utilities"] {
            let path = "\(directory)/\(name).app"
            guard FileManager.default.fileExists(atPath: path) else {
                continue
            }
            return cacheApplicationIcon(NSWorkspace.shared.icon(forFile: path), named: name)
        }

        missingApplicationIconNames.insert(name)
        return nil
    }

    private static func bundleIdentifier(for name: String) -> String? {
        if let directMatch = bundleIDByApplicationName[name] {
            return directMatch
        }
        if name.hasPrefix("Google Chrome Helper") {
            return bundleIDByApplicationName["Google Chrome"]
        }
        if name.hasPrefix("Code Helper") {
            return bundleIDByApplicationName["Code Helper"]
        }
        return nil
    }

    private static func cacheApplicationIcon(_ icon: NSImage, named name: String) -> NSImage {
        icon.isTemplate = false
        applicationIcons[name] = icon
        return icon
    }
}
