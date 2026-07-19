import AppKit
import SwiftUI

struct BabylonPairingView: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section(String(localized: "Connection")) {
                LabeledContent(String(localized: "Bonjour Service"), value: BabylonCaptureProtocol.serviceType)
                LabeledContent(String(localized: "Port"), value: "\(BabylonCaptureProtocol.port)")
            }

            Section(String(localized: "Pairing Token")) {
                Text(store.token.isEmpty ? String(localized: "Unavailable") : store.token)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button(String(localized: "Copy Token")) {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(store.token, forType: .string)
                    }
                    .disabled(store.token.isEmpty)

                    Button(String(localized: "Regenerate…"), role: .destructive) {
                        showsRegenerateConfirmation = true
                    }
                }
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Text(
                String(
                    localized: "Keep this token private. Regenerating it disconnects Babylon clients until their DEBUG configuration is updated."
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 320)
        .confirmationDialog(
            String(localized: "Regenerate Babylon Pairing Token?"),
            isPresented: $showsRegenerateConfirmation
        ) {
            Button(String(localized: "Regenerate Token"), role: .destructive) {
                store.regenerate()
            }
        } message: {
            Text(String(localized: "Existing Babylon clients will be disconnected."))
        }
    }

    // MARK: Private

    @State private var store = BabylonPairingStore.shared
    @State private var showsRegenerateConfirmation = false
}
