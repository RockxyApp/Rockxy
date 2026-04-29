import AppKit
import os
import SwiftUI

// MARK: - RockxyWorkspaceWindowManager

/// AppKit-backed window tab coordinator for the main Rockxy workspace.
///
/// Workspace capacity and edition behavior stay in `WorkspaceStore` and
/// `AppPolicy`; this type only presents already-created workspaces as native
/// macOS window tabs.
@MainActor
final class RockxyWorkspaceWindowManager {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = RockxyWorkspaceWindowManager()

    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("main")
    static let tabbingIdentifier = "\(RockxyIdentity.current.logSubsystem).mainWorkspace"

    func registerPrimaryWindow(_ window: NSWindow, coordinator: MainContentCoordinator) {
        let workspaceID = coordinator.workspaceStore.workspaces.first(where: { !$0.isClosable })?.id
            ?? coordinator.workspaceStore.activeWorkspaceID
        configure(window)
        register(window: window, workspaceID: workspaceID, coordinator: coordinator)
    }

    func openWorkspaceTab(coordinator: MainContentCoordinator, workspaceID: UUID) {
        guard coordinator.workspaceStore.workspaces.contains(where: { $0.id == workspaceID }) else {
            return
        }

        self.coordinator = coordinator
        coordinator.workspaceStore.selectWorkspace(id: workspaceID)

        let controller = WorkspaceTabWindowController(coordinator: coordinator, workspaceID: workspaceID)
        guard let window = controller.window else {
            Self.logger.error("Failed to create workspace tab window")
            return
        }

        retain(controller: controller, window: window)
        register(window: window, workspaceID: workspaceID, coordinator: coordinator)

        if let sibling = findSibling(excluding: window) {
            let target = sibling.tabbedWindows?.last ?? sibling
            target.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        syncWorkspaceOrderFromNativeTabs(around: window, coordinator: coordinator)
        updateWindowTitles(coordinator: coordinator)
    }

    func openNewWorkspaceTabFromNativeControl() {
        guard let coordinator,
              coordinator.workspaceStore.canCreateWorkspace else {
            return
        }
        let workspace = coordinator.workspaceStore.createWorkspace()
        openWorkspaceTab(coordinator: coordinator, workspaceID: workspace.id)
        prepareWorkspaceContent(workspace, coordinator: coordinator)
    }

    var canCreateWorkspaceTab: Bool {
        coordinator?.workspaceStore.canCreateWorkspace == true
    }

    func closeCurrentWorkspaceTab(coordinator: MainContentCoordinator) {
        syncWorkspaceOrderFromNativeTabs(coordinator: coordinator)
        let activeWorkspace = coordinator.workspaceStore.activeWorkspace
        guard activeWorkspace.isClosable else {
            return
        }

        if let keyWindow = NSApp.keyWindow,
           workspaceID(for: keyWindow) == activeWorkspace.id {
            keyWindow.close()
            return
        }

        if let window = window(forWorkspaceID: activeWorkspace.id) {
            window.close()
            return
        }

        coordinator.workspaceStore.closeWorkspace(id: activeWorkspace.id)
        updateWindowTitles(coordinator: coordinator)
    }

    func selectWorkspaceTab(at index: Int, coordinator: MainContentCoordinator) {
        syncWorkspaceOrderFromNativeTabs(coordinator: coordinator)
        guard let keyWindow = NSApp.keyWindow,
              let tabbedWindows = keyWindow.tabbedWindows,
              index >= 0,
              index < tabbedWindows.count else {
            coordinator.workspaceStore.selectWorkspace(at: index)
            updateWindowTitles(coordinator: coordinator)
            return
        }
        tabbedWindows[index].makeKeyAndOrderFront(nil)
    }

    func selectPreviousWorkspaceTab(coordinator: MainContentCoordinator) {
        syncWorkspaceOrderFromNativeTabs(coordinator: coordinator)
        guard visibleTabbedWindowCount > 1 else {
            coordinator.workspaceStore.selectPreviousWorkspace()
            updateWindowTitles(coordinator: coordinator)
            return
        }
        NSApp.sendAction(#selector(NSWindow.selectPreviousTab(_:)), to: nil, from: nil)
    }

    func selectNextWorkspaceTab(coordinator: MainContentCoordinator) {
        syncWorkspaceOrderFromNativeTabs(coordinator: coordinator)
        guard visibleTabbedWindowCount > 1 else {
            coordinator.workspaceStore.selectNextWorkspace()
            updateWindowTitles(coordinator: coordinator)
            return
        }
        NSApp.sendAction(#selector(NSWindow.selectNextTab(_:)), to: nil, from: nil)
    }

    func handleWindowDidBecomeKey(_ window: NSWindow) {
        guard let coordinator,
              let workspaceID = workspaceID(for: window) else {
            return
        }
        syncWorkspaceOrderFromNativeTabs(around: window, coordinator: coordinator)
        coordinator.workspaceStore.selectWorkspace(id: workspaceID)
        updateWindowTitles(coordinator: coordinator)
    }

    func handleWindowWillClose(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        let workspaceID = workspacesByWindow[key]
        release(windowKey: key)
        workspacesByWindow.removeValue(forKey: key)

        guard let coordinator,
              let workspaceID,
              let workspace = coordinator.workspaceStore.workspaces.first(where: { $0.id == workspaceID }),
              workspace.isClosable else {
            return
        }

        syncWorkspaceOrderFromNativeTabs(coordinator: coordinator)
        coordinator.workspaceStore.closeWorkspace(id: workspaceID)
        updateWindowTitles(coordinator: coordinator)
    }

    func updateWindowTitles(coordinator: MainContentCoordinator) {
        for window in windows {
            guard let workspaceID = workspaceID(for: window),
                  let workspace = coordinator.workspaceStore.workspaces.first(where: { $0.id == workspaceID }) else {
                continue
            }
            window.title = workspace.title
        }
    }

    func prepareWorkspaceContent(_ workspace: WorkspaceState, coordinator: MainContentCoordinator) {
        Task { @MainActor in
            await Task.yield()
            guard coordinator.workspaceStore.workspaces.contains(where: { $0.id == workspace.id }) else {
                return
            }
            coordinator.recomputeFilteredTransactions(for: workspace)
            coordinator.rebuildSidebarIndexes(for: workspace)
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "NativeWorkspaceTabs")

    private weak var coordinator: MainContentCoordinator?
    private var controllers: [ObjectIdentifier: WorkspaceTabWindowController] = [:]
    private var workspacesByWindow: [ObjectIdentifier: UUID] = [:]
    private var observersByWindow: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    private var windows: [NSWindow] {
        NSApp.windows.filter { $0.identifier == Self.mainWindowIdentifier }
    }

    private var visibleTabbedWindowCount: Int {
        guard let keyWindow = NSApp.keyWindow else {
            return 0
        }
        return (keyWindow.tabbedWindows ?? [keyWindow]).filter(\.isVisible).count
    }

    private func configure(_ window: NSWindow) {
        window.identifier = Self.mainWindowIdentifier
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.collectionBehavior.insert([.fullScreenPrimary, .managed])
    }

    private func register(window: NSWindow, workspaceID: UUID, coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        configure(window)
        let key = ObjectIdentifier(window)
        workspacesByWindow[key] = workspaceID
        installObserversIfNeeded(for: window)
        updateWindowTitles(coordinator: coordinator)
    }

    private func installObserversIfNeeded(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard observersByWindow[key] == nil else {
            return
        }

        let didBecomeKey = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else {
                return
            }
            MainActor.assumeIsolated {
                self?.handleWindowDidBecomeKey(window)
            }
        }

        let willClose = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else {
                return
            }
            MainActor.assumeIsolated {
                self?.handleWindowWillClose(window)
            }
        }

        observersByWindow[key] = [didBecomeKey, willClose]
    }

    private func retain(controller: WorkspaceTabWindowController, window: NSWindow) {
        controllers[ObjectIdentifier(window)] = controller
    }

    private func release(windowKey: ObjectIdentifier) {
        if let observers = observersByWindow.removeValue(forKey: windowKey) {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        controllers.removeValue(forKey: windowKey)
    }

    private func workspaceID(for window: NSWindow) -> UUID? {
        workspacesByWindow[ObjectIdentifier(window)]
    }

    private func syncWorkspaceOrderFromNativeTabs(
        around window: NSWindow? = nil,
        coordinator: MainContentCoordinator
    ) {
        guard let window = window ?? NSApp.keyWindow else {
            return
        }
        let orderedIDs = (window.tabbedWindows ?? [window]).compactMap { workspaceID(for: $0) }
        guard orderedIDs.count > 1 else {
            return
        }
        coordinator.workspaceStore.reorderWorkspaces(toWorkspaceIDs: orderedIDs)
    }

    private func window(forWorkspaceID targetWorkspaceID: UUID) -> NSWindow? {
        windows.first { workspaceID(for: $0) == targetWorkspaceID }
    }

    private func findSibling(excluding window: NSWindow) -> NSWindow? {
        windows.first { candidate in
            candidate !== window
                && candidate.isVisible
                && candidate.tabbingIdentifier == Self.tabbingIdentifier
        }
    }
}

// MARK: - WorkspaceTabWindowController

@MainActor
private final class WorkspaceTabWindow: NSWindow {
    override func performClose(_ sender: Any?) {
        if let coordinator = RockxyWorkspaceWindowManager.shared.currentCoordinator {
            RockxyWorkspaceWindowManager.shared.closeCurrentWorkspaceTab(coordinator: coordinator)
        } else {
            super.performClose(sender)
        }
    }
}

@MainActor
final class WorkspaceTabWindowController: NSWindowController {
    // MARK: Lifecycle

    init(coordinator: MainContentCoordinator, workspaceID: UUID) {
        let window = WorkspaceTabWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 900, height: 620)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: ContentView(
                coordinator: coordinator,
                managesLifecycle: false,
                representedWorkspaceID: workspaceID
            )
        )

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WorkspaceTabWindowController does not support NSCoder init")
    }
}

private extension RockxyWorkspaceWindowManager {
    var currentCoordinator: MainContentCoordinator? {
        coordinator
    }
}
