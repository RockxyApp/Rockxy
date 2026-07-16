import SwiftUI

// Renders the search filter bar interface for toolbar controls and filtering.

// MARK: - SearchFilterBar

/// Single-field search bar with a field selector (URL, host, path, method) and enable/disable toggle.
struct SearchFilterBar: View {
    @Binding var searchText: String
    @Binding var filterField: FilterField
    @Binding var isEnabled: Bool
    let isAdvancedFilterVisible: Bool
    let advancedFilterCount: Int
    let onAddFilter: () -> Void
    let onToggleAdvancedFilters: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .tint(.green)

            Picker("", selection: $filterField) {
                ForEach(FilterField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .frame(width: 130)

            TextField(String(localized: "Search..."), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(metrics.swiftUIFont())
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            Divider()
                .frame(height: 18)

            Button(action: onAddFilter) {
                Label(String(localized: "Add Filter"), systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(String(localized: "Add a compound filter rule"))

            Button(action: onToggleAdvancedFilters) {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    if advancedFilterCount > 0 {
                        Text("\(advancedFilterCount)")
                            .monospacedDigit()
                    }
                    Image(systemName: isAdvancedFilterVisible ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(isAdvancedFilterVisible
                ? String(localized: "Hide compound filters")
                : String(localized: "Show compound filters"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, max(4, (metrics.fontSize - 10) / 3))
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .onReceive(NotificationCenter.default.publisher(for: .focusMainSearchField)) { _ in
            isEnabled = true
            isSearchFocused = true
        }
    }

    @FocusState private var isSearchFocused: Bool
    @Environment(\.appUIDisplayMetrics) private var metrics
}
