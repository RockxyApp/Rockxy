import AppKit
@testable import Rockxy
import SwiftUI
import Testing

// MARK: - AdvancedFilterBarKeyboardTests

/// The bar advertises "Hide: Esc" and opens with the value field focused, so Escape must hide it
/// from inside that field, where the text field editor sees the key first.
@MainActor
@Suite(.serialized)
struct AdvancedFilterBarKeyboardTests {
    @Test("Escape in the focused value field hides the bar")
    func escapeInValueFieldHides() async throws {
        var hideCount = 0
        let suite = "AdvancedFilterBarKeyboardTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FilterPresetStore(userDefaults: defaults, storageKey: "presets")
        let bar = AdvancedFilterBar(
            rules: .constant([FilterRule(field: .statusCode, filterOperator: .is, value: "401")]),
            presetStore: store,
            onHide: { hideCount += 1 }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 110),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: bar)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        // The bar focuses its last value field when it appears; a test window is not key, so
        // put the field editor there directly, as a click in the field would.
        try await Task.sleep(for: .milliseconds(200))
        let field = try #require(Self.firstTextField(in: window.contentView))
        window.makeFirstResponder(field)
        #expect(window.firstResponder is NSTextView, "the value field should hold focus")

        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
        window.sendEvent(escape)
        try await Task.sleep(for: .milliseconds(100))

        #expect(hideCount == 1)
    }

    @Test("Escape in the Command Palette search field closes the palette")
    func escapeClosesCommandPalette() async throws {
        let presentation = PalettePresentation()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: PaletteHost(presentation: presentation))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        for _ in 0 ..< 40 where window.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        let sheet = try #require(window.attachedSheet)
        let field = try #require(Self.firstTextField(in: sheet.contentView))
        sheet.makeFirstResponder(field)
        #expect(sheet.firstResponder is NSTextView, "the search field should hold focus")

        try sheet.sendEvent(Self.escapeEvent(windowNumber: sheet.windowNumber))
        for _ in 0 ..< 40 where presentation.isPresented {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(!presentation.isPresented)
    }

    private static func escapeEvent(windowNumber: Int) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
    }

    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else {
            return nil
        }
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        for subview in view.subviews {
            if let field = firstTextField(in: subview) {
                return field
            }
        }
        return nil
    }
}

// MARK: - PalettePresentation

@MainActor
@Observable
private final class PalettePresentation {
    var isPresented = true
}

// MARK: - PaletteHost

private struct PaletteHost: View {
    @Bindable var presentation: PalettePresentation

    var body: some View {
        Color.clear
            .frame(width: 800, height: 600)
            .sheet(isPresented: $presentation.isPresented) {
                CommandPaletteView(commands: CommandPaletteCatalog.commands) { _ in }
            }
    }
}
