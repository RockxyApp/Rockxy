import SwiftUI

// Renders the breakpoint editor interface for breakpoint review and editing.

// MARK: - BreakpointEditorView

/// Right panel of the Breakpoints window — edits the selected paused item's draft.
/// Shows phase-aware message controls and tabbed content for the selected item.
struct BreakpointEditorView: View {
    // MARK: Internal

    @Bindable var manager: BreakpointManager

    @Binding var canApplySelectedChanges: Bool

    var body: some View {
        Group {
            if let itemId = manager.selectedItemId {
                pausedItemEditor(itemId: itemId)
            } else {
                emptyState
            }
        }
        .font(toolMetrics.font())
        .onChange(of: manager.selectedItemId) { _, _ in
            refreshApplyAvailability()
        }
        .onChange(of: selectedTab) { _, newValue in
            guard let selectedItemId = manager.selectedItemId else {
                return
            }
            if newValue == .raw {
                syncRawMessageFromDraft(itemId: selectedItemId, force: true)
            } else {
                refreshApplyAvailability()
            }
        }
    }

    // MARK: Private

    private static let httpMethods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "QUERY"]

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

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                String(localized: "Select Paused Traffic", bundle: RockxyLocalization.bundle),
                systemImage: "cursorarrow.click.2"
            )
        } description: {
            Text(String(
                localized: "Choose an item from the queue to inspect and edit its message.",
                bundle: RockxyLocalization.bundle
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var binaryBodyNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Original payload protected", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.secondaryFont(weight: .semibold))
                Text(
                    String(
                        localized: "This body is not UTF-8 text, so body edits are disabled. Applying request-line, status, or header changes preserves every body byte.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private var protectedBodyState: some View {
        ContentUnavailableView {
            Label(String(localized: "Binary Body", bundle: RockxyLocalization.bundle), systemImage: "doc.badge.lock")
        } description: {
            Text(
                String(
                    localized: "Body editing is unavailable. Applying metadata changes or continuing original preserves every body byte.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var saveTemplateSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Save Template", bundle: RockxyLocalization.bundle))
                .font(.system(size: max(17, toolMetrics.bodyFontSize + 4), weight: .semibold))

            TextField(String(localized: "Template name", bundle: RockxyLocalization.bundle), text: $saveTemplateName)
                .textFieldStyle(.roundedBorder)

            let validation = BreakpointRawMessage.validation(for: pendingTemplateRawMessage, kind: pendingTemplateKind)
            Label(validation.message, systemImage: "circle.fill")
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(validation.isValid ? Color.green : Color.red)

            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle)) {
                    isSaveTemplateSheetPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Save", bundle: RockxyLocalization.bundle)) {
                    savePendingTemplate()
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .disabled(!validation.isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    @ViewBuilder
    private func pausedItemEditor(itemId: UUID) -> some View {
        if let index = manager.pausedItems.firstIndex(where: { $0.id == itemId }) {
            let item = manager.pausedItems[index]
            VStack(spacing: 0) {
                alertBanner(item: item)
                Divider()
                if let message = item.editableDraft.executionValidationMessage {
                    validationBanner(message)
                    Divider()
                }
                if !item.editableDraft.isBodyEditable {
                    binaryBodyNotice
                    Divider()
                }
                requestLine(itemId: itemId)
                if let origin = item.editableDraft.redirectedOrigin,
                   let original = item.editableDraft.fixedHTTPSAuthority
                {
                    redirectNotice(to: origin, from: original)
                }
                Divider()
                tabContent(itemId: itemId)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            emptyState
        }
    }

    private func redirectNotice(to origin: String, from original: String) -> some View {
        Label(
            String(
                localized: "Execute sends this request to \(origin) over a new connection instead of \(original).",
                bundle: RockxyLocalization.bundle
            ),
            systemImage: "arrow.triangle.turn.up.right.diamond"
        )
        .font(toolMetrics.secondaryFont())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func validationBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.07))
            .accessibilityLabel(String(localized: "Breakpoint edit error", bundle: RockxyLocalization.bundle))
            .accessibilityValue(message)
    }

    private func alertBanner(item: PausedBreakpointItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
            Text(item.phase == .request
                ? String(localized: "Request paused for review", bundle: RockxyLocalization.bundle)
                : String(localized: "Response paused for review", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            if let matchedRuleName = item.matchedRuleName, !matchedRuleName.isEmpty {
                Text(matchedRuleName)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ElapsedTimeBadge(since: item.createdAt)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }

    private func requestLine(itemId: UUID) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if itemPhase(itemId: itemId) == .request {
                methodPicker(itemId: itemId)
                requestURLField(itemId: itemId)
            } else {
                statusCodePicker(itemId: itemId)
                readOnlyURL(itemId: itemId)
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func methodPicker(itemId: UUID) -> some View {
        let currentMethod = draftFor(itemId)?.method ?? "GET"
        return Picker("", selection: Binding(
            get: { currentMethod },
            set: { newValue in manager.updateDraft(id: itemId) { $0.method = newValue } }
        )) {
            if !Self.httpMethods.contains(currentMethod) {
                Text(currentMethod).tag(currentMethod)
            }
            ForEach(Self.httpMethods, id: \.self) { method in
                Text(method).tag(method)
            }
        }
        .labelsHidden()
        .frame(width: toolMetrics.menuWidth(100))
        .accessibilityLabel(String(localized: "HTTP method", bundle: RockxyLocalization.bundle))
    }

    private func requestURLField(itemId: UUID) -> some View {
        TextField(
            String(localized: "Request URL", bundle: RockxyLocalization.bundle),
            text: Binding(
                get: { draftFor(itemId)?.url ?? "" },
                set: { newValue in manager.updateDraft(id: itemId) { $0.url = newValue } }
            )
        )
        .textFieldStyle(.roundedBorder)
        .font(toolMetrics.font(monospaced: true))
        .frame(minHeight: toolMetrics.formControlHeight)
        .accessibilityLabel(String(localized: "Request URL", bundle: RockxyLocalization.bundle))
        .help(String(
            localized: "Edit the method, scheme, host, port, path, or query. Another host or port sends the request to that server.",
            bundle: RockxyLocalization.bundle
        ))
    }

    private func readOnlyURL(itemId: UUID) -> some View {
        HStack(spacing: 8) {
            Text(String(localized: "URL", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.secondaryFont(weight: .semibold))
                .foregroundStyle(.secondary)
            Text(draftFor(itemId)?.url ?? "")
                .font(toolMetrics.font(monospaced: true))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(draftFor(itemId)?.url ?? "")
            Spacer(minLength: 0)
        }
        .frame(minHeight: toolMetrics.formControlHeight)
    }

    private func statusCodePicker(itemId: UUID) -> some View {
        let currentStatusCode = draftFor(itemId)?.statusCode ?? 200
        return HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { currentStatusCode },
                set: { newValue in manager.updateDraft(id: itemId) { $0.statusCode = newValue } }
            )) {
                if !Self.statusCodes.contains(where: { $0.code == currentStatusCode }) {
                    Text(String(currentStatusCode)).tag(currentStatusCode)
                }
                ForEach(Self.statusCodes, id: \.code) { status in
                    Text("\(status.code) \(status.text)").tag(status.code)
                }
            }
            .labelsHidden()
            .frame(width: toolMetrics.menuWidth(160))
            .accessibilityLabel(String(localized: "Common HTTP response status", bundle: RockxyLocalization.bundle))

            TextField(
                String(localized: "Compact HTTP status code", bundle: RockxyLocalization.bundle),
                text: Binding(
                    get: { String(draftFor(itemId)?.statusCode ?? 200) },
                    set: { value in
                        let statusCode = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                        manager.updateDraft(id: itemId) { $0.statusCode = statusCode }
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(toolMetrics.font(monospaced: true))
            .frame(width: 68)
            .frame(minHeight: toolMetrics.formControlHeight)
            .accessibilityLabel(String(localized: "Custom HTTP response status code", bundle: RockxyLocalization.bundle))
        }
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
            .accessibilityLabel(String(localized: "Message editor section", bundle: RockxyLocalization.bundle))
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
                        TextField(String(localized: "Header name", bundle: RockxyLocalization.bundle), text: Binding(
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
                        .frame(minHeight: toolMetrics.formControlHeight)

                        TextField(String(localized: "Header value", bundle: RockxyLocalization.bundle), text: Binding(
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
                        .frame(minHeight: toolMetrics.formControlHeight)

                        Button {
                            manager.updateDraft(id: itemId) { draft in
                                draft.headers.removeAll { $0.id == header.id }
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Remove header", bundle: RockxyLocalization.bundle))
                        .accessibilityLabel(String(
                            localized: "Remove header \(header.name)",
                            bundle: RockxyLocalization.bundle
                        ))
                    }
                }

                addButton(String(localized: "Add Header", bundle: RockxyLocalization.bundle)) {
                    manager.updateDraft(id: itemId) { draft in
                        draft.headers.append(EditableHeader(name: "", value: ""))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
    }

    @ViewBuilder
    private func bodyEditor(itemId: UUID) -> some View {
        if draftFor(itemId)?.isBodyEditable == false {
            protectedBodyState
        } else {
            TextEditor(text: Binding(
                get: { draftFor(itemId)?.body ?? "" },
                set: { newValue in manager.updateDraft(id: itemId) { $0.body = newValue } }
            ))
            .font(toolMetrics.font(monospaced: true))
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func rawEditor(itemId: UUID) -> some View {
        if draftFor(itemId)?.isBodyEditable == false {
            protectedBodyState
        } else {
            let kind = rawKind(for: itemId)
            let validation = BreakpointRawMessage.validation(for: rawMessage, kind: kind)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(validation.message, systemImage: "circle.fill")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(validation.isValid ? Color.green : Color.red)
                    Spacer()
                    Menu {
                        Button(String(
                            localized: "Save current message as new template...",
                            bundle: RockxyLocalization.bundle
                        )) {
                            pendingTemplateKind = kind
                            pendingTemplateRawMessage = rawMessage
                            saveTemplateName = defaultTemplateName(for: kind)
                            isSaveTemplateSheetPresented = true
                        }
                        Divider()
                        ForEach(templateStore.templates(for: kind)) { template in
                            let validation = template.validation
                            Button {
                                applyTemplate(template, to: itemId)
                            } label: {
                                Label(
                                    template.name.isEmpty ? String(
                                        localized: "Untitled",
                                        bundle: RockxyLocalization.bundle
                                    ) : template.name,
                                    systemImage: validation.isValid ? "doc.text" : "exclamationmark.triangle"
                                )
                            }
                            .disabled(!validation.isValid)
                            .help(validation.message)
                        }
                    } label: {
                        Label(String(localized: "Template", bundle: RockxyLocalization.bundle), systemImage: "doc.text")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                MapLocalHTTPMessageEditor(text: Binding(
                    get: { rawMessage },
                    set: { updateRawMessage($0, itemId: itemId) }
                ), editorSettings: toolMetrics.codeEditorSettings)
                    .overlay(Rectangle().stroke(Color(nsColor: .separatorColor).opacity(0.35)))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .onAppear { syncRawMessageFromDraft(itemId: itemId, force: true) }
            .onChange(of: manager.selectedItemId) { _, _ in
                syncRawMessageFromDraft(itemId: itemId, force: true)
            }
            .sheet(isPresented: $isSaveTemplateSheetPresented) {
                saveTemplateSheet
            }
        }
    }

    private func queryDisplay(itemId: UUID) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                columnHeaders(name: "Name", value: "Value")

                ForEach(queryItems) { item in
                    HStack(spacing: 8) {
                        TextField(String(localized: "Parameter name", bundle: RockxyLocalization.bundle), text: Binding(
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
                        .frame(minHeight: toolMetrics.formControlHeight)

                        TextField(
                            String(localized: "Parameter value", bundle: RockxyLocalization.bundle),
                            text: Binding(
                                get: { queryItems.first(where: { $0.id == item.id })?.value ?? "" },
                                set: { newValue in
                                    if let idx = queryItems.firstIndex(where: { $0.id == item.id }) {
                                        queryItems[idx].value = newValue
                                        rebuildURLFromQuery(itemId: itemId)
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.secondaryFont(monospaced: true))
                        .frame(minHeight: toolMetrics.formControlHeight)

                        Button {
                            queryItems.removeAll { $0.id == item.id }
                            rebuildURLFromQuery(itemId: itemId)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Remove query parameter", bundle: RockxyLocalization.bundle))
                        .accessibilityLabel(String(
                            localized: "Remove query parameter \(item.name)",
                            bundle: RockxyLocalization.bundle
                        ))
                    }
                }

                addButton(String(localized: "Add Parameter", bundle: RockxyLocalization.bundle)) {
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

    private func columnHeaders(name: LocalizedStringResource, value: LocalizedStringResource) -> some View {
        HStack {
            Text(name)
                .font(toolMetrics.secondaryFont(weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
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

    private func rawKind(for itemId: UUID) -> BreakpointTemplateKind {
        itemPhase(itemId: itemId) == .response ? .response : .request
    }

    private func refreshApplyAvailability() {
        guard let selectedItemId = manager.selectedItemId,
              draftFor(selectedItemId) != nil else
        {
            canApplySelectedChanges = false
            return
        }
        canApplySelectedChanges = true
    }

    private func syncRawMessageFromDraft(itemId: UUID, force: Bool = false) {
        guard force || rawMessageItemID != itemId,
              let draft = draftFor(itemId) else
        {
            return
        }
        rawMessageItemID = itemId
        rawMessage = BreakpointRawMessage.rawMessage(from: draft, kind: rawKind(for: itemId))
        canApplySelectedChanges = true
    }

    private func updateRawMessage(_ newValue: String, itemId: UUID) {
        rawMessageItemID = itemId
        rawMessage = newValue
        let kind = rawKind(for: itemId)
        let validation = BreakpointRawMessage.validation(for: newValue, kind: kind)
        canApplySelectedChanges = validation.isValid
        guard validation.isValid else {
            return
        }
        manager.updateDraft(id: itemId) { draft in
            if let updated = try? BreakpointRawMessage.applying(newValue, kind: kind, to: draft) {
                draft = updated
            }
        }
    }

    private func applyTemplate(_ template: BreakpointTemplate, to itemId: UUID) {
        guard let application = template.applicationPayload,
              application.kind == rawKind(for: itemId),
              draftFor(itemId) != nil else
        {
            return
        }
        manager.updateDraft(id: itemId) { draft in
            draft = application.applying(to: draft)
        }
        rawMessageItemID = itemId
        rawMessage = template.rawMessage
        canApplySelectedChanges = true
    }

    private func defaultTemplateName(for kind: BreakpointTemplateKind) -> String {
        switch kind {
        case .request:
            String(localized: "Saved Request", bundle: RockxyLocalization.bundle)
        case .response:
            String(localized: "Saved Response", bundle: RockxyLocalization.bundle)
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
        case .headers: String(localized: "Headers", bundle: RockxyLocalization.bundle)
        case .body: String(localized: "Body", bundle: RockxyLocalization.bundle)
        case .raw: String(localized: "Raw", bundle: RockxyLocalization.bundle)
        case .query: String(localized: "Query", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ElapsedTimeBadge

/// Live-updating elapsed time badge for the editor banner.
private struct ElapsedTimeBadge: View {
    // MARK: Internal

    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(since))
            Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                .font(toolMetrics.font(monospaced: true))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
