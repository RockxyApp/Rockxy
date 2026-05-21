import Foundation

struct KeyboardShortcutSection: Identifiable, Equatable {
    let id: String
    let title: String
    let shortcuts: [KeyboardShortcutReference]
}

struct KeyboardShortcutReference: Identifiable, Equatable {
    let id: String
    let window: String
    let action: String
    let shortcut: String
    let context: String
    let menu: String?
    let note: String?

    var searchableText: String {
        [window, action, shortcut, context, menu, note]
            .compactMap(\.self)
            .joined(separator: " ")
            .lowercased()
    }
}

enum KeyboardShortcutCatalog {
    static let sections: [KeyboardShortcutSection] = [
        KeyboardShortcutSection(id: "universal", title: "Universal", shortcuts: [
            row("universal.new", "Current Window", "New rule, template, script, or item in the active window", "⌘N", "Active list or editor", "File", nil),
            row("universal.newFolder", "Current Window", "New Folder where folders are supported", "⇧⌘N", "Rule and script lists that support folders", "File", nil),
            row(
                "universal.default",
                "Current Window",
                "Primary action: Add, Save, Send, or Execute",
                "⌘↩",
                "Primary action in editors, Compose, and Breakpoint Queue",
                nil,
                nil
            ),
            row(
                "universal.cancel",
                "Current Window",
                "Cancel sheets and modal editors; close the Breakpoint Queue without resolving the selected item",
                "Esc",
                "Sheets and modal editors",
                nil,
                nil
            ),
            row("universal.delete", "Current Window", "Delete the selected item", "⌘⌫", "Focused list selection", "Edit", nil),
            row("universal.duplicate", "Current Window", "Duplicate the selected item", "⌘D", "Focused list selection", "Edit", nil),
            row(
                "universal.toggle",
                "Current Window",
                "Toggle the enabled state of the selected rule or script when the list has focus",
                "↵ / Space",
                "Focused rule or script list",
                nil,
                nil
            ),
            row("universal.filter", "Current Window", "Focus the filter or search field", "⌘F", "Focused window or list", "Edit", nil),
            row("universal.close", "Current Window", "Close the current window", "⌘W", "Key window", "File", nil),
            row("universal.settings", "App", "Settings", "⌘,", "App menu", "App", nil),
            row(
                "universal.editing",
                "Text Fields",
                "Copy, Paste, Cut, and Select All in text fields and standard editable controls",
                "⌘C / ⌘V / ⌘X / ⌘A",
                "Focused text field",
                "Edit",
                nil
            ),
        ]),
        KeyboardShortcutSection(id: "main", title: "Main Capture", shortcuts: [
            row("main.clear", "Main Capture", "Clear capture", "⌘K", "Main capture window", "Flow", nil),
            row("main.clearAll", "Main Capture", "Clear capture and filters", "⇧⌘K", "Main capture window", "Flow", nil),
            row("main.pause", "Main Capture", "Pause or resume capture", "⌘P", "Main capture window", "Tools", nil),
            row("main.search", "Main Capture", "Focus the search bar", "⌘L", "Main capture search field", "Edit", nil),
            row("main.first", "Main Capture", "Jump to the first or last captured row", "⌘↑", "Request table selection", "View", nil),
            row("main.last", "Main Capture", "Jump to the first or last captured row", "⌘↓", "Request table selection", "View", nil),
            row("main.move", "Main Capture", "Move row selection", "↑ / ↓", "Focused request table", nil, "Native table behavior."),
            row("main.editRepeat", "Main Capture", "Edit and Repeat the selected request", "⌘E", "Selected request", "Flow", nil),
            row("main.replay", "Main Capture", "Replay the selected request", "⌘R", "Selected request", "Flow", nil),
            row("main.breakpoint", "Main Capture", "Add a Breakpoint rule for the selected request URL", "⌘B", "Selected request", "Tools", nil),
            row("main.tabs", "Main Capture", "Switch workspace tabs", "⇧⌘[ / ⇧⌘]", "Main capture window", "View", nil),
        ]),
        KeyboardShortcutSection(id: "compose", title: "Compose", shortcuts: [
            row("compose.send", "Compose", "Send", "⌘↩", "Compose window", nil, nil),
            row("compose.url", "Compose", "Focus the URL field", "⌘L", "Compose URL field", nil, nil),
            row("compose.template", "Compose", "Open Template menu", "⌘T", "Compose footer", nil, nil),
            row("compose.history", "Compose", "Open History menu", "⌘Y", "Compose footer", nil, "⌘H is reserved by macOS for Hide App."),
            row("compose.reset", "Compose", "Reset to a fresh request", "⌘0", "Compose window", nil, nil),
        ]),
        KeyboardShortcutSection(id: "breakpointQueue", title: "Breakpoint Queue", shortcuts: [
            row("breakpoint.execute", "Breakpoint Queue", "Execute the selected paused item", "⌘↩", "Selected paused item", nil, nil),
            row("breakpoint.abort", "Breakpoint Queue", "Abort the selected paused item", "⌘.", "Selected paused item", nil, nil),
            row("breakpoint.close", "Breakpoint Queue", "Close the queue window; queued items remain paused", "Esc", "Breakpoint Queue window", nil, "Paused item stays queued."),
            row("breakpoint.previous", "Breakpoint Queue", "Move to the previous or next queued item", "⌘[", "Breakpoint Queue selection", nil, nil),
            row("breakpoint.next", "Breakpoint Queue", "Move to the previous or next queued item", "⌘]", "Breakpoint Queue selection", nil, nil),
        ]),
        KeyboardShortcutSection(id: "rules", title: "Rules Windows", shortcuts: [
            row("rules.new", "Rules Windows", "New rule", "⌘N", "Focused rules window", nil, nil),
            row("rules.newFolder", "Rules Windows", "New folder", "⇧⌘N", "Map Local and Scripting lists", nil, "Unavailable in rule windows without folder support."),
            row("rules.edit", "Rules Windows", "Edit selected rule", "⌘E", "Focused rules list", nil, nil),
            row("rules.duplicate", "Rules Windows", "Duplicate selected rule", "⌘D", "Focused rules list", nil, nil),
            row("rules.delete", "Rules Windows", "Delete selected rule", "⌘⌫", "Focused rules list", nil, nil),
            row("rules.toggle", "Rules Windows", "Toggle selected rule enabled state", "↵ / Space", "Focused rules list", nil, nil),
            row("rules.filter", "Rules Windows", "Filter rules", "⌘F", "Focused rules window", nil, nil),
            row("rules.templates", "Breakpoint Rules", "Open Breakpoint Templates from Breakpoint Rules", "⌘T", "Breakpoint Rules window", nil, nil),
        ]),
        KeyboardShortcutSection(id: "settings", title: "Settings", shortcuts: [
            row("settings.ssl.newApp", "SSL Proxying Settings", "Add app rule", "⌘N", "SSL Proxying list", nil, nil),
            row("settings.ssl.newDomain", "SSL Proxying Settings", "Add domain rule", "⇧⌘N", "SSL Proxying list", nil, nil),
            row("settings.ssl.edit", "SSL Proxying Settings", "Edit selected SSL proxying rule", "⌘E", "SSL Proxying list", nil, nil),
            row("settings.ssl.delete", "SSL Proxying Settings", "Delete selected SSL proxying rule", "⌘⌫", "SSL Proxying list", nil, nil),
            row("settings.ssl.toggle", "SSL Proxying Settings", "Toggle selected SSL proxying rule", "↵ / Space", "SSL Proxying list", nil, nil),
            row("settings.ssl.filter", "SSL Proxying Settings", "Filter SSL proxying rules", "⌘F", "SSL Proxying list", nil, nil),
        ]),
        KeyboardShortcutSection(id: "scriptEditor", title: "Script Editor", shortcuts: [
            row("script.save", "Script Editor", "Save and activate script", "⌘S", "Script Editor window", nil, nil),
            row("script.validate", "Script Editor", "Validate the matching rule against the sample URL", "⌘R", "Script Editor window", nil, nil),
            row("script.console", "Script Editor", "Toggle Console panel", "⇧⌘C", "Script Editor window", nil, nil),
            row("script.comment", "Script Editor", "Toggle line comment in the code editor", "⌘/", "Focused code editor", nil, nil),
            row("script.indent", "Script Editor", "Outdent or indent the selection in the code editor", "⌘] / ⌘[", "Focused code editor", nil, nil),
        ]),
        KeyboardShortcutSection(id: "templates", title: "Templates", shortcuts: [
            row("templates.new", "Breakpoint Templates", "New template of the selected kind", "⌘N", "Breakpoint Template Manager", nil, nil),
            row("templates.newOpposite", "Breakpoint Templates", "New template of the opposite kind", "⇧⌘N", "Breakpoint Template Manager", nil, nil),
            row("templates.duplicate", "Breakpoint Templates", "Duplicate selected template", "⌘D", "Breakpoint Template Manager", nil, nil),
            row("templates.delete", "Breakpoint Templates", "Delete selected template", "⌘⌫", "Breakpoint Template Manager", nil, nil),
        ]),
        KeyboardShortcutSection(id: "help", title: "Help", shortcuts: [
            row("help.shortcuts", "Menu Bar", "Open Help → Keyboard Shortcuts", "⌘?", "Help menu", "Help", nil),
        ]),
    ]

    static var allShortcuts: [KeyboardShortcutReference] {
        sections.flatMap(\.shortcuts)
    }

    static func filtered(by query: String) -> [KeyboardShortcutSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return sections
        }
        return sections.compactMap { section in
            let matches = section.shortcuts.filter { $0.searchableText.contains(trimmed) }
            guard !matches.isEmpty else {
                return nil
            }
            return KeyboardShortcutSection(id: section.id, title: section.title, shortcuts: matches)
        }
    }

    private static func row(
        _ id: String,
        _ window: String,
        _ action: String,
        _ shortcut: String,
        _ context: String,
        _ menu: String?,
        _ note: String?
    ) -> KeyboardShortcutReference {
        KeyboardShortcutReference(
            id: id,
            window: window,
            action: action,
            shortcut: shortcut,
            context: context,
            menu: menu,
            note: note
        )
    }
}
