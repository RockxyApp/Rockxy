import SwiftUI

// Renders the breakpoint sidebar interface for breakpoint review and editing.

// MARK: - BreakpointSidebarView

/// Left panel of the Breakpoints window showing breakpoint rules and paused items.
/// Two sections: Rules (breakpoint-type rules) and Paused (items awaiting user decision).
struct BreakpointSidebarView: View {
    let windowModel: BreakpointWindowModel
    let manager: BreakpointManager

    var body: some View {
        VStack(spacing: 0) {
            if manager.pausedItems.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "pause.circle")
                        .font(.title2).foregroundStyle(.secondary)
                    Text(String(localized: "No paused items."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(String(localized: "Manage breakpoint rules from Tools → Breakpoint Rules."))
                        .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(header: Text("Paused (\(manager.pausedItems.count))")) {
                        ForEach(manager.pausedItems) { item in
                            BreakpointQueueRow(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { windowModel.selectPausedItem(item.id) }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
