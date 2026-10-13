import Foundation
@testable import Rockxy
import Testing

// MARK: - MatchedRuleNavigationTargetTests

struct MatchedRuleNavigationTargetTests {
    @Test("Each windowed rule category routes to its existing tool window")
    func windowedCategoriesRouteToToolWindows() {
        let cases: [(RuleAction, String)] = [
            (.breakpoint(), "breakpointRules"),
            (.mapLocal(filePath: "/tmp/mock.json"), "mapLocal"),
            (.mapRemote(configuration: MapRemoteConfiguration()), "mapRemote"),
            (.block(statusCode: 403), "blockList"),
            (.modifyHeader(operations: []), "modifyHeaders"),
            (.networkCondition(preset: .wifi, delayMs: 0), "networkConditions"),
        ]

        for (action, expectedID) in cases {
            let target = MatchedRuleNavigationTarget(action: action)
            #expect(target.windowID == expectedID, "\(action.toolCategory) should open \(expectedID)")
            #expect(target.openHelp != nil)
        }
    }

    @Test("Throttle has no dedicated window and stays honestly unavailable")
    func throttleIsUnavailable() {
        let target = MatchedRuleNavigationTarget(action: .throttle(delayMs: 1_000))
        #expect(target == .unavailable)
        #expect(target.windowID == nil)
        #expect(target.openHelp == nil)
    }
}

// MARK: - InvestigationResultPresentationTests

struct InvestigationResultPresentationTests {
    // MARK: Internal

    @Test("Evidence groups keep observed → derived → inferred → unknown order and drop empties")
    func evidenceGroupsAreOrderedAndCompact() {
        let evidence = [
            makeEvidence(id: "a", kind: .inferred),
            makeEvidence(id: "b", kind: .observed),
            makeEvidence(id: "c", kind: .unknown),
            makeEvidence(id: "d", kind: .observed),
        ]

        let groups = InvestigationResultPresentation.evidenceGroups(for: evidence)
        #expect(groups.map(\.kind) == [.observed, .inferred, .unknown])
        #expect(groups.first?.evidence.map(\.id) == ["b", "d"])
    }

    @Test("Findings exclude unknowns and the unknowns section captures open questions")
    func findingsAndUnknownsSplitByKind() {
        let evidence = [
            makeEvidence(id: "obs", kind: .observed),
            makeEvidence(id: "der", kind: .derived),
            makeEvidence(id: "unk1", kind: .unknown),
            makeEvidence(id: "unk2", kind: .unknown),
        ]

        let findingGroups = InvestigationResultPresentation.findingGroups(for: evidence)
        #expect(findingGroups.allSatisfy { !$0.isUnknown })
        #expect(findingGroups.map(\.kind) == [.observed, .derived])
        #expect(InvestigationResultPresentation.findingCount(for: evidence) == 2)

        let unknowns = InvestigationResultPresentation.unknowns(for: evidence)
        #expect(unknowns.map(\.id) == ["unk1", "unk2"])
    }

    @Test("Empty evidence yields no groups, findings, or unknowns")
    func emptyEvidenceIsEmpty() {
        #expect(InvestigationResultPresentation.evidenceGroups(for: []).isEmpty)
        #expect(InvestigationResultPresentation.findingGroups(for: []).isEmpty)
        #expect(InvestigationResultPresentation.unknowns(for: []).isEmpty)
        #expect(InvestigationResultPresentation.findingCount(for: []) == 0)
    }

    // MARK: Private

    private func makeEvidence(id: String, kind: InvestigationEvidenceKind) -> InvestigationEvidence {
        InvestigationEvidence(
            id: id,
            kind: kind,
            title: "Finding \(id)",
            detail: "Detail \(id)",
            sourceTransactionID: nil
        )
    }
}

// MARK: - ContextDockInvestigationReportTests

/// Source contract for the conversation surface: assistant replies are enclosed by one coherent
/// neutral rounded `AssistantResponseContainer` (subtle background, hairline border, no assistant
/// identity/icon); the completed investigation uses editorial typography with bold text-only
/// "Summary" and "Next step" headings above a collapsed "Details" disclosure; user prompts stay
/// compact right-aligned bubbles; and every workflow capability survives only behind a Copy control
/// plus one ellipsis overflow menu.
struct ContextDockInvestigationReportTests {
    // MARK: Internal

    @Test("Configured model picker exposes runtime identity and data destination")
    func configuredModelPickerShowsRuntimeAndExecutionLocation() throws {
        let dock = try readProjectFile("Rockxy/Views/Inspector/AIAssistantDockView.swift")
        let presentation = try readProjectFile(
            "Rockxy/Models/Assistant/AssistantModelSelectionPresentation.swift"
        )

        #expect(dock.contains("AssistantModelSelectionPresentation("))
        #expect(dock.contains("modelPresentation.selectionLabel"))
        #expect(dock.contains("modelPresentation.destinationLabel"))
        #expect(presentation.contains("AssistantLocalRuntimePreset.matching(configuration)"))
        #expect(presentation.contains("configuration.executionLocation.isLocal"))
        #expect(presentation.contains("Local endpoint"))
        #expect(presentation.contains("Local ·"))
        #expect(presentation.contains("Remote ·"))
    }

    @Test("Investigation response uses editorial Summary/Next step headings and collapses evidence")
    func investigateRendersAnswerFirstResponse() throws {
        let dock = try readProjectFile("Rockxy/Views/Inspector/AIAssistantDockView.swift")
        let report = try readProjectFile("Rockxy/Views/Inspector/InvestigationEvidenceViews.swift")

        // User prompts render as compact right-aligned chat bubbles (the request side).
        #expect(dock.contains("AssistantUserMessageBubble(text: message.text)"))
        #expect(!dock.contains("AssistantQueryRow"))

        // Assistant turns share the one coherent rounded response container; the report nests inside
        // it. The wrapper is the shared card, never a duplicate identity card type.
        #expect(dock.contains("AssistantResponseContainer(content: content)"))
        #expect(!dock.contains("AssistantResponseCard"))
        #expect(dock.contains("assistantBubble {\n                InvestigationReportView("))
        #expect(dock.contains("InvestigationReportView("))

        // The answer/body sits below a bold text-only "Summary" heading. Local answer is
        // result.summary; a differing model answer is the primary answer rendered as Markdown —
        // never re-shown under a "Model Analysis" section.
        #expect(report.contains("Text(result.summary)"))
        #expect(report.contains("usesModelAnswer(result)"))
        #expect(report.contains("AssistantMarkdownText(source: message.text)"))
        #expect(report.contains("message.text != result.summary"))
        #expect(!report.contains("Model Analysis"))

        // Editorial text-only section headings for Summary and Next step (bold, no SF Symbol).
        #expect(report.contains("String(localized: \"Summary\", bundle: RockxyLocalization.bundle)"))
        #expect(report.contains("String(localized: \"Next step\", bundle: RockxyLocalization.bundle)"))
        #expect(!report.contains("String(localized: \"Proposed Actions\", bundle: RockxyLocalization.bundle)"))
        #expect(!report.contains("InvestigationFindingsDisclosure"))
        #expect(!report.contains("InvestigationReportHeader"))

        // result.nextStep renders below the "Next step" heading when nonempty — no lightbulb, no
        // "Try this next" copy, no pill or mini card.
        #expect(report.contains("result.nextStep"))
        #expect(report.contains("private func nextStep("))
        #expect(!report.contains("String(localized: \"Try this next\", bundle: RockxyLocalization.bundle)"))
        #expect(!report.contains("lightbulb"))

        // Summary and Next step read as three bounded editorial frames: one shared, reusable,
        // text-only section-frame component wraps each, and the Details disclosure wears the same
        // frame chrome. The chrome is a restrained native hairline — a small rounded rectangle with
        // a 0.5 separator-color stroke, compact padding, and no fill tint, icon, badge, shadow, or
        // material. Frames are editorial grouping only, never a dashboard/robot surface.
        #expect(report.contains("struct InvestigationSectionFrame<Content: View>: View"))
        #expect(report
            .contains(
                "InvestigationSectionFrame(title: String(localized: \"Summary\", bundle: RockxyLocalization.bundle)) {"
            ))
        #expect(report
            .contains(
                "InvestigationSectionFrame(title: String(localized: \"Next step\", bundle: RockxyLocalization.bundle)) {"
            ))
        #expect(report.contains("func investigationSectionFrameStyle() -> some View"))
        #expect(report.contains(".investigationSectionFrameStyle()"))
        #expect(report
            .contains(
                "RoundedRectangle(cornerRadius: 6)\n                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)"
            ))
        // The section frame carries no tint, shadow, material, or status color — the reusable
        // component takes only a text title plus content (no systemImage parameter or call site).
        #expect(report.contains("let title: String\n    @ViewBuilder let content: Content"))
        #expect(!report
            .contains(
                "InvestigationSectionFrame(title: String(localized: \"Summary\", bundle: RockxyLocalization.bundle), systemImage:"
            ))
        #expect(!report.contains(".fill(Color("))
        #expect(!report.contains(".shadow("))
        #expect(!report.contains(".ultraThinMaterial"))
        #expect(!report.contains("RoundedRectangle(cornerRadius: 6)\n                    .fill"))

        // Technical material collapses behind one quiet "Details" disclosure, collapsed by default,
        // that still carries scope, grouped findings, unknowns, and local/model attribution + count.
        #expect(report.contains("String(localized: \"Details\", bundle: RockxyLocalization.bundle)"))
        #expect(!report.contains("String(localized: \"Why this answer\", bundle: RockxyLocalization.bundle)"))
        #expect(report.contains("DisclosureGroup(isExpanded: $isEvidenceExpanded)"))
        #expect(report.contains("@State private var isEvidenceExpanded = false"))
        #expect(report.contains("String(localized: \"Scope\", bundle: RockxyLocalization.bundle)"))
        #expect(report.contains("String(localized: \"Findings\", bundle: RockxyLocalization.bundle)"))
        #expect(report.contains("String(localized: \"Unknowns\", bundle: RockxyLocalization.bundle)"))
        #expect(report.contains("InvestigationUnknownsView("))
        #expect(report.contains("scopeTransactionIDs.count) request](inflect: true)"))

        // Detail chrome is simplified: text-only section headings (no SF Symbol argument on
        // InvestigationReportSection) and no group-level accessibility override on the disclosure.
        #expect(report
            .contains(
                "InvestigationReportSection(title: String(localized: \"Scope\", bundle: RockxyLocalization.bundle)) {"
            ))
        #expect(report
            .contains(
                "InvestigationReportSection(title: String(localized: \"Findings\", bundle: RockxyLocalization.bundle)) {"
            ))
        #expect(!report.contains("systemImage: \"scope\""))
        #expect(!report.contains("systemImage: \"list.bullet\""))
        #expect(!report
            .contains(
                ".accessibilityLabel(String(localized: \"Why this answer, evidence and scope\", bundle: RockxyLocalization.bundle))"
            ))
        #expect(!report
            .contains(
                ".accessibilityHint(String(localized: \"Shows evidence and request scope\", bundle: RockxyLocalization.bundle))"
            ))

        // Model provenance lives inside the collapsed disclosure through attributionLabel — plain text
        // (no decorative cpu icon) carrying provider + model + scoped request count, with endpoint host
        // and token usage tucked into a quiet native menu.
        #expect(report.contains("attributionLabel(result)"))
        #expect(report.contains("modelAttributionLabel(modelResult, requestCount:"))
        #expect(report.contains("modelResult.provider.title"))
        #expect(report.contains("modelResult.model"))
        #expect(report.contains("modelResult.endpointHost"))
        #expect(report.contains("usage.inputTokens"))
        #expect(report.contains("usage.outputTokens"))
        #expect(report.contains(".menuStyle(.borderlessButton)"))
        #expect(!report.contains("Label(summary, systemImage: \"cpu\")"))
        #expect(!report.contains("systemImage: \"checkmark.seal\""))

        // The completed non-investigation model reply no longer renders modelAttribution(modelResult)
        // inline below the answer: standard provenance is removed from the visible body and the
        // modelAttribution helper (with its cpu/hand icons) is gone entirely.
        #expect(!dock.contains("modelAttribution(modelResult)"))
        #expect(!dock.contains("private func modelAttribution("))
        #expect(!dock.contains("hand.raised"))

        // Provider, model, endpoint host, and token usage stay accessible only as plain, icon-free
        // rows wired into the response footer's overflow menu through modelProvenanceMenuItems.
        #expect(dock.contains("overflowItems:"))
        #expect(dock.contains("modelProvenanceMenuItems(modelResult)"))
        #expect(dock.contains("modelResult.provider.title"))
        #expect(dock.contains("modelResult.model"))
        #expect(dock.contains("modelResult.endpointHost"))
        #expect(dock.contains("usage.inputTokens"))
        #expect(dock.contains("usage.outputTokens"))

        // The blocked-tool-call safety warning stays visible on the reply as concise plain text.
        #expect(dock.contains("blockedToolCallWarning"))

        // No workflow button is visible in the response body: no bordered/primary handoff button and
        // no in-body actions menu. Every handoff lives only in the footer overflow menu.
        #expect(!report.contains("primaryHandoffButton("))
        #expect(!report.contains("secondaryActionsMenu("))
        #expect(!report.contains(".buttonStyle(.bordered)"))
        #expect(!report.contains(".buttonStyle(.borderedProminent)"))
        #expect(report.contains("handoffMenuItems(result)"))
        #expect(report.contains("recommendedHandoffs(for: result.recipe)"))
        #expect(report.contains("performHandoff("))

        // Model escalation copy still calls the existing review callback and preparing state.
        #expect(report.contains("String(localized: \"Ask Configured Model\", bundle: RockxyLocalization.bundle)"))
        #expect(!report.contains("Continue With Model"))
        #expect(report.contains("onContinueWithModel()"))
        #expect(report
            .contains("String(localized: \"Preparing redacted preview…\", bundle: RockxyLocalization.bundle)"))

        // The existing handoff / replay callbacks remain wired.
        #expect(report.contains("onHandoff"))
        #expect(report.contains("onPrepareReplay"))
    }

    @Test("Expanded Details separates Scope, Findings, finding kinds, Unknowns, and provenance")
    func investigationDetailsUseDistinctBlocksAndDividers() throws {
        let report = try readProjectFile("Rockxy/Views/Inspector/InvestigationEvidenceViews.swift")

        // Major block titles (Scope / Findings / Unknowns) and the Details disclosure label share the
        // Summary / Next step title scale: secondaryFontSize semibold in primary text color — no
        // longer the smaller, secondary metadata scale that made the hierarchy read flat.
        #expect(report
            .contains(
                ".font(.system(size: metrics.secondaryFontSize, weight: .semibold))\n                .foregroundStyle(.primary)"
            ))
        #expect(!report
            .contains("Text(title)\n                .font(.system(size: metrics.metadataFontSize, weight: .semibold))"))
        #expect(report
            .contains(
                "Text(String(localized: \"Unknowns\", bundle: RockxyLocalization.bundle))\n"
                    + "                    .font(.system(size: metrics.secondaryFontSize, weight: .semibold))\n"
                    + "                    .foregroundStyle(.primary)"
            ))

        // Scope and Findings are distinct major blocks, each with its own vertical padding and a real
        // native Divider between them (no icons, dots, badges, or nested cards).
        #expect(report.contains("private func scopeSection("))
        #expect(report
            .contains(
                "scopeSection(result)\n                    .padding(.vertical, 8)\n\n                Divider()"
            ))
        #expect(report.contains("findingsSection(result)\n                    .padding(.vertical, 8)"))

        // Scope body stays selectable/readable at a legible app metric.
        #expect(report
            .contains(
                ".font(.system(size: metrics.secondaryFontSize))\n                .foregroundStyle(.secondary)\n                .textSelection(.enabled)"
            ))

        // Finding-kind subgroups (Observed / Derived / Inferred) are explicit headings at a legible
        // secondary scale and are separated by Dividers when more than one kind is present.
        #expect(report
            .contains(
                "Text(group.kind.title)\n                .font(.system(size: metrics.secondaryFontSize, weight: .medium))"
            ))
        #expect(report.contains("ForEach(Array(findingGroups.enumerated()), id: \\.element.id)"))
        #expect(report.contains("if index > 0 {\n                            Divider()"))

        // Evidence titles are no smaller than secondaryFontSize; evidence detail may stay metadata.
        #expect(report
            .contains(
                "Text(evidence.title)\n                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))"
            ))
        #expect(report
            .contains("Text(evidence.detail)\n                        .font(.system(size: metrics.metadataFontSize))"))

        // Unknowns, when present, are a peer block separated from Findings by a Divider (no empty
        // state); provenance stays at the bottom behind its own Divider.
        #expect(report
            .contains(
                "if !unknowns.isEmpty {\n                    Divider()\n                    InvestigationUnknownsView(unknowns: unknowns, onReveal: onReveal)"
            ))
        #expect(report.contains("Divider()\n\n                attributionLabel(result)"))

        // Reveal behavior, disabled semantics, help, and accessibility labels for evidence stay intact.
        #expect(report.contains(".disabled(evidence.sourceTransactionID == nil)"))
        #expect(report
            .contains(
                "String(localized: \"Reveal the request behind this finding\", bundle: RockxyLocalization.bundle)"
            ))
        #expect(report.contains("\\(evidence.kind.title) finding: \\(evidence.title)"))
    }

    @Test("Ellipsis overflow menu adopts configurable control typography, not mini footer sizing")
    func overflowMenuUsesControlFontMetric() throws {
        let components = try readProjectFile("Rockxy/Views/Inspector/AssistantConversationComponents.swift")

        // Isolate the overflow menu helper so the compact Copy control's sizing is not asserted here.
        let start = try #require(components.range(of: "private var overflowMenu: some View {"))
        let after = components[start.lowerBound...]
        let end = try #require(after.range(of: "private func compactAction("))
        let overflow = String(after[..<end.lowerBound])

        // Still a native Menu carrying every caller-supplied item and built-in action + callback.
        #expect(overflow.contains("Menu {"))
        #expect(overflow.contains("overflowItems"))
        #expect(overflow.contains("Button(action: onFollowUp)"))
        #expect(overflow.contains("String(localized: \"Follow Up\", bundle: RockxyLocalization.bundle)"))
        #expect(overflow.contains("systemImage: \"arrowshape.turn.up.left\""))
        #expect(overflow.contains("Button(action: onRevealRequest)"))
        #expect(overflow.contains("Label(String(localized: \"Reveal Request\", bundle: RockxyLocalization.bundle)"))
        #expect(overflow.contains("Button(action: onRetry)"))
        #expect(overflow.contains("String(localized: \"Review & Retry\", bundle: RockxyLocalization.bundle)"))
        #expect(overflow.contains("systemImage: \"arrow.clockwise\""))

        // The Menu and its ellipsis glyph use the app-wide configurable control font metric so items
        // no longer inherit the footer's metadata scale.
        #expect(overflow.contains(".font(.system(size: metrics.controlFontSize))"))
        #expect(overflow
            .contains("Image(systemName: \"ellipsis\")\n                .font(.system(size: metrics.controlFontSize))"))

        // The overflow Menu no longer forces .mini sizing; it stays compact via frame + fixedSize.
        #expect(!overflow.contains(".controlSize(.mini)"))
        #expect(overflow.contains(".fixedSize()"))
        #expect(overflow.contains(".frame(minWidth: 18, minHeight: 18)"))

        // Accessibility and help are preserved on the overflow control.
        #expect(overflow
            .contains(".accessibilityLabel(String(localized: \"More actions\", bundle: RockxyLocalization.bundle))"))
        #expect(overflow.contains(".help(String(localized: \"More actions\", bundle: RockxyLocalization.bundle))"))

        // The compact Copy control keeps its .mini sizing (asserted outside the overflow helper).
        let copyStart = try #require(components.range(of: "private func compactAction("))
        let copy = String(components[copyStart.lowerBound...])
        #expect(copy.contains(".controlSize(.mini)"))
    }

    @Test("User bubble stays a soft right-aligned bubble; the assistant response is a coherent card")
    func userBubbleAndAssistantResponseCardAreDistinct() throws {
        let components = try readProjectFile("Rockxy/Views/Inspector/AssistantConversationComponents.swift")

        // Request side: a compact, right-aligned, width-constrained bubble with a native control
        // surface, selectable text, and a correct "You:" accessibility label. No avatar or identity.
        #expect(components.contains("struct AssistantUserMessageBubble"))
        #expect(!components.contains("struct AssistantQueryRow"))
        #expect(components.contains(".frame(maxWidth: .infinity, alignment: .trailing)"))
        #expect(components.contains("Spacer(minLength: 44)"))
        #expect(components.contains(".textSelection(.enabled)"))
        #expect(components.contains("String(localized: \"You: \\(text)\", bundle: RockxyLocalization.bundle)"))

        // Response side: one coherent neutral rounded card — subtle background, hairline separator
        // border, compact padding. No assistant logo/icon/identity row and no duplicate card type.
        #expect(components.contains("struct AssistantResponseContainer"))
        #expect(!components.contains("struct AssistantResponseCard"))
        #expect(components.contains("Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9)"))
        #expect(components
            .contains(
                "RoundedRectangle(cornerRadius: 9)\n                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)"
            ))
        #expect(!components.contains("String(localized: \"Rockxy Assistant\", bundle: RockxyLocalization.bundle)"))
        #expect(!components.contains("String(localized: \"AI Assistant Response\", bundle: RockxyLocalization.bundle)"))
        #expect(!components.contains("waveform.badge.magnifyingglass"))

        // Response footer: exactly two quiet affordances — a Copy control and one ellipsis overflow
        // menu. Follow Up is a menu item only, never a visible icon button in the body.
        #expect(components.contains("struct AssistantResponseActionBar"))
        #expect(components.contains("Image(systemName: \"ellipsis\")"))
        #expect(components.contains("String(localized: \"Copy\", bundle: RockxyLocalization.bundle)"))
        #expect(components.contains("String(localized: \"Follow Up\", bundle: RockxyLocalization.bundle)"))
        #expect(components.contains("systemImage: \"arrowshape.turn.up.left\""))
    }

    @Test("Unknowns render only when non-empty and never show a verbose empty state")
    func unknownsRenderOnlyWhenPresent() throws {
        let report = try readProjectFile("Rockxy/Views/Inspector/InvestigationEvidenceViews.swift")
        #expect(report.contains("struct InvestigationUnknownsView"))
        #expect(report.contains("if !unknowns.isEmpty"))
        #expect(!report.contains("No open questions"))
    }

    @Test("Evidence without a source request cannot pretend to navigate")
    func evidenceWithoutSourceIsNotRevealable() throws {
        let report = try readProjectFile("Rockxy/Views/Inspector/InvestigationEvidenceViews.swift")
        #expect(report.contains(".disabled(evidence.sourceTransactionID == nil)"))
    }

    @Test("Empty launcher shows a sparkles hero and every recipe as a two-column card grid")
    func emptyStateUsesRecipeCardLauncher() throws {
        let dock = try readProjectFile("Rockxy/Views/Inspector/AIAssistantDockView.swift")
        let coordinator = try readProjectFile(
            "Rockxy/Views/Main/Extensions/MainContentCoordinator+DebugAssistant.swift"
        )

        // The empty state splits by selection: a restrained native prompt when nothing is selected,
        // the recipe-card launcher when a request is selected.
        #expect(dock.contains("if primaryTransaction == nil"))
        #expect(dock.contains("noSelectionEmptyState"))
        #expect(dock.contains("investigationLauncher"))

        // No selection: a restrained native empty state telling the user to select traffic. No cards.
        #expect(dock.contains("Investigate captured traffic"))
        #expect(dock.contains("Select a request to investigate, or type a question below."))
        #expect(!dock.contains("How can I help with this traffic?"))

        // Selected traffic: a centered sparkles hero above the "Start an investigation" title.
        #expect(dock.contains("Image(systemName: \"sparkles\")"))
        #expect(dock.contains("String(localized: \"Start an investigation\", bundle: RockxyLocalization.bundle)"))

        // A two-column grid rendering every recipe in existing allCases order (last card alone left).
        #expect(dock.contains("LazyVGrid"))
        #expect(dock.contains("GridItem(.flexible(), spacing: 6)"))
        #expect(dock.contains("ForEach(DebugAssistantRecipe.allCases)"))
        #expect(dock.contains("suggestionCard(recipe)"))

        // No workflow-taxonomy clusters, "More suggestions" disclosure, or adaptive grid remain.
        #expect(!dock.contains("struct AssistantSuggestionCluster"))
        #expect(!dock.contains("suggestionClusters"))
        #expect(!dock.contains("String(localized: \"More suggestions\", bundle: RockxyLocalization.bundle)"))
        #expect(!dock.contains("isMoreSuggestionsExpanded"))
        #expect(!dock.contains("GridItem(.adaptive("))

        // The prior flat text-only launcher (link button rendering recipe.prompt) is gone.
        #expect(!dock.contains("suggestionLauncher"))
        #expect(!dock.contains("primaryRecipes"))
        #expect(!dock.contains("private func suggestionButton("))
        #expect(!dock.contains("Text(recipe.prompt)"))

        // Each card: exactly one meaningful SF Symbol plus the short recipe.title (2-line max), a
        // native bordered/small button at HStack spacing 6, recipe.detail only as help, busy-disabled.
        // The prior custom .plain style, controlBackgroundColor surface, and rounded hairline overlay
        // are gone — the reference is the native bordered-button treatment, not a custom approximation.
        #expect(dock.contains("private func suggestionCard("))
        let suggestionCardBody = try #require(
            dock.components(separatedBy: "private func suggestionCard(")
                .dropFirst()
                .first?
                .components(separatedBy: "@ViewBuilder")
                .first
        )
        #expect(!suggestionCardBody.contains(".buttonStyle(.link)"))
        #expect(dock.contains("Image(systemName: recipe.systemImage)"))
        #expect(dock.contains("Text(recipe.title)"))
        #expect(dock.contains(".lineLimit(2)"))
        #expect(dock.contains("HStack(spacing: 6)"))
        #expect(dock.contains(".rockxyGlassButtonStyle()"))
        #expect(dock.contains(".controlSize(.small)"))
        #expect(!dock.contains("Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8)"))
        #expect(!dock.contains("RoundedRectangle(cornerRadius: 8)"))
        #expect(dock.contains(".help(recipe.detail)"))
        #expect(dock.contains(".disabled(isBusy)"))

        // No duplicate composer suggestion strip: exactly one prebuilt suggestion surface remains.
        #expect(!dock.contains("DebugAssistantRecipe.allCases.prefix(2)"))

        // Typed prompts still reach the matching recipe by routing through suggestedRecipe(for:).
        #expect(coordinator.contains("DebugAssistantRecipe.suggestedRecipe(for: prompt)"))

        // The grid renders all recipes exactly once, in existing order — no intent dropped/duplicated.
        #expect(DebugAssistantRecipe.allCases.count == 7)
        #expect(DebugAssistantRecipe.allCases.first == .explainRequest)
        #expect(DebugAssistantRecipe.allCases.last == .prepareBugReport)
    }

    @Test("Mode switcher exposes Details and AI Assistant as native icon segments")
    func modeSwitcherUsesNativeIconSegments() throws {
        let dock = try readProjectFile("Rockxy/Views/Inspector/ContextDockView.swift")
        let dockHeader = try #require(dock.components(separatedBy: "Divider()").first)
        #expect(dock.contains("title: String(localized: \"Details\", bundle: RockxyLocalization.bundle)"))
        #expect(dock.contains("systemImage: \"doc.text.magnifyingglass\""))
        #expect(dock.contains("title: String(localized: \"AI Assistant\", bundle: RockxyLocalization.bundle)"))
        #expect(dock.contains("systemImage: \"sparkles\""))
        #expect(dock.components(separatedBy: "WorkspaceModeSegment(").count == 3)
        #expect(dock.contains("WorkspaceModeSegmentedControl("))
        #expect(dock
            .contains("accessibilityLabel: String(localized: \"Inspector\", bundle: RockxyLocalization.bundle)"))
        #expect(dockHeader.contains(".workspaceModeSwitcherStyle()"))
        #expect(!dockHeader.contains(".rockxyFunctionalBar()"))
        #expect(dock
            .contains(".accessibilityLabel(String(localized: \"Inspector\", bundle: RockxyLocalization.bundle))"))
        // Stable internal enum cases are unchanged.
        #expect(dock.contains("ContextDockTab.details"))
        #expect(dock.contains("ContextDockTab.aiAssistant"))
    }

    @Test("Context Details renders every group as a native inspector table matching the horizontal inspector")
    func contextDetailsUsesInspectorTables() throws {
        let details = try readProjectFile("Rockxy/Views/Inspector/ContextDetailsView.swift")
        let table = try readProjectFile("Rockxy/Views/Inspector/ContextInspectorTable.swift")

        // Explicit Appearance-derived typography — no semantic font styles.
        #expect(details.contains("@Environment(\\.appUIDisplayMetrics)"))
        #expect(details.contains(".system(size: metrics."))
        #expect(!details.contains(".font(.headline"))
        #expect(!details.contains(".font(.subheadline"))
        #expect(!details.contains(".font(.caption"))
        #expect(!details.contains(".font(.callout"))

        // The reusable shell mirrors HeaderKeyValueTable's visual language.
        #expect(table.contains("struct ContextInspectorTable"))
        #expect(table.contains("VStack(spacing: 0)"))
        #expect(table.contains("Color(nsColor: .controlBackgroundColor)"))
        #expect(table.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(table.contains("RoundedRectangle(cornerRadius: 6)"))
        #expect(table.contains("lineWidth: 0.5"))
        #expect(table.contains(".clipShape(RoundedRectangle(cornerRadius: 6))"))
        // A vertical divider splits the field column from the value column.
        #expect(table.contains("struct ContextInspectorFieldRow"))
        #expect(table.contains("struct ContextInspectorInsightRow"))
        #expect(table.contains("struct ContextInspectorFullRow"))
        #expect(table.contains("struct ContextInspectorDisclosureTable"))

        // Flat ScrollView of stacked tables replaces List/Section, tinted rows, and loose dividers.
        #expect(details.contains("ScrollView {"))
        #expect(!details.contains("List {"))
        #expect(!details.contains("Section(String(localized:"))
        #expect(!details.contains(".listStyle"))
        #expect(!details.contains(".listRowBackground"))
        #expect(!details.contains("private func sectionHeader("))
        #expect(!details.contains("private func detailRow("))

        // Every named diagnostics group maps to a table.
        #expect(details.contains(#"ContextInspectorFieldTable("#))
        #expect(details.contains(#"title: String(localized: "Selection", bundle: RockxyLocalization.bundle)"#))
        #expect(details.contains(#"title: String(localized: "Details", bundle: RockxyLocalization.bundle)"#))
        #expect(details
            .contains(
                #"ContextInspectorTable(title: String(localized: "Rule Impact", bundle: RockxyLocalization.bundle))"#
            ))
        #expect(details
            .contains(
                #"ContextInspectorTable(title: String(localized: "Payload", bundle: RockxyLocalization.bundle))"#
            ))
        #expect(details
            .contains(
                #"ContextInspectorTable(title: String(localized: "Insights", bundle: RockxyLocalization.bundle))"#
            ))
        #expect(details
            .contains(#"ContextInspectorTable(title: String(localized: "Notes", bundle: RockxyLocalization.bundle))"#))
        #expect(details.contains(#"title: String(localized: "Timing", bundle: RockxyLocalization.bundle)"#))
        #expect(details.contains(#"title: String(localized: "Related Requests", bundle: RockxyLocalization.bundle)"#))

        // Rule Impact keeps truthful rows plus an in-table Open Rule action row.
        #expect(details.contains(#"label: String(localized: "Rule", bundle: RockxyLocalization.bundle)"#))
        #expect(details.contains(#"label: String(localized: "Action", bundle: RockxyLocalization.bundle)"#))
        #expect(details.contains(#"label: String(localized: "Pattern", bundle: RockxyLocalization.bundle)"#))
        #expect(details.contains("openRuleActionRow(windowID:"))

        // Timing and Related keep progressive disclosure via the table disclosure shell.
        #expect(details.contains("ContextInspectorDisclosureTable("))
        #expect(details.contains("isExpanded: $isTimingExpanded"))
        #expect(details.contains("isExpanded: $isRelatedExpanded"))

        // Technical data stays monospaced.
        #expect(details.contains("design: .monospaced"))

        // Behavior preserved: honest Open Rule routing, native Compare handoff, Notes identity.
        #expect(details.contains("matchedRuleNavigationTarget(transaction)"))
        #expect(details.contains("coordinator.compareTransactions(transactions[0], transactions[1])"))
        #expect(details.contains("ContextNotesEditor(coordinator: coordinator, transaction: transaction)"))
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        let root = try resolveProjectRoot()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound
        }
        url.deleteLastPathComponent()
        return url
    }
}
