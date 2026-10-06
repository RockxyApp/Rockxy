import SwiftUI

// Renders the compose request editor interface for the compose workflow.

// MARK: - ComposeRequestEditor

/// Left panel of the Compose window. Segmented tabs for Headers, Query, Body, and Raw.
struct ComposeRequestEditor: View {
    // MARK: Internal

    @Bindable var viewModel: ComposeViewModel

    let onLoadFromFile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            Group {
                switch selectedTab {
                case .headers:
                    headersEditor
                case .query:
                    queryEditor
                case .body:
                    bodyEditor
                case .raw:
                    rawView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Private

    @State private var selectedTab: ComposeRequestTab = .headers
    @State private var rawDraft = ""
    @State private var editsBodyAsForm = true
    @State private var rawError: String?
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    // MARK: - Bindings

    private var bodyBinding: Binding<String> {
        Binding(
            get: { viewModel.body },
            set: { viewModel.replaceUnavailableBody(with: $0) }
        )
    }

    private var headerBar: some View {
        HStack(spacing: toolMetrics.headerSpacing) {
            Text(String(localized: "Request", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            tabPicker

            Spacer()

            requestMenu
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .frame(minHeight: max(44, toolMetrics.formControlHeight + 16))
    }

    @ViewBuilder private var tabPicker: some View {
        if toolMetrics.bodyFontSize >= 20 {
            Picker(String(localized: "Request Section", bundle: RockxyLocalization.bundle), selection: $selectedTab) {
                ForEach(ComposeRequestTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 130)
            .accessibilityLabel(String(localized: "Request section", bundle: RockxyLocalization.bundle))
        } else {
            Picker(String(localized: "Request Section", bundle: RockxyLocalization.bundle), selection: $selectedTab) {
                ForEach(ComposeRequestTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityLabel(String(localized: "Request section", bundle: RockxyLocalization.bundle))
        }
    }

    private var requestMenu: some View {
        Menu {
            Button(String(localized: "Load from File...", bundle: RockxyLocalization.bundle)) {
                onLoadFromFile()
                selectedTab = .body
            }
            Divider()
            Button(String(localized: "JSON Prettier", bundle: RockxyLocalization.bundle)) {
                viewModel.prettifyJSONBody()
                selectedTab = .body
            }
            Button(String(localized: "Prettify XML", bundle: RockxyLocalization.bundle)) {
                viewModel.prettifyXMLBody()
                selectedTab = .body
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
        }
        .menuStyle(.button)
        .help(String(localized: "Request Body Options", bundle: RockxyLocalization.bundle))
    }

    // MARK: - Headers Tab

    private var headersEditor: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                columnHeaders(name: "Name", value: "Value")

                ForEach(viewModel.headers) { header in
                    HStack(spacing: 8) {
                        Toggle("", isOn: headerEnabledBinding(for: header.id))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .frame(width: 24)

                        TextField(
                            String(localized: "e.g. Content-Type", bundle: RockxyLocalization.bundle),
                            text: headerNameBinding(for: header.id)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(minHeight: toolMetrics.formControlHeight)

                        TextField(
                            String(localized: "e.g. application/json", bundle: RockxyLocalization.bundle),
                            text: headerValueBinding(for: header.id)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(minHeight: toolMetrics.formControlHeight)

                        removeButton {
                            viewModel.removeHeader(id: header.id)
                        }
                    }
                    .padding(.vertical, 4)
                }

                addButton(String(localized: "Add Header", bundle: RockxyLocalization.bundle)) {
                    viewModel.addHeader()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
    }

    // MARK: - Query Tab

    private var queryEditor: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                columnHeaders(name: "Name", value: "Value")

                ForEach(viewModel.queryItems) { item in
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 24)

                        TextField(
                            String(localized: "e.g. page", bundle: RockxyLocalization.bundle),
                            text: queryNameBinding(for: item.id)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(minHeight: toolMetrics.formControlHeight)

                        TextField(
                            String(localized: "e.g. 1", bundle: RockxyLocalization.bundle),
                            text: queryValueBinding(for: item.id)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(minHeight: toolMetrics.formControlHeight)

                        removeButton {
                            viewModel.removeQueryItem(id: item.id)
                        }
                    }
                    .padding(.vertical, 4)
                }

                addButton(String(localized: "Add Parameter", bundle: RockxyLocalization.bundle)) {
                    viewModel.addQueryItem()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
    }

    // MARK: - Body Tab

    private var bodyEditor: some View {
        VStack(spacing: 0) {
            if FormURLEncodedBody.isFormContentType(viewModel.headers) {
                HStack {
                    Picker(String(localized: "Body Format", bundle: RockxyLocalization.bundle), selection: $editsBodyAsForm) {
                        Text(String(localized: "Form", bundle: RockxyLocalization.bundle)).tag(true)
                        Text(String(localized: "Text", bundle: RockxyLocalization.bundle)).tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            if editsBodyAsForm, FormURLEncodedBody.isFormContentType(viewModel.headers) {
                formBodyEditor
            } else {
                TextEditor(text: bodyBinding)
                    .font(toolMetrics.font(monospaced: true))
                    .padding(8)
            }

            if let message = viewModel.lastFormattingError {
                Divider()
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Form Body

    private var formBodyEditor: some View {
        let fields = FormURLEncodedBody.fields(from: viewModel.body)
        return ScrollView {
            LazyVStack(spacing: 0) {
                columnHeaders(name: "Name", value: "Value")
                ForEach(Array(fields.indices), id: \.self) { index in
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 24)
                        TextField(
                            String(localized: "e.g. email", bundle: RockxyLocalization.bundle),
                            text: formFieldBinding(index: index, keyPath: \.name)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        TextField(
                            String(localized: "Value", bundle: RockxyLocalization.bundle),
                            text: formFieldBinding(index: index, keyPath: \.value)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        removeButton {
                            var updated = FormURLEncodedBody.fields(from: viewModel.body)
                            if updated.indices.contains(index) {
                                updated.remove(at: index)
                            }
                            viewModel.replaceUnavailableBody(with: FormURLEncodedBody.body(from: updated))
                        }
                    }
                    .padding(.vertical, 4)
                }
                addButton(String(localized: "Add Field", bundle: RockxyLocalization.bundle)) {
                    var updated = FormURLEncodedBody.fields(from: viewModel.body)
                    updated.append(FormURLEncodedBody.Field(name: "", value: ""))
                    viewModel.replaceUnavailableBody(with: FormURLEncodedBody.body(from: updated))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
    }

    private func formFieldBinding(
        index: Int,
        keyPath: WritableKeyPath<FormURLEncodedBody.Field, String>
    )
        -> Binding<String>
    {
        Binding(
            get: {
                let fields = FormURLEncodedBody.fields(from: viewModel.body)
                return fields.indices.contains(index) ? fields[index][keyPath: keyPath] : ""
            },
            set: { newValue in
                var fields = FormURLEncodedBody.fields(from: viewModel.body)
                guard fields.indices.contains(index) else {
                    return
                }
                fields[index][keyPath: keyPath] = newValue
                viewModel.replaceUnavailableBody(with: FormURLEncodedBody.body(from: fields))
            }
        )
    }

    // MARK: - Raw Tab

    private var rawView: some View {
        VStack(spacing: 0) {
            TextEditor(text: $rawDraft)
                .font(toolMetrics.font(monospaced: true))
                .padding(8)
                .accessibilityLabel(String(localized: "Raw request", bundle: RockxyLocalization.bundle))
            Divider()
            HStack(spacing: toolMetrics.controlSpacing) {
                if let rawError {
                    Label(rawError, systemImage: "exclamationmark.triangle")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else {
                    Text(String(
                        localized: "Edit the request line, headers, or body, then apply.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Revert", bundle: RockxyLocalization.bundle)) {
                    rawDraft = viewModel.rawRequestText
                    rawError = nil
                }
                .disabled(rawDraft == viewModel.rawRequestText)
                Button(String(localized: "Apply", bundle: RockxyLocalization.bundle)) {
                    do {
                        try viewModel.applyRawRequest(rawDraft)
                        rawDraft = viewModel.rawRequestText
                        rawError = nil
                    } catch {
                        rawError = error.localizedDescription
                    }
                }
                .disabled(rawDraft == viewModel.rawRequestText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .onAppear {
            rawDraft = viewModel.rawRequestText
            rawError = nil
        }
    }

    // MARK: - Shared Helpers

    private func columnHeaders(name: LocalizedStringResource, value: LocalizedStringResource) -> some View {
        HStack {
            Color.clear.frame(width: 24)
            Text(name)
                .font(toolMetrics.tableHeaderFont())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(toolMetrics.tableHeaderFont())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 24)
        }
        .padding(.bottom, 4)
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .frame(width: 24)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Remove", bundle: RockxyLocalization.bundle))
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Button(action: action) {
                Label(title, systemImage: "plus.circle")
                    .font(toolMetrics.secondaryFont())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 2)
    }

    private func headerEnabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.headers.first(where: { $0.id == id })?.isEnabled ?? true },
            set: { newValue in
                if let idx = viewModel.headers.firstIndex(where: { $0.id == id }) {
                    viewModel.headers[idx].isEnabled = newValue
                }
            }
        )
    }

    private func headerNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.headers.first(where: { $0.id == id })?.name ?? "" },
            set: { newValue in
                if let idx = viewModel.headers.firstIndex(where: { $0.id == id }) {
                    viewModel.headers[idx].name = newValue
                }
            }
        )
    }

    private func headerValueBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.headers.first(where: { $0.id == id })?.value ?? "" },
            set: { newValue in
                if let idx = viewModel.headers.firstIndex(where: { $0.id == id }) {
                    viewModel.headers[idx].value = newValue
                }
            }
        )
    }

    private func queryNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.queryItems.first(where: { $0.id == id })?.name ?? "" },
            set: { newValue in
                if let idx = viewModel.queryItems.firstIndex(where: { $0.id == id }) {
                    viewModel.queryItems[idx].name = newValue
                    viewModel.syncQueryToURL()
                }
            }
        )
    }

    private func queryValueBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.queryItems.first(where: { $0.id == id })?.value ?? "" },
            set: { newValue in
                if let idx = viewModel.queryItems.firstIndex(where: { $0.id == id }) {
                    viewModel.queryItems[idx].value = newValue
                    viewModel.syncQueryToURL()
                }
            }
        )
    }
}

// MARK: - ComposeRequestTab

private enum ComposeRequestTab: String, CaseIterable, Identifiable {
    case headers
    case query
    case body
    case raw

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .headers: String(localized: "Header", bundle: RockxyLocalization.bundle)
        case .query: String(localized: "Query", bundle: RockxyLocalization.bundle)
        case .body: String(localized: "Body", bundle: RockxyLocalization.bundle)
        case .raw: String(localized: "Raw", bundle: RockxyLocalization.bundle)
        }
    }
}
