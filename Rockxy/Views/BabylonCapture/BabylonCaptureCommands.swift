import SwiftUI

struct BabylonCaptureCommands: Commands {
    // MARK: Internal

    var body: some Commands {
        CommandMenu(String(localized: "Babylon", bundle: RockxyLocalization.bundle)) {
            Toggle(
                String(localized: "Accept Babylon Connections", bundle: RockxyLocalization.bundle),
                isOn: Binding(
                    get: { receiver.isEnabled },
                    set: { receiver.setEnabled($0) }
                )
            )

            Divider()

            Button(String(localized: "Pairing…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "babylonPairing")
            }

            Button(String(localized: "Runtime Events…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "babylonRuntime")
            }
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    private let receiver = BabylonCaptureReceiver.shared
}
