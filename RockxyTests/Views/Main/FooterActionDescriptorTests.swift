import Foundation
@testable import Rockxy
import Testing

struct FooterActionDescriptorTests {
    @Test("Footer tooling action order is stable")
    func toolingActionOrder() {
        let actions = FooterActionDescriptor.toolingActions(isAllowListActive: false)

        #expect(actions.map(\.id) == [
            .blockList,
            .allowList,
            .mapLocal,
            .scripting,
            .mapRemote,
            .breakpoint,
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
            .blockList,
            .allowList,
            .mapLocal,
            .scripting,
            .mapRemote,
            .breakpoint,
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

        #expect(action.title == "Proxy Overridden")
        #expect(action.systemImage == "checkmark.circle.fill")
        #expect(action.help == "Show system proxy override details. Toggle by: ⌥⌘O")
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
        #expect(actions.first { $0.id == .blockList }?.systemImage == "hand.raised.slash")
        #expect(actions.first { $0.id == .allowList }?.systemImage == "checkmark.shield")
        #expect(actions.first { $0.id == .mapLocal }?.systemImage == "folder.badge.gearshape")
        #expect(actions.first { $0.id == .scripting }?.systemImage == "curlybraces")
        #expect(actions.first { $0.id == .mapRemote }?.systemImage == "arrow.triangle.branch")
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
        let tooling = FooterActionDescriptor.toolingActions(isAllowListActive: true)

        #expect(tooling.first { $0.id == .allowList }?.isActive == true)
    }

    @Test("Footer tool actions render inline without overflow")
    func toolActionsRemainInline() {
        let actions = FooterActionDescriptor.toolingActions(isAllowListActive: false)

        #expect(FooterActionKind.allCases.filter { $0 != .proxyOverride } == actions.map(\.id))
    }
}

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

    @Test("main coordinator starts with proxy override indicator hidden")
    @MainActor
    func coordinatorStartsWithProxyOverrideHidden() {
        let coordinator = MainContentCoordinator()

        #expect(coordinator.isProxyOverridden == false)
        #expect(coordinator.isSystemProxyConfigured == false)
    }
}
