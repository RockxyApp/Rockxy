import AppKit
import CoreGraphics
import Foundation
@testable import Rockxy
import Testing

// MARK: - ToolWindowReadabilityTests

@MainActor
struct ToolWindowReadabilityTests {
    // MARK: Internal

    @Test("Tool window display metrics derive from Appearance font size")
    func toolWindowDisplayMetricsDeriveFromAppearanceFontSize() {
        // swiftlint:disable large_tuple
        let cases: [(
            fontSize: Int,
            body: CGFloat,
            secondary: CGFloat,
            metadata: CGFloat,
            header: CGFloat,
            row: CGFloat,
            footer: CGFloat,
            button: CGFloat,
            icon: CGFloat,
            smallIcon: CGFloat
        )] = [
            (10, 10, 10, 10, 12, 28, 26, 23, 12, 10),
            (12, 12, 11, 10, 12, 28, 26, 23, 12, 10),
            (13, 13, 12, 11, 12, 28, 26, 23, 13, 10),
            (14, 14, 13, 12, 13, 29, 27, 24, 14, 11),
            (20, 20, 19, 18, 19, 35, 33, 30, 20, 17),
            (28, 28, 27, 26, 27, 43, 41, 38, 28, 25),
        ]
        // swiftlint:enable large_tuple

        for item in cases {
            var appUI = AppUISettings()
            appUI.fontSize = item.fontSize
            let metrics = ToolWindowDisplayMetrics(appMetrics: AppUIDisplayMetrics(settings: appUI))

            #expect(metrics.bodyFontSize == item.body)
            #expect(metrics.secondaryFontSize == item.secondary)
            #expect(metrics.metadataFontSize == item.metadata)
            #expect(metrics.tableHeaderFontSize == item.header)
            #expect(metrics.tableRowHeight == item.row)
            #expect(metrics.footerControlHeight == item.footer)
            #expect(metrics.compactButtonSize == item.button)
            #expect(metrics.compactIconFontSize == item.icon)
            #expect(metrics.smallIconFontSize == item.smallIcon)
            #expect(metrics.formControlHeight >= metrics.bodyFontSize + 12)
            #expect(metrics.footerButtonWidth >= 100)
            #expect(metrics.menuWidth(90) >= 90)
            #expect(metrics.fieldWidth(200) >= 200)
        }
    }

    @Test("Tool window code editor settings follow Appearance font size")
    func codeEditorSettingsFollowAppearanceFontSize() {
        var appUI = AppUISettings()
        appUI.fontSize = 20
        appUI.tabWidth = 4
        let metrics = ToolWindowDisplayMetrics(appMetrics: AppUIDisplayMetrics(settings: appUI))

        #expect(metrics.codeEditorSettings.fontSize == 20)
        #expect(metrics.codeEditorSettings.tabWidth == 4)
        #expect(metrics.codeEditorSettings.useMonospacedFont == true)
        #expect(metrics.codeEditorSettings.wordWrap == false)
        #expect(metrics.codeEditorSettings.appKitFont.pointSize == 20)
    }

    @Test("Settings display metrics derive from Appearance font size")
    func settingsDisplayMetricsDeriveFromAppearanceFontSize() {
        // swiftlint:disable large_tuple
        let cases: [(
            fontSize: Int,
            sidebarMin: CGFloat,
            minWidth: CGFloat,
            minHeight: CGFloat,
            labelWidth: CGFloat,
            controlHeight: CGFloat
        )] = [
            (10, 200, 820, 560, 136, 24),
            (12, 200, 820, 560, 136, 24),
            (13, 200, 820, 560, 136, 25),
            (14, 200, 820, 560, 142, 26),
            (20, 230, 886, 560, 178, 32),
            (28, 270, 990, 570, 226, 40),
        ]
        // swiftlint:enable large_tuple

        for item in cases {
            var appUI = AppUISettings()
            appUI.fontSize = item.fontSize
            let metrics = SettingsDisplayMetrics(appMetrics: AppUIDisplayMetrics(settings: appUI))

            #expect(metrics.bodyFontSize == CGFloat(item.fontSize))
            #expect(metrics.secondaryFontSize == max(10, CGFloat(item.fontSize - 1)))
            #expect(metrics.metadataFontSize == max(10, CGFloat(item.fontSize - 2)))

            // Adaptive, bounded window geometry replaces the pinned 820x600 shell.
            #expect(metrics.sidebarMinWidth == item.sidebarMin)
            #expect(metrics.sidebarIdealWidth == max(220, item.sidebarMin))
            #expect(metrics.sidebarMaxWidth == max(280, max(220, item.sidebarMin) + 60))
            #expect(metrics.contentMinWidth == max(600, CGFloat(item.fontSize) * 8 + 496))
            #expect(metrics.windowMinWidth == item.minWidth)
            #expect(metrics.windowIdealWidth == max(1_000, item.minWidth + 140))
            #expect(metrics.windowMinHeight == item.minHeight)
            #expect(metrics.windowIdealHeight == item.minHeight + 96)

            // Field labels/indents adapt with font size (identical at the 13pt default).
            #expect(metrics.labelWidth == item.labelWidth)
            #expect(metrics.wideLabelWidth == item.labelWidth + 22)
            #expect(metrics.rowLeading == item.labelWidth + 14)
            #expect(metrics.controlHeight == item.controlHeight)
            #expect(metrics.fieldWidth(200) >= 200)
            #expect(metrics.menuWidth(120) >= 120)
        }
    }

    @Test("Settings scene and tabs use display metrics")
    func settingsSceneAndTabsUseDisplayMetrics() throws {
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")
        let sceneSource = try readProjectFile("Rockxy/Views/Settings/SettingsWindowScene.swift")
        #expect(appSource.contains("SettingsWindowScene()"))
        #expect(sceneSource.contains("struct SettingsWindowScene: Scene"))
        #expect(sceneSource
            .contains("Window(String(localized: \"Settings\", bundle: RockxyLocalization.bundle), id: \"settings\")"))
        #expect(
            sceneSource.contains("AppUIDisplayMetricsProvider {\n                SettingsView()"),
            "Settings window must inherit Appearance display metrics"
        )

        let files = [
            "Rockxy/Views/Settings/SettingsView.swift",
            "Rockxy/Views/Settings/GeneralSettingsTab.swift",
            "Rockxy/Views/Settings/AppearanceSettingsTab.swift",
            "Rockxy/Views/Settings/PrivacySettingsTab.swift",
            "Rockxy/Views/Settings/AssistantSettingsTab.swift",
            "Rockxy/Views/Settings/MCPSettingsTab.swift",
            "Rockxy/Views/Settings/GitHubSettingsTab.swift",
            "Rockxy/Views/Settings/PluginsSettingsTab.swift",
            "Rockxy/Views/Settings/PluginDetailView.swift",
            "Rockxy/Views/Settings/ToolsSettingsTab.swift",
            "Rockxy/Views/Settings/AdvancedSettingsTab.swift",
        ]

        for file in files {
            let source = try readProjectFile(file)
            #expect(source.contains("SettingsDisplayMetrics"), "\(file) should derive settings metrics from Appearance")
        }
    }

    @Test("Assistant dock follows Appearance typography and keeps protocol summaries monospaced")
    func assistantDockUsesDisplayMetrics() throws {
        let source = try readProjectFile("Rockxy/Views/Inspector/ContextDockView.swift")

        #expect(source.contains("@Environment(\\.appUIDisplayMetrics)"))
        // UI/prose uses explicit proportional .system(size:) roles derived from Appearance metrics,
        // no longer routed through swiftUIFont (which could force all prose monospaced). Technical
        // data (request summaries, model IDs) stays explicitly monospaced. The native icon switcher
        // keeps Details / AI Assistant in help and accessibility labels.
        #expect(!source.contains("swiftUIFont"))
        #expect(source.contains("assistantFont(appMetrics."))
        #expect(source.contains("monospaced: true"))
        #expect(!source.contains(".font(.caption"))
        #expect(!source.contains(".font(.callout"))
        #expect(!source.contains(".font(.subheadline"))
        #expect(!source.contains(".disabled(isBusy || primaryTransaction == nil)"))
        #expect(!source.contains(".disabled(conversationIsEmpty && !isBusy)"))
        #expect(source.contains("Ask Rockxy AI Assistant…"))
    }

    @Test("Assistant dock uses a compact native hierarchy with progressive disclosure")
    func assistantDockKeepsConversationChromeCompact() throws {
        let source = try readProjectFile("Rockxy/Views/Inspector/ContextDockView.swift")
        let components = try readProjectFile("Rockxy/Views/Inspector/AssistantConversationComponents.swift")

        #expect(source.contains("ContentUnavailableView"))
        #expect(source.contains("InvestigationReportView("))
        #expect(source.contains("Image(systemName: \"arrow.up\")"))
        #expect(source
            .contains(
                "accessibilityLabel(String(localized: \"Conversation History\", bundle: RockxyLocalization.bundle))"
            ))
        #expect(source
            .contains("accessibilityLabel(String(localized: \"New Conversation\", bundle: RockxyLocalization.bundle))"))
        #expect(source
            .contains("accessibilityLabel(String(localized: \"Send Message\", bundle: RockxyLocalization.bundle))"))
        #expect(components.contains("String(localized: \"Copy\", bundle: RockxyLocalization.bundle)"))
        #expect(components.contains("String(localized: \"Review & Retry\", bundle: RockxyLocalization.bundle)"))
        // The generic response footer is two quiet affordances only: a Copy control and one ellipsis
        // overflow menu. Controls keep accessibility labels/help. Card/identity chrome removal and the
        // plain right-aligned user bubble are asserted in detail by ContextDockPresentationTests.
        #expect(!components.contains("ViewThatFits(in: .horizontal)"))
        #expect(components.contains("compactAction("))
        #expect(components.contains("Image(systemName: \"ellipsis\")"))
        #expect(components.contains(".accessibilityLabel(title)"))
        #expect(components.contains(".help(title)"))
        #expect(components.contains("struct AssistantResponseContainer"))
        #expect(components.contains("AssistantMarkdownText"))
        #expect(components.contains("inlineOnlyPreservingWhitespace"))
        #expect(source.contains("AssistantMarkdownText("))
        #expect(source.contains("AssistantStreamingText(source: text)"))
        #expect(source.contains("Generating with \\(model)"))
        #expect(!source.contains("ATTACHED TRAFFIC · LOCAL"))
        #expect(!source.contains("Waiting for traffic context"))
        #expect(!source.contains("Searches conversation titles and message text"))
        #expect(!source.contains("Local review before send"))
        #expect(!source.contains("Text(String(localized: \"Rockxy AI Assistant\", bundle: RockxyLocalization.bundle))"))
    }

    @Test("Assistant Review Data uses shared tool-window typography and a native preview editor")
    func assistantReviewDataUsesToolWindowMetrics() throws {
        let source = try readProjectFile("Rockxy/Views/Inspector/DebugAssistantReviewDataSheet.swift")

        #expect(source.contains("ToolWindowDisplayMetrics"))
        #expect(source.contains("InspectorBodyTextEditor("))
        #expect(source.contains("settings.wordWrap = true"))
        #expect(source.contains("editorSettings: previewEditorSettings"))
        #expect(source.contains("isEditable: false"))
        #expect(source.contains(".keyboardShortcut(.cancelAction)"))
        #expect(!source.contains(".font(.title2"))
        #expect(!source.contains(".font(.headline"))
        #expect(!source.contains(".font(.caption"))
        #expect(!source.contains("GroupBox"))
    }

    @Test("Assistant settings use shared section and field components")
    func assistantSettingsUseSharedComponents() throws {
        let source = try readProjectFile("Rockxy/Views/Settings/AssistantSettingsTab.swift")
        let components = try readProjectFile("Rockxy/Views/Settings/SettingsSectionComponents.swift")

        #expect(source.components(separatedBy: "SettingsSection(").count - 1 == 4)
        #expect(source.contains("SettingsFieldRow"))
        #expect(source.contains("SettingsIndentedContent"))
        #expect(source.contains("1. Local Model Setup"))
        #expect(source.contains("2. Provider & Model"))
        #expect(source.contains("3. Connection"))
        #expect(source.contains("Download & Use"))
        #expect(source.contains("Global Default"))
        #expect(source.contains("Image(systemName: \"arrow.clockwise\")"))
        #expect(source.contains(".accessibilityLabel(String("))
        #expect(source.contains("localized: \"Refresh Available Models\""))
        #expect(!source.contains("Button(String(localized: \"Fetch Models\", bundle: RockxyLocalization.bundle))"))
        #expect(!source.contains("LazyVGrid("))
        #expect(components.contains("SettingsDisplayMetrics"))
        // Settings sections share Developer Setup's flat hierarchy and rows
        // reflow instead of preserving an artificial fixed label gutter.
        #expect(!components.contains("GroupBox"))
        #expect(components.contains("ViewThatFits(in: .horizontal)"))
        #expect(components.contains("settingsMetrics.labelWidth"))
        #expect(components.contains("settingsMetrics.fieldSpacing"))
        #expect(!components.contains("Color.clear.frame(width: settingsMetrics.rowLeading)"))
        #expect(!components.contains("separatorColor).opacity(0.62)"))
    }

    @Test("Ollama setup uses a compact native installation sheet")
    func ollamaRuntimeSetupUsesNativeInstallationSheet() throws {
        let source = try readProjectFile("Rockxy/Views/Settings/AssistantRuntimeSetupSheet.swift")

        #expect(source.contains("SettingsDisplayMetrics"))
        #expect(source.contains("AssistantInstallPathControl"))
        #expect(source.contains("NSPathControl"))
        #expect(source.contains("fontSize: settingsMetrics.bodyFontSize"))
        #expect(source.contains("control.font = .systemFont(ofSize: fontSize)"))
        #expect(source.contains("Text(String(localized: \"Install Ollama\", bundle: RockxyLocalization.bundle))"))
        #expect(source.contains("Button(String(localized: \"Install\", bundle: RockxyLocalization.bundle))"))
        #expect(source.contains(".keyboardShortcut(.cancelAction)"))
        #expect(source.contains("The developer signature and Gatekeeper approval are checked before installation."))
        #expect(!source.contains("Set Up Ollama on This Mac"))
        #expect(!source.contains("shippingbox.and.arrow.backward.fill"))
        #expect(!source.contains("Verified Runtime"))
        #expect(!source.contains("Nothing will be installed until you confirm."))
        #expect(!source.contains("GroupBox"))
    }

    @Test("Custom tool windows are wrapped in display metrics provider")
    func customToolWindowsAreWrappedInDisplayMetricsProvider() throws {
        let source = try readProjectFile("Rockxy/RockxyApp.swift")
        let windowIDs = [
            "advancedProxySettings",
            "certificateSetup",
            "customCertificates",
            "mapLocal",
            "mapLocalEditor",
            "mapRemote",
            "mapRemoteEditor",
            "blockList",
            "modifyHeaders",
            "networkConditions",
            "sslProxyingList",
            "bypassProxyList",
            "externalProxySettings",
            "socksProxySettings",
            "allowList",
            "diff",
            "scriptingList",
            "scriptEditor",
            "bodyPreviewerTabs",
            "customColumns",
            "protobufSettings",
            "protobufSchemaList",
            "breakpointRules",
            "breakpointRuleEditor",
            "breakpointTemplates",
            "breakpoints",
            "compose",
        ]

        for id in windowIDs {
            #expect(source.contains(#"id: "\#(id)""#), "Missing window id \(id)")
            let idRange = try #require(source.range(of: #"id: "\#(id)""#))
            let remaining = source[idRange.upperBound...]
            let providerRange = remaining.range(of: "ToolWindowDisplayMetricsProvider")
            #expect(providerRange != nil, "Window \(id) must use ToolWindowDisplayMetricsProvider")
            if let providerRange {
                #expect(remaining.distance(from: remaining.startIndex, to: providerRange.lowerBound) < 140)
            }
        }
    }

    @Test("Diff workspace keeps the approved native hierarchy and honest action routing")
    func diffWorkspaceUsesNativeHierarchy() throws {
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")
        let windowSource = try readProjectFile("Rockxy/Views/Diff/DiffWindowView.swift")
        let tableSource = try readProjectFile("Rockxy/Views/Diff/DiffCandidateTableView.swift")
        let viewerSource = try readProjectFile("Rockxy/Views/Diff/DiffViewerView.swift")
        let controlsSource = try readProjectFile("Rockxy/Views/Diff/DiffControlBar.swift")
        let contextSource = try readProjectFile("Rockxy/Views/Inspector/ContextDetailsView.swift")

        let diffSceneStart = try #require(
            appSource.range(of: "Window(String(localized: \"Diff\", bundle: RockxyLocalization.bundle), id: \"diff\")")
        )
        let scenesAfterDiff = appSource[diffSceneStart.lowerBound...]
        let nextSceneStart = try #require(
            scenesAfterDiff
                .range(
                    of: "Window(String(localized: \"Scripting\", bundle: RockxyLocalization.bundle), id: \"scriptingList\")"
                )
        )
        let diffSceneSource = scenesAfterDiff[..<nextSceneStart.lowerBound]
        #expect(diffSceneSource.contains(".windowToolbarStyle(.unifiedCompact)"))
        let diffMenuStart = try #require(appSource.range(of: "private var diffMenu: some Commands"))
        let menusAfterDiff = appSource[diffMenuStart.lowerBound...]
        let nextMenuStart = try #require(menusAfterDiff.range(of: "private var scriptingMenu: some Commands"))
        let diffMenuSource = menusAfterDiff[..<nextMenuStart.lowerBound]
        #expect(diffMenuSource.contains(#".keyboardShortcut("y", modifiers: [.command, .option])"#))
        #expect(diffMenuSource.contains(#".keyboardShortcut("d", modifiers: [.command, .option])"#))

        #expect(windowSource.contains("Basic Compare"))
        #expect(windowSource.contains("Local · Read-only"))
        #expect(windowSource.contains("Comparison Source"))
        #expect(windowSource.contains("$viewModel.workspaceMode"))
        #expect(windowSource.contains(".disabled(!viewModel.canSwapSides)"))
        #expect(windowSource.contains("exportErrorMessage"))
        #expect(windowSource.contains("DiffExportFormatter.write"))
        #expect(windowSource.contains(#".keyboardShortcut("s", modifiers: [.command, .option])"#))
        #expect(windowSource.contains("Export the comparison as a text file"))

        #expect(tableSource.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(tableSource.contains("Color(nsColor: .separatorColor)"))
        #expect(tableSource.contains("Comparison Set"))
        #expect(tableSource.contains("viewModel.clearCandidates()"))
        #expect(tableSource.contains("ContentUnavailableView"))
        #expect(tableSource.contains("DiffMethodBadge"))
        #expect(!tableSource.contains("private func statusColor"))

        #expect(viewerSource.contains("GeometryReader"))
        #expect(viewerSource.contains("ScrollView([.horizontal, .vertical])"))
        #expect(viewerSource.contains("ScrollView(.vertical)"))
        #expect(viewerSource.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(viewerSource.contains(".frame(width: paneWidth, alignment: .leading)"))
        #expect(viewerSource.contains(".fixedSize(horizontal: allowsHorizontalOverflow, vertical: false)"))
        #expect(viewerSource.contains("case .textReady"))
        #expect(viewerSource.contains("comparisonContent(showsIdentity: false)"))
        #expect(viewerSource.contains("Left text"))
        #expect(viewerSource.contains("Right text"))
        #expect(viewerSource.contains("Theme.Highlight.green"))
        #expect(viewerSource.contains("Theme.Highlight.red"))

        #expect(controlsSource.contains("Text(target.title)"))
        #expect(controlsSource.contains("Text(mode.title)"))
        #expect(controlsSource.contains("viewModel.compareText()"))
        #expect(controlsSource.contains("viewModel.editText()"))
        #expect(!controlsSource.contains("Text(target.rawValue)"))
        #expect(!controlsSource.contains("Text(mode.rawValue)"))

        #expect(contextSource.contains("coordinator.compareTransactions(transactions[0], transactions[1])"))
        #expect(!contextSource.contains("NotificationCenter.default.post(name: .openDiffWindow"))
    }

    @Test("Compose uses a native request surface with honest shortcuts and no dead-end affordances")
    func composeUsesNativeRequestSurface() throws {
        let windowSource = try readProjectFile("Rockxy/Views/Compose/ComposeWindowView.swift")
        let editorSource = try readProjectFile("Rockxy/Views/Compose/ComposeRequestEditor.swift")
        let responseSource = try readProjectFile("Rockxy/Views/Compose/ComposeResponseViewer.swift")

        // Native request target row replaces the web-like rounded capsule.
        #expect(!windowSource.contains("RoundedRectangle(cornerRadius: 16)"))
        #expect(!windowSource.contains(".background(.quaternary"))
        #expect(windowSource.contains(".textFieldStyle(.roundedBorder)"))
        #expect(windowSource.contains("toolMetrics.contentHorizontalPadding"))

        // The no-op Expand Raw Message affordance is gone.
        #expect(!windowSource.contains("Expand Raw Message"))
        #expect(!windowSource.contains("arrow.up.left.and.arrow.down.right"))

        // Primary Send action keeps a clear loading state and honest disabled logic.
        #expect(windowSource.contains(".rockxyGlassButtonStyle(prominent: true)"))
        #expect(windowSource.contains("cancelActiveSend"))
        #expect(windowSource.contains(#".keyboardShortcut(".", modifiers: .command)"#))
        #expect(windowSource.contains("viewModel.url.isEmpty || viewModel.isUnsupportedForReplay"))
        #expect(windowSource.contains(".disabled(isSending)"))
        #expect(windowSource
            .contains(#"isSending ? String(localized: "⌘. Cancel", bundle: RockxyLocalization.bundle)"#))
        #expect(!windowSource.contains(#""TRACE", "CONNECT""#))

        // Preserved shortcuts: Send, Cancel, Template, History, Focus URL, Reset.
        #expect(windowSource.contains(".keyboardShortcut(.return, modifiers: .command)"))
        #expect(windowSource.contains(#".keyboardShortcut("t", modifiers: .command)"#))
        #expect(windowSource.contains(#".keyboardShortcut("y", modifiers: .command)"#))
        #expect(windowSource.contains(#".keyboardShortcut("l", modifiers: .command)"#))
        #expect(windowSource.contains(#".keyboardShortcut("0", modifiers: .command)"#))

        // Request/Response navigation uses consistent native pickers that adapt at large fonts.
        #expect(editorSource.contains("ComposeRequestTab.allCases"))
        #expect(editorSource.contains(".pickerStyle(.segmented)"))
        #expect(editorSource.contains(".pickerStyle(.menu)"))
        #expect(editorSource.contains("toolMetrics.bodyFontSize >= 20"))
        #expect(responseSource.contains(".pickerStyle(.segmented)"))
        #expect(responseSource.contains(".pickerStyle(.menu)"))
        #expect(editorSource.contains("toolMetrics.tableHeaderFont()"))
        #expect(editorSource.contains("viewModel.replaceUnavailableBody"))
        #expect(responseSource.contains("History snapshot truncated"))

        // Restrained add/remove: no loud filled red minus glyph.
        #expect(!editorSource.contains("minus.circle.fill"))

        // Import, privacy, and destructive history actions are explicit.
        #expect(windowSource.contains("Import Failed"))
        #expect(windowSource.contains("Clear Compose History?"))
        #expect(windowSource.contains("URLs and bodies remain stored locally"))
    }

    @Test("Readable tool windows use tool metrics")
    func readableToolWindowsUseToolMetrics() throws {
        let files = [
            "Rockxy/Views/Rules/MapRemoteWindowView.swift",
            "Rockxy/Views/Rules/MapLocalWindowView.swift",
            "Rockxy/Views/Rules/MapLocalEditorWindowView.swift",
            "Rockxy/Views/Rules/BlockListWindowView.swift",
            "Rockxy/Views/Rules/AllowListWindowView.swift",
            "Rockxy/Views/Rules/AddAllowListRuleSheet.swift",
            "Rockxy/Views/Rules/NetworkConditionsWindowView.swift",
            "Rockxy/Views/Rules/ModifyHeaderWindowView.swift",
            "Rockxy/Views/Rules/ModifyHeaderEditorView.swift",
            "Rockxy/Views/Rules/ProtobufSettingsWindowView.swift",
            "Rockxy/Views/Rules/ProtobufSchemaListWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRulesWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRuleRow.swift",
            "Rockxy/Views/Breakpoint/BreakpointEditorView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRuleEditorWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointTemplateWindowView.swift",
            "Rockxy/Views/Scripting/ScriptingListWindowView.swift",
            "Rockxy/Views/Scripting/ScriptEditorWindowView.swift",
            "Rockxy/Views/Scripting/ScriptConsolePanel.swift",
            "Rockxy/Views/Settings/PreviewerTabSettingsView.swift",
            "Rockxy/Views/Settings/CustomHeaderColumnsView.swift",
        ]

        for file in files {
            let source = try readProjectFile(file)
            #expect(source.contains("ToolWindowDisplayMetrics"), "\(file) should derive readable tool-window metrics")
        }
    }

    @Test("Workspace presentation windows share live coordinator stores")
    func workspacePresentationWindowsShareLiveCoordinatorStores() throws {
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")
        let previewSource = try readProjectFile("Rockxy/Views/Settings/PreviewerTabSettingsView.swift")
        let columnsSource = try readProjectFile("Rockxy/Views/Settings/CustomHeaderColumnsView.swift")
        let centerSource = try readProjectFile("Rockxy/Views/RequestList/CenterContentView.swift")
        let tableSource = try readProjectFile("Rockxy/Views/RequestList/RequestTableView.swift")
        let requestInspectorSource = try readProjectFile("Rockxy/Views/Inspector/RequestInspectorView.swift")
        let responseInspectorSource = try readProjectFile("Rockxy/Views/Inspector/ResponseInspectorView.swift")

        #expect(appSource.contains("PreviewerTabSettingsView(store: mainCoordinator.previewTabStore)"))
        #expect(appSource.contains("CustomHeaderColumnsView(store: mainCoordinator.headerColumnStore)"))
        #expect(!previewSource.contains("@State private var store = PreviewTabStore()"))
        #expect(!columnsSource.contains("@State private var store = HeaderColumnStore()"))
        #expect(!columnsSource.contains("store.reload()"))

        #expect(previewSource.contains("Table(PreviewRenderMode.allCases)"))
        #expect(previewSource.contains("ToolWindowDisplayMetrics"))
        #expect(columnsSource.contains("ContentUnavailableView"))
        #expect(columnsSource.contains("ToolWindowDisplayMetrics"))

        #expect(centerSource.contains("headerColumns: coordinator.headerColumnStore.columns"))
        #expect(tableSource.contains("var headerColumns: [HeaderColumn] = []"))
        #expect(tableSource.contains("parent.headerColumns.filter(\\.isEnabled)"))
        #expect(tableSource.contains("mainCoordinator.activeSortDescriptors = reconciledSortDescriptors"))
        #expect(!columnsSource.contains(".keyboardShortcut(.space, modifiers: [])"))

        #expect(requestInspectorSource.contains(
            ".onChange(of: previewTabStore.requestTabs.map(\\.id))"
        ))
        #expect(responseInspectorSource.contains(
            ".onChange(of: previewTabStore.responseTabs.map(\\.id))"
        ))
    }

    @Test("Tool windows do not pin exact frames that can clip scaled text")
    func toolWindowsDoNotPinExactFramesThatCanClipScaledText() throws {
        let files = [
            "Rockxy/Views/Rules/ModifyHeaderWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointTemplateWindowView.swift",
        ]
        let forbiddenSnippets = [
            ".frame(width: 860, height: 620)",
            ".frame(width: 802, height: 631)",
        ]

        for file in files {
            let source = try readProjectFile(file)
            #expect(
                source.contains(".frame(\n            minWidth: max("),
                "\(file) should use scalable min window dimensions"
            )
            for snippet in forbiddenSnippets {
                #expect(!source.contains(snippet), "\(file) must not pin exact window size \(snippet)")
            }
        }
    }

    @Test("Custom list tables no longer hard-code tiny primary rows")
    func customListTablesNoLongerHardCodeTinyPrimaryRows() throws {
        let files = [
            "Rockxy/Views/Rules/BlockListWindowView.swift",
            "Rockxy/Views/Rules/AllowListWindowView.swift",
        ]
        let forbiddenSnippets = [
            ".font(.system(size: 10.5",
            ".frame(height: 22)",
            "ForEach(0 ..< 17",
        ]

        for file in files {
            let source = try readProjectFile(file)
            for snippet in forbiddenSnippets {
                #expect(!source.contains(snippet), "\(file) must not keep \(snippet)")
            }
        }
    }

    @Test("Block and Allow List retain readable table rhythm")
    func blockAndAllowListRetainReadableTableRhythm() throws {
        let blockListFile = "Rockxy/Views/Rules/BlockListWindowView.swift"
        let blockListTableFile = "Rockxy/Views/Rules/BlockListTableView.swift"
        let allowListFile = "Rockxy/Views/Rules/AllowListWindowView.swift"
        let files = [blockListTableFile, allowListFile]
        let forbiddenSnippets = [
            ".frame(width: 1_200, height: 642)",
            ".controlSize(.large)",
            ".padding(.top, toolMetrics.footerTopPadding)",
            ".frame(height: tableHeight)",
            "private var tableHeight",
            "zebraRowCount",
            "questionmark.circle.fill",
        ]

        for file in files {
            let source = try readProjectFile(file)
            #expect(source.contains(".frame(minHeight: toolMetrics.tableRowHeight * 8, maxHeight: .infinity)"))
            for snippet in forbiddenSnippets {
                #expect(!source.contains(snippet), "\(file) must not keep \(snippet)")
            }
        }

        let blockListSource = try readProjectFile(blockListFile)
        #expect(blockListSource.contains("minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496)"))
        #expect(blockListSource.contains("minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)"))

        let allowListSource = try readProjectFile(allowListFile)
        #expect(allowListSource.contains("minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496)"))
        #expect(allowListSource.contains("minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)"))
        #expect(!allowListSource.contains(".frame(width: 1_200, height: 672)"))
    }

    @Test("List-style tool windows do not add an extra footer top gap")
    func listStyleToolWindowsDoNotAddExtraFooterTopGap() throws {
        let files = [
            "Rockxy/Views/Rules/MapLocalWindowView.swift",
            "Rockxy/Views/Rules/MapRemoteWindowView.swift",
            "Rockxy/Views/Rules/BlockListWindowView.swift",
            "Rockxy/Views/Rules/AllowListWindowView.swift",
            "Rockxy/Views/Rules/NetworkConditionsWindowView.swift",
            "Rockxy/Views/Rules/ProtobufSettingsWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRulesWindowView.swift",
        ]

        for file in files {
            let source = try readProjectFile(file)
            #expect(
                !source.contains(".padding(.top, toolMetrics.footerTopPadding)"),
                "\(file) should mirror Scripting footer spacing"
            )
        }
    }

    @Test("Tool window form controls scale from display metrics")
    func toolWindowFormControlsScaleFromDisplayMetrics() throws {
        let files = [
            "Rockxy/Views/Rules/AddAllowListRuleSheet.swift",
            "Rockxy/Views/Rules/BlockListWindowView.swift",
            "Rockxy/Views/Rules/ModifyHeaderWindowView.swift",
            "Rockxy/Views/Rules/ModifyHeaderEditorView.swift",
            "Rockxy/Views/Rules/MapLocalWindowView.swift",
            "Rockxy/Views/Rules/MapLocalEditorWindowView.swift",
            "Rockxy/Views/Rules/MapRemoteWindowView.swift",
            "Rockxy/Views/Rules/NetworkConditionsWindowView.swift",
            "Rockxy/Views/Rules/ProtobufSettingsWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRuleEditorWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointEditorView.swift",
            "Rockxy/Views/Scripting/ScriptEditorWindowView.swift",
            "Rockxy/Views/Scripting/ScriptingListWindowView.swift",
            "Rockxy/Views/Compose/ComposeWindowView.swift",
            "Rockxy/Views/Compose/ComposeRequestEditor.swift",
            "Rockxy/Views/Diff/DiffControlBar.swift",
            "Rockxy/Views/Export/ExportScopeSheet.swift",
            "Rockxy/Views/Import/ImportReviewSheet.swift",
            "Rockxy/Views/Settings/AddSSLDomainSheet.swift",
            "Rockxy/Views/Settings/AddSSLAppDomainSheet.swift",
            "Rockxy/Views/Settings/BypassProxySettingsSheet.swift",
            "Rockxy/Views/Settings/BypassProxyListView.swift",
            "Rockxy/Views/Settings/SSLProxyingListView.swift",
            "Rockxy/Views/Settings/ExternalProxySettingsView.swift",
            "Rockxy/Views/Settings/SOCKSProxySettingsView.swift",
            "Rockxy/Views/Settings/AdvancedProxySettingsView.swift",
        ]

        for file in files {
            let source = try readProjectFile(file)
            let scalesControls = source.contains("toolMetrics.formControlHeight")
                || source.contains("toolMetrics.menuWidth")
                || source.contains("toolMetrics.fieldWidth")
                || source.contains("toolMetrics.bodyFontSize")
            #expect(scalesControls, "\(file) should scale control containers from display metrics")
            #expect(source.contains("toolMetrics.font("), "\(file) should apply readable fonts to controls")
        }
    }

    @Test("Settings-launched windows keep fixed shells while scaling typography")
    func settingsLaunchedWindowsKeepFixedShellsWhileScalingTypography() throws {
        let files = [
            "Rockxy/Views/Settings/BypassProxyListView.swift",
            "Rockxy/Views/Settings/SSLProxyingListView.swift",
            "Rockxy/Views/Settings/ExternalProxySettingsView.swift",
            "Rockxy/Views/Settings/SOCKSProxySettingsView.swift",
            "Rockxy/Views/Settings/AdvancedProxySettingsView.swift",
        ]
        let forbiddenSnippets = [
            ".font(.caption",
            ".font(.callout",
            ".font(.system(.body",
            ".font(.system(size: 11",
            ".font(.system(size: 12",
            ".font(.system(size: 13",
            "height: max(",
            "width: max(",
            ".frame(minWidth:",
        ]

        for file in files {
            let source = try readProjectFile(file)
            #expect(source.contains("ToolWindowDisplayMetrics"), "\(file) should use tool metrics from Appearance")
            for snippet in forbiddenSnippets {
                #expect(
                    !source.contains(snippet),
                    "\(file) must not keep compact fixed setting-window layout \(snippet)"
                )
            }
        }
    }

    @Test("Upstream Proxy uses one safe native settings workflow")
    func upstreamProxyUsesOneSafeNativeWorkflow() throws {
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")
        let externalSource = try readProjectFile(
            "Rockxy/Views/Settings/ExternalProxySettingsView.swift"
        )
        let socksSource = try readProjectFile(
            "Rockxy/Views/Settings/SOCKSProxySettingsView.swift"
        )
        let policyNoticeSource = try readProjectFile(
            "Rockxy/Views/Common/PolicyLockNotice.swift"
        )
        let storeSource = try readProjectFile(
            "Rockxy/Models/Settings/UpstreamProxyStore.swift"
        )

        #expect(appSource.contains(#"id: "externalProxySettings""#))
        #expect(appSource.contains(#"id: "socksProxySettings""#))

        let proxyMenuStart = try #require(
            appSource.range(of: #"Menu(String(localized: "Proxy Settings", bundle: RockxyLocalization.bundle))"#)
        )
        let appAfterProxyMenu = appSource[proxyMenuStart.lowerBound...]
        let proxyMenuEnd = try #require(
            appAfterProxyMenu.range(of: "\n            Divider()")
        )
        let proxyMenuSource = appAfterProxyMenu[..<proxyMenuEnd.lowerBound]
        #expect(proxyMenuSource.contains(#"openWindow(id: "externalProxySettings")"#))
        #expect(!proxyMenuSource.contains(#"openWindow(id: "socksProxySettings")"#))
        #expect(
            proxyMenuSource.components(
                separatedBy: #"openWindow(id: "externalProxySettings")"#
            ).count == 2
        )

        #expect(externalSource.contains("UpstreamProxySettingsViewModel"))
        #expect(externalSource.contains("Upstream bypass entries are still"))
        #expect(externalSource.contains("captured by Rockxy"))
        #expect(externalSource.contains("Rockxy connects to those destinations directly"))
        #expect(externalSource.contains("private var footerActions: some View"))
        #expect(externalSource.contains("HStack(spacing: Theme.Layout.controlSpacing)"))
        #expect(externalSource
            .contains("footerButtonLabel(String(localized: \"Cancel\", bundle: RockxyLocalization.bundle))"))
        #expect(externalSource
            .contains("footerButtonLabel(String(localized: \"Apply\", bundle: RockxyLocalization.bundle))"))
        #expect(!externalSource.contains("saveDraft()"))
        #expect(!externalSource.contains("Rockxy Pro"))
        #expect(!externalSource.contains("has not supported Authentication"))

        #expect(socksSource.contains(#"openWindow(id: "externalProxySettings")"#))
        #expect(!socksSource.contains("UpstreamProxyStore.shared"))
        #expect(!socksSource.contains("saveConfiguration"))

        #expect(policyNoticeSource.contains("struct PolicyLockNotice"))
        #expect(!externalSource.contains("struct PolicyLockNotice"))
        #expect(storeSource.contains("configuration draftConfiguration"))
    }

    @Test("Tool window forms avoid fixed compact typography")
    func toolWindowFormsAvoidFixedCompactTypography() throws {
        let files = [
            "Rockxy/Views/Rules",
            "Rockxy/Views/Breakpoint",
            "Rockxy/Views/Scripting",
            "Rockxy/Views/Compose",
            "Rockxy/Views/Diff",
        ]
        let forbiddenSnippets = [
            ".font(.system(.body",
            ".font(.caption",
            ".font(.callout",
        ]

        for directory in files {
            let sourceFiles = try projectSwiftFiles(under: directory)
            for file in sourceFiles {
                let source = try readProjectFile(file)
                for snippet in forbiddenSnippets {
                    #expect(!source.contains(snippet), "\(file) must not keep fixed compact typography \(snippet)")
                }
            }
        }
    }

    @Test("Popup sheets avoid fixed compact control containers")
    func popupSheetsAvoidFixedCompactControlContainers() throws {
        let files = [
            "Rockxy/Views/Export/ExportScopeSheet.swift",
            "Rockxy/Views/Export/GistPublishConfirmationSheet.swift",
            "Rockxy/Views/Import/ImportReviewSheet.swift",
            "Rockxy/Views/Settings/AddSSLDomainSheet.swift",
            "Rockxy/Views/Settings/AddSSLAppDomainSheet.swift",
            "Rockxy/Views/Settings/BypassProxySettingsSheet.swift",
        ]
        let forbiddenSnippets = [
            ".font(.caption",
            ".font(.system(.body",
            ".frame(height: 25",
            ".frame(height: 28",
            ".frame(height: 29",
            ".frame(width: 68",
            ".frame(width: 80",
        ]

        for file in files {
            let source = try readProjectFile(file)
            #expect(source.contains("ToolWindowDisplayMetrics"), "\(file) should use tool metrics")
            for snippet in forbiddenSnippets {
                #expect(!source.contains(snippet), "\(file) must not keep fixed compact popup layout \(snippet)")
            }
        }
    }

    @Test("Readable dialogs do not keep compact fixed typography")
    func readableDialogsDoNotKeepCompactFixedTypography() throws {
        let files = [
            "Rockxy/Views/Rules/AddAllowListRuleSheet.swift",
            "Rockxy/Views/Rules/BlockListWindowView.swift",
            "Rockxy/Views/Rules/NetworkConditionsWindowView.swift",
            "Rockxy/Views/Rules/ModifyHeaderWindowView.swift",
            "Rockxy/Views/Rules/ModifyHeaderEditorView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRuleEditorWindowView.swift",
        ]
        let forbiddenSnippets = [
            ".font(.caption",
            ".font(.system(size: 13",
            ".frame(width: 600",
            ".frame(width: 680",
            ".frame(width: 785",
            ".frame(width: 834",
        ]

        for file in files {
            let source = try readProjectFile(file)
            for snippet in forbiddenSnippets {
                #expect(!source.contains(snippet), "\(file) must not keep \(snippet)")
            }
        }
    }

    @Test("Rule-style tool windows use shared layout spacing")
    func ruleStyleToolWindowsUseSharedLayoutSpacing() throws {
        let adaptiveFooterFiles = [
            "Rockxy/Views/Rules/MapLocalWindowView.swift",
            "Rockxy/Views/Rules/MapRemoteWindowView.swift",
            "Rockxy/Views/Rules/BlockListWindowView.swift",
            "Rockxy/Views/Rules/AllowListWindowView.swift",
            "Rockxy/Views/Rules/ModifyHeaderWindowView.swift",
            "Rockxy/Views/Rules/NetworkConditionsWindowView.swift",
            "Rockxy/Views/Rules/ProtobufSettingsWindowView.swift",
            "Rockxy/Views/Rules/ProtobufSchemaListWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRulesWindowView.swift",
        ]
        for file in adaptiveFooterFiles {
            let source = try readProjectFile(file)
            #expect(
                source.contains("toolMetrics.contentHorizontalPadding"),
                "\(file) should use shared horizontal padding"
            )
            #expect(
                source.contains(".padding(.vertical, toolMetrics.footerTopPadding)"),
                "\(file) should use the approved adaptive footer rhythm"
            )
            #expect(!source.contains(".padding(.horizontal, 22)"), "\(file) should not use old oversized padding")
        }
    }

    @Test("Map Remote uses the approved native window and editor structure")
    func mapRemoteUsesApprovedNativeStructure() throws {
        let windowSource = try readProjectFile("Rockxy/Views/Rules/MapRemoteWindowView.swift")
        let editorSource = try readProjectFile("Rockxy/Views/Rules/MapRemoteEditorViewModel.swift")

        #expect(windowSource
            .contains(#"TextField(String(localized: "Search rules", bundle: RockxyLocalization.bundle)"#))
        #expect(windowSource.contains("minWidth: max(900, toolMetrics.bodyFontSize * 30 + 520)"))
        #expect(windowSource.contains("minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)"))
        #expect(windowSource.contains(#"String(localized: "Remote Destination", bundle: RockxyLocalization.bundle)"#))
        #expect(windowSource.contains(#"String(localized: "Rule Details", bundle: RockxyLocalization.bundle)"#))
        #expect(windowSource.contains("ContentUnavailableView"))
        #expect(windowSource.contains("width: toolMetrics.menuWidth(150)"))
        #expect(windowSource.contains("dataEntryMenuLabel"))
        #expect(windowSource.contains("footerButtonLabel"))
        #expect(windowSource.contains(".keyboardShortcut(.cancelAction)"))
        #expect(windowSource.contains(".keyboardShortcut(.defaultAction)"))
        #expect(windowSource.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(windowSource.contains(".stroke(Color(nsColor: .separatorColor), lineWidth: 1)"))
        #expect(windowSource.contains("viewModel.save()"))
        #expect(!windowSource.contains(".frame(width: 1_202, height: 640)"))
        #expect(!windowSource.contains("Test your Rule"))
        #expect(!windowSource.contains("Preserve the Original URL"))
        #expect(windowSource.contains("Keep original request path and query"))
        #expect(windowSource.contains(".focused($isDestinationHostFocused)"))
        #expect(editorSource.contains("condition.sourceURLPattern"))
        #expect(editorSource.contains("condition.includeSubpaths"))
        #expect(editorSource.contains("func save(using gate: RulePolicyGate = .shared) async -> Bool"))
        #expect(editorSource.contains("private(set) var isSaving = false"))

        let editorMarker = try #require(windowSource.range(of: "// MARK: - MapRemoteEditorWindowView"))
        let editorViewSource = String(windowSource[editorMarker.lowerBound...])
        #expect(
            !editorViewSource.contains("font(monospaced: true)"),
            "Map Remote Editor should use the shared Rockxy form font instead of per-field font overrides"
        )
        #expect(
            !editorViewSource.contains("secondaryFont(monospaced: true)"),
            "Map Remote Editor supporting copy should use the shared Rockxy secondary font"
        )
    }

    @Test("Map Local uses the approved native window and editor structure")
    func mapLocalUsesApprovedNativeStructure() throws {
        let windowSource = try readProjectFile("Rockxy/Views/Rules/MapLocalWindowView.swift")
        let editorSource = try readProjectFile("Rockxy/Views/Rules/MapLocalEditorWindowView.swift")
        let source = windowSource + "\n" + editorSource

        #expect(source.contains(#"TextField(String(localized: "Search rules", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains("minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496)"))
        #expect(source.contains("minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)"))
        #expect(source.contains(#"String(localized: "Rule Details", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains(#"String(localized: "Response Source", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains("responseStatusRow"))
        #expect(source.contains("urlValidationMessage"))
        #expect(source.contains(".frame(height: max(680, toolMetrics.bodyFontSize * 20 + 420))"))
        #expect(source.contains("width: toolMetrics.menuWidth(150)"))
        #expect(!source.contains("width: toolMetrics.menuWidth(175)"))
        #expect(source.contains(".frame(maxWidth: .infinity, alignment: .center)"))
        #expect(source.contains(".textSelection(.enabled)"))
        #expect(source.contains("dataEntryMenuLabel"))
        #expect(source.contains("footerButtonLabel"))
        #expect(source.contains(".keyboardShortcut(.cancelAction)"))
        #expect(source.contains(".keyboardShortcut(.defaultAction)"))
        #expect(source.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(source.contains(".stroke(Color(nsColor: .separatorColor), lineWidth: 1)"))
        #expect(!source.contains(".frame(width: 1_024, height: 570)"))
        #expect(!source.contains("api.proxyman.com"))
        #expect(!source.contains("Test your Rule"))
        #expect(!source.contains("Auto-Save"))
        #expect(!source.contains("New Folder"))
        #expect(!source.contains("Support Status Code, Headers and Body"))
        #expect(!source.contains("Map Response Body with a local file (Saved)"))
    }

    @Test("Allow List uses the approved native window and editor structure")
    func allowListUsesApprovedNativeStructure() throws {
        let windowSource = try readProjectFile("Rockxy/Views/Rules/AllowListWindowView.swift")
        let editorSource = try readProjectFile("Rockxy/Views/Rules/AddAllowListRuleSheet.swift")

        #expect(windowSource
            .contains(#"TextField(String(localized: "Search rules", bundle: RockxyLocalization.bundle)"#))
        #expect(windowSource.contains("RoundedRectangle(cornerRadius: 6)"))
        #expect(windowSource.contains("ALLOW LIST OFF"))
        #expect(windowSource.contains("Migrate from Another Proxy"))
        #expect(windowSource.contains("private enum AllowListTableLayout"))
        #expect(windowSource.contains("static let contentInset: CGFloat = 10"))
        #expect(windowSource.contains("width: AllowListTableLayout.nameWidth,"))
        #expect(windowSource.contains("alignment: .center"))
        #expect(windowSource.contains(".padding(.leading, AllowListTableLayout.contentInset)"))
        #expect(windowSource.contains(".overlay(alignment: .trailing)"))
        #expect(!windowSource.contains(".padding(.trailing, 10)"))
        #expect(!windowSource.contains("AllowListFilterBar"))
        #expect(!windowSource.contains("isFilterBarVisible"))

        #expect(editorSource.contains(#"String(localized: "Rule Details", bundle: RockxyLocalization.bundle)"#))
        #expect(editorSource.contains(#"String(localized: "Capture Effect", bundle: RockxyLocalization.bundle)"#))
        #expect(editorSource.contains("dataEntryMenuLabel"))
        #expect(editorSource.contains("chevron.up.chevron.down"))
        #expect(editorSource.contains("footerButtonLabel"))
    }

    @Test("Network Conditions uses the approved native window and editor structure")
    func networkConditionsUsesApprovedNativeStructure() throws {
        let source = try readProjectFile("Rockxy/Views/Rules/NetworkConditionsWindowView.swift")

        // Always-visible search field, mirroring the approved Map Remote window.
        #expect(source.contains(#"TextField(String(localized: "Search rules", bundle: RockxyLocalization.bundle)"#))

        // Adaptive min window sizing consistent with Map Remote (shared minHeight formula).
        #expect(source.contains("minWidth: max("))
        #expect(source.contains("toolMetrics.bodyFontSize"))
        #expect(source.contains("minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)"))
        #expect(source.contains("minHeight: max(460, toolMetrics.bodyFontSize * 14 + 278)"))

        // Native empty state instead of a bare overlay label.
        #expect(source.contains("ContentUnavailableView"))

        // textBackgroundColor table/card surfaces with rounded corners and a separator stroke.
        #expect(source.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(source.contains("RoundedRectangle(cornerRadius: 6)"))
        #expect(source.contains(".stroke(Color(nsColor: .separatorColor), lineWidth: 1)"))

        // Approved editor sections.
        #expect(source.contains(#"String(localized: "Rule Details", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains(#"String(localized: "Network Profile", bundle: RockxyLocalization.bundle)"#))

        // Shared footer button label and native footer shortcuts.
        #expect(source.contains("footerButtonLabel"))
        #expect(source.contains(".keyboardShortcut(.cancelAction)"))
        #expect(source.contains(".keyboardShortcut(.defaultAction)"))
        #expect(source.contains(".id(session.id)"))
        #expect(source.contains("onSave: @escaping (ProxyRule) async -> Bool"))
        #expect(!source.contains(".keyboardShortcut(.space, modifiers: [])"))

        // Regressions locked out: fixed frame, reference placeholder, per-field monospace override.
        #expect(!source.contains(".frame(width: 1_198, height: 641)"))
        #expect(!source.contains("api.proxyman.com"))
        #expect(!source.contains("font(monospaced: true)"))
        #expect(!source.contains("secondaryFont(monospaced: true)"))

        // No misleading bandwidth / packet-loss copy (the engine applies no random bandwidth or packet loss).
        #expect(!source.contains("generated randomly"))
        #expect(!source.contains("Packets Dropped"))
    }

    @Test("Breakpoint Rules and editor use scalable min frames, not a fixed 1200x675 shell")
    func breakpointWindowsUseScalableMinFrames() throws {
        let windowSource = try readProjectFile("Rockxy/Views/Breakpoint/BreakpointRulesWindowView.swift")
        let editorSource = try readProjectFile("Rockxy/Views/Breakpoint/BreakpointRuleEditorWindowView.swift")

        // Adaptive min sizing derived from Appearance metrics.
        #expect(windowSource.contains(".frame(\n            minWidth: max("))
        #expect(windowSource.contains("minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496)"))
        #expect(windowSource.contains("minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)"))

        #expect(editorSource.contains(".frame(\n            minWidth: max("))
        #expect(editorSource.contains("minWidth: max(760, toolMetrics.bodyFontSize * 24 + 472)"))
        #expect(editorSource.contains("minHeight: max(430, toolMetrics.bodyFontSize * 13 + 261)"))

        // No fixed 1200x675 shell in either window.
        for file in [windowSource, editorSource] {
            #expect(!file.contains(".frame(width: 1200, height: 675)"))
            #expect(!file.contains(".frame(width: 1_200, height: 675)"))
        }
    }

    @Test("Breakpoint Rules window uses the approved native management structure")
    func breakpointRulesUsesApprovedNativeStructure() throws {
        let source = try readProjectFile("Rockxy/Views/Breakpoint/BreakpointRulesWindowView.swift")

        // Fixed search field, native Table, and a separate Enabled column.
        #expect(source.contains(#"TextField(String(localized: "Search rules", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains(#".keyboardShortcut("f", modifiers: .command)"#))
        #expect(source.contains(".focused($searchIsFocused)"))
        #expect(source.contains("Table(viewModel.filteredBreakpointRules"))
        #expect(source.contains(#"TableColumn(String(localized: "Enabled", bundle: RockxyLocalization.bundle))"#))

        // Info banner + status capsule + native empty state.
        #expect(source.contains(#"Image(systemName: "pause.circle")"#))
        #expect(source.contains(".rockxyChipStyle("))
        #expect(source.contains("ACTIVE"))
        #expect(source.contains("BREAKPOINTS OFF"))
        #expect(source.contains("ContentUnavailableView"))

        // Semantic card surfaces.
        #expect(source.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(source.contains("RoundedRectangle(cornerRadius: 6)"))
        #expect(source.contains(".stroke(Color(nsColor: .separatorColor), lineWidth: 1)"))

        // Forbidden legacy markers: hidden filter bar, New Folder, Test your Rule,
        // bare Space shortcut, fixed shell.
        #expect(!source.contains("BreakpointFilterBar"))
        #expect(!source.contains("isFilterBarVisible"))
        #expect(!source.contains("filterColumn"))
        #expect(!source.contains("New Folder"))
        #expect(!source.contains("Test your Rule"))
        #expect(!source.contains(".keyboardShortcut(.space, modifiers: [])"))
    }

    @Test("Breakpoint rule editor uses the approved native editor structure")
    func breakpointRuleEditorUsesApprovedNativeStructure() throws {
        let source = try readProjectFile("Rockxy/Views/Breakpoint/BreakpointRuleEditorWindowView.swift")

        // Approved editor sections and semantic card surfaces.
        #expect(source.contains(#"String(localized: "Rule Details", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains(#"String(localized: "Pause Phases", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(source.contains(".stroke(Color(nsColor: .separatorColor), lineWidth: 1)"))

        // Equal footer buttons via the shared label, with native footer shortcuts.
        #expect(source.contains("footerButtonLabel"))
        #expect(source.components(separatedBy: "footerButtonLabel(").count - 1 >= 2)
        #expect(source.contains(".keyboardShortcut(.cancelAction)"))
        #expect(source.contains(".keyboardShortcut(.return, modifiers: .command)"))

        // Exactly one custom caret (menu chevron) in the editor.
        #expect(source.components(separatedBy: "chevron.up.chevron.down").count - 1 == 1)

        // Forbidden legacy markers.
        #expect(!source.contains("New Folder"))
        #expect(!source.contains("Test your Rule"))
        #expect(!source.contains(".keyboardShortcut(.space, modifiers: [])"))
    }

    @Test("Breakpoint Templates window uses the approved native master-detail structure")
    func breakpointTemplateWindowUsesApprovedNativeStructure() throws {
        let source = try readProjectFile("Rockxy/Views/Breakpoint/BreakpointTemplateWindowView.swift")
        let queueEditorSource = try readProjectFile("Rockxy/Views/Breakpoint/BreakpointEditorView.swift")

        // Adaptive 860/620 min frame (shared tool-window family), search field, segmented kind control.
        #expect(source.contains("minWidth: max(860,"))
        #expect(source.contains("minHeight: max(620,"))
        #expect(source.contains(#"String(localized: "Search"#))
        #expect(source.contains(".pickerStyle(.segmented)"))

        // Native list + real empty state, approved section titles, shared code-editor settings.
        #expect(source.contains("ContentUnavailableView"))
        #expect(source.contains("Template Details"))
        #expect(source.contains("Raw HTTP Message"))
        #expect(source.contains("codeEditorSettings"))
        #expect(source.contains("Open Queue"))

        // Semantic card surfaces: textBackgroundColor, radius 6, 1pt separator strokes.
        #expect(source.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(source.contains("RoundedRectangle(cornerRadius: 6)"))
        #expect(source.contains(".stroke(Color(nsColor: .separatorColor), lineWidth: 1)"))

        // Accessible add/remove controls and an explicit delete confirmation (no silent count guard).
        #expect(source.contains("accessibilityLabel"))
        #expect(
            source.contains(".confirmationDialog(") || source.contains(".alert("),
            "Breakpoint Templates window must confirm deletion instead of guarding on template count"
        )

        // Forbidden legacy markers (contract item 5).
        #expect(!source.contains("NSSound.beep()"))
        #expect(!source.contains("templates.count <= 1"))
        #expect(!source.contains("Breakpoint Window -> Select Raw Tab -> Template"))
        #expect(!source.contains("cornerRadius: 10"))
        #expect(!source.contains(".overlay(Rectangle().stroke"))
        #expect(!source.contains(".keyboardShortcut(.delete, modifiers: .command)"))

        // Queue application is atomic: invalid templates are disabled and cannot update the visible raw draft.
        #expect(queueEditorSource.contains(".disabled(!validation.isValid)"))
        #expect(queueEditorSource.contains("guard let application = template.applicationPayload"))
        #expect(queueEditorSource.contains("draft = application.applying(to: draft)"))
    }

    @Test("Breakpoint Queue uses a native interruption-safe master-detail flow")
    func breakpointQueueUsesNativeInterruptionSafeStructure() throws {
        let source = try readProjectFile("Rockxy/Views/Breakpoint/BreakpointWindowView.swift")
        let editorSource = try readProjectFile("Rockxy/Views/Breakpoint/BreakpointEditorView.swift")
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")

        #expect(source.contains("HSplitView"))
        #expect(source.contains("VSplitView"))
        #expect(source.contains("List(selection: queueSelection)"))
        #expect(source.contains("ContentUnavailableView"))
        #expect(source.contains(#"String(localized: "No Paused Traffic", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains("ToolWindowDisplayMetrics"))
        #expect(source.contains("minWidth: max(1_060, toolMetrics.bodyFontSize * 34 + 618)"))
        #expect(source.contains("minHeight: max(640, toolMetrics.bodyFontSize * 18 + 406)"))
        #expect(appSource.contains(".defaultSize(width: 1_120, height: 720)"))

        #expect(source.contains(#"String(localized: "Continue Original", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains(#"String(localized: "Abort with 503", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains(#"String(localized: "Apply Changes & Continue", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains(#".keyboardShortcut(".", modifiers: .command)"#))
        #expect(!source.contains(#"String(localized: "Skip Once", bundle: RockxyLocalization.bundle)"#))
        #expect(!source.contains(#"String(localized: "Execute All", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains(".confirmationDialog("))

        #expect(editorSource.contains("ContentUnavailableView"))
        #expect(editorSource.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(editorSource.contains("RoundedRectangle(cornerRadius: 6)"))
        #expect(editorSource.contains(".stroke(Color(nsColor: .separatorColor), lineWidth: 1)"))
        #expect(editorSource.contains(#"String(localized: "Path and query", bundle: RockxyLocalization.bundle)"#))
        #expect(editorSource.contains(#"String(localized: "Host, path, and query", bundle: RockxyLocalization.bundle)"#))
        #expect(editorSource.contains("httpSchemePrefix(itemId: itemId)"))
        #expect(editorSource.contains("canApplySelectedChanges = validation.isValid"))
        #expect(editorSource.contains("syncRawMessageFromDraft(itemId: selectedItemId, force: true)"))
        #expect(source.contains("item.editableDraft.isBodyEditable"))
        #expect(editorSource
            .contains(#"String(localized: "Original payload protected", bundle: RockxyLocalization.bundle)"#))
        #expect(editorSource.contains("draftFor(itemId)?.isBodyEditable == false"))
        #expect(editorSource.contains("canApplySelectedChanges = true"))
    }

    @Test("HTTPS decryption and full proxy bypass keep distinct native workflows")
    func httpsDecryptionAndFullProxyBypassUseApprovedStructure() throws {
        let sslSource = try readProjectFile("Rockxy/Views/Settings/SSLProxyingListView.swift")
        let sslViewModelSource = try readProjectFile("Rockxy/Views/Settings/SSLProxyingListViewModel.swift")
        let sslApplicationSheetSource = try readProjectFile("Rockxy/Views/Settings/AddSSLApplicationSheet.swift")
        let requestTableSource = try readProjectFile("Rockxy/Views/RequestList/RequestTableView.swift")
        let sidebarSource = try readProjectFile("Rockxy/Views/Sidebar/SidebarView.swift")
        let contentSource = try readProjectFile("Rockxy/ContentView.swift")
        let notificationSource = try readProjectFile("Rockxy/Core/Services/Infrastructure/AppNotifications.swift")
        let bypassSource = try readProjectFile("Rockxy/Views/Settings/BypassProxyListView.swift")
        let tlsExceptionsSource = try readProjectFile("Rockxy/Views/Settings/BypassProxySettingsSheet.swift")
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")

        #expect(sslSource.contains("Table(viewModel.filteredRows"))
        #expect(sslSource.contains(#"TableColumn(String(localized: "Target", bundle: RockxyLocalization.bundle))"#))
        #expect(sslSource.contains(#"TableColumn(String(localized: "Scope", bundle: RockxyLocalization.bundle))"#))
        #expect(sslSource.contains(#"TableColumn(String(localized: "Behavior", bundle: RockxyLocalization.bundle))"#))
        #expect(sslViewModelSource.contains(#"String(localized: "Decrypt HTTPS", bundle: RockxyLocalization.bundle)"#))
        #expect(sslViewModelSource
            .contains(#"String(localized: "Tunnel Without Decryption", bundle: RockxyLocalization.bundle)"#))
        #expect(sslSource.contains("Tunnel rules take priority on overlaps"))
        #expect(sslSource.contains("row order does not affect matching"))
        #expect(sslSource.contains("PASSTHROUGH ACTIVE"))
        #expect(sslSource.contains(#".keyboardShortcut("f", modifiers: .command)"#))
        #expect(!appSource.contains(".commands { SSLProxyingCommands() }"))
        #expect(!sslSource.contains(#"CommandMenu(String(localized: "HTTPS Decryption""#))
        #expect(!sslSource.contains(#".keyboardShortcut("n", modifiers: .command)"#))
        #expect(!sslSource.contains(#".keyboardShortcut("n", modifiers: [.command, .option])"#))
        #expect(notificationSource.contains("openSSLProxyingList"))
        #expect(contentSource.contains(#"openWindow(id: "sslProxyingList")"#))
        #expect(requestTableSource.contains("Open HTTPS Decryption"))
        #expect(requestTableSource.contains("handleOpenSSLProxyingList"))
        #expect(sidebarSource.contains("Open HTTPS Decryption"))
        #expect(sslSource.contains("Replace existing HTTPS decryption settings?"))
        #expect(!sslSource.contains("Include List"))
        #expect(!sslSource.contains("Exclude List"))

        #expect(sslApplicationSheetSource.contains("List(selection: $selectedIdentifier)"))
        #expect(sslApplicationSheetSource.contains("DisclosureGroup"))
        #expect(sslApplicationSheetSource.contains(
            "} label: {\n                            applicationRow(app, identity: identity)"
        ))
        #expect(sslApplicationSheetSource.contains(#"ForEach(app.domains, id: \.self)"#))
        #expect(sslApplicationSheetSource
            .contains(#"String(localized: "Behavior", bundle: RockxyLocalization.bundle)"#))
        #expect(sslApplicationSheetSource.contains(".pickerStyle(.segmented)"))
        #expect(sslApplicationSheetSource.contains(".rockxyGlassButtonStyle(prominent: true)"))

        #expect(bypassSource.contains("Table(filteredDomains"))
        #expect(bypassSource.contains("System-proxy clients matching these patterns connect directly"))
        #expect(bypassSource.contains("Manually configured clients that still reach Rockxy"))
        #expect(bypassSource.contains("Replace existing Full Proxy Bypass entries?"))
        #expect(bypassSource.contains("No Full Proxy Bypass Entries"))

        #expect(tlsExceptionsSource.contains("TLS Passthrough Exceptions"))
        #expect(tlsExceptionsSource.contains("They do not bypass the proxy"))
        #expect(appSource
            .contains(
                #"Window(String(localized: "HTTPS Decryption", bundle: RockxyLocalization.bundle), id: "sslProxyingList")"#
            ))
        #expect(appSource
            .contains(
                #"Window(String(localized: "Full Proxy Bypass", bundle: RockxyLocalization.bundle), id: "bypassProxyList")"#
            ))
    }

    @Test("Scripting List uses the approved native window and honest action routing")
    func scriptingListUsesApprovedNativeStructure() throws {
        let source = try readProjectFile("Rockxy/Views/Scripting/ScriptingListWindowView.swift")
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")

        // Adaptive metric-driven shell, no pinned 1200x672 frame.
        #expect(source.contains("minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496)"))
        #expect(source.contains("minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)"))
        #expect(!source.contains(".frame(width: 1_200, height: 672)"))

        // Header: real master toggle + always-visible search + filter selector.
        #expect(source.contains(#"String(localized: "Enable Scripting", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains("TextField("))
        #expect(source.contains("localized: \"Search scripts\""))
        #expect(source.contains("ScriptListFilterColumn.allCases"))

        // Native Table with an explicit optional-ID single selection
        // and the separated Enabled / Method / Matching Rule / Status columns.
        #expect(source.contains("Table(viewModel.filteredDisplayRows, selection: selectedRow)"))
        #expect(source.contains("Binding<ScriptListRowID?>"))
        #expect(!source.contains("Binding<Set<ScriptListRowID>>"))
        #expect(source.components(separatedBy: "TableColumn(").count - 1 == 5)
        #expect(source.contains(".font(toolMetrics.tableHeaderFont())"))
        #expect(source.contains(".alignment(.center)"))
        #expect(source.contains(".controlSize(toggleControlSize)"))
        #expect(source.contains("font(monospaced: true)"))

        // Empty state distinguishes no scripts from no search results.
        #expect(source.contains("ContentUnavailableView"))
        #expect(source.contains(#"String(localized: "No Scripts", bundle: RockxyLocalization.bundle)"#))
        #expect(source.contains(#"String(localized: "No Matching Scripts", bundle: RockxyLocalization.bundle)"#))

        // Info banner is truthful for all three modes (never always "stops").
        #expect(source.contains("Scripting is off."))
        #expect(source.contains("Matching scripts can run in sequence"))
        #expect(source.contains("stops after the first matching script returns a result"))

        // Status capsule + semantic card surfaces.
        #expect(source.contains("SCRIPTING OFF"))
        #expect(source.contains("ACTIVE"))
        #expect(source.contains(".rockxyChipStyle("))
        #expect(source.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(source.contains("RoundedRectangle(cornerRadius: 6)"))
        #expect(source.contains(".stroke(Color(nsColor: .separatorColor), lineWidth: 1)"))

        // Both delete kinds are confirmed; folder removal preserves its scripts.
        #expect(source.contains(".confirmationDialog("))
        #expect(source.contains("Scripts inside it are kept"))

        // Single user-visible alert for surfaced operation failures.
        #expect(source.contains("viewModel.operationError"))

        // List-to-editor handoff is preserved on create / edit / double-click.
        #expect(source.contains(#"openWindow(id: "scriptEditor")"#))
        #expect(source.contains("viewModel.createNewScript()"))
        #expect(source.contains("viewModel.openEditorForSelection()"))
        #expect(source.contains("viewModel.openEditor(for: id)"))

        // Enable toggles read from the snapshot and route through the view model.
        #expect(source.contains("get: { script.isEnabled }"))
        #expect(source.contains("viewModel.setScriptEnabled(id: script.id, enabled: enabled)"))
        #expect(source.contains("viewModel.setScriptsEnabled(ids: folder.scriptIDs"))

        // Truthful shortcuts.
        #expect(source.contains(#".keyboardShortcut("n", modifiers: .command)"#))
        #expect(source.contains(#".keyboardShortcut("n", modifiers: [.command, .shift])"#))
        #expect(source.contains(#".keyboardShortcut("d", modifiers: .command)"#))
        #expect(source.contains(".keyboardShortcut(.delete, modifiers: .command)"))
        #expect(source.contains(#".keyboardShortcut("f", modifiers: .command)"#))
        #expect(source.contains(".focused($searchIsFocused)"))
        #expect(source.contains(".onKeyPress(.return, phases: .down, action: handleReturnKeyPress)"))
        #expect(source.contains(".onKeyPress(.space, phases: .down, action: handleSpaceKeyPress)"))

        // One dynamic enable/disable label, no duplicate "Enable Rule" items.
        #expect(source.contains("enableDisableLabel"))
        #expect(source.contains(#"String(localized: "Disable Script", bundle: RockxyLocalization.bundle)"#))
        #expect(!source.contains("Enable Rule"))
        #expect(!source.contains(#"runtimeStatus == "Active""#))

        // Removed no-op affordances.
        #expect(!source.contains("Show in Finder"))
        #expect(!source.contains("Export Settings"))
        #expect(!source.contains("Import Settings"))
        #expect(!source.contains("Open local file with"))
        #expect(!source.contains("questionmark.circle"))

        // Scene is resizable native chrome, not a contentSize-only 1200x672 shell.
        let sceneStart = try #require(
            appSource
                .range(
                    of: "Window(String(localized: \"Scripting\", bundle: RockxyLocalization.bundle), id: \"scriptingList\")"
                )
        )
        let scenesAfter = appSource[sceneStart.lowerBound...]
        let nextScene = try #require(
            scenesAfter
                .range(
                    of: "Window(String(localized: \"Script Editor\", bundle: RockxyLocalization.bundle), id: \"scriptEditor\")"
                )
        )
        let sceneSource = scenesAfter[..<nextScene.lowerBound]
        #expect(sceneSource.contains(".windowToolbarStyle(.unifiedCompact)"))
        #expect(!sceneSource.contains(".windowResizability(.contentSize)"))
        #expect(!sceneSource.contains(".defaultSize(width: 1_200, height: 672)"))
    }

    // MARK: Private

    private enum ResolveError: Error, CustomStringConvertible {
        case rootNotFound(filePath: String)

        // MARK: Internal

        var description: String {
            switch self {
            case let .rootNotFound(filePath):
                "Could not locate RockxyTests directory from \(filePath)"
            }
        }
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        let root = try resolveProjectRoot()
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func projectSwiftFiles(under relativePath: String) throws -> [String] {
        let root = try resolveProjectRoot()
        let url = root.appendingPathComponent(relativePath)
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var files: [String] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else {
                continue
            }
            let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            files.append(relative)
        }
        return files.sorted()
    }

    private func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        url.deleteLastPathComponent()
        return url
    }
}

// MARK: - Advanced Proxy Settings workflow contracts

@MainActor
extension ToolWindowReadabilityTests {
    @Test("Advanced Proxy Settings derives system routing from live coordinator state, not autoStartProxy")
    func advancedProxySettingsUsesLiveCoordinatorState() throws {
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")
        let viewSource = try readProjectFile("Rockxy/Views/Settings/AdvancedProxySettingsView.swift")

        // The scene injects the live coordinator and uses the standard tool-window shell.
        #expect(appSource.contains("AdvancedProxySettingsView(coordinator: mainCoordinator)"))
        let sceneStart = try #require(
            appSource
                .range(
                    of: "String(localized: \"Advanced Proxy Settings\", bundle: RockxyLocalization.bundle)"
                )
        )
        let scenesAfter = appSource[sceneStart.lowerBound...]
        let nextScene = try #require(
            scenesAfter
                .range(
                    of: "String(localized: \"Babylon Pairing\", bundle: RockxyLocalization.bundle)"
                )
        )
        let sceneSource = scenesAfter[..<nextScene.lowerBound]
        #expect(sceneSource.contains(".windowResizability(.contentSize)"))
        #expect(sceneSource.contains(".defaultPosition(.center)"))
        #expect(sceneSource.contains(".windowToolbarStyle(.unifiedCompact)"))

        // The view takes the coordinator and reads live proxy state for routing.
        // The live listen port comes from the coordinator runtime snapshot, not the
        // bare activeProxyPort, so the endpoint reflects the real address + fallback.
        #expect(viewSource.contains("let coordinator: MainContentCoordinator"))
        #expect(viewSource.contains("coordinator.isProxyRunning"))
        #expect(viewSource.contains("coordinator.isSystemProxyConfigured"))
        #expect(viewSource.contains("coordinator.toggleSystemProxyOverride()"))
        #expect(viewSource.contains("coordinator.refreshProxyOverrideStatus()"))

        // No live-state decision may read the orphaned autoStartProxy field, and the
        // old static-shortcut / no-op affordances must be gone.
        #expect(!viewSource.contains("autoStartProxy"))
        #expect(!viewSource.contains("systemProxyActive"))
        #expect(!viewSource.contains("Toggle ON"))
        #expect(!viewSource.contains("Toggle OFF"))
        #expect(!viewSource.contains("\u{2325}\u{2318}O"))

        // Enabling routing is unavailable while the proxy server is stopped.
        #expect(viewSource.contains(".disabled(!coordinator.isProxyRunning)"))

        // Listener settings use an explicit validated draft with Cancel / Apply / Restore Defaults.
        #expect(viewSource.contains("AdvancedProxySettingsDraft"))
        #expect(viewSource.contains("private func applyListenerSettings()"))
        #expect(viewSource.contains("draft = savedDraft"))
        #expect(viewSource.contains("draft = .default"))
        #expect(viewSource.contains(".disabled(!isDirty || !draft.canApply)"))
        #expect(viewSource.contains("listenerChangeNeedsRestart"))
        #expect(viewSource.contains("apply after the proxy restarts"))

        // Live endpoint + restart truth read the coordinator runtime snapshot,
        // never a hard-coded loopback endpoint.
        #expect(viewSource.contains("coordinator.runtimeListenerSnapshot"))
        #expect(viewSource.contains("snapshot.listenAddress"))
        #expect(viewSource.contains("snapshot.resolvedPort"))
        #expect(viewSource.contains("matchesRequestedListener"))
        #expect(!viewSource.contains("127.0.0.1:\\(coordinator.activeProxyPort)"))

        // The unsupported IPv6 dual-stack control and its dishonest copy are gone.
        #expect(!viewSource.contains("$draft.listenIPv6"))
        #expect(!viewSource.contains("draft.listenIPv6"))
        #expect(!viewSource.contains("Listen on IPv4 & IPv6"))
        #expect(!viewSource.contains("::0 (IPv6)"))

        // Truthful system-proxy copy that acknowledges apps may ignore the setting.
        #expect(viewSource.contains("macOS System Proxy Enabled"))
        #expect(viewSource.contains("Proxy-aware traffic"))
        #expect(!viewSource.contains("System Traffic Routed Through Rockxy"))

        // Merge-only apply so unrelated listener edits elsewhere are not clobbered.
        #expect(viewSource.contains("changedFrom: savedDraft"))

        // Cancel restores the draft and dismisses; accessibility is provided for the port.
        #expect(viewSource.contains("@Environment(\\.dismiss) private var dismiss"))
        #expect(viewSource.contains("dismiss()"))
        #expect(viewSource
            .contains(
                ".accessibilityLabel(String(localized: \"Listener port number\", bundle: RockxyLocalization.bundle))"
            ))

        // Footer and helper actions adapt to large fonts instead of overflowing one row.
        #expect(viewSource.contains("ViewThatFits(in: .horizontal)"))

        // Honest live-vs-next-start separation and shared tool-window shell.
        #expect(viewSource.contains("Live listener"))
        #expect(viewSource.contains("ToolWindowDisplayMetrics"))
        #expect(viewSource.contains("coordinator.systemProxyWarning"))
        #expect(viewSource.contains("coordinator.proxyError"))
    }
}
