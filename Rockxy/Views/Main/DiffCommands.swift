import SwiftUI

// The Diff menu: open the workspace, compare two selected rows, or assemble a pair one side at a time.

// MARK: - DiffCommands

struct DiffCommands: Commands {
    // MARK: Internal

    let proxyActions: MainContentCommandActions

    var body: some Commands {
        CommandMenu(String(localized: "Diff", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Open Diff View…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "diff")
            }
            .keyboardShortcut("y", modifiers: [.command, .option])

            Divider()

            Button(String(localized: "Compare Selected", bundle: RockxyLocalization.bundle)) {
                proxyActions.compareSelected()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(!proxyActions.canCompareSelected)

            Button(String(localized: "Set Selected as Left Side", bundle: RockxyLocalization.bundle)) {
                proxyActions.setDiffSide(left: true)
            }
            .disabled(!proxyActions.canSetDiffSide)

            Button(String(localized: "Set Selected as Right Side", bundle: RockxyLocalization.bundle)) {
                proxyActions.setDiffSide(left: false)
            }
            .disabled(!proxyActions.canSetDiffSide)
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
}
