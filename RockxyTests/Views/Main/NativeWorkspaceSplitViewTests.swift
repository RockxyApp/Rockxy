import AppKit
@testable import Rockxy
import SwiftUI
import Testing

@MainActor
struct NativeWorkspaceSplitViewTests {
    @Test("Sidebar and inspector share one balanced width policy")
    func balancedUtilityPaneWidths() {
        #expect(MainWindowLayoutMetrics.utilityPaneMinimumWidth == 300)
        #expect(MainWindowLayoutMetrics.utilityPaneIdealWidth == 380)
        #expect(MainWindowLayoutMetrics.utilityPaneMaximumWidth == 520)
    }

    @Test("Workspace uses one native vertical split for both utility columns")
    func nativeThreePaneConfiguration() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)

        #expect(controller.splitView.isVertical)
        #expect(controller.splitView.dividerStyle == .thin)
        #expect(controller.splitViewItems.count == 3)
        #expect(controller.splitViewItems[0].canCollapse)
        #expect(!controller.splitViewItems[1].canCollapse)
        #expect(controller.splitViewItems[2].canCollapse)
        #expect(controller.splitViewItems[0].minimumThickness == 200)
        #expect(controller.splitViewItems[0].maximumThickness == 350)
        #expect(controller.splitViewItems[1].minimumThickness == 600)
        #expect(controller.splitViewItems[2].minimumThickness == 300)
        #expect(controller.splitViewItems[2].maximumThickness == 520)
    }

    @Test("Collapsing utility columns preserves all hosted pane controllers")
    func collapsePreservesPaneControllers() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let paneControllers = controller.splitViewItems.map(\.viewController)

        controller.setSidebarPresented(false, animated: false)
        controller.setInspectorPresented(false, animated: false)
        #expect(!controller.isSidebarPresented)
        #expect(!controller.isInspectorPresented)

        controller.setSidebarPresented(true, animated: false)
        controller.setInspectorPresented(true, animated: false)
        #expect(controller.isSidebarPresented)
        #expect(controller.isInspectorPresented)
        #expect(controller.splitViewItems.map(\.viewController).elementsEqual(
            paneControllers,
            by: { $0 === $1 }
        ))
    }

    @Test("Repeated SwiftUI updates coalesce both utility column presentations")
    func repeatedPresentationUpdatesAreCoalesced() {
        let coordinator = NativeWorkspaceSplitView<Color, Color, Color>.Coordinator()

        coordinator.recordInitialPresentation(sidebar: true, inspector: false)
        #expect(!coordinator.shouldApplySidebarPresentation(true))
        #expect(coordinator.shouldApplySidebarPresentation(false))
        #expect(!coordinator.shouldApplySidebarPresentation(false))
        #expect(!coordinator.shouldApplyInspectorPresentation(false))
        #expect(coordinator.shouldApplyInspectorPresentation(true))
        #expect(!coordinator.shouldApplyInspectorPresentation(true))
    }

    @Test("Workspace window chrome supports full-height native split materials")
    func fullSizeWindowChrome() {
        let window = NSWindow()

        NativeWorkspaceWindowChrome.configure(window)

        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
    }

    @Test("Main toolbar places the sidebar toggle before its tracking separator")
    func nativeSidebarToolbarChrome() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let coordinator = MainContentCoordinator()
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: coordinator,
                onOpenDeveloperHub: {}
            )
        )
        let window = NSWindow(contentViewController: controller)

        window.toolbar = toolbar.managedToolbar

        let identifiers = toolbar.managedToolbar.items.map(\.itemIdentifier)
        let toggleIndex = identifiers.firstIndex(
            of: NativeWorkspaceToolbar.sidebarToggleIdentifier
        )
        let trackingSeparatorIndex = identifiers.firstIndex(
            of: NativeWorkspaceToolbar.sidebarTrackingSeparatorIdentifier
        )

        #expect(identifiers.first == .flexibleSpace)
        #expect(toggleIndex != nil)
        #expect(trackingSeparatorIndex == toggleIndex.map { $0 + 1 })
        if let trackingSeparatorIndex {
            #expect(
                toolbar.managedToolbar.items[trackingSeparatorIndex]
                    is NSTrackingSeparatorToolbarItem
            )
        }
    }

    @Test("Native toolbar toggle collapses and restores the sidebar split item")
    func nativeToolbarTogglesSidebar() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {}
            )
        )
        let window = NSWindow(contentViewController: controller)
        window.toolbar = toolbar.managedToolbar
        guard let toggleItem = toolbar.managedToolbar.items.first(where: {
            $0.itemIdentifier == NativeWorkspaceToolbar.sidebarToggleIdentifier
        }),
              let action = toggleItem.action else {
            Issue.record("Sidebar toolbar item was not installed")
            return
        }

        NSApp.sendAction(action, to: toggleItem.target, from: toggleItem)
        #expect(!controller.isSidebarPresented)

        NSApp.sendAction(action, to: toggleItem.target, from: toggleItem)
        #expect(controller.isSidebarPresented)
    }

    private func makeController(
        sidebarPresented: Bool,
        inspectorPresented: Bool
    ) -> NativeWorkspaceSplitViewController {
        let controller = NativeWorkspaceSplitViewController()
        controller.configure(
            sidebarController: NSHostingController(rootView: Color.clear),
            workspaceController: NSHostingController(rootView: Color.clear),
            inspectorController: NSHostingController(rootView: Color.clear),
            isSidebarPresented: sidebarPresented,
            isInspectorPresented: inspectorPresented,
            layout: NativeWorkspaceSplitLayout(
                autosaveName: "NativeWorkspaceSplitViewTests-\(UUID().uuidString)",
                sidebarMinimumWidth: 200,
                sidebarIdealWidth: 250,
                sidebarMaximumWidth: 350,
                workspaceMinimumWidth: 600,
                inspectorMinimumWidth: 300,
                inspectorIdealWidth: 380,
                inspectorMaximumWidth: 520
            )
        )
        controller.view.frame = CGRect(x: 0, y: 0, width: 1_300, height: 700)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }
}
