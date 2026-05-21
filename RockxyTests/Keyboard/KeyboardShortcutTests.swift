import Foundation
@testable import Rockxy
import Testing

@Suite("Keyboard shortcuts")
struct KeyboardShortcutTests {
    @Test("KS convention row is documented", arguments: KeyboardShortcutCatalog.allShortcuts)
    func conventionRowIsDocumented(shortcut: KeyboardShortcutReference) throws {
        let reference = try Self.documentation(named: "keyboard-shortcuts.md")
        #expect(Self.shortcutIsDocumented(shortcut.shortcut, in: reference))
        #expect(reference.localizedCaseInsensitiveContains(shortcut.action))
    }

    @Test("KS_MENU_01 discoverable menu shortcuts are listed with menu locations")
    func menuShortcutsHaveMenuLocation() {
        let menuBacked = KeyboardShortcutCatalog.allShortcuts.filter { $0.menu != nil }
        #expect(!menuBacked.isEmpty)
        #expect(menuBacked.allSatisfy { $0.menu?.isEmpty == false })
    }

    @Test("KS_CONFLICT_01 no duplicate shortcut in the same documented context")
    func noDuplicateShortcutInSameContext() {
        let grouped = Dictionary(grouping: KeyboardShortcutCatalog.allShortcuts) { shortcut in
            "\(shortcut.window)|\(shortcut.context)|\(shortcut.shortcut)"
        }
        let duplicates = grouped.filter { _, rows in rows.count > 1 }
        #expect(duplicates.isEmpty)
    }

    @Test("KS_FOCUS_01 rules lists document immediate toggle focus")
    func rulesListToggleFocusIsDocumented() throws {
        let reference = try Self.documentation(named: "keyboard-shortcuts.md")
        #expect(reference.contains("`↵` / `Space`"))
        #expect(reference.localizedCaseInsensitiveContains("list has focus"))
    }

    @Test("KS_FOCUS_02 Compose documents URL autofocus and focus shortcut")
    func composeURLFocusIsDocumented() throws {
        let reference = try Self.documentation(named: "keyboard-shortcuts.md")
        #expect(reference.contains("Focus the URL field"))
        #expect(reference.contains("`⌘L`"))
    }

    @Test("KS_FOCUS_03 Breakpoint Queue documents execute without an extra click")
    func breakpointQueueExecuteFocusIsDocumented() throws {
        let reference = try Self.documentation(named: "keyboard-shortcuts.md")
        #expect(reference.contains("Execute the selected paused item"))
        #expect(reference.contains("`⌘↩`"))
    }

    @Test("Help sheet is backed by the same shortcut catalog")
    func helpSheetUsesCatalog() {
        let allRows = KeyboardShortcutCatalog.allShortcuts
        #expect(allRows.count >= 40)
        #expect(KeyboardShortcutCatalog.filtered(by: "compose").contains { $0.title == "Compose" })
        #expect(KeyboardShortcutCatalog.filtered(by: "breakpoint").contains { $0.title == "Breakpoint Queue" })
    }

    private static func documentation(named name: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("docs").appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func shortcutIsDocumented(_ shortcut: String, in reference: String) -> Bool {
        let parts = shortcut.components(separatedBy: " / ")
        return parts.allSatisfy { reference.contains("`\($0)`") }
    }
}
