import CoreGraphics
import Foundation
@testable import Rockxy
import Testing

@MainActor
struct ToolWindowReadabilityTests {
    @Test("Tool window display metrics derive from Appearance font size")
    func toolWindowDisplayMetricsDeriveFromAppearanceFontSize() {
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

    @Test("Settings display metrics derive from Appearance font size")
    func settingsDisplayMetricsDeriveFromAppearanceFontSize() {
        let cases: [(fontSize: Int, width: CGFloat, height: CGFloat, labelWidth: CGFloat, controlHeight: CGFloat)] = [
            (10, 820, 600, 160, 24),
            (12, 820, 600, 160, 24),
            (13, 820, 600, 160, 25),
            (14, 820, 600, 160, 26),
            (20, 820, 600, 160, 32),
            (28, 820, 600, 160, 40),
        ]

        for item in cases {
            var appUI = AppUISettings()
            appUI.fontSize = item.fontSize
            let metrics = SettingsDisplayMetrics(appMetrics: AppUIDisplayMetrics(settings: appUI))

            #expect(metrics.bodyFontSize == CGFloat(item.fontSize))
            #expect(metrics.secondaryFontSize == max(10, CGFloat(item.fontSize - 1)))
            #expect(metrics.metadataFontSize == max(10, CGFloat(item.fontSize - 2)))
            #expect(metrics.windowWidth == item.width)
            #expect(metrics.windowHeight == item.height)
            #expect(metrics.labelWidth == item.labelWidth)
            #expect(metrics.controlHeight == item.controlHeight)
            #expect(metrics.fieldWidth(200) >= 200)
            #expect(metrics.menuWidth(120) >= 120)
        }
    }

    @Test("Settings scene and tabs use display metrics")
    func settingsSceneAndTabsUseDisplayMetrics() throws {
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")
        #expect(appSource.contains("Settings {\n            AppUIDisplayMetricsProvider"), "Settings scene must inherit Appearance display metrics")

        let files = [
            "Rockxy/Views/Settings/SettingsView.swift",
            "Rockxy/Views/Settings/GeneralSettingsTab.swift",
            "Rockxy/Views/Settings/AppearanceSettingsTab.swift",
            "Rockxy/Views/Settings/PrivacySettingsTab.swift",
            "Rockxy/Views/Settings/MCPSettingsTab.swift",
            "Rockxy/Views/Settings/GitHubSettingsTab.swift",
            "Rockxy/Views/Settings/PluginsSettingsTab.swift",
            "Rockxy/Views/Settings/PluginDetailView.swift",
            "Rockxy/Views/Settings/ToolsSettingsTab.swift",
            "Rockxy/Views/Settings/PreviewerTabSettingsView.swift",
            "Rockxy/Views/Settings/CustomHeaderColumnsView.swift",
            "Rockxy/Views/Settings/AdvancedSettingsTab.swift",
        ]

        for file in files {
            let source = try readProjectFile(file)
            #expect(source.contains("SettingsDisplayMetrics"), "\(file) should derive settings metrics from Appearance")
        }
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
            #expect(source.contains(#"id: "\#(id)") {"#), "Missing window id \(id)")
            let idRange = try #require(source.range(of: #"id: "\#(id)") {"#))
            let remaining = source[idRange.upperBound...]
            let providerRange = remaining.range(of: "ToolWindowDisplayMetricsProvider")
            #expect(providerRange != nil, "Window \(id) must use ToolWindowDisplayMetricsProvider")
            if let providerRange {
                #expect(remaining.distance(from: remaining.startIndex, to: providerRange.lowerBound) < 140)
            }
        }
    }

    @Test("Readable tool windows use tool metrics")
    func readableToolWindowsUseToolMetrics() throws {
        let files = [
            "Rockxy/Views/Rules/MapRemoteWindowView.swift",
            "Rockxy/Views/Rules/MapLocalWindowView.swift",
            "Rockxy/Views/Rules/BlockListWindowView.swift",
            "Rockxy/Views/Rules/AllowListWindowView.swift",
            "Rockxy/Views/Rules/AddAllowListRuleSheet.swift",
            "Rockxy/Views/Rules/NetworkConditionsWindowView.swift",
            "Rockxy/Views/Rules/ModifyHeaderWindowView.swift",
            "Rockxy/Views/Rules/ModifyHeaderEditorView.swift",
            "Rockxy/Views/Rules/ProtobufSettingsWindowView.swift",
            "Rockxy/Views/Rules/ProtobufSchemaListWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRulesWindowView.swift",
            "Rockxy/Views/Breakpoint/AddBreakpointRuleSheet.swift",
            "Rockxy/Views/Breakpoint/BreakpointWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointQueueListView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRuleRow.swift",
            "Rockxy/Views/Breakpoint/BreakpointEditorView.swift",
            "Rockxy/Views/Breakpoint/BreakpointRuleEditorWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointTemplateWindowView.swift",
            "Rockxy/Views/Scripting/ScriptingListWindowView.swift",
            "Rockxy/Views/Scripting/ScriptListRow.swift",
            "Rockxy/Views/Scripting/ScriptEditorWindowView.swift",
            "Rockxy/Views/Scripting/ScriptConsolePanel.swift",
        ]

        for file in files {
            let source = try readProjectFile(file)
            #expect(source.contains("ToolWindowDisplayMetrics"), "\(file) should derive readable tool-window metrics")
        }
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
            #expect(source.contains(".frame(\n            minWidth: max("), "\(file) should use scalable min window dimensions")
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

    @Test("Block and Allow List follow Scripting window layout rhythm")
    func blockAndAllowListFollowScriptingWindowLayoutRhythm() throws {
        let files = [
            "Rockxy/Views/Rules/BlockListWindowView.swift",
            "Rockxy/Views/Rules/AllowListWindowView.swift",
        ]
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
            #expect(source.contains(".frame(width: 1_200, height: 672)"), "\(file) should match Scripting window height")
            #expect(source.contains(".frame(minHeight: toolMetrics.tableRowHeight * 8, maxHeight: .infinity)"))
            for snippet in forbiddenSnippets {
                #expect(!source.contains(snippet), "\(file) must not keep \(snippet)")
            }
        }
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
            #expect(!source.contains(".padding(.top, toolMetrics.footerTopPadding)"), "\(file) should mirror Scripting footer spacing")
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
            "Rockxy/Views/Rules/MapRemoteWindowView.swift",
            "Rockxy/Views/Rules/NetworkConditionsWindowView.swift",
            "Rockxy/Views/Rules/ProtobufSettingsWindowView.swift",
            "Rockxy/Views/Breakpoint/AddBreakpointRuleSheet.swift",
            "Rockxy/Views/Breakpoint/BreakpointRuleEditorWindowView.swift",
            "Rockxy/Views/Breakpoint/BreakpointSheetView.swift",
            "Rockxy/Views/Breakpoint/BreakpointEditorView.swift",
            "Rockxy/Views/Scripting/ScriptEditorWindowView.swift",
            "Rockxy/Views/Scripting/ScriptListRow.swift",
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
                #expect(!source.contains(snippet), "\(file) must not keep compact fixed setting-window layout \(snippet)")
            }
        }
    }

    @Test("Settings shell keeps fixed dimensions while font size changes")
    func settingsShellKeepsFixedDimensionsWhileFontSizeChanges() throws {
        let source = try readProjectFile("Rockxy/Views/Settings/SettingsView.swift")

        #expect(source.contains(".frame(width: settingsMetrics.windowWidth, height: settingsMetrics.windowHeight)"))
        #expect(!source.contains(".frame(minWidth: settingsMetrics.windowWidth"))
        #expect(!source.contains(".frame(minHeight: settingsMetrics.windowHeight"))
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
            "Rockxy/Views/Breakpoint/AddBreakpointRuleSheet.swift",
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

    @Test("Rule-style tool windows share Scripting layout spacing")
    func ruleStyleToolWindowsShareScriptingLayoutSpacing() throws {
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
            #expect(source.contains("toolMetrics.contentHorizontalPadding"), "\(file) should use shared horizontal padding")
            #expect(source.contains("toolMetrics.footerBottomPadding"), "\(file) should use shared footer padding")
            #expect(!source.contains(".padding(.horizontal, 22)"), "\(file) should not use old oversized padding")
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

    private enum ResolveError: Error, CustomStringConvertible {
        case rootNotFound(filePath: String)

        var description: String {
            switch self {
            case let .rootNotFound(filePath):
                "Could not locate RockxyTests directory from \(filePath)"
            }
        }
    }
}
