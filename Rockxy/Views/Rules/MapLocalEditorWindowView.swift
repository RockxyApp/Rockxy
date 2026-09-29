import AppKit
import os
import SwiftUI

// Presents the native Map Local rule editor window.
// Split out of `MapLocalWindowView.swift` to keep each file within the length limit.

// MARK: - MapLocalEditorWindowView

struct MapLocalEditorWindowView: View {
    // MARK: Internal

    @State var viewModel = MapLocalEditorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing + 3) {
                    Text(editorTitle)
                        .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))

                    if let provenance = quickCreateProvenance {
                        provenanceBanner(provenance)
                    }

                    ruleDetailsSection
                    responseSourceSection
                }
                .padding(.horizontal, toolMetrics.formHorizontalPadding)
                .padding(.vertical, toolMetrics.formVerticalPadding)
            }

            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496))
        .frame(height: max(680, toolMetrics.bodyFontSize * 20 + 420))
        .navigationTitle(viewModel.windowTitle)
        .onAppear { viewModel.load(context: editorStore.context) }
        .onChange(of: editorStore.draftVersion) { _, _ in
            viewModel.load(context: editorStore.context)
        }
        .alert(
            String(localized: "Map Local", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle)) { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var editorStore = MapLocalEditorStore.shared
    @State private var isSaving = false

    private var editorTitle: String {
        viewModel.existingID == nil
            ? String(localized: "New Map Local Rule", bundle: RockxyLocalization.bundle)
            : String(localized: "Edit Map Local Rule", bundle: RockxyLocalization.bundle)
    }

    private var quickCreateProvenance: String? {
        guard let draft = viewModel.draft else {
            return nil
        }
        if let sourceURL = draft.sourceURL {
            return String(
                localized: "Created from \(draft.sourceMethod ?? "ANY") \(sourceURL.absoluteString)",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(localized: "Created from domain \(draft.sourceHost)", bundle: RockxyLocalization.bundle)
    }

    private var fileStatusColor: Color {
        if viewModel.isCapturedBinary {
            return .blue
        }
        if viewModel.isExternalReference {
            return viewModel.isSelectedFileAvailable ? .green : .orange
        }
        return viewModel.isSelectedFileAvailable ? .green : .secondary
    }

    private var fileStatusMessage: String {
        if viewModel.isCapturedBinary {
            return String(
                localized: "Captured binary response will be written when the rule is saved.",
                bundle: RockxyLocalization.bundle
            )
        }
        if viewModel.isExternalReference {
            if viewModel.isExternalFullHTTPMessage {
                return String(
                    localized: "Full HTTP response file detected — previewing file-owned status, headers, and body.",
                    bundle: RockxyLocalization.bundle
                )
            }
            return viewModel.isSelectedFileAvailable
                ? String(localized: "External file available", bundle: RockxyLocalization.bundle)
                : String(localized: "External file is currently unavailable", bundle: RockxyLocalization.bundle)
        }
        return viewModel.isSelectedFileAvailable
            ? String(localized: "Rockxy-owned response file available", bundle: RockxyLocalization.bundle)
            : String(
                localized: "Rockxy will create this response file when the rule is saved.",
                bundle: RockxyLocalization.bundle
            )
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var localFileResponseDescription: String {
        if viewModel.isInlineResponseEditable {
            return String(
                localized: "Edit the status line, response headers, and body. Rockxy always recalculates Content-Length.",
                bundle: RockxyLocalization.bundle
            )
        }
        if viewModel.isCapturedBinary {
            return String(
                localized: "Edit status and headers here. Captured binary body bytes stay preserved and text after the blank line is ignored.",
                bundle: RockxyLocalization.bundle
            )
        }
        if viewModel.isExternalFullHTTPMessage {
            if viewModel.externalFullMessageHasBinaryBody {
                return String(
                    localized: "Read-only preview. This file controls the status and headers; its binary body is preserved but not shown.",
                    bundle: RockxyLocalization.bundle
                )
            }
            return String(
                localized: "Read-only preview. This file controls the status, ordered headers, and body at request time.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "Edit status and headers here. The body comes from the user-owned file and text after the blank line is ignored.",
            bundle: RockxyLocalization.bundle
        )
    }

    private var ruleDetailsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Rule Details", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                    fieldGroup(String(localized: "Name", bundle: RockxyLocalization.bundle)) {
                        TextField(
                            String(localized: "Untitled", bundle: RockxyLocalization.bundle),
                            text: $viewModel.name
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(String(localized: "Rule name", bundle: RockxyLocalization.bundle))
                    }
                    .frame(width: max(250, toolMetrics.fieldWidth(250)))

                    fieldGroup(String(localized: "URL pattern", bundle: RockxyLocalization.bundle)) {
                        TextField("https://example.com/api/*", text: $viewModel.urlText)
                            .textFieldStyle(.roundedBorder)
                            .font(toolMetrics.font(monospaced: true))
                            .accessibilityLabel(String(localized: "URL pattern", bundle: RockxyLocalization.bundle))
                    }
                    .frame(maxWidth: .infinity)
                }

                if let validationMessage = viewModel.urlValidationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.red)
                }

                MapLocalHTTPSPrerequisiteNotice(
                    isHTTPSPattern: viewModel.isHTTPSPattern,
                    targetHost: viewModel.httpsTargetHost,
                    toolMetrics: toolMetrics
                )

                HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
                    inlineField(String(localized: "Method", bundle: RockxyLocalization.bundle)) {
                        methodMenu
                    }
                    inlineField(String(localized: "Match type", bundle: RockxyLocalization.bundle)) {
                        matchTypeMenu
                    }

                    if viewModel.matchType == .wildcard {
                        Text(String(localized: "Supports * and ?.", bundle: RockxyLocalization.bundle))
                            .font(toolMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if viewModel.matchType == .wildcard {
                    Toggle(
                        String(localized: "Include all subpaths of this URL", bundle: RockxyLocalization.bundle),
                        isOn: $viewModel.includeSubpaths
                    )
                    .toggleStyle(.checkbox)
                }

                inlineField(String(localized: "GraphQL Operation", bundle: RockxyLocalization.bundle)) {
                    TextField(
                        String(localized: "Any operation", bundle: RockxyLocalization.bundle),
                        text: $viewModel.graphQLOperationName
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: max(220, toolMetrics.fieldWidth(220)))
                    .accessibilityLabel(String(
                        localized: "GraphQL operation name to match",
                        bundle: RockxyLocalization.bundle
                    ))
                    .help(String(
                        localized: "Serve this response only for GraphQL requests with this exact operation name. Leave empty to match every request to the URL.",
                        bundle: RockxyLocalization.bundle
                    ))
                }

                if let validationMessage = viewModel.directoryRegexValidationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.red)
                }

                MapLocalRuleTesterSection(viewModel: viewModel, toolMetrics: toolMetrics)

                Divider()

                HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
                    Text(String(localized: "Response delay", bundle: RockxyLocalization.bundle))
                        .foregroundStyle(.secondary)
                    delayMenu
                    if viewModel.delayPreset == .custom {
                        Stepper(
                            String(AttributedString(
                                localized: "^[\(viewModel.customDelaySeconds) second](inflect: true)",
                                bundle: RockxyLocalization.bundle,
                                locale: RockxyLocalization.locale
                            ).characters),
                            value: $viewModel.customDelaySeconds,
                            in: 0 ... 300
                        )
                        .frame(width: toolMetrics.fieldWidth(160))
                    }
                    Spacer()
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

    private var responseSourceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Response Source", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                Picker(
                    String(localized: "Source type", bundle: RockxyLocalization.bundle),
                    selection: $viewModel.targetMode
                ) {
                    Text(MapLocalTargetMode.localFile.displayName).tag(MapLocalTargetMode.localFile)
                    Text(MapLocalTargetMode.localDirectory.displayName).tag(MapLocalTargetMode.localDirectory)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: toolMetrics.menuWidth(240))
                .frame(maxWidth: .infinity, alignment: .center)

                Divider()

                responseStatusRow

                if viewModel.targetMode == .localFile {
                    localFileSection
                } else {
                    localDirectorySection
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

    private var localFileSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            HStack(alignment: .bottom, spacing: toolMetrics.controlSpacing) {
                fieldGroup(String(localized: "Local file", bundle: RockxyLocalization.bundle)) {
                    Text(viewModel.filePath)
                        .font(toolMetrics.font(monospaced: true))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .padding(.horizontal, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        }
                        .help(viewModel.filePath)
                }
                .frame(maxWidth: .infinity)

                Button(String(localized: "Choose…", bundle: RockxyLocalization.bundle)) { viewModel.choosePath() }
                    .frame(height: toolMetrics.formControlHeight)

                fileActionsMenu
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(fileStatusColor)
                    .frame(width: 8, height: 8)
                Text(fileStatusMessage)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.responseContentType)
                    .font(toolMetrics.metadataFont(monospaced: true))
                    .foregroundStyle(.secondary)
                    .help(String(
                        localized: "Configured Content-Type, or the file-extension fallback.",
                        bundle: RockxyLocalization.bundle
                    ))
            }

            if let validationMessage = viewModel.externalFileValidationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.orange)
            }

            MapLocalHTTPResponseSection(
                text: $viewModel.httpMessageText,
                bodyIsEditable: viewModel.isInlineResponseEditable,
                bodyDescription: localFileResponseDescription,
                toolMetrics: toolMetrics,
                messageIsEditable: !viewModel.isExternalFullHTTPMessage
            )
        }
    }

    private var responseStatusRow: some View {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "Status code", bundle: RockxyLocalization.bundle))
                .foregroundStyle(.secondary)
            TextField(
                "",
                value: Binding(
                    get: { viewModel.responseStatusCode },
                    set: { viewModel.setResponseStatusCode($0) }
                ),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 84, height: toolMetrics.formControlHeight)
            .accessibilityLabel(String(localized: "HTTP response status code", bundle: RockxyLocalization.bundle))
            .disabled(viewModel.isExternalFullHTTPMessage)
            Text(viewModel.isExternalFullHTTPMessage
                ? String(
                    localized: "The selected full HTTP response file controls this status code.",
                    bundle: RockxyLocalization.bundle
                )
                : String(
                    localized: "Applied to every response from this rule. Valid range: 100–599.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var localDirectorySection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            fieldGroup(String(localized: "Local directory", bundle: RockxyLocalization.bundle)) {
                HStack(spacing: toolMetrics.controlSpacing) {
                    TextField(
                        String(localized: "Choose a directory", bundle: RockxyLocalization.bundle),
                        text: $viewModel.directoryPath
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    Button(String(localized: "Choose…", bundle: RockxyLocalization.bundle)) { viewModel.choosePath() }
                    Button(String(localized: "Show in Finder", bundle: RockxyLocalization.bundle)) {
                        viewModel.showSelectedPathInFinder()
                    }
                    .disabled(!viewModel.isDirectoryValid)
                }
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isDirectoryValid ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.isDirectoryValid
                    ? String(localized: "Directory available", bundle: RockxyLocalization.bundle)
                    : String(
                        localized: "Choose an available directory to continue.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(
                    String(
                        localized: "Request subpaths resolve to files inside this directory. Root requests and missing files continue to the origin.",
                        bundle: RockxyLocalization.bundle
                    )
                        + " "
                        + String(
                            localized: "Regex directory rules use the first capture group as the relative file path.",
                            bundle: RockxyLocalization.bundle
                        )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))

            MapLocalHTTPResponseSection(
                text: $viewModel.httpMessageText,
                bodyIsEditable: false,
                bodyDescription: String(
                    localized:
                    "Edit status and headers here. Response bodies come from the matched file in this directory; text after the blank line is ignored.",
                    bundle: RockxyLocalization.bundle
                ),
                toolMetrics: toolMetrics
            )
        }
    }

    private var methodMenu: some View {
        Menu {
            ForEach(Array(MapLocalEditorMenuContent.methodSections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { method in
                    Button { viewModel.method = method } label: {
                        menuCheckmarkLabel(method.rawValue, isSelected: viewModel.method == method)
                    }
                }
                if index < MapLocalEditorMenuContent.methodSections.count - 1 {
                    Divider()
                }
            }
        } label: {
            dataEntryMenuLabel(viewModel.method.rawValue, width: toolMetrics.menuWidth(90))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: toolMetrics.menuWidth(90))
    }

    private var matchTypeMenu: some View {
        Menu {
            ForEach(Array(MapLocalEditorMenuContent.matchTypeSections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { matchType in
                    Button { viewModel.matchType = matchType } label: {
                        menuCheckmarkLabel(matchType.displayName, isSelected: viewModel.matchType == matchType)
                    }
                }
                if index < MapLocalEditorMenuContent.matchTypeSections.count - 1 {
                    Divider()
                }
            }
        } label: {
            dataEntryMenuLabel(viewModel.matchType.displayName, width: toolMetrics.menuWidth(150))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: toolMetrics.menuWidth(150))
    }

    private var delayMenu: some View {
        Menu {
            ForEach(Array(MapLocalEditorMenuContent.delaySections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { preset in
                    Button { viewModel.delayPreset = preset } label: {
                        menuCheckmarkLabel(preset.displayName, isSelected: viewModel.delayPreset == preset)
                    }
                }
                if index < MapLocalEditorMenuContent.delaySections.count - 1 {
                    Divider()
                }
            }
        } label: {
            dataEntryMenuLabel(viewModel.delayPreset.displayName, width: toolMetrics.menuWidth(160))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: toolMetrics.menuWidth(160))
    }

    private var fileActionsMenu: some View {
        Menu {
            Button(String(localized: "Show in Finder", bundle: RockxyLocalization.bundle)) {
                viewModel.showSelectedPathInFinder()
            }
            .disabled(!viewModel.isSelectedFileAvailable)
            Divider()
            ForEach(MapLocalExternalEditor.allCases) { editor in
                Button(String(localized: "Open with \(editor.displayName)", bundle: RockxyLocalization.bundle)) {
                    viewModel.openSelectedPath(with: editor)
                }
                .disabled(!viewModel.isSelectedFileAvailable)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: toolMetrics.footerControlHeight, height: toolMetrics.formControlHeight)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help(String(localized: "File Actions", bundle: RockxyLocalization.bundle))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
            }
            .keyboardShortcut(.cancelAction)

            Button {
                saveAndClose()
            } label: {
                footerButtonLabel(
                    isSaving
                        ? String(localized: "Saving…", bundle: RockxyLocalization.bundle)
                        : viewModel.existingID == nil
                        ? String(localized: "Add", bundle: RockxyLocalization.bundle)
                        : String(localized: "Save", bundle: RockxyLocalization.bundle)
                )
            }
            .keyboardShortcut(.defaultAction)
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(!viewModel.isSaveEnabled || isSaving)
        }
        .padding(.horizontal, toolMetrics.formHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    private func provenanceBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
            Text(message)
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(message)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        }
    }

    private func menuCheckmarkLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    private func dataEntryMenuLabel(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .frame(width: width, height: toolMetrics.formControlHeight, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }

    private func inlineField(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
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
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                width: max(64, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 3),
                height: max(16, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
            )
    }

    private func saveAndClose() {
        guard let rule = viewModel.makeRule() else {
            return
        }
        isSaving = true
        Task {
            let outcome: RulePersistenceOutcome
            if viewModel.existingID == nil {
                switch await RulePolicyGate.shared.addRulePersisting(rule) {
                case .quotaExceeded:
                    viewModel.errorMessage = String(
                        localized:
                        "The active Map Local rule limit was reached. Disable another rule and try again.",
                        bundle: RockxyLocalization.bundle
                    )
                    isSaving = false
                    return
                case let .loadFailed(message):
                    // The engine was not mutated. Keep new-rule semantics so a
                    // retry first reloads the user's existing on-disk rules.
                    outcome = .failed(message: message)
                case let .persisted(result):
                    outcome = result
                    if case .failed = result {
                        // The optimistic engine mutation already added this rule under
                        // `rule.id`. Adopt that identity so the next Save updates the same
                        // rule (retry-update) instead of adding a duplicate with a new UUID.
                        viewModel.adoptFailedAddIdentity(rule)
                    }
                }
            } else {
                outcome = await RulePolicyGate.shared.updateRulePersisting(rule)
            }
            isSaving = false
            // Only dismiss when the change was durably written. A failed save
            // keeps the editor open with the error visible so the user does not
            // believe a lost rule was saved.
            if case let .failed(message) = outcome {
                viewModel.errorMessage = message
                return
            }
            dismiss()
        }
    }
}

// MARK: - MapLocalExternalEditor

enum MapLocalExternalEditor: String, CaseIterable, Identifiable {
    case code
    case cursor
    case textEdit
    case xcode

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .code: "Code"
        case .cursor: "Cursor"
        case .textEdit: "TextEdit"
        case .xcode: "Xcode"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .code: "com.microsoft.VSCode"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .textEdit: "com.apple.TextEdit"
        case .xcode: "com.apple.dt.Xcode"
        }
    }
}
