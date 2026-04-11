import SwiftUI

// Presents the breakpoint window for breakpoint review and editing.

// MARK: - BreakpointWindowView

/// Standalone window for managing breakpoint-paused requests. Two-column layout:
/// left sidebar lists all paused items, right side shows the editor for the selected item.
/// Bottom bar provides Cancel / Abort 503 / Execute action buttons.
struct BreakpointWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                BreakpointSidebarView(windowModel: windowModel, manager: manager)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 260, maxHeight: .infinity)

                BreakpointEditorView(manager: manager, windowModel: windowModel)
                    .frame(minWidth: 400, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            actionBar
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private let manager = BreakpointManager.shared
    private let windowModel = BreakpointWindowModel.shared

    private var actionBar: some View {
        HStack {
            Button(String(localized: "Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            switch windowModel.selectionMode {
            case .none:
                Button(String(localized: "Abort (503)")) {}
                    .disabled(true)
                Button(String(localized: "Execute")) {}
                    .disabled(true)

            case .pausedItem:
                Button(String(localized: "Abort (503)")) {
                    guard let selectedId = manager.selectedItemId else {
                        return
                    }
                    manager.resolve(id: selectedId, decision: .abort)
                }
                .disabled(manager.selectedItemId == nil)

                Button(String(localized: "Execute")) {
                    guard let selectedId = manager.selectedItemId else {
                        return
                    }
                    manager.resolve(id: selectedId, decision: .execute)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(manager.selectedItemId == nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
