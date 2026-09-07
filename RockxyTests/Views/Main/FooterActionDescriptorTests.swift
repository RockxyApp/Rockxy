import Foundation
@testable import Rockxy
import Testing

// MARK: - FooterActionDescriptorTests

struct FooterActionDescriptorTests {
    // MARK: Internal

    @Test("Footer tooling action order is stable")
    func toolingActionOrder() {
        let actions = FooterActionDescriptor.toolingActions(isAllowListActive: false)

        #expect(actions.map(\.id) == [
            .breakpoint,
            .mapLocal,
            .scripting,
            .networkConditions,
        ])
    }

    @Test("Proxy override action appears after Network Conditions only when active")
    func proxyOverrideActionIsConditional() {
        let inactive = FooterActionDescriptor.toolingActions(
            isAllowListActive: false,
            isProxyOverridden: false
        )
        let active = FooterActionDescriptor.toolingActions(
            isAllowListActive: false,
            isProxyOverridden: true
        )

        #expect(!inactive.contains { $0.id == .proxyOverride })
        #expect(active.map(\.id) == [
            .breakpoint,
            .mapLocal,
            .scripting,
            .networkConditions,
            .proxyOverride,
        ])
    }

    @Test("Proxy override action metadata matches footer contract")
    func proxyOverrideActionMetadata() throws {
        let actions = FooterActionDescriptor.toolingActions(
            isAllowListActive: false,
            isProxyOverridden: true
        )
        let action = try #require(actions.first { $0.id == .proxyOverride })

        #expect(action.title == String(localized: "Proxy Overridden", bundle: RockxyLocalization.bundle))
        #expect(action.systemImage == "checkmark.circle.fill")
        #expect(action.help == String(
            localized: "Show system proxy override details. Toggle by: ⌥⌘O",
            bundle: RockxyLocalization.bundle
        ))
        #expect(action.isActive)
        #expect(action.isEnabled)
    }

    @Test("Footer action IDs stay unique in normal and proxy override states")
    func footerActionIDsStayUnique() {
        for isProxyOverridden in [false, true] {
            let actions = FooterActionDescriptor.toolingActions(
                isAllowListActive: false,
                isProxyOverridden: isProxyOverridden
            )
            #expect(Set(actions.map(\.id)).count == actions.count)
        }
    }

    @Test("Footer actions use SF Symbol names")
    func actionSymbolsArePresent() {
        let actions = FooterActionDescriptor.toolingActions(isAllowListActive: false)

        #expect(actions.allSatisfy { !$0.systemImage.isEmpty })
        #expect(actions.first { $0.id == .mapLocal }?.systemImage == "folder.badge.gearshape")
        #expect(actions.first { $0.id == .scripting }?.systemImage == "curlybraces")
        #expect(actions.first { $0.id == .breakpoint }?.systemImage == "pause.circle")
        #expect(actions.first { $0.id == .networkConditions }?.systemImage == "speedometer")

        let activeActions = FooterActionDescriptor.toolingActions(
            isAllowListActive: false,
            isProxyOverridden: true
        )
        #expect(activeActions.first { $0.id == .proxyOverride }?.systemImage == "checkmark.circle.fill")
        #expect(activeActions.first { $0.id == .proxyOverride }?.help.contains("⌥⌘O") == true)
    }

    @Test("Allow List active state reflects manager state")
    func activeStates() {
        let tooling = FooterActionDescriptor.toolingActions(
            isAllowListActive: true,
            quickTools: [.allowList, .mapLocal, .scripting, .networkConditions]
        )

        #expect(tooling.first { $0.id == .allowList }?.isActive == true)
    }

    @Test("Footer tool actions render inline without overflow")
    func toolActionsRemainInline() {
        let actions = FooterActionDescriptor.toolingActions(isAllowListActive: false)

        #expect(FooterActionKind.defaultQuickTools == actions.map(\.id))
    }

    @Test("Each customizable tool maps to its approved tool-window ID")
    func toolWindowIDMapping() {
        #expect(FooterActionKind.blockList.toolWindowID == "blockList")
        #expect(FooterActionKind.allowList.toolWindowID == "allowList")
        #expect(FooterActionKind.mapRemote.toolWindowID == "mapRemote")
        #expect(FooterActionKind.mapLocal.toolWindowID == "mapLocal")
        #expect(FooterActionKind.scripting.toolWindowID == "scriptingList")
        #expect(FooterActionKind.breakpoint.toolWindowID == "breakpointRules")
        #expect(FooterActionKind.networkConditions.toolWindowID == "networkConditions")
        #expect(FooterActionKind.proxyOverride.toolWindowID == nil)
    }

    @Test("Quick Tools stay labeled while Customize remains compact and accessible")
    func quickToolsUseLabeledNativeGlassControls() throws {
        let source = try readProjectFile("Rockxy/Views/RequestList/StatusBarView.swift")

        #expect(source.contains("Label(descriptor.title, systemImage: descriptor.systemImage)"))
        #expect(source.contains(".rockxyGlassButtonStyle(prominent: descriptor.isActive)"))
        #expect(source
            .contains(
                "Label(String(localized: \"Quick Tools\", bundle: RockxyLocalization.bundle), systemImage: \"hammer\")"
            ))
        #expect(source.contains("Image(systemName: \"ellipsis\")"))
        #expect(!source
            .contains(
                "Label(String(localized: \"Customize\", bundle: RockxyLocalization.bundle), systemImage: \"ellipsis\")"
            ))
        #expect(!source.contains("showsCustomizeTitle"))
        #expect(source.contains("quickTools\n                    .layoutPriority(0)"))
        #expect(source.contains("breakpointQueueIndicator"))
        #expect(source.contains("onOpenToolWindow(\"breakpoints\")"))
        #expect(source.contains("pausedBreakpointCount"))
        #expect(source.contains("centerStatus\n                    .layoutPriority(3)"))
        #expect(source.contains("rightStats\n                    .layoutPriority(3)"))
        #expect(source.contains("ViewThatFits(in: .horizontal)"))
        #expect(source
            .contains(
                ".accessibilityLabel(String(localized: \"Customize Quick Tools\", bundle: RockxyLocalization.bundle))"
            ))
        #expect(!source.contains("struct FooterToolIconLabel"))
        #expect(!source.contains("struct FooterToolingChrome"))
        #expect(!source.contains("FooterToolingChrome("))
    }

    // MARK: Private

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

// MARK: - QuickToolsLayoutTests

struct QuickToolsLayoutTests {
    @Test("Approved defaults place three tools on top and four in the footer")
    func approvedDefaults() {
        let layout = QuickToolsLayout.default

        #expect(layout.commandBar == [.blockList, .allowList, .mapRemote])
        #expect(layout.footer == [.breakpoint, .mapLocal, .scripting, .networkConditions])
    }

    @Test("All seven customizable tools occur exactly once across both regions")
    func sevenUniqueAssignments() {
        let layout = QuickToolsLayout.default
        let combined = layout.commandBar + layout.footer

        #expect(combined.count == 7)
        #expect(Set(combined) == Set(FooterActionKind.customizableQuickTools))
        #expect(!combined.contains(.proxyOverride))
        #expect(layout.commandBar.count == QuickToolsLayout.commandBarSlotCount)
        #expect(layout.footer.count == QuickToolsLayout.footerSlotCount)
    }

    @Test("Encode/decode round trips a valid layout")
    func encodeDecodeRoundTrip() {
        let layout = QuickToolsLayout(
            commandBar: [.scripting, .breakpoint, .networkConditions],
            footer: [.blockList, .allowList, .mapRemote, .mapLocal]
        )

        let decoded = QuickToolsLayout.decode(layout.encoded)

        #expect(decoded == layout)
    }

    @Test("Empty storage decodes to nil so callers fall back to migration")
    func emptyStorageDecodesNil() {
        #expect(QuickToolsLayout.decode("") == nil)
        #expect(QuickToolsLayout.decode("   ") == nil)
    }

    @Test("Persistence decoding tolerates whitespace around tool IDs")
    func persistenceWhitespaceRepair() throws {
        let decoded = try #require(QuickToolsLayout.decode(
            " blockList, allowList,mapRemote | breakpoint,mapLocal,scripting,networkConditions "
        ))

        #expect(decoded == .default)
    }

    @Test("Malformed and duplicate persistence repairs to a valid unique layout")
    func malformedRepair() throws {
        // Duplicates, an unknown token, proxyOverride, and a missing footer side.
        let repaired = try #require(
            QuickToolsLayout.decode("blockList,blockList,proxyOverride,bogus|allowList,allowList")
        )

        let combined = repaired.commandBar + repaired.footer
        #expect(repaired.commandBar.count == 3)
        #expect(repaired.footer.count == 4)
        #expect(Set(combined) == Set(FooterActionKind.customizableQuickTools))
        #expect(!combined.contains(.proxyOverride))
        // Cleaned survivors keep their leading position before backfill.
        #expect(repaired.commandBar.first == .blockList)
    }

    @Test("Legacy footer order migrates its four tools to the footer and the rest on top")
    func legacyFooterMigration() {
        let legacy = "breakpoint,mapLocal,scripting,networkConditions"
        let layout = QuickToolsLayout.resolved(storageRaw: "", legacyFooterRaw: legacy)

        #expect(layout.footer == [.breakpoint, .mapLocal, .scripting, .networkConditions])
        #expect(Set(layout.commandBar) == [.blockList, .allowList, .mapRemote])
    }

    @Test("A customized legacy footer migration preserves its exact four selections")
    func legacyFooterMigrationPreservesSelection() {
        let legacy = "allowList,scripting,mapRemote,breakpoint"
        let layout = QuickToolsLayout.resolved(storageRaw: "", legacyFooterRaw: legacy)

        #expect(layout.footer == [.allowList, .scripting, .mapRemote, .breakpoint])
        #expect(Set(layout.commandBar) == [.blockList, .mapLocal, .networkConditions])
    }

    @Test("New storage value wins over the legacy footer key")
    func newStorageWinsOverLegacy() {
        let stored = QuickToolsLayout(
            commandBar: [.mapLocal, .scripting, .networkConditions],
            footer: [.blockList, .allowList, .mapRemote, .breakpoint]
        )
        let layout = QuickToolsLayout.resolved(
            storageRaw: stored.encoded,
            legacyFooterRaw: "breakpoint,mapLocal,scripting,networkConditions"
        )

        #expect(layout == stored)
    }

    @Test("Assigning a tool already in the other region swaps the two slots")
    func crossRegionSwap() {
        let layout = QuickToolsLayout.default
        // mapLocal currently lives in footer slot 1; move it to command-bar slot 0.
        let swapped = layout.assigning(.mapLocal, to: .commandBar, slot: 0)

        #expect(swapped.commandBar[0] == .mapLocal)
        // The displaced command-bar tool (blockList) lands where mapLocal used to sit.
        #expect(swapped.footer[1] == .blockList)
        // Invariant preserved.
        let combined = swapped.commandBar + swapped.footer
        #expect(Set(combined) == Set(FooterActionKind.customizableQuickTools))
        #expect(combined.count == 7)
    }

    @Test("Assigning within the same region swaps intra-region slots")
    func intraRegionSwap() {
        let layout = QuickToolsLayout.default
        // allowList is command-bar slot 1; assign it to slot 0 (blockList).
        let swapped = layout.assigning(.allowList, to: .commandBar, slot: 0)

        #expect(swapped.commandBar[0] == .allowList)
        #expect(swapped.commandBar[1] == .blockList)
        #expect(swapped.footer == layout.footer)
    }

    @Test("Assigning a tool to the slot it already occupies is a no-op")
    func idempotentAssignment() {
        let layout = QuickToolsLayout.default
        #expect(layout.assigning(.blockList, to: .commandBar, slot: 0) == layout)
    }

    @Test("Responsive policy collapses three to two to zero, never icon-only")
    func responsivePolicy() {
        #expect(QuickToolsResponsivePolicy.candidateCommandBarCounts == [3, 2, 0])

        #expect(QuickToolsResponsivePolicy.visibleCommandBarCount { $0 <= 3 } == 3)
        #expect(QuickToolsResponsivePolicy.visibleCommandBarCount { $0 <= 2 } == 2)
        #expect(QuickToolsResponsivePolicy.visibleCommandBarCount { $0 == 0 } == 0)
        // No candidate produces one visible capsule — it never falls to a single icon.
        #expect(!QuickToolsResponsivePolicy.candidateCommandBarCounts.contains(1))
    }
}

// MARK: - FooterMutationIndicatorBuilderTests

struct FooterMutationIndicatorBuilderTests {
    // MARK: Internal

    @Test("Indicators are ordered Map Local, Map Remote, then Breakpoint")
    func indicatorOrder() {
        let rules = [
            makeRule(.breakpoint()),
            makeRule(.mapRemote(configuration: .init())),
            makeRule(.mapLocal(filePath: "/tmp/a.json")),
        ]

        let indicators = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )

        #expect(indicators.map(\.id) == [.mapLocal, .mapRemote, .breakpoint])
    }

    @Test("Indicator count reflects only enabled rules per category")
    func enabledRuleCounts() {
        let rules = [
            makeRule(.mapLocal(filePath: "/tmp/a.json")),
            makeRule(.mapLocal(filePath: "/tmp/b.json")),
            makeRule(.mapLocal(filePath: "/tmp/c.json"), isEnabled: false),
            makeRule(.mapRemote(configuration: .init())),
            makeRule(.breakpoint(), isEnabled: false),
            makeRule(.block(statusCode: 403)),
            makeRule(.throttle(delayMs: 50)),
        ]

        let indicators = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )

        #expect(indicators.map(\.id) == [.mapLocal, .mapRemote])
        #expect(indicators.first { $0.id == .mapLocal }?.count == 2)
        #expect(indicators.first { $0.id == .mapRemote }?.count == 1)
    }

    @Test("A category is omitted when its tool-level switch is off")
    func toolSwitchGating() {
        let rules = [
            makeRule(.mapLocal(filePath: "/tmp/a.json")),
            makeRule(.mapRemote(configuration: .init())),
            makeRule(.breakpoint()),
        ]

        let withoutMapLocal = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: false,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )
        #expect(withoutMapLocal.map(\.id) == [.mapRemote, .breakpoint])

        let withoutBreakpoint = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: false
        )
        #expect(withoutBreakpoint.map(\.id) == [.mapLocal, .mapRemote])

        let allOff = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: false,
            mapRemoteToolEnabled: false,
            breakpointToolEnabled: false
        )
        #expect(allOff.isEmpty)
    }

    @Test("No indicators are produced when no enabled rules exist")
    func zeroStateOmission() {
        let emptyRules = FooterMutationIndicatorBuilder.indicators(
            rules: [],
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )
        #expect(emptyRules.isEmpty)

        let onlyDisabled = FooterMutationIndicatorBuilder.indicators(
            rules: [
                makeRule(.mapLocal(filePath: "/tmp/a.json"), isEnabled: false),
                makeRule(.breakpoint(), isEnabled: false),
            ],
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )
        #expect(onlyDisabled.isEmpty)
    }

    @Test("Indicators map to their existing tool-window IDs")
    func targetWindowIDs() {
        let rules = [
            makeRule(.mapLocal(filePath: "/tmp/a.json")),
            makeRule(.mapRemote(configuration: .init())),
            makeRule(.breakpoint()),
        ]

        let indicators = FooterMutationIndicatorBuilder.indicators(
            rules: rules,
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )

        #expect(indicators.first { $0.id == .mapLocal }?.windowID == "mapLocal")
        #expect(indicators.first { $0.id == .mapRemote }?.windowID == "mapRemote")
        #expect(indicators.first { $0.id == .breakpoint }?.windowID == "breakpointRules")
    }

    @Test("Indicators carry SF Symbols and accessible count copy")
    func indicatorMetadata() throws {
        let indicators = FooterMutationIndicatorBuilder.indicators(
            rules: [
                makeRule(.mapLocal(filePath: "/tmp/a.json")),
                makeRule(.mapLocal(filePath: "/tmp/b.json")),
            ],
            mapLocalToolEnabled: true,
            mapRemoteToolEnabled: true,
            breakpointToolEnabled: true
        )

        let mapLocal = try #require(indicators.first { $0.id == .mapLocal })
        #expect(mapLocal.systemImage == "folder.badge.gearshape")
        #expect(mapLocal.title == "Map Local")
        #expect(mapLocal.accessibilityLabel.contains("2"))
        #expect(indicators.allSatisfy { !$0.systemImage.isEmpty })
    }

    // MARK: Private

    private func makeRule(_ action: RuleAction, isEnabled: Bool = true) -> ProxyRule {
        ProxyRule(
            name: "test",
            isEnabled: isEnabled,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: action
        )
    }
}

// MARK: - ProxyOverrideCommandActionsTests

struct ProxyOverrideCommandActionsTests {
    @Test("system proxy override command is enabled only while proxy is running")
    @MainActor
    func toggleSystemProxyOverrideCommandAvailability() {
        let coordinator = MainContentCoordinator()
        let actions = MainContentCommandActions(coordinator: coordinator)

        coordinator.isProxyRunning = false
        #expect(actions.canToggleSystemProxyOverride == false)

        coordinator.isProxyRunning = true
        #expect(actions.canToggleSystemProxyOverride)
    }

    @Test("recording command is enabled only while proxy is running")
    @MainActor
    func toggleRecordingCommandAvailability() {
        let coordinator = MainContentCoordinator()
        let actions = MainContentCommandActions(coordinator: coordinator)

        #expect(actions.canToggleRecording == false)

        coordinator.isProxyRunning = true
        #expect(actions.canToggleRecording)
    }

    @Test("first and last navigation are available without an existing selection")
    @MainActor
    func firstAndLastNavigationAvailability() {
        let coordinator = MainContentCoordinator()
        let actions = MainContentCommandActions(coordinator: coordinator)

        #expect(actions.hasSelectedTransaction == false)
        #expect(actions.hasVisibleTransactions == false)

        coordinator.transactions = [TestFixtures.makeTransaction()]
        coordinator.recomputeFilteredTransactions()

        #expect(actions.hasSelectedTransaction == false)
        #expect(actions.hasVisibleTransactions)
    }

    @Test("OpenAPI export command requires eligible HTTP traffic")
    @MainActor
    func openAPIExportCommandAvailability() {
        let coordinator = MainContentCoordinator()
        let actions = MainContentCommandActions(coordinator: coordinator)

        #expect(actions.canExportOpenAPI == false)

        coordinator.transactions = [
            TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/users")
        ]

        #expect(actions.canExportOpenAPI)
    }

    @Test("main coordinator starts with proxy override indicator hidden")
    @MainActor
    func coordinatorStartsWithProxyOverrideHidden() {
        let coordinator = MainContentCoordinator()

        #expect(coordinator.isProxyOverridden == false)
        #expect(coordinator.isSystemProxyConfigured == false)
    }

    @Test("stale proxy override keeps the footer recovery action visible")
    func staleProxyOverrideKeepsRecoveryActionVisible() {
        let reconciliation = MainContentCoordinator.reconcileProxyOverride(
            overridePort: 9_090,
            activeProxyPort: 8_888
        )
        let actions = FooterActionDescriptor.toolingActions(
            isAllowListActive: false,
            isProxyOverridden: reconciliation.isOverridden
        )

        #expect(!reconciliation.matchesActiveProxyPort)
        #expect(actions.last?.id == .proxyOverride)
    }
}
