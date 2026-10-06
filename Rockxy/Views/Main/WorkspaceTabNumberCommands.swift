import SwiftUI

// MARK: - WorkspaceTabNumberCommands

/// View ▸ Select Tab 1–8 (⌘1–⌘8) and Select Last Tab (⌘9), the tab-picking convention of
/// Safari and Finder.
struct WorkspaceTabNumberCommands: View {
    let actions: MainContentCommandActions

    var body: some View {
        Menu(String(localized: "Select Tab", bundle: RockxyLocalization.bundle)) {
            ForEach(1 ... 8, id: \.self) { number in
                Button(String(localized: "Tab \(String(number))", bundle: RockxyLocalization.bundle)) {
                    actions.selectWorkspaceTab(at: number - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                .disabled(number > actions.workspaceTabCount)
            }
            Button(String(localized: "Last Tab", bundle: RockxyLocalization.bundle)) {
                actions.selectWorkspaceTab(at: actions.workspaceTabCount - 1)
            }
            .keyboardShortcut("9", modifiers: .command)
            .disabled(actions.workspaceTabCount < 2)
        }
    }
}
