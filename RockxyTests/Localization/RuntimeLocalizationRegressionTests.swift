import Foundation
@testable import Rockxy
import Testing

// MARK: - RuntimeLocalizationRegressionTests

/// Guards the corrective pass that makes the runtime app-language selection apply to
/// surfaces that previously stayed frozen in the language captured at first use:
/// inflected `AttributedString` counts, cached localized `static let` messages, the
/// native workspace toolbar labels, and the Developer Setup catalog/guide values.
@MainActor
struct RuntimeLocalizationRegressionTests {
    // MARK: Internal

    @Test("Inflected AttributedString counts resolve through the runtime bundle and locale")
    func inflectedCountsUseRuntimeBundleAndLocale() throws {
        let files = [
            "Rockxy/Views/Projects/ProjectPresentation.swift",
            "Rockxy/Views/Import/ImportReviewSheet.swift",
            "Rockxy/Views/RequestList/RequestTableView.swift",
            "Rockxy/Views/Rules/RuleListView.swift",
            "Rockxy/Views/Export/GistPublishConfirmationSheet.swift",
            "Rockxy/Models/UI/ExportScope.swift",
            "Rockxy/Models/UI/SessionProvenance.swift",
            "Rockxy/Views/RequestList/StatusBarView.swift",
            "Rockxy/Views/Breakpoint/BreakpointWindowView.swift",
            "Rockxy/Views/Inspector/AIAssistantDockView.swift",
            "Rockxy/Views/Inspector/AIInspectorView.swift",
            "Rockxy/Views/Inspector/Web3RPCInspectorView.swift",
            "Rockxy/Views/Inspector/ProtobufTreeView.swift",
            "Rockxy/Views/Settings/SSLProxyingListView.swift",
            "Rockxy/Views/Settings/BypassProxyListView.swift",
            "Rockxy/Views/Sidebar/NoiseControlManagerSheet.swift",
            "Rockxy/Views/Scripting/ScriptingListWindowView.swift",
            "Rockxy/Views/Main/Extensions/MainContentCoordinator+Export.swift",
            "Rockxy/Views/Main/Extensions/MainContentCoordinator+Import.swift",
            "Rockxy/Views/Main/Extensions/MainContentCoordinator+GistPublish.swift",
            "Rockxy/ContentView.swift",
            "Rockxy/Views/Components/JSONTreeView.swift",
            "Rockxy/Views/Diff/DiffControlBar.swift",
        ]

        for file in files {
            let source = try readProjectFile(file)
            for range in ranges(of: "AttributedString(", in: source) {
                // Skip AppKit's NSAttributedString(...) which shares the suffix.
                if range.lowerBound > source.startIndex,
                   source[source.index(before: range.lowerBound)] == "N"
                {
                    continue
                }
                let window = callWindow(in: source, from: range.upperBound)
                // Only inflected/localized initializers must carry the runtime bundle/locale.
                guard window.contains("localized:") else {
                    continue
                }
                #expect(
                    window.contains("RockxyLocalization.bundle"),
                    "\(file): AttributedString(localized:) must pass RockxyLocalization.bundle"
                )
                #expect(
                    window.contains("RockxyLocalization.locale"),
                    "\(file): AttributedString(localized:) must pass RockxyLocalization.locale for inflection"
                )
            }
        }
    }

    @Test("Inflection markup never goes through plain String(localized:)")
    func inflectionMarkupNeverUsesPlainStringLocalized() throws {
        // `String(localized:)` does not apply automatic grammar agreement, so a key
        // written as ^[\(count) rule](inflect: true) renders its raw markup on screen.
        // Only `String(AttributedString(localized:...).characters)` resolves it.
        let root = try resolveProjectRoot().appendingPathComponent("Rockxy")
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var offenders: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else {
                continue
            }
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("(inflect: true)") else {
                continue
            }
            // Match the wrapped form too: `String(\n    localized: "^[…]")` is the same
            // defect, and `AttributedString(`/`NSAttributedString(` must not be mistaken
            // for it, so every `String(` whose call starts with the `localized:` label is
            // inspected regardless of where the formatter broke the line.
            for range in ranges(of: "String(", in: source) {
                if range.lowerBound > source.startIndex,
                   source[source.index(before: range.lowerBound)].isLetter
                   || source[source.index(before: range.lowerBound)] == "_"
                {
                    continue
                }
                let window = callWindow(in: source, from: range.upperBound)
                guard window.drop(while: { $0.isWhitespace }).hasPrefix("localized:") else {
                    continue
                }
                if window.contains("(inflect: true)") {
                    offenders.append(url.lastPathComponent)
                    break
                }
            }
        }
        #expect(
            offenders.isEmpty,
            "Inflected keys must resolve through AttributedString: \(offenders.sorted().joined(separator: ", "))"
        )
    }

    @Test("Presentation messages are re-resolving computed values, not cached static lets")
    func presentationMessagesAreRecomputed() throws {
        let diff = try readProjectFile("Rockxy/Views/Diff/DiffFormatter.swift")
        #expect(diff.contains("static var captureTruncationNotice: String {"))
        #expect(!diff.contains("static let captureTruncationNotice ="))

        let protobufSettings = try readProjectFile("Rockxy/Views/Rules/ProtobufSettingsWindowView.swift")
        #expect(protobufSettings.contains("static var capabilityNotice: String {"))
        #expect(!protobufSettings.contains("static let capabilityNotice ="))

        let protobufSchemas = try readProjectFile("Rockxy/Views/Rules/ProtobufSchemaListWindowView.swift")
        #expect(protobufSchemas.contains("static var capabilityNotice: String {"))
        #expect(!protobufSchemas.contains("static let capabilityNotice ="))

        let gist = try readProjectFile("Rockxy/Views/Export/GistPublishConfirmationSheet.swift")
        #expect(gist.contains("static var redactionDescription: String {"))
        #expect(gist.contains("static var redactionOffWarning: String {"))
        #expect(gist.contains("static var publicWarning: String {"))
        #expect(!gist.contains("static let redactionDescription ="))
        #expect(!gist.contains("static let publicWarning ="))

        let helper = try readProjectFile("Rockxy/Core/ProxyEngine/HelperManager.swift")
        #expect(helper.contains("static var applicationMustReopenMessage: String {"))
        #expect(helper.contains("static var helperApprovalMessage: String {"))
        #expect(helper.contains("static var helperPackageIncompleteMessage: String {"))
        #expect(!helper.contains("static let applicationMustReopenMessage ="))
        #expect(!helper.contains("static let helperApprovalMessage ="))
        #expect(!helper.contains("static let helperPackageIncompleteMessage ="))
    }

    @Test("Native workspace toolbar re-resolves labels when the runtime language changes")
    func nativeWorkspaceToolbarRefreshesOnLanguageChange() throws {
        let source = try readProjectFile("Rockxy/Views/Common/NativeWorkspaceWindowChrome.swift")

        // Tool-window descriptor labels are re-resolved on demand instead of frozen once.
        #expect(source.contains("static var toolWindowItemDescriptors: [ToolWindowItemDescriptor] {"))
        #expect(!source.contains("static let toolWindowItemDescriptors:"))
        // Stable identifiers stay cached so the allowed/customizable sets never shift.
        #expect(source.contains("static let toolWindowItemIdentifiers:"))

        // The observation tracks the language selection and refreshes existing items in place.
        #expect(source.contains("_ = AppLanguageController.shared.selectedOptionID"))
        #expect(source.contains("func refreshLocalizedLabelsIfLanguageChanged()"))
        #expect(source.contains("for item in managedToolbar.items"))
    }

    @Test("Developer Setup catalog re-resolves target titles and summaries on demand")
    func developerSetupCatalogIsRecomputed() throws {
        let source = try readProjectFile("Rockxy/Models/UI/DeveloperSetupCatalog.swift")

        #expect(source.contains("static var python: SetupTarget {"))
        #expect(source.contains("static var docker: SetupTarget {"))
        #expect(source.contains("static var runtimeTargets: [SetupTarget] {"))
        #expect(!source.contains("static let python ="))
        #expect(!source.contains("static let runtimeTargets:"))
        // Identity list stays a stable constant for pinning defaults.
        #expect(source.contains("static let defaultPinnedTargetIDs:"))
    }

    @Test("Developer Setup guide tips rebind to the runtime bundle and locale")
    func developerSetupGuideTipsRebindToRuntime() throws {
        let source = try readProjectFile("Rockxy/Models/UI/DeveloperSetupGuideCatalog.swift")

        #expect(source
            .contains("func runtimeLocalized(_ resource: LocalizedStringResource) -> LocalizedStringResource"))
        #expect(source.contains(".atURL(RockxyLocalization.bundle.bundleURL)"))
        #expect(source.contains("locale: RockxyLocalization.locale"))
        #expect(source.contains("runtimeLocalized(title)"))
        #expect(source.contains("runtimeLocalized(message)"))
    }

    @Test("Developer Setup selection is tracked by stable identity and re-derived from the catalog")
    func developerSetupSelectionTrackedByStableIdentity() {
        let viewModel = DeveloperSetupViewModel(coordinator: MainContentCoordinator())

        // Stored by stable identifier so the selection survives a runtime language switch.
        viewModel.selectedTargetID = .golang
        #expect(viewModel.selectedTarget.id == .golang)
        // Re-derives from the catalog on every read rather than holding a frozen copy.
        #expect(viewModel.selectedTarget == SetupTarget.target(for: .golang))

        // Assigning through the value setter maps back to the stable identifier.
        viewModel.selectedTarget = SetupTarget.docker
        #expect(viewModel.selectedTargetID == .docker)
        #expect(viewModel.selectedTarget.id == .docker)
    }

    @Test("HTTP status-code table and breakpoint call sites use a contextual compact key, not Code")
    func statusCodeCallSitesUseStatusCodeKey() throws {
        let sites = [
            (
                "Rockxy/Views/RequestList/RequestTableView.swift",
                "id: \"code\",\n                title: String(localized: \"Compact HTTP status code\", bundle: RockxyLocalization.bundle)"
            ),
            (
                "Rockxy/Views/Diff/DiffCandidateTableView.swift",
                "TableColumn(String(localized: \"Compact HTTP status code\", bundle: RockxyLocalization.bundle))"
            ),
            (
                "Rockxy/Views/Breakpoint/BreakpointEditorView.swift",
                "TextField(\n                String(localized: \"Compact HTTP status code\", bundle: RockxyLocalization.bundle)"
            ),
        ]
        for (file, expectedCallSite) in sites {
            let source = try readProjectFile(file)
            #expect(
                !source.contains("localized: \"Code\""),
                "\(file): must not localize the ambiguous \"Code\" key for HTTP status codes"
            )
            // Compared with whitespace collapsed: the formatter rewraps these call sites whenever
            // the surrounding view is edited, and that must not read as a localization regression.
            #expect(
                Self.collapsingWhitespace(source).contains(Self.collapsingWhitespace(expectedCallSite)),
                "\(file): the target status-code call site must use its contextual localization key"
            )
        }
    }

    @Test("VS Code Open-with menu renders the app name verbatim, not through localization")
    func vsCodeLabelIsVerbatim() throws {
        let source = try readProjectFile("Rockxy/Views/Inspector/ResponseInspectorView.swift")
        // Editor product names ("Code", "Cursor", …) render verbatim, never through the catalog.
        #expect(source.contains("Text(verbatim: editor.name)"))
        #expect(source.contains("ResponseBodyEditor(name: \"Code\""))
        #expect(!source.contains("Label(\"Code\""))
        #expect(!source.contains("localized: \"Code\""))
    }

    @Test("Visible enum displayName owners resolve user-facing labels through the runtime bundle")
    func enumDisplayNamesResolveThroughRuntimeBundle() throws {
        let files = [
            "Rockxy/Models/UI/MainTab.swift",
            "Rockxy/Models/UI/InspectorTab.swift",
            "Rockxy/Models/UI/RequestInspectorTab.swift",
            "Rockxy/Models/UI/ResponseInspectorTab.swift",
            "Rockxy/Models/UI/ProtocolFilter.swift",
            "Rockxy/Models/UI/FilterField.swift",
            "Rockxy/Models/Log/LogLevel.swift",
            "Rockxy/Models/Rules/NetworkConditionPreset.swift",
        ]
        for file in files {
            let source = try readProjectFile(file)
            let displayName = try #require(
                declaration(named: "var displayName: String", in: source),
                "\(file): expected a displayName accessor"
            )
            #expect(
                displayName.contains("String(localized:"),
                "\(file): displayName must contain at least one localized visible label"
            )
            for range in ranges(of: "String(localized:", in: displayName) {
                let window = callWindow(in: displayName, from: range.upperBound)
                #expect(
                    window.contains("bundle: RockxyLocalization.bundle"),
                    "\(file): every localized displayName case must use RockxyLocalization.bundle"
                )
            }
            #expect(
                !displayName.contains("String(localized: \"Code\""),
                "\(file): displayName must resolve visible labels through RockxyLocalization.bundle"
            )
        }
    }

    @Test("Protocol, header, and app-name tokens stay verbatim in enum displayName")
    func enumTokensStayVerbatim() {
        // Verbatim tokens never change with the selected language.
        #expect(InspectorTab.websocket.displayName == "WebSocket")
        #expect(InspectorTab.graphql.displayName == "GraphQL")
        #expect(ResponseInspectorTab.ai.displayName == "AI")
        #expect(ResponseInspectorTab.setCookie.displayName == "Set-Cookie")
        #expect(FilterField.url.displayName == "URL")
        #expect(ProtocolFilter.http.displayName == "HTTP")
        #expect(ProtocolFilter.grpc.displayName == "gRPC")
        #expect(NetworkConditionPreset.threeG.displayName == "3G")
        #expect(NetworkConditionPreset.wifi.displayName == "WiFi")
        // Localized labels resolve to a non-empty string in any runtime language.
        #expect(!MainTab.traffic.displayName.isEmpty)
        #expect(!LogLevel.warning.displayName.isEmpty)
        #expect(!FilterField.statusCode.displayName.isEmpty)
        #expect(!NetworkConditionPreset.veryBadNetwork.displayName.isEmpty)
        #expect(!RequestInspectorTab.synopsis.displayName.isEmpty)
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
    }

    /// Removes every whitespace character so a pinned call site survives the formatter rewrapping
    /// it across lines. Applied to both sides, so the spaces inside the compared string literals
    /// drop out symmetrically and the match still means what it says.
    private static func collapsingWhitespace(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    /// The substring covering a single call starting at `start`, up to the matching
    /// close paren (with a generous cap) so multi-line argument lists are inspected
    /// without depending on the formatter's exact line wrapping.
    private func callWindow(in source: String, from start: String.Index) -> String {
        var depth = 1
        var index = start
        let end = source.endIndex
        while index < end, depth > 0 {
            switch source[index] {
            case "(":
                depth += 1
            case ")":
                depth -= 1
            default:
                break
            }
            index = source.index(after: index)
        }
        return String(source[start ..< index])
    }

    private func ranges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchStart ..< haystack.endIndex) {
            result.append(found)
            searchStart = found.upperBound
        }
        return result
    }

    private func declaration(named signature: String, in source: String) -> String? {
        guard let signatureRange = source.range(of: signature),
              let openingBrace = source[signatureRange.upperBound...].firstIndex(of: "{") else
        {
            return nil
        }
        var depth = 0
        var cursor = openingBrace
        while cursor < source.endIndex {
            switch source[cursor] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[signatureRange.lowerBound ... cursor])
                }
            default: break
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        let root = try resolveProjectRoot()
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
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
