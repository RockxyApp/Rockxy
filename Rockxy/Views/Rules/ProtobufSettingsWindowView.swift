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

// MARK: - ProtobufLocalOnlyNotice

/// Capability banner shared by the Protobuf mapping and schema windows.
struct ProtobufLocalOnlyNotice: View {
    // MARK: Internal

    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text(message)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.07))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - ProtobufSettingsWindowView

struct ProtobufSettingsWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ProtobufLocalOnlyNotice(message: Self.capabilityNotice)
            Divider()
            rulesTable
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496),
            minHeight: max(560, toolMetrics.bodyFontSize * 16 + 344)
        )
        .sheet(item: $editorSession) { session in
            ProtobufRuleEditorSheet(
                session: session,
                schemas: schemaStore.schemas,
                onSave: saveRule
            )
            .environment(\.appUIDisplayMetrics, appMetrics)
        }
    }

    // MARK: Private

    private static var capabilityNotice: String {
        String(
            localized:
            """
            Requests whose URL matches an enabled definition open in the Protobuf tab decoded as its \
            message type. Client WebSocket frames use the request type and server frames the response \
            type. Definitions and schemas are stored locally on this Mac.
            """, bundle: RockxyLocalization.bundle
        )
    }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var mappingStore = ProtobufMappingRuleStore.shared
    @State private var schemaStore = ProtobufSchemaStore.shared
    @State private var editorSession: ProtobufRuleEditorSession?

    private var footerHint: String {
        let countText = String(AttributedString(
            localized: "^[\(mappingStore.rules.count) definition](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
        return "\(countText) · ⌘N \(String(localized: "New", bundle: RockxyLocalization.bundle)) · ⌘↩ \(String(localized: "Edit", bundle: RockxyLocalization.bundle))"
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    /// Whether a definition takes effect: disabled, missing a type, naming a type that no
    /// imported schema defines, or active.
    private func runtimeStatus(for rule: ProtobufMappingRule) -> (title: String, color: Color) {
        guard rule.isEnabled else {
            return (String(localized: "Disabled", bundle: RockxyLocalization.bundle), .secondary)
        }
        let names = [rule.messageType, rule.requestMessageType ?? "", rule.responseMessageType ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else {
            return (String(localized: "Best guess", bundle: RockxyLocalization.bundle), .secondary)
        }
        let known = schemaStore.combinedSchema().messages
        guard names.allSatisfy({ known[$0] != nil }) else {
            return (String(localized: "Type not found", bundle: RockxyLocalization.bundle), .orange)
        }
        return (String(localized: "Active", bundle: RockxyLocalization.bundle), .green)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Protobuf Mapping", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))
                Text(String(
                    localized: "Associate a request pattern with a Protobuf message type and schema.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var rulesTable: some View {
        Table(mappingStore.rules, selection: $mappingStore.selectedRuleID) {
            TableColumn(String(localized: "Status", bundle: RockxyLocalization.bundle)) { rule in
                let status = runtimeStatus(for: rule)
                Text(status.title)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(status.color)
                    .help(status.title)
            }
            .width(min: 94, ideal: 120)

            TableColumn(String(localized: "URL", bundle: RockxyLocalization.bundle)) { rule in
                Text(rule.urlPattern)
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rule.urlPattern)
            }
            .width(min: 160, ideal: 240)

            TableColumn(String(localized: "Method", bundle: RockxyLocalization.bundle)) { rule in
                Text(rule.method.displayName)
            }
            .width(min: max(96, toolMetrics.bodyFontSize * 6), ideal: max(120, toolMetrics.bodyFontSize * 8))

            TableColumn(String(localized: "Payload", bundle: RockxyLocalization.bundle)) { rule in
                Text(rule.payloadEncoding.displayName)
            }
            .width(min: max(120, toolMetrics.bodyFontSize * 8), ideal: max(150, toolMetrics.bodyFontSize * 10))

            TableColumn(String(localized: "Message Type", bundle: RockxyLocalization.bundle)) { rule in
                Text(rule.messageType.isEmpty ? String(localized: "Auto", bundle: RockxyLocalization.bundle) : rule
                    .messageType)
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 150, ideal: 190)

            TableColumn(String(localized: "Schema", bundle: RockxyLocalization.bundle)) { rule in
                schemaCell(for: rule)
            }
            .width(min: 150, ideal: 180)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            tableContextMenu(ids: ids)
        } primaryAction: { ids in
            if let id = ids.first {
                openEditorForRule(id)
            }
        }
        .overlay {
            if mappingStore.rules.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Mapping Definitions", bundle: RockxyLocalization.bundle),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(String(
                        localized: "Click \"+\" or press ⌘N to add a definition.",
                        bundle: RockxyLocalization.bundle
                    ))
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(minHeight: toolMetrics.tableRowHeight * 8, maxHeight: .infinity)
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: toolMetrics.controlSpacing) {
                footerLeadingContent
                Spacer()
                footerActions
            }
            VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                footerLeadingContent
                HStack(spacing: toolMetrics.controlSpacing) {
                    Spacer()
                    footerActions
                }
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var footerLeadingContent: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            addRemoveControl
            Text(footerHint)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
    }

    private var footerActions: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Button(String(localized: "Local Schemas…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "protobufSchemaList")
            }
            .rockxyGlassButtonStyle()
            moreMenu
        }
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
            .help(String(localized: "New Definition", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "New mapping definition", bundle: RockxyLocalization.bundle))

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
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(mappingStore.selectedRuleID == nil)
            .help(String(localized: "Delete Definition", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(
                localized: "Delete selected mapping definition",
                bundle: RockxyLocalization.bundle
            ))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(width: max(43, toolMetrics.compactButtonSize * 2 + 1), height: toolMetrics.footerControlHeight)
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New…", bundle: RockxyLocalization.bundle)) {
                editorSession = ProtobufRuleEditorSession(mode: .create)
            }

            Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
                openEditorForSelection()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(mappingStore.selectedRuleID == nil)

            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                mappingStore.duplicateSelectedRule()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(mappingStore.selectedRuleID == nil)

            Divider()

            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                mappingStore.removeSelectedRule()
            }
            .disabled(mappingStore.selectedRuleID == nil)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More", bundle: RockxyLocalization.bundle))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .rockxyGlassButtonStyle()
        .fixedSize()
    }

    private func schemaCell(for rule: ProtobufMappingRule) -> some View {
        let reference = mappingStore.schemaReference(for: rule.schemaID, schemas: schemaStore.schemas)
        let color: Color = switch reference {
        case .notSelected: .secondary
        case .selected: .primary
        case .missing: .orange
        }
        return HStack(spacing: 5) {
            if reference == .missing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: toolMetrics.smallIconFontSize))
                    .foregroundStyle(.orange)
            }
            Text(reference.displayLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(color)
        }
        .help(reference.displayLabel)
    }

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first, mappingStore.rules.contains(where: { $0.id == id }) {
            Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
                openEditorForRule(id)
            }
            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                mappingStore.duplicateRule(id: id)
            }
            Divider()
            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
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

    private func saveRule(_ rule: ProtobufMappingRule) throws {
        switch editorSession?.mode {
        case .create:
            try mappingStore.addRule(rule)
        case .edit:
            try mappingStore.updateRule(rule)
        case nil:
            throw ProtobufMappingRuleStoreError.ruleNoLongerExists
        }
    }
}

// MARK: - ProtobufRuleEditorSheet

private struct ProtobufRuleEditorSheet: View {
    // MARK: Internal

    enum Field: Hashable {
        case url
        case messageType
        case requestMessageType
        case responseMessageType
    }

    let session: ProtobufRuleEditorSession
    let schemas: [ProtobufSchemaDescriptor]
    let onSave: (ProtobufMappingRule) throws -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing + 3) {
                    Text(editorTitle)
                        .font(toolMetrics.font(weight: .medium))
                    Text(
                        String(
                            localized: "Matching requests and WebSocket frames decode as this message type in the Protobuf tab.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    matchingRuleSection
                    protobufSection
                }
                .padding(.horizontal, toolMetrics.formHorizontalPadding)
                .padding(.vertical, toolMetrics.formVerticalPadding)
            }

            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(720, toolMetrics.bodyFontSize * 24 + 432),
            minHeight: max(460, toolMetrics.bodyFontSize * 14 + 278)
        )
        .onAppear(perform: loadSession)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @FocusState private var focusedField: Field?
    @State private var ruleID = UUID()
    @State private var isEnabled = true
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
    @State private var inlineError: String?

    private var editorTitle: String {
        switch session.mode {
        case .create:
            String(localized: "New Mapping Definition", bundle: RockxyLocalization.bundle)
        case .edit:
            String(localized: "Edit Mapping Definition", bundle: RockxyLocalization.bundle)
        }
    }

    private var sessionButtonTitle: String {
        switch session.mode {
        case .create:
            String(localized: "Add", bundle: RockxyLocalization.bundle)
        case .edit:
            String(localized: "Save", bundle: RockxyLocalization.bundle)
        }
    }

    /// Message types from the chosen schema, or from every imported schema when none is chosen.
    private var availableMessageTypes: [String] {
        let store = ProtobufSchemaStore.shared
        if let schemaID, let schema = schemas.first(where: { $0.id == schemaID }) {
            return store.messageNames(for: schema)
        }
        return store.combinedSchema().messageNames
    }

    private func messageTypeMenu(_ binding: Binding<String>) -> some View {
        Menu {
            ForEach(availableMessageTypes, id: \.self) { name in
                Button(name) {
                    binding.wrappedValue = name
                }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(availableMessageTypes.isEmpty)
        .help(String(localized: "Choose a message type from the imported schemas", bundle: RockxyLocalization.bundle))
        .accessibilityLabel(String(localized: "Choose message type", bundle: RockxyLocalization.bundle))
    }

    private var schemaReference: ProtobufSchemaReference {
        guard let schemaID else {
            return .notSelected
        }
        guard let schema = schemas.first(where: { $0.id == schemaID }) else {
            return .missing
        }
        return .selected(schema.fileName)
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var matchingRuleSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Matching Rule", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                fieldGroup(String(localized: "URL pattern", bundle: RockxyLocalization.bundle)) {
                    TextField("/v1/*", text: $urlPattern)
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font(monospaced: true))
                        .focused($focusedField, equals: .url)
                        .accessibilityLabel(String(localized: "URL pattern", bundle: RockxyLocalization.bundle))
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
                        inlineField(String(localized: "Method", bundle: RockxyLocalization.bundle)) {
                            methodPicker
                        }
                        inlineField(String(localized: "Match type", bundle: RockxyLocalization.bundle)) {
                            matchTypePicker
                        }
                        wildcardHint
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                        inlineField(String(localized: "Method", bundle: RockxyLocalization.bundle)) {
                            methodPicker
                        }
                        inlineField(String(localized: "Match type", bundle: RockxyLocalization.bundle)) {
                            matchTypePicker
                        }
                        wildcardHint
                    }
                }

                Toggle(
                    String(localized: "Include all subpaths of this URL", bundle: RockxyLocalization.bundle),
                    isOn: $includeSubpaths
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font())
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var methodPicker: some View {
        Picker("", selection: $method) {
            ForEach(HTTPMethodFilter.allCases) { method in
                Text(method.displayName).tag(method)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(
            width: max(toolMetrics.menuWidth(140), toolMetrics.bodyFontSize * 8),
            height: toolMetrics.formControlHeight
        )
        .accessibilityLabel(String(localized: "HTTP method", bundle: RockxyLocalization.bundle))
    }

    private var matchTypePicker: some View {
        Picker("", selection: $matchType) {
            ForEach(RuleMatchType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(
            width: max(toolMetrics.menuWidth(160), toolMetrics.bodyFontSize * 10),
            height: toolMetrics.formControlHeight
        )
        .accessibilityLabel(String(localized: "Match type", bundle: RockxyLocalization.bundle))
    }

    @ViewBuilder private var wildcardHint: some View {
        if matchType == .wildcard {
            Text(String(localized: "Supports * and ?.", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
    }

    private var protobufSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Protobuf", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
                    inlineField(String(localized: "Schema", bundle: RockxyLocalization.bundle)) {
                        Picker("", selection: $schemaID) {
                            Text(String(localized: "Not selected", bundle: RockxyLocalization.bundle)).tag(UUID?.none)
                            if let schemaID, !schemas.contains(where: { $0.id == schemaID }) {
                                Text(String(localized: "Missing Schema", bundle: RockxyLocalization.bundle))
                                    .tag(Optional(schemaID))
                            }
                            ForEach(schemas) { schema in
                                Text(schema.fileName).tag(Optional(schema.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(
                            width: max(toolMetrics.menuWidth(240), toolMetrics.bodyFontSize * 12),
                            height: toolMetrics.formControlHeight
                        )
                        .accessibilityLabel(String(localized: "Local schema", bundle: RockxyLocalization.bundle))
                    }
                    if schemaReference == .missing {
                        Label(
                            String(localized: "Missing Schema", bundle: RockxyLocalization.bundle),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.orange)
                    }
                    Spacer()
                }

                fieldGroup(String(localized: "Message type", bundle: RockxyLocalization.bundle)) {
                    HStack(spacing: 4) {
                        TextField("package.Message", text: $messageType)
                            .textFieldStyle(.roundedBorder)
                            .font(toolMetrics.font(monospaced: true))
                            .focused($focusedField, equals: .messageType)
                            .accessibilityLabel(String(localized: "Message type", bundle: RockxyLocalization.bundle))
                        messageTypeMenu($messageType)
                    }
                }

                Toggle(
                    String(
                        localized: "Use different message types for request and response",
                        bundle: RockxyLocalization.bundle
                    ),
                    isOn: $useDifferentMessageTypes
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font())

                if useDifferentMessageTypes {
                    HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                        fieldGroup(String(localized: "Request", bundle: RockxyLocalization.bundle)) {
                            HStack(spacing: 4) {
                                TextField("package.Request", text: $requestMessageType)
                                    .textFieldStyle(.roundedBorder)
                                    .font(toolMetrics.font(monospaced: true))
                                    .focused($focusedField, equals: .requestMessageType)
                                    .accessibilityLabel(String(
                                        localized: "Request message type",
                                        bundle: RockxyLocalization.bundle
                                    ))
                                messageTypeMenu($requestMessageType)
                            }
                        }
                        fieldGroup(String(localized: "Response", bundle: RockxyLocalization.bundle)) {
                            HStack(spacing: 4) {
                                TextField("package.Response", text: $responseMessageType)
                                    .textFieldStyle(.roundedBorder)
                                    .font(toolMetrics.font(monospaced: true))
                                    .focused($focusedField, equals: .responseMessageType)
                                    .accessibilityLabel(String(
                                        localized: "Response message type",
                                        bundle: RockxyLocalization.bundle
                                    ))
                                messageTypeMenu($responseMessageType)
                            }
                        }
                    }
                }

                inlineField(String(localized: "Payload", bundle: RockxyLocalization.bundle)) {
                    if toolMetrics.bodyFontSize >= 20 {
                        Picker("", selection: $payloadEncoding) {
                            payloadEncodingOptions
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(
                            width: max(toolMetrics.menuWidth(240), toolMetrics.bodyFontSize * 12),
                            height: toolMetrics.formControlHeight
                        )
                        .accessibilityLabel(String(localized: "Payload encoding", bundle: RockxyLocalization.bundle))
                    } else {
                        Picker("", selection: $payloadEncoding) {
                            payloadEncodingOptions
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()
                        .frame(minHeight: toolMetrics.formControlHeight)
                        .accessibilityLabel(String(localized: "Payload encoding", bundle: RockxyLocalization.bundle))
                    }
                }
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var payloadEncodingOptions: some View {
        ForEach(ProtobufPayloadEncoding.allCases) { encoding in
            Text(encoding.displayName).tag(encoding)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let inlineError {
                Label(inlineError, systemImage: "exclamationmark.triangle.fill")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    attemptSave()
                } label: {
                    footerButtonLabel(sessionButtonTitle)
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
            }
        }
        .padding(.horizontal, toolMetrics.formHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    private func inlineField(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            content()
        }
    }

    private func fieldGroup(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
                .frame(height: toolMetrics.formControlHeight)
                .frame(maxWidth: .infinity)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                width: max(64, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 3),
                height: max(16, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
            )
    }

    private func loadSession() {
        guard case let .edit(rule) = session.mode else {
            Task { @MainActor in
                await Task.yield()
                focusedField = .url
            }
            return
        }
        ruleID = rule.id
        isEnabled = rule.isEnabled
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
        let base = ProtobufMappingRule(id: ruleID, isEnabled: isEnabled, urlPattern: urlPattern)
        return base.withEditedFields(
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

    private func attemptSave() {
        let rule = makeRule()
        do {
            try ProtobufMappingRuleStore.validate(rule)
        } catch let error as ProtobufMappingRuleValidationError {
            inlineError = error.errorDescription
            focusedField = focusedField(for: error)
            return
        } catch {
            inlineError = error.localizedDescription
            return
        }

        do {
            try onSave(rule)
            dismiss()
        } catch {
            inlineError = error.localizedDescription
        }
    }

    private func focusedField(for error: ProtobufMappingRuleValidationError) -> Field {
        guard error == .invalidMessageType else {
            return .url
        }
        if !ProtobufMappingRuleStore.isMessageTypeValid(messageType) {
            return .messageType
        }
        if useDifferentMessageTypes,
           !ProtobufMappingRuleStore.isMessageTypeValid(requestMessageType)
        {
            return .requestMessageType
        }
        return .responseMessageType
    }
}
