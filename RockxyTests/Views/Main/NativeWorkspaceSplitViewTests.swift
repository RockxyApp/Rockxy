import AppKit
@testable import Rockxy
import SwiftUI
import Testing

// MARK: - NativeWorkspaceSplitViewTests

@MainActor
struct NativeWorkspaceSplitViewTests {
    // MARK: Internal

    @Test("Workspace defaults favor the Context Dock over the navigation sidebar")
    func flexibleInspectorWidthPolicy() {
        #expect(MainWindowLayoutMetrics.sidebarMinimumWidth == 200)
        #expect(MainWindowLayoutMetrics.sidebarIdealWidth == 250)
        #expect(MainWindowLayoutMetrics.sidebarMaximumWidth == 350)
        #expect(MainWindowLayoutMetrics.workspaceMinimumWidth == 320)
        #expect(MainWindowLayoutMetrics.contextDockMinimumWidth == 260)
        #expect(MainWindowLayoutMetrics.contextDockIdealWidth == 320)
        #expect(MainWindowLayoutMetrics.sidebarIdealWidth < MainWindowLayoutMetrics.contextDockIdealWidth)
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
        #expect(controller.splitViewItems[1].minimumThickness == 320)
        #expect(controller.splitViewItems[2].minimumThickness == 220)
        #expect(controller.splitViewItems[2].maximumThickness == 10_000)
    }

    @Test("Context Dock sizing policy permits widths beyond the former maximum")
    func contextDockSupportsWideResize() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let availableInspectorWidth = 1_600
            - controller.splitView.dividerThickness * 2
            - controller.splitViewItems[0].minimumThickness
            - controller.splitViewItems[1].minimumThickness

        #expect(availableInspectorWidth > 520)
        #expect(controller.splitViewItems[2].maximumThickness >= availableInspectorWidth)
    }

    @Test("Vertical dividers have a forgiving horizontal drag target")
    func verticalDividerHitTarget() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let drawnRect = NSRect(x: 800, y: 0, width: 1, height: 700)
        let effectiveRect = controller.splitView(
            controller.splitView,
            effectiveRect: drawnRect,
            forDrawnRect: drawnRect,
            ofDividerAt: 1
        )

        #expect(effectiveRect.width >= NativeSplitDividerInteraction.minimumHitThickness)
        #expect(effectiveRect.minX < drawnRect.minX)
        #expect(effectiveRect.maxX > drawnRect.maxX)
    }

    @Test("Context Dock divider moves through a useful width range after layout")
    func contextDockDividerMovesAfterLayout() {
        let controller = makeConfiguredController(
            sidebarPresented: true,
            inspectorPresented: true,
            autosaveName: uniqueAutosaveName()
        )
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_600, height: 700))

        controller.splitView.setPosition(900, ofDividerAt: 1)
        controller.view.layoutSubtreeIfNeeded()
        let wideInspectorWidth = controller.splitViewItems[2].viewController.view.frame.width

        controller.splitView.setPosition(1_250, ofDividerAt: 1)
        controller.view.layoutSubtreeIfNeeded()
        let compactInspectorWidth = controller.splitViewItems[2].viewController.view.frame.width

        #expect(wideInspectorWidth > compactInspectorWidth)
        #expect(wideInspectorWidth > 600)
        #expect(compactInspectorWidth >= 220)
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
        #expect(window.titleVisibility == .hidden)
        #expect(window.toolbarStyle == .unified)
    }

    @Test("Project changes and late scene updates cannot duplicate the selector")
    func projectChangesDoNotRenderAWindowTitle() {
        let coordinator = MainContentCoordinator()
        let window = NSWindow()
        let manager = RockxyWorkspaceWindowManager.shared
        window.title = RockxyIdentity.current.displayName

        manager.registerPrimaryWindow(window, coordinator: coordinator)
        defer {
            manager.handleWindowWillClose(window)
        }

        #expect(window.title == RockxyIdentity.current.displayName)
        #expect(window.titleVisibility == .hidden)

        // Simulate the old Project-title assignment followed by a delayed SwiftUI
        // reconciliation. The window manager owns a persistent invariant instead
        // of repairing only the synchronous Project-switch callback.
        window.title = "New Project 3"
        window.titleVisibility = .visible

        #expect(window.title == RockxyIdentity.current.displayName)
        #expect(window.titleVisibility == .hidden)

        manager.projectDidChange(coordinator: coordinator)

        #expect(window.title == RockxyIdentity.current.displayName)
        #expect(window.titleVisibility == .hidden)
    }

    @Test("Main toolbar keeps the sidebar toggle inside the leading pane before its tracking separator")
    func nativeSidebarToolbarChrome() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let coordinator = MainContentCoordinator()
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: coordinator,
                onOpenDeveloperHub: {}
            ),
            toolbarIdentifier: uniqueToolbarIdentifier(),
            autosavesConfiguration: false
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
        let projectSelectorIndex = identifiers.firstIndex(
            of: NativeWorkspaceToolbar.projectSelectorIdentifier
        )

        #expect(identifiers.first == .flexibleSpace)
        #expect(toggleIndex != nil)
        #expect(trackingSeparatorIndex == toggleIndex.map { $0 + 1 })
        #expect(projectSelectorIndex == trackingSeparatorIndex.map { $0 + 1 })
        #expect(!identifiers.contains {
            $0.rawValue.hasSuffix(".toolbar.workspaceTitle")
        })
        if let trackingSeparatorIndex {
            #expect(
                toolbar.managedToolbar.items[trackingSeparatorIndex]
                    is NSTrackingSeparatorToolbarItem
            )
        }
        if let toggleIndex {
            #expect(!toolbar.managedToolbar.items[toggleIndex].isNavigational)
        }
        if let projectSelectorIndex,
           let selectorView = toolbar.managedToolbar.items[projectSelectorIndex].view
        {
            let width = selectorView.fittingSize.width
            let expectedInnerWidth = ProjectToolbarSelectorMetrics.preferredWidth(
                for: coordinator.projectStore.activeProject.name
            )
            #expect(width >= expectedInnerWidth)
            #expect(width >= ProjectToolbarSelectorMetrics.minimumWidth)
            #expect(width <= ProjectToolbarSelectorMetrics.maximumWidth)
        } else {
            Issue.record("Project selector toolbar item was not hosted")
        }
    }

    @Test("Main toolbar supports and persists native user customization")
    func nativeToolbarCustomizationConfiguration() {
        // The autosave contract is verified under a unique identifier so the shared production
        // toolbar preferences are never written. The default initializer opts into autosaving.
        let autosaveIdentifier = uniqueToolbarIdentifier()
        let autosavingToolbar = NativeWorkspaceToolbar(
            splitViewController: makeController(sidebarPresented: true, inspectorPresented: true),
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {}
            ),
            toolbarIdentifier: autosaveIdentifier
        )
        #expect(autosavingToolbar.managedToolbar.autosavesConfiguration)
        autosavingToolbar.managedToolbar.autosavesConfiguration = false
        removeToolbarConfigurationDefaults(autosaveIdentifier)

        // `customizationToolbar` matches by the production identifier, so the customization contract
        // is exercised with a non-autosaving toolbar that carries that identifier. Autosave is off,
        // so nothing is written to the production preferences.
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {}
            ),
            toolbarIdentifier: NativeWorkspaceToolbar.toolbarIdentifier,
            autosavesConfiguration: false
        )
        let window = NSWindow(contentViewController: controller)
        window.toolbar = toolbar.managedToolbar

        #expect(toolbar.managedToolbar.allowsUserCustomization)
        #expect(!toolbar.managedToolbar.autosavesConfiguration)

        let defaults = toolbar.toolbarDefaultItemIdentifiers(toolbar.managedToolbar)
        let allowed = toolbar.toolbarAllowedItemIdentifiers(toolbar.managedToolbar)
        let immovable = toolbar.toolbarImmovableItemIdentifiers(toolbar.managedToolbar)

        #expect(defaults == NativeWorkspaceToolbar.defaultItemIdentifiers)
        #expect(allowed == NativeWorkspaceToolbar.allowedItemIdentifiers)
        #expect(Set(allowed).count == allowed.count)
        #expect(Set(defaults).isSubset(of: Set(allowed)))
        #expect(allowed.contains(.space))
        #expect(allowed.contains(.flexibleSpace))
        #expect(Set(NativeWorkspaceToolbar.userCustomizableItemIdentifiers).isSubset(of: Set(allowed)))
        #expect(NativeWorkspaceToolbar.userCustomizableItemIdentifiers.count == 25)
        #expect(NativeWorkspaceToolbar.toolWindowItemDescriptors.count == 14)
        #expect(immovable == [NativeWorkspaceToolbar.sidebarTrackingSeparatorIdentifier])

        let preferredWindow = window
        let fallbackWindow = NSWindow()
        let fallbackToolbar = NSToolbar(identifier: NativeWorkspaceToolbar.toolbarIdentifier)
        fallbackToolbar.allowsUserCustomization = true
        fallbackWindow.toolbar = fallbackToolbar

        #expect(NativeWorkspaceToolbar.customizationToolbar(
            preferredWindow: preferredWindow,
            fallbackWindows: [fallbackWindow]
        ) === toolbar.managedToolbar)

        let unrelatedWindow = NSWindow()
        unrelatedWindow.toolbar = NSToolbar(identifier: "unrelated.toolbar")
        #expect(NativeWorkspaceToolbar.customizationToolbar(
            preferredWindow: unrelatedWindow,
            fallbackWindows: [fallbackWindow]
        ) === fallbackToolbar)
    }

    @Test("Every customizable toolbar option has a complete native palette representation")
    func customizableToolbarItemCatalogIsComplete() throws {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {}
            ),
            toolbarIdentifier: uniqueToolbarIdentifier(),
            autosavesConfiguration: false
        )

        for identifier in NativeWorkspaceToolbar.userCustomizableItemIdentifiers {
            let item = try #require(toolbar.toolbar(
                toolbar.managedToolbar,
                itemForItemIdentifier: identifier,
                willBeInsertedIntoToolbar: false
            ))
            #expect(!item.label.isEmpty)
            #expect(!item.paletteLabel.isEmpty)
            #expect(item.image != nil || item.view != nil)
        }

        let toolWindowIDs = NativeWorkspaceToolbar.toolWindowItemDescriptors.map(\.windowID)
        #expect(Set(toolWindowIDs).count == toolWindowIDs.count)
        #expect(Set(toolWindowIDs) == [
            "allowList",
            "blockList",
            "bodyPreviewerTabs",
            "breakpointRules",
            "bypassProxyList",
            "customColumns",
            "diff",
            "externalProxySettings",
            "mapLocal",
            "mapRemote",
            "modifyHeaders",
            "networkConditions",
            "scriptingList",
            "sslProxyingList",
        ])
    }

    @Test("Tracking separator uses a compact default-set palette label")
    func trackingSeparatorPaletteLabelIsCompact() throws {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {}
            ),
            toolbarIdentifier: uniqueToolbarIdentifier(),
            autosavesConfiguration: false
        )

        let separator = try #require(toolbar.toolbar(
            toolbar.managedToolbar,
            itemForItemIdentifier: NativeWorkspaceToolbar.sidebarTrackingSeparatorIdentifier,
            willBeInsertedIntoToolbar: false
        ))

        #expect(separator.label == String(localized: "Source List Divider", bundle: RockxyLocalization.bundle))
        #expect(separator.paletteLabel == String(localized: "Divider", bundle: RockxyLocalization.bundle))
    }

    @Test("Optional toolbar items can be removed and restored independently")
    func customizableToolbarItemsRoundTrip() throws {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {}
            ),
            toolbarIdentifier: uniqueToolbarIdentifier(),
            autosavesConfiguration: false
        )
        let window = NSWindow(contentViewController: controller)
        window.toolbar = toolbar.managedToolbar

        for identifier in NativeWorkspaceToolbar.userCustomizableItemIdentifiers {
            if !toolbar.managedToolbar.items.contains(where: { $0.itemIdentifier == identifier }) {
                toolbar.managedToolbar.insertItem(
                    withItemIdentifier: identifier,
                    at: toolbar.managedToolbar.items.count
                )
            }
            let index = try #require(
                toolbar.managedToolbar.items.firstIndex { $0.itemIdentifier == identifier }
            )
            toolbar.managedToolbar.removeItem(at: index)
            #expect(!toolbar.managedToolbar.items.contains { $0.itemIdentifier == identifier })

            toolbar.managedToolbar.insertItem(withItemIdentifier: identifier, at: index)
            let restored = try #require(toolbar.managedToolbar.items.first {
                $0.itemIdentifier == identifier
            })
            #expect(!restored.paletteLabel.isEmpty)
        }

        #expect(toolbar.managedToolbar.items.contains {
            $0.itemIdentifier == NativeWorkspaceToolbar.sidebarTrackingSeparatorIdentifier
        })

        // Proxy Status is the toolbar's centered item; removing and re-adding items must not
        // drop it from the centered set.
        #expect(toolbar.managedToolbar.centeredItemIdentifiers.contains(
            NativeWorkspaceToolbar.proxyStatusIdentifier
        ))
    }

    @Test("Releasing a workspace controller deallocates the controller and its toolbar")
    func toolbarReleaseDeallocatesControllerAndToolbar() async {
        weak var weakController: NativeWorkspaceSplitViewController?
        weak var weakToolbar: NativeWorkspaceToolbar?

        do {
            let controller = makeController(sidebarPresented: true, inspectorPresented: true)
            let toolbar = NativeWorkspaceToolbar(
                splitViewController: controller,
                configuration: NativeWorkspaceToolbarConfiguration(
                    coordinator: MainContentCoordinator(),
                    onOpenDeveloperHub: {}
                ),
                toolbarIdentifier: uniqueToolbarIdentifier(),
                autosavesConfiguration: false
            )
            // A bare window (no contentViewController) is used deliberately: if AppKit retains the
            // window past this scope it only keeps the NSToolbar alive, never the controller, so the
            // deallocation assertions below stay reliable.
            let window = NSWindow()
            // The controller strongly owns the toolbar (associated object) while the toolbar keeps
            // only a weak reference back, so this mirrors the production ownership graph.
            controller.attachNativeToolbar(toolbar, to: window)

            weakController = controller
            weakToolbar = toolbar
            #expect(weakController != nil)
            #expect(weakToolbar != nil)
        }

        // Drain any observation follow-up task scheduled during startObservingState().
        await Task.yield()

        #expect(weakController == nil)
        #expect(weakToolbar == nil)
    }

    @Test("Workspace windows with the same toolbar identity share customization")
    func customizableToolbarConfigurationSynchronizesAcrossWindows() async throws {
        let identifier = uniqueToolbarIdentifier()
        let firstController = makeController(sidebarPresented: true, inspectorPresented: true)
        let secondController = makeController(sidebarPresented: true, inspectorPresented: true)
        let firstToolbar = NativeWorkspaceToolbar(
            splitViewController: firstController,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {}
            ),
            toolbarIdentifier: identifier,
            autosavesConfiguration: false
        )
        let secondToolbar = NativeWorkspaceToolbar(
            splitViewController: secondController,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {}
            ),
            toolbarIdentifier: identifier,
            autosavesConfiguration: false
        )
        let firstWindow = NSWindow(contentViewController: firstController)
        let secondWindow = NSWindow(contentViewController: secondController)
        firstWindow.toolbar = firstToolbar.managedToolbar
        secondWindow.toolbar = secondToolbar.managedToolbar

        let removedIdentifier = NativeWorkspaceToolbar.developerHubIdentifier
        let removedIndex = try #require(firstToolbar.managedToolbar.items.firstIndex {
            $0.itemIdentifier == removedIdentifier
        })
        firstToolbar.managedToolbar.removeItem(at: removedIndex)

        for _ in 0 ..< 6 where secondToolbar.managedToolbar.items.contains(where: {
            $0.itemIdentifier == removedIdentifier
        }) {
            await Task.yield()
        }
        #expect(!secondToolbar.managedToolbar.items.contains {
            $0.itemIdentifier == removedIdentifier
        })

        firstToolbar.managedToolbar.insertItem(
            withItemIdentifier: removedIdentifier,
            at: removedIndex
        )
        for _ in 0 ..< 6 where !secondToolbar.managedToolbar.items.contains(where: {
            $0.itemIdentifier == removedIdentifier
        }) {
            await Task.yield()
        }
        #expect(secondToolbar.managedToolbar.items.contains {
            $0.itemIdentifier == removedIdentifier
        })
    }

    @Test("Native toolbar toggle collapses and restores the sidebar split item")
    func nativeToolbarTogglesSidebar() {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {}
            ),
            toolbarIdentifier: uniqueToolbarIdentifier(),
            autosavesConfiguration: false
        )
        let window = NSWindow(contentViewController: controller)
        window.toolbar = toolbar.managedToolbar
        guard let toggleItem = toolbar.managedToolbar.items.first(where: {
            $0.itemIdentifier == NativeWorkspaceToolbar.sidebarToggleIdentifier
        }),
            let action = toggleItem.action else
        {
            Issue.record("Sidebar toolbar item was not installed")
            return
        }

        NSApp.sendAction(action, to: toggleItem.target, from: toggleItem)
        #expect(!controller.isSidebarPresented)

        NSApp.sendAction(action, to: toggleItem.target, from: toggleItem)
        #expect(controller.isSidebarPresented)
    }

    @Test("Developer Hub opening leaves the AppKit toolbar action turn before building its SwiftUI window")
    func developerHubOpenIsDeferredDuringCaptureStateUpdates() async throws {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let coordinator = MainContentCoordinator()
        var actionDispatchReturned = false
        var openCount = 0
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: coordinator,
                onOpenDeveloperHub: {
                    #expect(actionDispatchReturned)
                    openCount += 1
                }
            ),
            toolbarIdentifier: uniqueToolbarIdentifier(),
            autosavesConfiguration: false
        )
        let window = NSWindow(contentViewController: controller)
        window.toolbar = toolbar.managedToolbar
        toolbar.startObservingState()
        await Task.yield()

        // Match the reported trigger: capture state changes immediately before the
        // Developer Hub action is dispatched from the native toolbar.
        coordinator.isProxyRunning = true

        let developerHubItem = try #require(toolbar.managedToolbar.items.first {
            $0.itemIdentifier == NativeWorkspaceToolbar.developerHubIdentifier
        })
        let action = try #require(developerHubItem.action)

        NSApp.sendAction(action, to: developerHubItem.target, from: developerHubItem)
        #expect(openCount == 0)
        actionDispatchReturned = true

        try await waitUntil { openCount == 1 }
        #expect(openCount == 1)
    }

    @Test("Custom tool-window items dispatch their canonical SwiftUI scene after the AppKit action")
    func customToolWindowDispatchIsDeferred() async throws {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        var actionDispatchReturned = false
        var openedWindowID: String?
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {},
                onOpenToolWindow: { id in
                    #expect(actionDispatchReturned)
                    openedWindowID = id
                }
            ),
            toolbarIdentifier: uniqueToolbarIdentifier(),
            autosavesConfiguration: false
        )
        let window = NSWindow(contentViewController: controller)
        window.toolbar = toolbar.managedToolbar
        toolbar.managedToolbar.insertItem(
            withItemIdentifier: NativeWorkspaceToolbar.mapRemoteIdentifier,
            at: toolbar.managedToolbar.items.count
        )

        let item = try #require(toolbar.managedToolbar.items.first {
            $0.itemIdentifier == NativeWorkspaceToolbar.mapRemoteIdentifier
        })
        let action = try #require(item.action)

        NSApp.sendAction(action, to: item.target, from: item)
        #expect(openedWindowID == nil)
        actionDispatchReturned = true

        try await waitUntil { openedWindowID != nil }
        #expect(openedWindowID == "mapRemote")
    }

    @Test("Capture start leaves the AppKit toolbar action turn before mutating SwiftUI state")
    func proxyToggleIsDeferredFromNativeToolbarAction() async throws {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        var actionDispatchReturned = false
        var toggleCount = 0
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: MainContentCoordinator(),
                onOpenDeveloperHub: {},
                onToggleProxy: {
                    #expect(actionDispatchReturned)
                    toggleCount += 1
                }
            ),
            toolbarIdentifier: uniqueToolbarIdentifier(),
            autosavesConfiguration: false
        )
        let window = NSWindow(contentViewController: controller)
        window.toolbar = toolbar.managedToolbar

        let proxyItem = try #require(toolbar.managedToolbar.items.first {
            $0.itemIdentifier == NativeWorkspaceToolbar.proxyToggleIdentifier
        })
        let action = try #require(proxyItem.action)

        NSApp.sendAction(action, to: proxyItem.target, from: proxyItem)
        #expect(toggleCount == 0)
        actionDispatchReturned = true

        try await waitUntil { toggleCount == 1 }
        #expect(toggleCount == 1)
    }

    @Test("Dynamic toolbar state survives palette creation and item re-addition")
    func customizableToolbarDynamicStateRemainsLive() async throws {
        let controller = makeController(sidebarPresented: true, inspectorPresented: true)
        let coordinator = MainContentCoordinator()
        let toolbar = NativeWorkspaceToolbar(
            splitViewController: controller,
            configuration: NativeWorkspaceToolbarConfiguration(
                coordinator: coordinator,
                onOpenDeveloperHub: {}
            ),
            toolbarIdentifier: uniqueToolbarIdentifier(),
            autosavesConfiguration: false
        )
        let window = NSWindow(contentViewController: controller)
        window.toolbar = toolbar.managedToolbar
        toolbar.startObservingState()
        await Task.yield()

        let activeProxyItem = try #require(toolbar.managedToolbar.items.first {
            $0.itemIdentifier == NativeWorkspaceToolbar.proxyToggleIdentifier
        })
        #expect(activeProxyItem.label == String(localized: "Start", bundle: RockxyLocalization.bundle))
        #expect(activeProxyItem.paletteLabel == String(
            localized: "Start or Stop Proxy",
            bundle: RockxyLocalization.bundle
        ))

        // AppKit asks for separate item instances while constructing the palette.
        // That must not replace the live toolbar instance tracked by state updates.
        _ = toolbar.toolbar(
            toolbar.managedToolbar,
            itemForItemIdentifier: NativeWorkspaceToolbar.proxyToggleIdentifier,
            willBeInsertedIntoToolbar: false
        )
        coordinator.isProxyRunning = true
        for _ in 0 ..< 6 where activeProxyItem.label != String(localized: "Stop", bundle: RockxyLocalization.bundle) {
            await Task.yield()
        }
        #expect(activeProxyItem.label == String(localized: "Stop", bundle: RockxyLocalization.bundle))
        #expect(activeProxyItem.paletteLabel == String(
            localized: "Start or Stop Proxy",
            bundle: RockxyLocalization.bundle
        ))

        let proxyIndex = try #require(toolbar.managedToolbar.items.firstIndex {
            $0.itemIdentifier == NativeWorkspaceToolbar.proxyToggleIdentifier
        })
        toolbar.managedToolbar.removeItem(at: proxyIndex)
        toolbar.managedToolbar.insertItem(
            withItemIdentifier: NativeWorkspaceToolbar.proxyToggleIdentifier,
            at: proxyIndex
        )
        let restoredProxyItem = try #require(toolbar.managedToolbar.items.first {
            $0.itemIdentifier == NativeWorkspaceToolbar.proxyToggleIdentifier
        })
        #expect(restoredProxyItem.label == String(localized: "Stop", bundle: RockxyLocalization.bundle))
        #expect(restoredProxyItem.paletteLabel == String(
            localized: "Start or Stop Proxy",
            bundle: RockxyLocalization.bundle
        ))

        coordinator.isProxyRunning = false
        for _ in 0 ..< 6
            where restoredProxyItem.label != String(localized: "Start", bundle: RockxyLocalization.bundle)
        {
            await Task.yield()
        }
        #expect(restoredProxyItem.label == String(localized: "Start", bundle: RockxyLocalization.bundle))

        let transaction = TestFixtures.makeTransaction()
        coordinator.selectedTransaction = transaction
        coordinator.selectedTransactionIDs = [transaction.id]
        coordinator.setBottomInspectorVisible(true)
        let bottomItem = try #require(toolbar.managedToolbar.items.first {
            $0.itemIdentifier == NativeWorkspaceToolbar.bottomInspectorIdentifier
        })
        let expectedBottomToolTip = String(localized: "Hide Bottom Inspector", bundle: RockxyLocalization.bundle)
        for _ in 0 ..< 6 where !bottomItem.isEnabled || bottomItem.toolTip != expectedBottomToolTip {
            await Task.yield()
        }
        #expect(bottomItem.isEnabled)
        #expect(bottomItem.toolTip == expectedBottomToolTip)

        let contextItem = try #require(toolbar.managedToolbar.items.first {
            $0.itemIdentifier == NativeWorkspaceToolbar.contextDockIdentifier
        })
        let initialContextVisibility = coordinator.isContextDockVisible
        let action = try #require(contextItem.action)
        NSApp.sendAction(action, to: contextItem.target, from: contextItem)
        let expectedContextToolTip = initialContextVisibility
            ? String(localized: "Show Context Dock", bundle: RockxyLocalization.bundle)
            : String(localized: "Hide Context Dock", bundle: RockxyLocalization.bundle)
        for _ in 0 ..< 6 where contextItem.toolTip != expectedContextToolTip {
            await Task.yield()
        }
        #expect(coordinator.isContextDockVisible != initialContextVisibility)
        #expect(contextItem.toolTip == expectedContextToolTip)

        toolbar.managedToolbar.insertItem(
            withItemIdentifier: NativeWorkspaceToolbar.recordingIdentifier,
            at: toolbar.managedToolbar.items.count
        )
        let recordingItem = try #require(toolbar.managedToolbar.items.first {
            $0.itemIdentifier == NativeWorkspaceToolbar.recordingIdentifier
        })
        #expect(!recordingItem.isEnabled)

        coordinator.isProxyRunning = true
        for _ in 0 ..< 6 where !recordingItem.isEnabled {
            await Task.yield()
        }
        #expect(recordingItem.isEnabled)
        #expect(recordingItem.label == String(localized: "Pause Recording", bundle: RockxyLocalization.bundle))

        coordinator.isRecording = false
        for _ in 0 ..< 6 where recordingItem.label != String(
            localized: "Resume Recording",
            bundle: RockxyLocalization.bundle
        ) {
            await Task.yield()
        }
        #expect(recordingItem.label == String(localized: "Resume Recording", bundle: RockxyLocalization.bundle))
        #expect(recordingItem.paletteLabel == String(localized: "Toggle Recording", bundle: RockxyLocalization.bundle))

        toolbar.managedToolbar.insertItem(
            withItemIdentifier: NativeWorkspaceToolbar.detachedInspectorIdentifier,
            at: toolbar.managedToolbar.items.count
        )
        let detachedInspectorItem = try #require(toolbar.managedToolbar.items.first {
            $0.itemIdentifier == NativeWorkspaceToolbar.detachedInspectorIdentifier
        })
        #expect(detachedInspectorItem.isEnabled)
    }

    // MARK: - Project selector sizing metrics

    @Test("Project selector preferred width stays within its metric bounds")
    func projectSelectorPreferredWidthWithinBounds() {
        let names = [
            "",
            "QA",
            "My Project",
            "Checkout Service API",
            String(repeating: "Extremely Long Project Name ", count: 8),
        ]

        for name in names {
            let width = ProjectToolbarSelectorMetrics.preferredWidth(for: name)
            #expect(width >= ProjectToolbarSelectorMetrics.minimumWidth)
            #expect(width <= ProjectToolbarSelectorMetrics.maximumWidth)
        }
    }

    @Test("Project selector width grows monotonically and clamps at both extremes")
    func projectSelectorPreferredWidthMonotonicAndClamped() {
        let shortWidth = ProjectToolbarSelectorMetrics.preferredWidth(for: "QA")
        let mediumWidth = ProjectToolbarSelectorMetrics.preferredWidth(for: "Checkout Service API")
        let longWidth = ProjectToolbarSelectorMetrics.preferredWidth(
            for: String(repeating: "Extremely Long Project Name ", count: 8)
        )

        #expect(shortWidth <= mediumWidth)
        #expect(mediumWidth <= longWidth)

        #expect(shortWidth == ProjectToolbarSelectorMetrics.minimumWidth)
        #expect(longWidth == ProjectToolbarSelectorMetrics.maximumWidth)

        #expect(mediumWidth > ProjectToolbarSelectorMetrics.minimumWidth)
        #expect(mediumWidth < ProjectToolbarSelectorMetrics.maximumWidth)
    }

    @Test("Hosted Project selector responds to the active Project name")
    func hostedProjectSelectorRespondsToProjectName() throws {
        let shortCoordinator = MainContentCoordinator()
        try shortCoordinator.projectStore.renameProject(
            id: shortCoordinator.projectStore.activeProjectID,
            to: "QA"
        )
        let longCoordinator = MainContentCoordinator()
        try longCoordinator.projectStore.renameProject(
            id: longCoordinator.projectStore.activeProjectID,
            to: String(repeating: "Long Project ", count: 6)
        )

        let shortView = NSHostingView(
            rootView: ProjectToolbarSelectorView(coordinator: shortCoordinator)
        )
        let longView = NSHostingView(
            rootView: ProjectToolbarSelectorView(coordinator: longCoordinator)
        )

        #expect(shortView.fittingSize.width == ProjectToolbarSelectorMetrics.minimumWidth)
        #expect(longView.fittingSize.width == ProjectToolbarSelectorMetrics.maximumWidth)
        #expect(shortView.fittingSize.width < longView.fittingSize.width)
    }

    @Test("Project manager adopts useful resizable tool-window geometry")
    func projectManagerToolWindowGeometry() {
        let hostingView = NSHostingView(
            rootView: ProjectManagerSheet(coordinator: MainContentCoordinator())
        )
        let size = hostingView.fittingSize

        #expect(size.width >= 720)
        #expect(size.height >= 500)
        #expect(size.width > size.height)
    }

    // MARK: - Startup geometry readiness

    @Test("Layout readiness rejects zero, negative, and non-finite bounds")
    func layoutReadinessRejectsInvalidBounds() {
        #expect(!NativeWorkspaceSplitSizing.isLayoutReady(.zero))
        #expect(!NativeWorkspaceSplitSizing.isLayoutReady(CGRect(x: 0, y: 0, width: 0, height: 700)))
        #expect(!NativeWorkspaceSplitSizing.isLayoutReady(CGRect(x: 0, y: 0, width: 1_300, height: 0)))
        #expect(!NativeWorkspaceSplitSizing.isLayoutReady(CGRect(x: 0, y: 0, width: -10, height: 700)))
        #expect(!NativeWorkspaceSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: CGFloat.nan, height: 700)
        ))
        #expect(NativeWorkspaceSplitSizing.isLayoutReady(CGRect(x: 0, y: 0, width: 1_300, height: 700)))
    }

    @Test("Ideal placement seats every presented pane at or above its minimum")
    func idealPlacementRespectsMinimums() throws {
        let placement = try #require(NativeWorkspaceSplitSizing.idealPlacement(
            totalWidth: 1_300,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: true,
            sidebarIdealWidth: 250,
            inspectorIdealWidth: 380,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))

        let sidebarWidth = try #require(placement.leadingDividerPosition)
        let trailing = try #require(placement.trailingDividerPosition)
        let inspectorWidth = 1_300 - trailing - 1
        let workspaceWidth = trailing - (sidebarWidth + 1)

        #expect(sidebarWidth >= 200)
        #expect(inspectorWidth >= 300)
        #expect(workspaceWidth >= 600)
    }

    @Test("Ideal placement is skipped when the window cannot seat the workspace minimum")
    func idealPlacementSkippedWhenTooNarrow() {
        let placement = NativeWorkspaceSplitSizing.idealPlacement(
            totalWidth: 1_150,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: true,
            sidebarIdealWidth: 250,
            inspectorIdealWidth: 380,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        )

        #expect(placement == nil)
    }

    @Test("Ideal placement omits the divider for a collapsed pane")
    func idealPlacementForSinglePresentedPane() throws {
        let placement = try #require(NativeWorkspaceSplitSizing.idealPlacement(
            totalWidth: 1_300,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: false,
            sidebarIdealWidth: 250,
            inspectorIdealWidth: 380,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))

        #expect(placement.leadingDividerPosition == 250)
        #expect(placement.trailingDividerPosition == nil)
    }

    @Test("Configuring at zero bounds never produces negative arranged geometry")
    func zeroBoundsProducesNonNegativeGeometry() {
        let autosaveName = uniqueAutosaveName()
        let controller = makeConfiguredController(
            sidebarPresented: true,
            inspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: .zero)

        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Moving from a zero frame to a sufficient frame preserves visibility and safe geometry")
    func deferredLayoutPreservesVisibilityAndSafeGeometry() {
        let autosaveName = uniqueAutosaveName()
        removeSplitViewAutosaveDefaults(autosaveName)
        let controller = makeConfiguredController(
            sidebarPresented: true,
            inspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: .zero)
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_300, height: 700))

        #expect(controller.isSidebarPresented)
        #expect(controller.isInspectorPresented)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Minima readiness rejects raw-invalid and too-narrow widths but accepts a minimum-capable width")
    func minimaReadinessGuardsInitialLatch() {
        // Raw-negative width must be rejected, not standardized to a positive value.
        #expect(!NativeWorkspaceSplitSizing.canSeatRequestedMinima(
            totalWidth: -1_300,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: true,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))

        // 200 + 600 + 300 + two dividers = 1_102 required; 900 cannot seat the minima.
        #expect(!NativeWorkspaceSplitSizing.canSeatRequestedMinima(
            totalWidth: 900,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: true,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))

        // 1_150 seats the minima (1_102) even though it cannot seat the ideals.
        #expect(NativeWorkspaceSplitSizing.canSeatRequestedMinima(
            totalWidth: 1_150,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: true,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))

        // A collapsed inspector drops its pane and divider from the requirement.
        #expect(NativeWorkspaceSplitSizing.canSeatRequestedMinima(
            totalWidth: 810,
            dividerThickness: 1,
            sidebarPresented: true,
            inspectorPresented: false,
            sidebarMinimumWidth: 200,
            workspaceMinimumWidth: 600,
            inspectorMinimumWidth: 300
        ))
    }

    @Test("A provisional too-narrow pass stays safe when the workspace later expands")
    func provisionalTooNarrowPassStaysSafeAcrossExpansion() {
        let autosaveName = uniqueAutosaveName()
        removeSplitViewAutosaveDefaults(autosaveName)
        let controller = makeConfiguredController(
            sidebarPresented: true,
            inspectorPresented: true,
            autosaveName: autosaveName
        )

        // Positive and finite, but too narrow to seat sidebar + workspace + inspector minima
        // plus dividers. The provisional pass and the later expanded pass must both keep
        // every arranged pane in valid geometry.
        layout(controller, at: CGRect(x: 0, y: 0, width: 900, height: 700))
        expectNonNegativeArrangedGeometry(controller)
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_300, height: 700))

        #expect(controller.isSidebarPresented)
        #expect(controller.isInspectorPresented)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("A window too narrow for ideal placement preserves visibility without negative geometry")
    func insufficientWidthPreservesVisibility() {
        let autosaveName = uniqueAutosaveName()
        let controller = makeConfiguredController(
            sidebarPresented: true,
            inspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: CGRect(x: 0, y: 0, width: 1_150, height: 700))

        #expect(controller.isSidebarPresented)
        #expect(controller.isInspectorPresented)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeController(
        sidebarPresented: Bool,
        inspectorPresented: Bool
    )
        -> NativeWorkspaceSplitViewController
    {
        let controller = makeConfiguredController(
            sidebarPresented: sidebarPresented,
            inspectorPresented: inspectorPresented,
            autosaveName: uniqueAutosaveName()
        )
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_300, height: 700))
        return controller
    }

    private func layout(_ controller: NativeWorkspaceSplitViewController, at frame: CGRect) {
        controller.view.frame = frame
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
    }

    private func makeConfiguredController(
        sidebarPresented: Bool,
        inspectorPresented: Bool,
        autosaveName: String
    )
        -> NativeWorkspaceSplitViewController
    {
        let controller = NativeWorkspaceSplitViewController()
        controller.configure(
            sidebarController: NSHostingController(rootView: Color.clear),
            workspaceController: NSHostingController(rootView: Color.clear),
            inspectorController: NSHostingController(rootView: Color.clear),
            isSidebarPresented: sidebarPresented,
            isInspectorPresented: inspectorPresented,
            layout: NativeWorkspaceSplitLayout(
                autosaveName: autosaveName,
                sidebarMinimumWidth: 200,
                sidebarIdealWidth: 250,
                sidebarMaximumWidth: 350,
                workspaceMinimumWidth: 320,
                inspectorMinimumWidth: 220,
                inspectorIdealWidth: 380
            )
        )
        return controller
    }

    private func uniqueAutosaveName() -> String {
        AppKitAutosaveTestKeys.uniqueSplitViewAutosaveName(for: .workspaceSplitView)
    }

    private func uniqueToolbarIdentifier() -> NSToolbar.Identifier {
        AppKitAutosaveTestKeys.uniqueToolbarIdentifier(for: .workspaceSplitView)
    }

    private func waitUntil(
        attempts: Int = 500,
        condition: @MainActor () -> Bool
    )
        async throws
    {
        for _ in 0 ..< attempts {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        if condition() {
            return
        }
        throw NativeWorkspaceSplitViewTestTimeout()
    }

    private func expectNonNegativeArrangedGeometry(_ controller: NativeWorkspaceSplitViewController) {
        for item in controller.splitViewItems {
            let frame = item.viewController.view.frame
            #expect(frame.width.isFinite)
            #expect(frame.height.isFinite)
            #expect(frame.width >= 0)
            #expect(frame.height >= 0)
        }
    }

    private func removeSplitViewAutosaveDefaults(_ autosaveName: String) {
        UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames \(autosaveName)")
    }

    private func removeToolbarConfigurationDefaults(_ identifier: NSToolbar.Identifier) {
        UserDefaults.standard.removeObject(forKey: "NSToolbar Configuration \(identifier)")
    }
}

// MARK: - NativeWorkspaceSplitViewTestTimeout

private struct NativeWorkspaceSplitViewTestTimeout: Error {}
