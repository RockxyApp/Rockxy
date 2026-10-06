import AppKit
import SwiftUI

// Bottom toolbar for the sidebar, providing a native filter field and an add-favorite button.
// Mirrors Xcode's navigator control bar: the add action stands apart from the expanding search field.

// MARK: - SidebarBottomBar

struct SidebarBottomBar: View {
    // MARK: Internal

    @Binding var filterText: String
    @Binding var isAddFavoritePresented: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isAddFavoritePresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: metrics.sidebarIconFontSize))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Add favorite app or domain", bundle: RockxyLocalization.bundle))
            .help(String(localized: "Add favorite app or domain", bundle: RockxyLocalization.bundle))

            NativeSidebarSearchField(
                text: $filterText,
                fontSize: metrics.sidebarNavigationFontSize
            )
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - NativeSidebarSearchField

private struct NativeSidebarSearchField: NSViewRepresentable {
    // MARK: Internal

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        // MARK: Lifecycle

        init(text: Binding<String>) {
            self.text = text
            super.init()
            focusObserver = NotificationCenter.default.addObserver(
                forName: .focusSidebarSearchField,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.focusSearchField()
                }
            }
        }

        deinit {
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
            }
        }

        // MARK: Internal

        var text: Binding<String>
        weak var searchField: NSSearchField?

        func focusSearchField() {
            guard let searchField, let window = searchField.window else {
                return
            }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(searchField)
        }

        // MARK: Private

        nonisolated(unsafe) private var focusObserver: NSObjectProtocol?

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else {
                return
            }
            text.wrappedValue = searchField.stringValue
        }
    }

    @Binding var text: String

    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = String(localized: "Filter", bundle: RockxyLocalization.bundle)
        searchField.toolTip = String(localized: "Filter sidebar items", bundle: RockxyLocalization.bundle)
        searchField.controlSize = .regular
        searchField.focusRingType = .exterior
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = context.coordinator
        context.coordinator.searchField = searchField
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchField.setAccessibilityLabel(String(localized: "Filter sidebar", bundle: RockxyLocalization.bundle))
        configure(searchField)
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
        configure(searchField)
    }

    // MARK: Private

    private func configure(_ searchField: NSSearchField) {
        searchField.font = .systemFont(ofSize: fontSize)
        guard let searchCell = searchField.cell as? NSSearchFieldCell else {
            return
        }
        searchCell.searchButtonCell?.image = NSImage(
            systemSymbolName: "line.3.horizontal.decrease.circle",
            accessibilityDescription: String(localized: "Filter", bundle: RockxyLocalization.bundle)
        )
    }
}
