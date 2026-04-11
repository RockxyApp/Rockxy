import SwiftUI

// MARK: - AllowListFilterBar

struct AllowListFilterBar: View {
    // MARK: Internal

    @Binding var filterColumn: AllowListFilterColumn
    @Binding var filterText: String

    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker(String(localized: "Column"), selection: $filterColumn) {
                ForEach(AllowListFilterColumn.allCases, id: \.self) { column in
                    Text(column.displayName).tag(column)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            TextField(
                String(localized: "Filter"),
                text: $filterText,
                prompt: Text(String(localized: "Filter (Hide: ESC)"))
            )
            .textFieldStyle(.roundedBorder)
            .focused($isTextFieldFocused)
            .onExitCommand(perform: onDismiss)
            .onAppear { isTextFieldFocused = true }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.background)
    }

    // MARK: Private

    @FocusState private var isTextFieldFocused: Bool
}
