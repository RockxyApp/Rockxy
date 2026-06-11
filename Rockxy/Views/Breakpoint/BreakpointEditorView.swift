import SwiftUI

// Renders the breakpoint editor interface for breakpoint review and editing.

// MARK: - BreakpointEditorView

/// Right panel of the Breakpoints window — edits the selected paused item's draft.
/// Shows method/URL/status pickers and tabbed content (Headers, Body, Query)
/// adapted from the original BreakpointSheetView.
struct BreakpointEditorView: View {
    // MARK: Internal

    @Bindable var manager: BreakpointManager

    let windowModel: BreakpointWindowModel

    var body: some View {
        Group {
            switch windowModel.selectionMode {
            case .none:
                emptyState
            case let .pausedItem(itemId):
                pausedItemEditor(itemId: itemId)
            }
        }
        .font(toolMetrics.font())
    }

    // MARK: Private

    private static let httpMethods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    private static let statusCodes: [(code: Int, text: String)] = [
        (200, "OK"),
        (201, "Created"),
        (204, "No Content"),
        (301, "Moved Permanently"),
        (302, "Found"),
        (304, "Not Modified"),
        (400, "Bad Request"),
        (401, "Unauthorized"),
        (403, "Forbidden"),
        (404, "Not Found"),
        (500, "Internal Server Error"),
        (502, "Bad Gateway"),
        (503, "Service Unavailable"),
    ]

    @State private var selectedTab: BreakpointEditorTab = .headers
    @State private var queryItems: [EditableQueryItem] = []
    @State private var lastSyncedURL: String = ""
    @State private var rawMessage: String = ""
    @State private var rawMessageItemID: UUID?
    @State private var templateStore = BreakpointTemplateStore.shared
    @State private var isSaveTemplateSheetPresented = false
    @State private var saveTemplateName = ""
    @State private var pendingTemplateKind: BreakpointTemplateKind = .request
    @State private var pendingTemplateRawMessage = ""
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "cursorarrow.click.2")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "Create breakpoint from context menu or Tools menu."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pausedItemEditor(itemId: UUID) -> some View {
        if let index = manager.pausedItems.firstIndex(where: { $0.id == itemId }) {
            let item = manager.pausedItems[index]
            VStack(spacing: 0) {
                alertBanner(item: item)
                Divider()
                requestLine(itemId: itemId)
                Divider()
                tabContent(itemId: itemId)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            emptyState
        }
    }

    private func alertBanner(item: PausedBreakpointItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(item.phase == .request
                ? String(localized: "Request paused at breakpoint")
                : String(localized: "Response paused at breakpoint"))
                .font(toolMetrics.font())
                .foregroundStyle(.primary)
            Spacer()
            ElapsedTimeBadge(since: item.createdAt)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }

    private func requestLine(itemId: UUID) -> some View {
        HStack(spacing: 8) {
            if itemPhase(itemId: itemId) == .request {
                methodPicker(itemId: itemId)
                urlField(itemId: itemId)
            } else {
                statusCodePicker(itemId: itemId)
                urlField(itemId: itemId)
            }
        }
        .padding(12)
    }

    private func methodPicker(itemId: UUID) -> some View {
        Picker("", selection: Binding(
            get: { draftFor(itemId)?.method ?? "GET" },
            set: { newValue in manager.updateDraft(id: itemId) { $0.method = newValue } }
        )) {
            ForEach(Self.httpMethods, id: \.self) { method in
                Text(method).tag(method)
            }
        }
        .labelsHidden()
        .frame(width: 100)
    }

    private func urlField(itemId: UUID) -> some View {
        TextField(String(localized: "URL"), text: Binding(
            get: { draftFor(itemId)?.url ?? "" },
            set: { newValue in manager.updateDraft(id: itemId) { $0.url = newValue } }
        ))
        .textFieldStyle(.roundedBorder)
        .font(toolMetrics.font(monospaced: true))
    }

    private func statusCodePicker(itemId: UUID) -> some View {
        Picker("", selection: Binding(
            get: { draftFor(itemId)?.statusCode ?? 200 },
            set: { newValue in manager.updateDraft(id: itemId) { $0.statusCode = newValue } }
        )) {
            ForEach(Self.statusCodes, id: \.code) { status in
                Text("\(status.code) \(status.text)").tag(status.code)
            }
        }
        .labelsHidden()
        .frame(width: 160)
    }

    private func tabContent(itemId: UUID) -> some View {
        let tabs = availableTabs(for: itemId)
        return VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(tabs) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .onAppear {
                let currentTabs = availableTabs(for: itemId)
                if !currentTabs.contains(selectedTab) {
                    selectedTab = .headers
                }
            }
            .onChange(of: manager.selectedItemId) { _, _ in
                let currentTabs = availableTabs(for: itemId)
                if !currentTabs.contains(selectedTab) {
                    selectedTab = .headers
                }
            }

            Group {
                switch selectedTab {
                case .headers:
                    headersEditor(itemId: itemId)
                case .body:
                    bodyEditor(itemId: itemId)
                case .raw:
                    rawEditor(itemId: itemId)
                case .query:
                    queryDisplay(itemId: itemId)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func headersEditor(itemId: UUID) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                columnHeaders(name: "Name", value: "Value")

                let headers = draftFor(itemId)?.headers ?? []
                ForEach(headers) { header in
                    HStack(spacing: 8) {
                        TextField(String(localized: "Header name"), text: Binding(
                            get: { headerValue(itemId: itemId, headerId: header.id)?.name ?? "" },
                            set: { newName in
                                manager.updateDraft(id: itemId) { draft in
                                    if let idx = draft.headers.firstIndex(where: { $0.id == header.id }) {
                                        draft.headers[idx].name = newName
                                    }
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.secondaryFont(monospaced: true))

                        TextField(String(localized: "Header value"), text: Binding(
                            get: { headerValue(itemId: itemId, headerId: header.id)?.value ?? "" },
                            set: { newValue in
                                manager.updateDraft(id: itemId) { draft in
                                    if let idx = draft.headers.firstIndex(where: { $0.id == header.id }) {
                                        draft.headers[idx].value = newValue
                                    }
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.secondaryFont(monospaced: true))

                        Button {
                            manager.updateDraft(id: itemId) { draft in
                                draft.headers.removeAll { $0.id == header.id }
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                addButton(String(localized: "Add Header")) {
                    manager.updateDraft(id: itemId) { draft in
                        draft.headers.append(EditableHeader(name: "", value: ""))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
    }

    private func bodyEditor(itemId: UUID) -> some View {
        TextEditor(text: Binding(
            get: { draftFor(itemId)?.body ?? "" },
            set: { newValue in manager.updateDraft(id: itemId) { $0.body = newValue } }
        ))
        .font(toolMetrics.font(monospaced: true))
        .padding(8)
    }

    private func rawEditor(itemId: UUID) -> some View {
        let kind = rawKind(for: itemId)
        let validation = BreakpointRawMessage.validation(for: rawMessage, kind: kind)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(validation.message, systemImage: "circle.fill")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(validation.isValid ? Color.green : Color.red)
                Spacer()
                Menu {
                    Button(String(localized: "Save current message as new template...")) {
                        pendingTemplateKind = kind
                        pendingTemplateRawMessage = rawMessage
                        saveTemplateName = defaultTemplateName(for: kind)
                        isSaveTemplateSheetPresented = true
                    }
                    Divider()
                    ForEach(templateStore.templates(for: kind)) { template in
                        Button(template.name.isEmpty ? String(localized: "Untitled") : template.name) {
                            applyTemplate(template, to: itemId)
                        }
                    }
                } label: {
                    Label(String(localized: "Template"), systemImage: "doc.text")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            MapLocalHTTPMessageEditor(text: Binding(
                get: { rawMessage },
                set: { updateRawMessage($0, itemId: itemId) }
            ))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor).opacity(0.35)))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear { syncRawMessageFromDraft(itemId: itemId, force: true) }
        .onChange(of: manager.selectedItemId) { _, _ in
            syncRawMessageFromDraft(itemId: itemId, force: true)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .raw {
                syncRawMessageFromDraft(itemId: itemId, force: rawMessageItemID != itemId)
            }
        }
        .sheet(isPresented: $isSaveTemplateSheetPresented) {
            saveTemplateSheet
        }
    }

    private func queryDisplay(itemId: UUID) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                columnHeaders(name: "Name", value: "Value")

                ForEach(queryItems) { item in
                    HStack(spacing: 8) {
                        TextField(String(localized: "Parameter name"), text: Binding(
                            get: { queryItems.first(where: { $0.id == item.id })?.name ?? "" },
                            set: { newName in
                                if let idx = queryItems.firstIndex(where: { $0.id == item.id }) {
                                    queryItems[idx].name = newName
                                    rebuildURLFromQuery(itemId: itemId)
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.secondaryFont(monospaced: true))

                        TextField(String(localized: "Parameter value"), text: Binding(
                            get: { queryItems.first(where: { $0.id == item.id })?.value ?? "" },
                            set: { newValue in
                                if let idx = queryItems.firstIndex(where: { $0.id == item.id }) {
                                    queryItems[idx].value = newValue
                                    rebuildURLFromQuery(itemId: itemId)
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.secondaryFont(monospaced: true))

                        Button {
                            queryItems.removeAll { $0.id == item.id }
                            rebuildURLFromQuery(itemId: itemId)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                addButton(String(localized: "Add Parameter")) {
                    queryItems.append(EditableQueryItem(name: "", value: ""))
                    rebuildURLFromQuery(itemId: itemId)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
        .onAppear { syncQueryItemsFromURL(itemId: itemId) }
        .onChange(of: draftFor(itemId)?.url) { _, _ in syncQueryItemsFromURL(itemId: itemId) }
    }

    private func itemPhase(itemId: UUID) -> BreakpointPhase? {
        manager.pausedItems.first(where: { $0.id == itemId })?.phase
    }

    private func availableTabs(for itemId: UUID) -> [BreakpointEditorTab] {
        if itemPhase(itemId: itemId) == .response {
            return [.headers, .body, .raw]
        }
        return [.headers, .body, .raw, .query]
    }

    private func syncQueryItemsFromURL(itemId: UUID) {
        let currentURL = draftFor(itemId)?.url ?? ""
        guard currentURL != lastSyncedURL else {
            return
        }
        lastSyncedURL = currentURL
        let parsed = URLComponents(string: currentURL)?.queryItems ?? []
        queryItems = parsed.map { EditableQueryItem(name: $0.name, value: $0.value ?? "") }
    }

    private func rebuildURLFromQuery(itemId: UUID) {
        guard var components = URLComponents(string: draftFor(itemId)?.url ?? "") else {
            return
        }
        let nonEmpty = queryItems.filter { !$0.name.isEmpty }
        components.queryItems = nonEmpty.isEmpty ? nil : nonEmpty.map { URLQueryItem(name: $0.name, value: $0.value) }
        if let newURL = components.string {
            lastSyncedURL = newURL
            manager.updateDraft(id: itemId) { $0.url = newURL }
        }
    }

    // MARK: Helpers

    private func draftFor(_ itemId: UUID) -> BreakpointRequestData? {
        manager.pausedItems.first(where: { $0.id == itemId })?.editableDraft
    }

    private func headerValue(itemId: UUID, headerId: UUID) -> EditableHeader? {
        draftFor(itemId)?.headers.first(where: { $0.id == headerId })
    }

    private func columnHeaders(name: String, value: String) -> some View {
        HStack {
            Text(String(localized: String.LocalizationValue(name)))
                .font(toolMetrics.secondaryFont(weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: String.LocalizationValue(value)))
                .font(toolMetrics.secondaryFont(weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 24)
        }
        .padding(.bottom, 4)
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

    private func rawKind(for itemId: UUID) -> BreakpointTemplateKind {
        itemPhase(itemId: itemId) == .response ? .response : .request
    }

    private func syncRawMessageFromDraft(itemId: UUID, force: Bool = false) {
        guard force || rawMessageItemID != itemId,
              let draft = draftFor(itemId)
        else {
            return
        }
        rawMessageItemID = itemId
        rawMessage = BreakpointRawMessage.rawMessage(from: draft, kind: rawKind(for: itemId))
    }

    private func updateRawMessage(_ newValue: String, itemId: UUID) {
        rawMessageItemID = itemId
        rawMessage = newValue
        let kind = rawKind(for: itemId)
        guard BreakpointRawMessage.validation(for: newValue, kind: kind).isValid else {
            return
        }
        manager.updateDraft(id: itemId) { draft in
            if let updated = try? BreakpointRawMessage.applying(newValue, kind: kind, to: draft) {
                draft = updated
            }
        }
    }

    private func applyTemplate(_ template: BreakpointTemplate, to itemId: UUID) {
        rawMessageItemID = itemId
        rawMessage = template.rawMessage
        updateRawMessage(template.rawMessage, itemId: itemId)
    }

    private var saveTemplateSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Save Template"))
                .font(.system(size: max(17, toolMetrics.bodyFontSize + 4), weight: .semibold))

            TextField(String(localized: "Template name"), text: $saveTemplateName)
                .textFieldStyle(.roundedBorder)

            let validation = BreakpointRawMessage.validation(for: pendingTemplateRawMessage, kind: pendingTemplateKind)
            Label(validation.message, systemImage: "circle.fill")
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(validation.isValid ? Color.green : Color.red)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    isSaveTemplateSheetPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Save")) {
                    savePendingTemplate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!validation.isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func defaultTemplateName(for kind: BreakpointTemplateKind) -> String {
        switch kind {
        case .request:
            String(localized: "Saved Request")
        case .response:
            String(localized: "Saved Response")
        }
    }

    private func savePendingTemplate() {
        let template = templateStore.addTemplate(kind: pendingTemplateKind)
        templateStore.updateTemplate(
            id: template.id,
            name: saveTemplateName,
            rawMessage: pendingTemplateRawMessage
        )
        isSaveTemplateSheetPresented = false
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - BreakpointEditorTab

private enum BreakpointEditorTab: String, CaseIterable, Identifiable {
    case headers
    case body
    case raw
    case query

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .headers: String(localized: "Headers")
        case .body: String(localized: "Body")
        case .raw: String(localized: "Raw")
        case .query: String(localized: "Query")
        }
    }
}

// MARK: - ElapsedTimeBadge

/// Live-updating elapsed time badge for the editor banner.
private struct ElapsedTimeBadge: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(since))
            Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                .font(toolMetrics.font(monospaced: true))
                .foregroundStyle(.secondary)
        }
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
