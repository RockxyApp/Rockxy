import Foundation

// Searchable catalog of workspace commands for the Command Palette.

// MARK: - CommandPaletteAction

/// What a palette command does. Tool windows open by scene ID; everything else
/// is dispatched to the main workspace's command actions.
enum CommandPaletteAction: Hashable {
    case openWindow(String)
    case startProxy
    case stopProxy
    case toggleRecording
    case toggleSystemProxy
    case toggleNoCaching
    case clearSession
    case clearSessionAndFilters
    case compose
    case openSession
    case saveSession
    case importHAR
    case exportHAR
    case exportCSV
    case exportRockxySession
    case exportOpenAPIYAML
    case exportOpenAPIHTML
    case toggleAdvancedFilters
    case findInCapture
    case searchAppsAndDomains
    case toggleTrafficInsights
    case toggleSplitView
    case newTab
    case showKeyboardShortcuts
}

// MARK: - CommandPaletteCommand

struct CommandPaletteCommand: Identifiable, Hashable {
    let id: String
    let title: String
    /// Menu or area the command lives in, shown as secondary text.
    let category: String
    /// Keyboard notation of the menu shortcut, when the command has one.
    let shortcut: String?
    /// Extra search terms that do not appear in the title.
    let keywords: [String]
    let action: CommandPaletteAction
}

// MARK: - CommandPaletteCatalog

enum CommandPaletteCatalog {
    // MARK: Internal

    static var commands: [CommandPaletteCommand] {
        let file = String(localized: "File", bundle: RockxyLocalization.bundle)
        let view = String(localized: "View", bundle: RockxyLocalization.bundle)
        let flow = String(localized: "Flow", bundle: RockxyLocalization.bundle)
        let tools = String(localized: "Tools", bundle: RockxyLocalization.bundle)
        let setup = String(localized: "Setup", bundle: RockxyLocalization.bundle)
        let help = String(localized: "Help", bundle: RockxyLocalization.bundle)

        return [
            command("proxy.start", "Start Proxy", tools, nil, ["capture", "record"], .startProxy),
            command("proxy.stop", "Stop Proxy", tools, "⌘.", ["capture"], .stopProxy),
            command("proxy.recording", "Pause or Resume Recording", tools, "⌥⌘R", ["capture"], .toggleRecording),
            command("proxy.system", "Toggle System Proxy", tools, "⌥⌘O", ["override", "network"], .toggleSystemProxy),
            command("session.clear", "Clear Session", flow, "⌘K", ["delete", "reset"], .clearSession),
            command(
                "session.clearAll",
                "Clear Session and Filters",
                flow,
                "⇧⌘K",
                ["delete", "reset"],
                .clearSessionAndFilters
            ),
            command("flow.compose", "Compose…", flow, "⌥⌘N", ["request", "new", "send"], .compose),
            command("file.open", "Open Session…", file, "⌘O", ["rockxysession", "load"], .openSession),
            command("file.save", "Save Session…", file, "⇧⌘S", ["rockxysession"], .saveSession),
            command("file.importHAR", "Import HAR…", file, "⇧⌘I", ["archive", "browser"], .importHAR),
            command("file.exportHAR", "Export HAR…", file, "⇧⌘E", ["archive", "share"], .exportHAR),
            command("file.exportCSV", "Export CSV…", file, nil, ["spreadsheet", "share"], .exportCSV),
            command(
                "file.exportSession",
                "Export Rockxy Session…",
                file,
                nil,
                ["rockxysession", "selected", "share"],
                .exportRockxySession
            ),
            command("file.openAPIYAML", "Export OpenAPI YAML…", file, nil, ["swagger", "spec"], .exportOpenAPIYAML),
            command("file.openAPIHTML", "Export OpenAPI HTML…", file, nil, ["swagger", "docs"], .exportOpenAPIHTML),
            command(
                "view.filters",
                "Show or Hide Advanced Filters",
                view,
                "⇧⌘F",
                ["filter", "rules"],
                .toggleAdvancedFilters
            ),
            command("view.find", "Find in Capture", view, "⌘F", ["search"], .findInCapture),
            command(
                "view.sidebarSearch",
                "Search Apps and Domains",
                view,
                "⌥⌘F",
                ["sidebar", "host"],
                .searchAppsAndDomains
            ),
            command("view.insights", "Traffic Insights", view, "⇧⌘D", ["report", "overview"], .toggleTrafficInsights),
            command("view.splitView", "Show or Hide Split View", view, nil, ["pane", "compare", "side"], .toggleSplitView),
            command("view.newTab", "New Tab", view, "⌘T", ["workspace"], .newTab),
            command(
                "tools.https",
                "HTTPS Decryption…",
                tools,
                "⌥⌘P",
                ["ssl", "proxying", "tls"],
                .openWindow("sslProxyingList")
            ),
            command("tools.mapLocal", "Map Local…", tools, "⌥⌘L", ["mock", "file"], .openWindow("mapLocal")),
            command("tools.noCaching", "Turn No Caching On or Off", tools, "⌥⌘C", ["cache", "fresh", "headers"], .toggleNoCaching),
            command("tools.mapRemote", "Map Remote…", tools, nil, ["redirect", "rewrite"], .openWindow("mapRemote")),
            command(
                "tools.breakpoints",
                "Breakpoint Rules…",
                tools,
                "⇧⌘B",
                ["pause", "intercept"],
                .openWindow("breakpointRules")
            ),
            command("tools.block", "Block List…", tools, "⌥⌘[", ["deny"], .openWindow("blockList")),
            command("tools.allow", "Allow List…", tools, "⌥⌘A", ["only"], .openWindow("allowList")),
            command("tools.headers", "Modify Headers…", tools, nil, ["cors", "rewrite"], .openWindow("modifyHeaders")),
            command(
                "tools.network",
                "Network Conditions…",
                tools,
                nil,
                ["throttle", "slow", "offline", "latency"],
                .openWindow("networkConditions")
            ),
            command(
                "tools.advancedProxy",
                "Advanced Proxy Settings",
                tools,
                nil,
                ["port", "listener", "socks", "lan", "access control", "allow devices", "block devices"],
                .openWindow("advancedProxySettings")
            ),
            command(
                "tools.reverseProxy",
                "Reverse Proxy…",
                tools,
                nil,
                ["local port", "forward", "curl", "base url"],
                .openWindow("reverseProxy")
            ),
            command(
                "tools.dnsSpoofing",
                "DNS Spoofing…",
                tools,
                nil,
                ["hosts", "resolve", "ip", "staging", "dns"],
                .openWindow("dnsSpoofing")
            ),
            command(
                "tools.tlsKeyLog",
                "TLS Key Log…",
                tools,
                nil,
                ["sslkeylogfile", "wireshark", "secrets", "pcap"],
                .openWindow("tlsKeyLog")
            ),
            command(
                "tools.scripts",
                "Script List…",
                tools,
                "⌥⌘I",
                ["javascript", "scripting"],
                .openWindow("scriptingList")
            ),
            command("tools.bypass", "Full Proxy Bypass…", tools, "⌥⌘B", ["exclude"], .openWindow("bypassProxyList")),
            command("tools.diff", "Open Diff View…", tools, "⌥⌘Y", ["compare"], .openWindow("diff")),
            command("tools.columns", "Custom Header Columns…", tools, nil, ["table"], .openWindow("customColumns")),
            command(
                "setup.automatic",
                "Automatic Setup…",
                setup,
                nil,
                ["terminal", "browser", "chrome"],
                .openWindow("automaticSetup")
            ),
            command("setup.manual", "Manual Setup…", setup, nil, ["environment", "proxy"], .openWindow("manualSetup")),
            command(
                "setup.devices",
                "Debug My App…",
                setup,
                nil,
                ["ios", "android", "simulator", "device"],
                .openWindow("developerSetupHub")
            ),
            command(
                "setup.certificate",
                "Certificate Setup…",
                setup,
                nil,
                ["root", "trust", "ca"],
                .openWindow("certificateSetup")
            ),
            command("app.settings", "Settings…", view, "⌘,", ["preferences"], .openWindow("settings")),
            command("help.shortcuts", "Keyboard Shortcuts", help, "⇧⌘/", ["keys"], .showKeyboardShortcuts),
        ]
    }

    // MARK: Private

    private static func command(
        _ id: String,
        _ title: String.LocalizationValue,
        _ category: String,
        _ shortcut: String?,
        _ keywords: [String],
        _ action: CommandPaletteAction
    )
        -> CommandPaletteCommand
    {
        CommandPaletteCommand(
            id: id,
            title: String(localized: title, bundle: RockxyLocalization.bundle),
            category: category,
            shortcut: shortcut,
            keywords: keywords,
            action: action
        )
    }
}

// MARK: - CommandPaletteMatcher

/// Fuzzy ranking: every query character must appear in order in the title (or a
/// keyword). Matches at word starts and consecutive runs score higher, so "mlo"
/// finds Map Local and "exp csv" finds Export CSV.
enum CommandPaletteMatcher {
    static func rank(_ commands: [CommandPaletteCommand], query: String) -> [CommandPaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return commands
        }
        return commands
            .enumerated()
            .compactMap { index, command -> (Int, Int, CommandPaletteCommand)? in
                let candidates = [command.title] + command.keywords + [command.category]
                let best = candidates.compactMap { score(query: trimmed, candidate: $0) }.max()
                return best.map { ($0, index, command) }
            }
            .sorted { lhs, rhs in lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 > rhs.0 }
            .map(\.2)
    }

    /// Returns a score when every non-space query character appears in order, else `nil`.
    static func score(query: String, candidate: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        let haystack = Array(candidate.lowercased())
        guard !needle.isEmpty else {
            return 0
        }
        var score = 0
        var needleIndex = 0
        var previousMatch: Int?
        for (index, character) in haystack.enumerated() where needleIndex < needle.count {
            guard character == needle[needleIndex] else {
                continue
            }
            score += 1
            if index == 0 || !haystack[index - 1].isLetter {
                score += 8
            }
            if let previousMatch, previousMatch == index - 1 {
                score += 5
            }
            previousMatch = index
            needleIndex += 1
        }
        guard needleIndex == needle.count else {
            return nil
        }
        if candidate.lowercased().hasPrefix(query.lowercased()) {
            score += 20
        }
        return score
    }
}
