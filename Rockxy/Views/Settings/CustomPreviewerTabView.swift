import SwiftUI

// Renders the custom previewer tab interface for the settings experience.

struct CustomPreviewerTabView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Custom Body Previewer Tabs"))
                .font(.system(size: 13, weight: .semibold))
            Text(String(localized: "Select tabs to render body content as a specific format"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                panelColumn(title: String(localized: "Request Panel"), panel: .request)
                panelColumn(title: String(localized: "Response Panel"), panel: .response)
            }

            Divider()

            Toggle(isOn: $store.autoBeautify) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Auto beautify minified content"))
                        .font(.system(size: 12))
                    Text(String(localized: "Only applies to HTML, CSS, and JavaScript"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.checkbox)

            if !allCustomTabs.isEmpty {
                Divider()

                Text(String(localized: "Custom Tabs"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(allCustomTabs) { tab in
                        HStack(spacing: 8) {
                            Text(tab.name)
                                .font(.system(size: 12))
                            Text(tab.panel == .request
                                ? String(localized: "Request")
                                : String(localized: "Response"))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Menu {
                                Button(String(localized: "Edit Script…")) {
                                    openWindow(id: "scriptingList")
                                }
                                Divider()
                                Button(String(localized: "Remove"), role: .destructive) {
                                    store.removeTab(id: tab.id)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 16)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .frame(width: 20)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label(String(localized: "Add Custom Tabs"), systemImage: "plus")
                }
            }
        }
        .padding(12)
        .frame(width: 480)
        .sheet(isPresented: $showAddSheet) {
            AddCustomTabSheet(
                store: store,
                defaultPanel: .request,
                onDismiss: { showAddSheet = false }
            )
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @State private var store = PreviewTabStore()
    @State private var showAddSheet = false

    private var allCustomTabs: [PreviewTab] {
        store.customTabs(for: .request) + store.customTabs(for: .response)
    }

    private func panelColumn(title: String, panel: PreviewPanel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(PreviewRenderMode.allCases) { mode in
                    Toggle(mode.displayName, isOn: Binding(
                        get: { store.isEnabled(renderMode: mode, panel: panel) },
                        set: { enabled in
                            if enabled {
                                store.enableTab(renderMode: mode, panel: panel)
                            } else {
                                store.disableTab(renderMode: mode, panel: panel)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity)
    }
}
