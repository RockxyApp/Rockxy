import AppKit
import SwiftUI

// MARK: - PayloadActionsBar

/// Opens a captured payload in an installed editor, reveals it in Finder, or saves its
/// exact bytes. Shared by the request Body tab and WebSocket frame details.
struct PayloadActionsBar: View {
    // MARK: Internal

    let payload: Data
    /// Unique, stable name for the temporary copy, e.g. a transaction or frame id.
    let fileStem: String
    let fileExtension: String
    /// Default file name (without extension) offered by Save As.
    let suggestedName: String
    var saveTitle = String(localized: "Save Body As…", bundle: RockxyLocalization.bundle)

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            Menu(String(localized: "Open with", bundle: RockxyLocalization.bundle)) {
                ForEach(ResponseBodyEditor.installed) { editor in
                    Button {
                        open(with: editor.bundleIdentifier)
                    } label: {
                        Label {
                            Text(verbatim: editor.name)
                        } icon: {
                            Image(systemName: editor.systemImage)
                        }
                    }
                }
                Divider()
                Button(String(localized: "Open by System…", bundle: RockxyLocalization.bundle)) {
                    open(with: nil)
                }
                Button(String(localized: "Show in Finder…", bundle: RockxyLocalization.bundle)) {
                    if let url = temporaryURL() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button(saveTitle) {
                save()
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: metrics.secondaryFontSize))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    static func fileExtension(for contentType: ContentType?) -> String {
        switch contentType {
        case .json: "json"
        case .xml: "xml"
        case .html: "html"
        case .form,
             .text: "txt"
        default: "bin"
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private func temporaryURL() -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RockxyInspector", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(fileStem).appendingPathExtension(fileExtension)
            try payload.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func open(with bundleIdentifier: String?) {
        guard let url = temporaryURL() else {
            return
        }
        if let bundleIdentifier, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).\(fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try payload.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Could Not Save Body", bundle: RockxyLocalization.bundle)
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))
            alert.runModal()
        }
    }
}
