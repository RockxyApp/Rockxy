import SwiftUI

// MARK: - ProtobufRuleEditorSession

struct ProtobufRuleEditorSession: Identifiable {
    enum Mode {
        case create
        case edit(ProtobufMappingRule)
    }

    let id = UUID()
    let mode: Mode
}

// MARK: - ProtobufSettingsWindowView

struct ProtobufSettingsWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rulesTable
            shortcutHelp
            footer
        }
        .font(toolMetrics.font())
        .frame(width: 1_240, height: 660)
        .sheet(item: $editorSession) { session in
            ProtobufRuleEditorSheet(
                session: session,
                schemas: schemaStore.schemas,
                canUploadSchema: schemaStore.canUploadSchema,
                onAddSchema: { openWindow(id: "protobufSchemaList") },
                onSave: saveRule
            )
        }
        .onDeleteCommand {
            mappingStore.removeSelectedRule()
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var mappingStore = ProtobufMappingRuleStore()
    @State private var schemaStore = ProtobufSchemaStore.shared
    @State private var editorSession: ProtobufRuleEditorSession?
    @State private var errorMessage: String?

    private var toggleLabel: String {
        guard let selectedRule = mappingStore.selectedRule else {
            return String(localized: "Enable Rule")
        }
        return selectedRule.isEnabled ? String(localized: "Disable Rule") : String(localized: "Enable Rule")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: toolMetrics.headerSpacing) {
            Text(String(localized: "Protobuf Mapping Rules"))
                .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .medium))

            Text(String(localized: "Define Protobuf Message Type for each Protobuf Request/Response."))
                .font(toolMetrics.font())

            Text(
                String(
                    localized: "Each request is checked against the rules from top to bottom, stopping when a match is found."
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)

            if !schemaStore.canUploadSchema {
                PolicyLockNotice(
                    title: String(localized: "Schema upload unavailable"),
                    message: String(
                        localized: "Mapping rules can be prepared, but uploaded schema decoding is disabled by the current app policy."
                    )
                )
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
    }

    private var rulesTable: some View {
        ZStack {
            Table(mappingStore.rules, selection: $mappingStore.selectedRuleID) {
                TableColumn(String(localized: "URL")) { rule in
                    HStack(spacing: 6) {
                        Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(rule.isEnabled ? .green : .secondary)
                        Text(rule.urlPattern)
                            .lineLimit(1)
                    }
                }
                TableColumn(String(localized: "Method")) { rule in
                    Text(rule.method.displayName)
                }
                .width(96)
                TableColumn(String(localized: "Payload Encoding")) { rule in
                    Text(rule.payloadEncoding.displayName)
                }
                .width(150)
                TableColumn(String(localized: "Message Type")) { rule in
                    Text(rule.messageType.isEmpty ? String(localized: "Auto") : rule.messageType)
                }
                .width(180)
                TableColumn(String(localized: "Schema")) { rule in
                    Text(mappingStore.schemaName(for: rule.schemaID, schemas: schemaStore.schemas))
                        .foregroundStyle(rule.schemaID == nil ? .secondary : .primary)
                }
                .width(180)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                tableContextMenu(ids: ids)
            }

            if mappingStore.rules.isEmpty {
                Text(String(localized: "Click \"+\" or ⌘N to add new entry"))
                    .font(.system(size: toolMetrics.emptyStateFontSize))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 380)
        .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
    }

    private var shortcutHelp: some View {
        Text(String(localized: "New: ⌘N    Edit: ⌘↩    Delete: ⌘⌫    Duplicate: ⌘D    Toggle: ␣"))
            .font(.system(size: toolMetrics.shortcutFontSize))
            .foregroundStyle(.secondary)
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.top, toolMetrics.shortcutTopPadding)
            .padding(.bottom, toolMetrics.shortcutBottomPadding)
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            addRemoveControl

            Button(String(localized: "Protobuf Schema…")) {
                openWindow(id: "protobufSchemaList")
            }

            Button {
                // Help content is intentionally lightweight until user-facing docs are wired into Help.
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.bordered)

            if let errorMessage {
                Text(errorMessage)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            moreMenu
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.bottom, toolMetrics.footerBottomPadding)
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                editorSession = ProtobufRuleEditorSession(mode: .create)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help(String(localized: "New Mapping Rule"))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 18)

            Button {
                mappingStore.removeSelectedRule()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .foregroundStyle(mappingStore.selectedRuleID == nil ? .tertiary : .primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(mappingStore.selectedRuleID == nil)
            .help(String(localized: "Delete Mapping Rule"))
        }
        .frame(width: max(43, toolMetrics.compactButtonSize * 2 + 1), height: toolMetrics.footerControlHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New…")) {
                editorSession = ProtobufRuleEditorSession(mode: .create)
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button(String(localized: "Edit…")) {
                openEditorForSelection()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(mappingStore.selectedRuleID == nil)

            Button(String(localized: "Duplicate")) {
                mappingStore.duplicateSelectedRule()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(mappingStore.selectedRuleID == nil)

            Button(toggleLabel) {
                if let id = mappingStore.selectedRuleID {
                    mappingStore.toggleRule(id: id)
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(mappingStore.selectedRuleID == nil)

            Divider()

            Button(String(localized: "Delete"), role: .destructive) {
                mappingStore.removeSelectedRule()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(mappingStore.selectedRuleID == nil)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More"))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        Button(String(localized: "Edit…")) {
            if let id = ids.first {
                openEditorForRule(id)
            }
        }
        Button(String(localized: "Duplicate")) {
            mappingStore.selectedRuleID = ids.first
            mappingStore.duplicateSelectedRule()
        }
        Button(toggleLabel) {
            if let id = ids.first {
                mappingStore.toggleRule(id: id)
            }
        }
        Divider()
        Button(String(localized: "Delete"), role: .destructive) {
            if let id = ids.first {
                mappingStore.removeRule(id: id)
            }
        }
    }

    private func openEditorForSelection() {
        guard let selectedRule = mappingStore.selectedRule else {
            return
        }
        editorSession = ProtobufRuleEditorSession(mode: .edit(selectedRule))
    }

    private func openEditorForRule(_ id: UUID) {
        guard let rule = mappingStore.rules.first(where: { $0.id == id }) else {
            return
        }
        mappingStore.selectedRuleID = id
        editorSession = ProtobufRuleEditorSession(mode: .edit(rule))
    }

    private func saveRule(_ rule: ProtobufMappingRule) {
        do {
            switch editorSession?.mode {
            case .create:
                try mappingStore.addRule(rule)
            case .edit:
                try mappingStore.updateRule(rule)
            case nil:
                break
            }
            editorSession = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ProtobufRuleEditorSheet

private struct ProtobufRuleEditorSheet: View {
    // MARK: Internal

    let session: ProtobufRuleEditorSession
    let schemas: [ProtobufSchemaDescriptor]
    let canUploadSchema: Bool
    let onAddSchema: () -> Void
    let onSave: (ProtobufMappingRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            matchingRuleSection
            protobufSection
            footer
        }
        .font(toolMetrics.font())
        .padding(28)
        .frame(width: 1_040)
        .onAppear(perform: loadSession)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var ruleID = UUID()
    @State private var urlPattern = "/v1/*"
    @State private var method: HTTPMethodFilter = .any
    @State private var matchType: RuleMatchType = .wildcard
    @State private var includeSubpaths = true
    @State private var schemaID: UUID?
    @State private var messageType = ""
    @State private var useDifferentMessageTypes = false
    @State private var requestMessageType = ""
    @State private var responseMessageType = ""
    @State private var payloadEncoding: ProtobufPayloadEncoding = .auto

    private var sessionButtonTitle: String {
        switch session.mode {
        case .create:
            String(localized: "Add")
        case .edit:
            String(localized: "Save")
        }
    }

    private var matchingRuleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Matching Rule"))
                .font(.system(size: max(17, toolMetrics.bodyFontSize + 4), weight: .medium))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(String(localized: "Matching Rule:"))
                        .frame(width: 150, alignment: .trailing)
                    TextField(String(localized: "/v1/*"), text: $urlPattern)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    Spacer()
                        .frame(width: 150)
                    Picker(String(localized: "Method"), selection: $method) {
                        ForEach(HTTPMethodFilter.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .frame(width: 140)

                    Picker(String(localized: "Match Type"), selection: $matchType) {
                        ForEach(RuleMatchType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .frame(width: 170)

                    Text(String(localized: "Support wildcard * and ?."))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Test your Rule")) {}
                        .buttonStyle(.link)
                }

                HStack {
                    Spacer()
                        .frame(width: 150)
                    Toggle(String(localized: "Include all subpaths of this URL"), isOn: $includeSubpaths)
                        .toggleStyle(.checkbox)
                }
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var protobufSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Protobuf"))
                .font(.system(size: max(17, toolMetrics.bodyFontSize + 4), weight: .medium))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(String(localized: "Schema:"))
                        .frame(width: 150, alignment: .trailing)
                    Button(String(localized: "Add Schema…")) {
                        onAddSchema()
                    }
                    .disabled(!canUploadSchema)

                    if !canUploadSchema {
                        Label(String(localized: "Schema upload unavailable"), systemImage: "lock.fill")
                            .font(toolMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Text(String(localized: "Message Type:"))
                        .frame(width: 150, alignment: .trailing)
                    Picker(String(localized: "Schema"), selection: $schemaID) {
                        Text(String(localized: "Not selected")).tag(UUID?.none)
                        ForEach(schemas) { schema in
                            Text(schema.fileName).tag(Optional(schema.id))
                        }
                    }
                    .frame(width: 240)
                    TextField(String(localized: "package.Message"), text: $messageType)
                        .textFieldStyle(.roundedBorder)
                    if schemaID == nil {
                        Label(
                            String(localized: "Not found in Schema List"),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                        .frame(width: 162)
                    Text(String(localized: "If the Message Type does not exist, add the Schema first."))
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                        .frame(width: 162)
                    Toggle(
                        String(localized: "Use different Message Type for Request / Response"),
                        isOn: $useDifferentMessageTypes
                    )
                    .toggleStyle(.checkbox)
                }

                if useDifferentMessageTypes {
                    HStack(spacing: 12) {
                        Text(String(localized: "Request:"))
                            .frame(width: 150, alignment: .trailing)
                        TextField(String(localized: "package.Request"), text: $requestMessageType)
                            .textFieldStyle(.roundedBorder)
                        Text(String(localized: "Response:"))
                        TextField(String(localized: "package.Response"), text: $responseMessageType)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 12) {
                    Text(String(localized: "Payload Type:"))
                        .frame(width: 150, alignment: .trailing)
                    Picker(String(localized: "Payload Type"), selection: $payloadEncoding) {
                        ForEach(ProtobufPayloadEncoding.allCases) { encoding in
                            Text(encoding.displayName).tag(encoding)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                }
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var footer: some View {
        HStack {
            Button {
                // Help intentionally mirrors the reference window's compact affordance.
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(String(localized: "Cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(sessionButtonTitle) {
                onSave(makeRule())
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func loadSession() {
        guard case let .edit(rule) = session.mode else {
            return
        }
        ruleID = rule.id
        urlPattern = rule.urlPattern
        method = rule.method
        matchType = rule.matchType
        includeSubpaths = rule.includeSubpaths
        schemaID = rule.schemaID
        messageType = rule.messageType
        requestMessageType = rule.requestMessageType ?? ""
        responseMessageType = rule.responseMessageType ?? ""
        useDifferentMessageTypes = rule.requestMessageType != nil || rule.responseMessageType != nil
        payloadEncoding = rule.payloadEncoding
    }

    private func makeRule() -> ProtobufMappingRule {
        ProtobufMappingRule(
            id: ruleID,
            urlPattern: urlPattern,
            method: method,
            matchType: matchType,
            includeSubpaths: includeSubpaths,
            schemaID: schemaID,
            messageType: messageType,
            requestMessageType: useDifferentMessageTypes ? requestMessageType : nil,
            responseMessageType: useDifferentMessageTypes ? responseMessageType : nil,
            payloadEncoding: payloadEncoding
        )
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
