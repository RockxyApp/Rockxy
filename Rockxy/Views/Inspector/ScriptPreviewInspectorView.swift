import AppKit
import SwiftUI

// Shows the preview tabs a script published for the selected exchange.

// MARK: - ScriptPreviewInspectorView

/// Lists the tabs scripts attached with `context.previewTabs` for one panel. A picker
/// switches between them; the text is read-only and selectable.
struct ScriptPreviewInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    let panel: PreviewPanel

    var body: some View {
        let tabs = Self.tabs(of: transaction, panel: panel)
        if tabs.isEmpty {
            InspectorEmptyStateView(
                String(localized: "No Script Preview", bundle: RockxyLocalization.bundle),
                systemImage: "curlybraces",
                description: String(
                    localized: "No script published a preview tab for this exchange.",
                    bundle: RockxyLocalization.bundle
                )
            )
        } else {
            let index = min(selectedIndex, tabs.count - 1)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    if tabs.count > 1 {
                        Picker(
                            String(localized: "Preview", bundle: RockxyLocalization.bundle),
                            selection: $selectedIndex
                        ) {
                            ForEach(Array(tabs.enumerated()), id: \.offset) { offset, tab in
                                Text(tab.title).tag(offset)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240)
                    } else {
                        Text(tabs[index].title)
                            .font(.system(size: metrics.fontSize, weight: .semibold))
                    }
                    Spacer()
                    Button(String(localized: "Copy", bundle: RockxyLocalization.bundle)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tabs[index].text, forType: .string)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
                let text = tabs[index].text
                AsyncInspectorTextEditor(
                    renderID: "\(transaction.id.uuidString)-script-\(panel.rawValue)-\(index)-\(text.count)"
                ) {
                    .text(text)
                }
            }
        }
    }

    static func tabs(of transaction: HTTPTransaction, panel: PreviewPanel) -> [ScriptPreviewTab] {
        transaction.scriptPreviews.filter { $0.panel == panel }
    }

    static func isApplicable(to transaction: HTTPTransaction, panel: PreviewPanel) -> Bool {
        transaction.scriptPreviews.contains { $0.panel == panel }
    }

    // MARK: Private

    @State private var selectedIndex = 0
    @Environment(\.appUIDisplayMetrics) private var metrics
}
