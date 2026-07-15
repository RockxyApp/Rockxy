import SwiftUI

// MARK: - CapturedValueSuggestion

struct CapturedValueSuggestion: Identifiable, Equatable {
    let value: String
    let requestCount: Int

    var id: String {
        value
    }
}

// MARK: - CapturedValueDisplayPolicy

enum CapturedValueDisplayPolicy {
    static let initialResultLimit = 50
    static let searchResultLimit = 100

    static func matching(
        _ suggestions: [CapturedValueSuggestion],
        searchText: String
    )
        -> [CapturedValueSuggestion]
    {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return suggestions
        }
        return suggestions.filter {
            $0.value.localizedCaseInsensitiveContains(query)
        }
    }

    static func displayed(
        _ suggestions: [CapturedValueSuggestion],
        searchText: String
    )
        -> [CapturedValueSuggestion]
    {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = query.isEmpty ? initialResultLimit : searchResultLimit
        return Array(matching(suggestions, searchText: query).prefix(limit))
    }
}

// MARK: - CapturedValueKind

enum CapturedValueKind: Hashable {
    case application
    case domain
    case path

    // MARK: Internal

    var systemImage: String {
        switch self {
        case .application: "app"
        case .domain: "globe"
        case .path: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

// MARK: - CapturedApplicationSelectionField

struct CapturedApplicationSelectionField: View {
    // MARK: Internal

    @Binding var selection: String

    let suggestions: [CapturedValueSuggestion]

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isPickerPresented.toggle()
            } label: {
                HStack(spacing: 8) {
                    CapturedApplicationIconView(name: selection, size: 20)
                    Text(selection.isEmpty ? String(localized: "Any application") : selection)
                        .foregroundStyle(selection.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(String(localized: "Choose…"))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
            .popover(isPresented: $isPickerPresented, arrowEdge: .trailing) {
                CapturedValuePicker(
                    title: String(localized: "Choose Application"),
                    searchPrompt: String(localized: "Search captured applications"),
                    emptySelectionTitle: String(localized: "Any Application"),
                    selection: selection,
                    suggestions: suggestions,
                    kind: .application
                ) { value in
                    selection = value
                    isPickerPresented = false
                }
            }

            if !selection.isEmpty {
                Button {
                    selection = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Use any application"))
            }
        }
    }

    // MARK: Private

    @State private var isPickerPresented = false
}

// MARK: - CapturedTextSuggestionField

struct CapturedTextSuggestionField: View {
    // MARK: Internal

    @Binding var text: String

    let placeholder: String
    let pickerTitle: String
    let searchPrompt: String
    let emptySelectionTitle: String
    let suggestions: [CapturedValueSuggestion]
    let kind: CapturedValueKind
    var requestsInitialFocus = false

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
            Button(String(localized: "Browse…")) {
                isPickerPresented.toggle()
            }
            .fixedSize()
            .help(String(localized: "Search values seen in captured traffic"))
            .popover(isPresented: $isPickerPresented, arrowEdge: .trailing) {
                CapturedValuePicker(
                    title: pickerTitle,
                    searchPrompt: searchPrompt,
                    emptySelectionTitle: emptySelectionTitle,
                    selection: text,
                    suggestions: suggestions,
                    kind: kind
                ) { value in
                    text = value
                    isPickerPresented = false
                }
            }
        }
        .task {
            guard requestsInitialFocus else {
                return
            }
            await Task.yield()
            isTextFieldFocused = true
        }
    }

    // MARK: Private

    @State private var isPickerPresented = false
    @FocusState private var isTextFieldFocused: Bool
}

// MARK: - CapturedValuePicker

private struct CapturedValuePicker: View {
    // MARK: Internal

    let title: String
    let searchPrompt: String
    let emptySelectionTitle: String
    let selection: String
    let suggestions: [CapturedValueSuggestion]
    let kind: CapturedValueKind
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            searchField
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    pickerRow(value: "", title: emptySelectionTitle, requestCount: nil)
                    ForEach(displayedSuggestions) { suggestion in
                        pickerRow(
                            value: suggestion.value,
                            title: suggestion.value,
                            requestCount: suggestion.requestCount
                        )
                    }

                    if matchingSuggestions.isEmpty, !trimmedSearchText.isEmpty {
                        Text(String(localized: "No captured value matches your search."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(14)
                    }
                }
            }
            .frame(height: 250)

            if matchingSuggestions.count > displayedSuggestions.count {
                Divider()
                Text(
                    String(
                        localized: "Showing \(displayedSuggestions.count) of \(matchingSuggestions.count). Search to find more."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 360)
    }

    // MARK: Private

    @State private var searchText = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingSuggestions: [CapturedValueSuggestion] {
        CapturedValueDisplayPolicy.matching(suggestions, searchText: trimmedSearchText)
    }

    private var displayedSuggestions: [CapturedValueSuggestion] {
        CapturedValueDisplayPolicy.displayed(suggestions, searchText: trimmedSearchText)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(searchPrompt, text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    }

    private func pickerRow(value: String, title: String, requestCount: Int?) -> some View {
        Button {
            onSelect(value)
        } label: {
            HStack(spacing: 8) {
                leadingIcon(for: value)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let requestCount {
                    Text("\(requestCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help(String(localized: "\(requestCount) captured requests"))
                }
                if selection == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func leadingIcon(for value: String) -> some View {
        if kind == .application {
            CapturedApplicationIconView(name: value, size: 20)
        } else {
            Image(systemName: value.isEmpty ? "circle.dashed" : kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
    }
}

// MARK: - CapturedApplicationIconView

struct CapturedApplicationIconView: View {
    // MARK: Internal

    let name: String
    let size: CGFloat

    var body: some View {
        if let icon = AppIconProvider.applicationIcon(named: name, size: size) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: max(4, size * 0.22), style: .continuous)
                .fill(background)
                .frame(width: size, height: size)
                .overlay {
                    if name.isEmpty {
                        Image(systemName: "app.dashed")
                            .font(.system(size: max(9, size * 0.48), weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: max(9, size * 0.5), weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
        }
    }

    // MARK: Private

    private var background: LinearGradient {
        let colors = name.isEmpty
            ? (Color.gray.opacity(0.15), Color.gray.opacity(0.3))
            : Theme.Sidebar.appIconGradient(for: name)
        return LinearGradient(
            colors: [colors.0, colors.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
