import SwiftUI

// Renders the custom header columns interface for the settings experience.

struct CustomHeaderColumnsView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Custom Header Columns"))
                .font(settingsMetrics.font(weight: .semibold))
            Text(
                String(localized: "Get Value of Request/Response Headers and display it as a Column on the Flow Table.")
            )
            .font(settingsMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                headerPanel(
                    title: String(localized: "Request Headers"),
                    source: .request,
                    selectedID: $selectedRequestID,
                    showAdd: $showAddRequest
                )
                headerPanel(
                    title: String(localized: "Response Headers"),
                    source: .response,
                    selectedID: $selectedResponseID,
                    showAdd: $showAddResponse
                )
            }

            Text(String(localized: "To manage the default columns, please Right-click on the Header Column."))
                .font(settingsMetrics.metadataFont())
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .font(settingsMetrics.font())
        .frame(width: settingsMetrics.fieldWidth(560))
        .onAppear {
            store.reload()
        }
    }

    // MARK: Private

    @State private var store = HeaderColumnStore()
    @State private var selectedRequestID: UUID?
    @State private var selectedResponseID: UUID?
    @State private var showAddRequest = false
    @State private var showAddResponse = false
    @State private var newHeaderName = ""
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder
    private func headerPanel(
        title: String,
        source: HeaderColumnSource,
        selectedID: Binding<UUID?>,
        showAdd: Binding<Bool>
    )
        -> some View
    {
        let allHeaders = mergedHeaderNames(for: source)

        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(settingsMetrics.secondaryFont(weight: .medium))

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(allHeaders, id: \.self) { name in
                            let storedCol = store.columns.first {
                                $0.headerName == name && $0.source == source
                            }
                            let isChecked = storedCol?.isEnabled ?? false

                            HStack(spacing: 6) {
                                Button {
                                    if let col = storedCol {
                                        store.toggleColumn(id: col.id)
                                    } else {
                                        store.addColumn(headerName: name, source: source)
                                    }
                                } label: {
                                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                        .font(settingsMetrics.font())
                                        .foregroundStyle(
                                            isChecked
                                                ? Color.accentColor
                                                : Color(nsColor: .tertiaryLabelColor)
                                        )
                                }
                                .buttonStyle(.plain)

                                Text(name)
                                    .font(settingsMetrics.secondaryFont())
                                    .foregroundStyle(isChecked ? .primary : .secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedID.wrappedValue == storedCol?.id
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 3)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedID.wrappedValue = storedCol?.id
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(minHeight: 220)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6)
                )

                HStack(spacing: 0) {
                    Button {
                        showAdd.wrappedValue = true
                    } label: {
                        Image(systemName: "plus")
                            .font(settingsMetrics.secondaryFont())
                            .frame(width: settingsMetrics.controlHeight, height: settingsMetrics.controlHeight)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: showAdd) {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                TextField(
                                    String(localized: "Header name"),
                                    text: $newHeaderName
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(settingsMetrics.font())
                                .frame(width: settingsMetrics.fieldWidth(150))
                                .frame(minHeight: settingsMetrics.controlHeight)
                                Button(String(localized: "Add")) {
                                    let name = newHeaderName
                                        .trimmingCharacters(in: .whitespaces)
                                    guard !name.isEmpty else {
                                        return
                                    }
                                    store.addColumn(
                                        headerName: name,
                                        source: source
                                    )
                                    newHeaderName = ""
                                    showAdd.wrappedValue = false
                                }
                                .disabled(
                                    newHeaderName
                                        .trimmingCharacters(in: .whitespaces)
                                        .isEmpty
                                )
                            }
                        }
                        .padding(12)
                        .font(settingsMetrics.font())
                        .frame(width: settingsMetrics.fieldWidth(220))
                    }

                    Button {
                        if let id = selectedID.wrappedValue {
                            store.removeColumn(id: id)
                            selectedID.wrappedValue = nil
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(settingsMetrics.secondaryFont())
                            .frame(width: settingsMetrics.controlHeight, height: settingsMetrics.controlHeight)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedID.wrappedValue == nil)

                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(alignment: .top) { Divider() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func mergedHeaderNames(for source: HeaderColumnSource) -> [String] {
        let storedNames = store.columns
            .filter { $0.source == source }
            .map(\.headerName)
        let discoveredNames = source == .request
            ? store.discoveredRequestHeaders
            : store.discoveredResponseHeaders

        var allNames = Set(storedNames)
        allNames.formUnion(discoveredNames)
        return allNames.sorted()
    }
}
