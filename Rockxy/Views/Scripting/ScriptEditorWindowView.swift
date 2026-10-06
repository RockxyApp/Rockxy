import SwiftUI

/// The Script Editor window. Intent-dependent: it edits whatever script the
/// Scripting List hands off via `ScriptEditorSession`. Layout is a compact
/// matching-configuration GroupBox over a resizable code-editor / console
/// HSplitView, with a restrained bottom action bar. All chrome scales from
/// `ToolWindowDisplayMetrics` so 13, 20 and 28-point Appearance sizes stay
/// readable.
struct ScriptEditorWindowView: View {
    // MARK: Internal

    var body: some View {
        content
            .font(toolMetrics.font())
            .frame(
                minWidth: max(900, min(1_180, toolMetrics.bodyFontSize * 20 + 640)),
                minHeight: max(620, min(720, toolMetrics.bodyFontSize * 10 + 480))
            )
            .onAppear { consumePendingIntent() }
            .onChange(of: ScriptEditorSession.shared.contextVersion) { _, _ in
                consumePendingIntent()
            }
            .confirmationDialog(
                String(localized: "Unsaved Changes", bundle: RockxyLocalization.bundle),
                isPresented: $viewModel.isShowingUnsavedSwitchPrompt,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Save & Switch", bundle: RockxyLocalization.bundle)) {
                    Task { await viewModel.resolveUnsavedSwitch(.saveAndSwitch) }
                }
                Button(String(localized: "Discard Changes", bundle: RockxyLocalization.bundle), role: .destructive) {
                    Task { await viewModel.resolveUnsavedSwitch(.discard) }
                }
                Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {
                    Task { await viewModel.resolveUnsavedSwitch(.cancel) }
                }
            } message: {
                Text(
                    String(
                        localized: "“\(viewModel.currentScriptDisplayName)” has unsaved changes. Save them before switching scripts?",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
            .confirmationDialog(
                String(localized: "Reset Shared State", bundle: RockxyLocalization.bundle),
                isPresented: $isShowingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Reset Shared State", bundle: RockxyLocalization.bundle), role: .destructive) {
                    viewModel.resetSharedState()
                }
                Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {}
            } message: {
                Text(
                    String(
                        localized: "This removes every stored shared value for “\(viewModel.currentScriptDisplayName)”. This cannot be undone.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var viewModel = ScriptEditorViewModel()
    @State private var isShowingResetConfirmation = false

    // MARK: - Derived

    private var statusLineText: String {
        if viewModel.isDirty {
            return String(localized: "Unsaved changes", bundle: RockxyLocalization.bundle)
        }
        return viewModel.statusMessage
    }

    private var statusDotColor: Color {
        if viewModel.isDirty {
            return .orange
        }
        switch viewModel.statusTone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var methodMenuWidth: CGFloat {
        max(90, toolMetrics.bodyFontSize * 5.2)
    }

    private var patternModeMenuWidth: CGFloat {
        max(150, toolMetrics.bodyFontSize * 8.5)
    }

    private var footerLabelHeight: CGFloat {
        max(16, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
    }

    // MARK: - Top-level content routing

    @ViewBuilder private var content: some View {
        switch viewModel.contentState {
        case .awaitingIntent:
            unavailableState
        case .loading:
            loadingState
        case .editing:
            editorContent
        }
    }

    private var unavailableState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Script Loaded", bundle: RockxyLocalization.bundle), systemImage: "curlybraces")
        } description: {
            Text(String(
                localized: "Open a script from the Scripting window to edit it here.",
                bundle: RockxyLocalization.bundle
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: toolMetrics.controlSpacing) {
            ProgressView()
            Text(String(localized: "Loading script…", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            matchingConfigurationSection
            Divider()
            HSplitView {
                ScriptCodeEditor(text: $viewModel.code, editorSettings: toolMetrics.codeEditorSettings)
                    .frame(minWidth: 360)
                    .layoutPriority(1)
                    .clipped()
                if viewModel.consolePanelVisible {
                    ScriptConsolePanel(viewModel: viewModel)
                        .frame(minWidth: 220, idealWidth: 300)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            actionBar
        }
    }

    // MARK: - Matching configuration

    private var matchingConfigurationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                labeledField(String(localized: "Name", bundle: RockxyLocalization.bundle)) {
                    TextField(
                        String(localized: "Untitled Script", bundle: RockxyLocalization.bundle),
                        text: $viewModel.name
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font())
                    .frame(minHeight: toolMetrics.formControlHeight)
                    .accessibilityLabel(String(localized: "Script name", bundle: RockxyLocalization.bundle))
                }

                labeledField(String(localized: "URL Pattern", bundle: RockxyLocalization.bundle)) {
                    ViewThatFits(in: .horizontal) {
                        patternControls(stacked: false)
                        patternControls(stacked: true)
                    }
                }

                labeledField(String(localized: "GraphQL Operation", bundle: RockxyLocalization.bundle)) {
                    TextField(
                        String(localized: "Any operation", bundle: RockxyLocalization.bundle),
                        text: $viewModel.graphQLOperationName
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: max(260, toolMetrics.bodyFontSize * 16), alignment: .leading)
                    .accessibilityLabel(String(
                        localized: "GraphQL operation name to match",
                        bundle: RockxyLocalization.bundle
                    ))
                    .help(String(
                        localized: "Run this script only for GraphQL requests with this exact operation name. Leave empty to run for every matching URL.",
                        bundle: RockxyLocalization.bundle
                    ))
                }

                testMatchRow
                Divider()
                runOptionsGroup
                statusRow
            }
            .padding(toolMetrics.controlSpacing)
        } label: {
            Text(String(localized: "Matching Configuration", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var testMatchRow: some View {
        labeledField(String(localized: "Test URL", bundle: RockxyLocalization.bundle)) {
            ViewThatFits(in: .horizontal) {
                testMatchControls(stacked: false)
                testMatchControls(stacked: true)
            }
        }
    }

    private var runOptionsGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: toolMetrics.controlSpacing) {
                    runOptionsLabel
                    runOptionToggles
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                    runOptionsLabel
                    runOptionToggles
                }
            }
            Text(String(localized: "A Mock API script runs on Request and replaces the response.", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var runOptionsLabel: some View {
        Text(String(localized: "Run script on:", bundle: RockxyLocalization.bundle))
            .font(toolMetrics.font(weight: .medium))
            .fixedSize()
    }

    private var runOptionToggles: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Toggle(isOn: Binding(
                get: { viewModel.runOnRequest },
                set: { viewModel.setRunOnRequest($0) }
            )) { Text(String(localized: "Request", bundle: RockxyLocalization.bundle)) }
                .toggleStyle(.checkbox)
            Toggle(isOn: $viewModel.runOnResponse) { Text(String(localized: "Response", bundle: RockxyLocalization.bundle)) }
                .toggleStyle(.checkbox)
            Toggle(isOn: Binding(
                get: { viewModel.runAsMock },
                set: { viewModel.setRunAsMock($0) }
            )) { Text(String(localized: "Mock API", bundle: RockxyLocalization.bundle)) }
                .toggleStyle(.checkbox)
        }
        .fixedSize()
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
            Text(statusLineText.isEmpty ? " " : statusLineText)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Menus

    private var methodMenu: some View {
        Menu {
            ForEach(Array(ScriptEditorMenuContent.methodSections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { method in
                    Button {
                        viewModel.method = method
                    } label: {
                        menuCheckmarkLabel(method.label, isSelected: viewModel.method == method)
                    }
                }
                if index < ScriptEditorMenuContent.methodSections.count - 1 {
                    Divider()
                }
            }
        } label: {
            dataEntryMenuLabel(viewModel.method.label, width: methodMenuWidth)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "HTTP method", bundle: RockxyLocalization.bundle))
    }

    private var patternModeMenu: some View {
        Menu {
            ForEach(Array(ScriptEditorMenuContent.patternModeSections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { mode in
                    Button {
                        viewModel.patternMode = mode
                    } label: {
                        menuCheckmarkLabel(mode.title, isSelected: viewModel.patternMode == mode)
                    }
                }
                if index < ScriptEditorMenuContent.patternModeSections.count - 1 {
                    Divider()
                }
            }
        } label: {
            dataEntryMenuLabel(viewModel.patternMode.title, width: patternModeMenuWidth)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Pattern mode", bundle: RockxyLocalization.bundle))
    }

    private var consoleFilterMenu: some View {
        Menu {
            ForEach(ScriptConsoleLogLevel.allCases) { level in
                Toggle(isOn: Binding(
                    get: { viewModel.consoleFilter.contains(level) },
                    set: { newValue in
                        if newValue {
                            viewModel.consoleFilter.insert(level)
                        } else {
                            viewModel.consoleFilter.remove(level)
                        }
                    }
                )) { Text(level.title) }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: toolMetrics.compactIconFontSize))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(String(localized: "Filter console levels", bundle: RockxyLocalization.bundle))
        .accessibilityLabel(String(localized: "Filter console levels", bundle: RockxyLocalization.bundle))
    }

    // MARK: - Action bar

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: toolMetrics.controlSpacing) {
                secondaryActionControls
                Spacer(minLength: toolMetrics.controlSpacing)
                consoleActionControls
                primaryActionControls
            }
            VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                HStack(spacing: toolMetrics.controlSpacing) {
                    secondaryActionControls
                    Spacer(minLength: toolMetrics.controlSpacing)
                    consoleActionControls
                }
                HStack(spacing: toolMetrics.controlSpacing) {
                    Spacer(minLength: 0)
                    primaryActionControls
                }
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var secondaryActionControls: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            actionMenu
            Button {
                viewModel.beautify()
            } label: {
                footerActionLabel(String(localized: "Beautify", bundle: RockxyLocalization.bundle))
            }
            .rockxyGlassButtonStyle()
            .fixedSize()

            Button {
                viewModel.insertHeaderExample()
            } label: {
                footerActionLabel(String(localized: "Insert Header Example", bundle: RockxyLocalization.bundle))
            }
            .rockxyGlassButtonStyle()
            .fixedSize()
        }
    }

    private var actionMenu: some View {
        Menu {
            Button(String(localized: "Toggle Console", bundle: RockxyLocalization.bundle)) {
                viewModel.toggleConsolePanel()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Button(String(localized: "Reset Shared State…", bundle: RockxyLocalization.bundle), role: .destructive) {
                isShowingResetConfirmation = true
            }
            .disabled(viewModel.pluginID == nil)
        } label: {
            Label(String(localized: "Actions", bundle: RockxyLocalization.bundle), systemImage: "ellipsis.circle")
                .font(toolMetrics.font())
                .frame(minHeight: footerLabelHeight)
        }
        .menuIndicator(.hidden)
        .rockxyGlassButtonStyle()
        .fixedSize()
    }

    private var consoleActionControls: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            consoleFilterMenu

            Button {
                viewModel.clearConsole()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: toolMetrics.compactIconFontSize))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(viewModel.consoleEntries.isEmpty)
            .help(String(localized: "Clear console", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Clear console", bundle: RockxyLocalization.bundle))

            Divider()
                .frame(height: toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
        }
        .fixedSize()
    }

    private var primaryActionControls: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Button {
                viewModel.validateScript()
            } label: {
                footerActionLabel(String(localized: "Validate", bundle: RockxyLocalization.bundle))
            }
            .rockxyGlassButtonStyle()
            .keyboardShortcut("r", modifiers: .command)
            .fixedSize()

            Button {
                Task { await viewModel.saveAndActivate() }
            } label: {
                footerActionLabel(
                    String(localized: "Save & Activate", bundle: RockxyLocalization.bundle),
                    weight: .semibold
                )
            }
            .rockxyGlassButtonStyle(prominent: true)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(viewModel.isSaving)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func patternControls(stacked: Bool) -> some View {
        let field = TextField("https://api.example.com/v1/*", text: $viewModel.urlPattern)
            .textFieldStyle(.roundedBorder)
            .font(toolMetrics.font(monospaced: true))
            .frame(
                minWidth: max(220, toolMetrics.bodyFontSize * 12),
                minHeight: toolMetrics.formControlHeight
            )
            .accessibilityLabel(String(localized: "URL pattern", bundle: RockxyLocalization.bundle))

        let menus = HStack(spacing: toolMetrics.controlSpacing) {
            methodMenu
            patternModeMenu
            if viewModel.patternMode == .wildcard {
                Toggle(isOn: $viewModel.includeSubpaths) {
                    Text(String(localized: "Include subpaths", bundle: RockxyLocalization.bundle))
                }
                .toggleStyle(.checkbox)
            }
        }
        .fixedSize()

        if stacked {
            VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                field
                menus
            }
        } else {
            HStack(spacing: toolMetrics.controlSpacing) {
                field.frame(maxWidth: .infinity)
                menus
            }
        }
    }

    @ViewBuilder
    private func testMatchControls(stacked: Bool) -> some View {
        let field = TextField("https://api.example.com/v1/users", text: $viewModel.sampleURL)
            .textFieldStyle(.roundedBorder)
            .font(toolMetrics.font(monospaced: true))
            .frame(
                minWidth: max(260, toolMetrics.bodyFontSize * 12),
                minHeight: toolMetrics.formControlHeight
            )
            .accessibilityLabel(String(localized: "Test URL", bundle: RockxyLocalization.bundle))

        let button = Button {
            viewModel.runRuleTest()
        } label: {
            Text(String(localized: "Test Match", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .medium))
                .frame(minHeight: toolMetrics.formControlHeight)
        }
        .rockxyGlassButtonStyle()
        .fixedSize()

        let preview = Group {
            if !viewModel.testRulePreview.isEmpty {
                Text(viewModel.testRulePreview)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .lineLimit(stacked ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if stacked {
            VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                field
                HStack(spacing: toolMetrics.controlSpacing) {
                    button
                    preview
                }
            }
        } else {
            HStack(spacing: toolMetrics.controlSpacing) {
                field.frame(maxWidth: .infinity)
                button
                preview
            }
        }
    }

    // MARK: - Shared label helpers

    private func labeledField(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
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

    private func footerActionLabel(_ title: String, weight: Font.Weight = .regular) -> some View {
        Text(title)
            .font(toolMetrics.font(weight: weight))
            .frame(minHeight: footerLabelHeight)
    }

    private func dataEntryMenuLabel(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(toolMetrics.font())
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
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

    private func consumePendingIntent() {
        if let intent = ScriptEditorSession.shared.consumePending() {
            Task { await viewModel.requestLoad(intent: intent) }
        }
    }
}
