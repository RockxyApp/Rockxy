import SwiftUI

struct KeyboardShortcutsView: View {
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            shortcutList
            Divider()
            footer
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 520, idealHeight: 620)
    }

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredSections: [KeyboardShortcutSection] {
        KeyboardShortcutCatalog.filtered(by: searchText)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Keyboard Shortcuts"))
                .font(.title3.weight(.semibold))

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search shortcuts"), text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var shortcutList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(filteredSections) { section in
                    shortcutSection(section)
                }
            }
            .padding(20)
        }
    }

    private func shortcutSection(_ section: KeyboardShortcutSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                ForEach(section.shortcuts) { shortcut in
                    GridRow {
                        shortcutKeys(shortcut.shortcut)
                        Text(shortcut.action)
                            .font(.system(size: 13))
                        Text(shortcut.window)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note = shortcut.note {
                        GridRow {
                            Color.clear
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .gridCellColumns(2)
                        }
                    }
                }
            }
        }
    }

    private func shortcutKeys(_ shortcut: String) -> some View {
        Text(shortcut)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .frame(minWidth: 72, minHeight: 24)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
            }
    }

    private var footer: some View {
        Text(String(localized: "Some shortcuts depend on focus — click the panel first."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
    }
}
