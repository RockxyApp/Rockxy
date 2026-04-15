import SwiftUI

// Presents the preview tab popover for the request and response inspector.

struct PreviewTabPopover: View {
    // MARK: Internal

    let panel: PreviewPanel
    let store: PreviewTabStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Preview Tabs"))
                .font(.system(size: 12, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
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

            Divider()

            Toggle(isOn: Binding(
                get: { store.autoBeautify },
                set: { store.autoBeautify = $0 }
            )) {
                Text(String(localized: "Auto beautify"))
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            if !store.customTabs(for: panel).isEmpty {
                Divider()

                Text(String(localized: "Custom Tabs"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.customTabs(for: panel)) { tab in
                        HStack(spacing: 4) {
                            Text(tab.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

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

            Divider()

            Button {
                showAddSheet = true
            } label: {
                Label(String(localized: "Add Custom Tab"), systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(12)
        .frame(width: 220)
        .sheet(isPresented: $showAddSheet) {
            AddCustomTabSheet(
                store: store,
                defaultPanel: panel,
                onDismiss: { showAddSheet = false }
            )
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @State private var showAddSheet = false
}
