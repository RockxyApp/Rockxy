@preconcurrency import AppKit
import os
import SwiftUI

// MARK: - RockxyWorkspaceWindowManager

/// AppKit-backed window tab coordinator for the main Rockxy workspace.
///
/// Workspace capacity and edition behavior stay in `WorkspaceStore` and
/// `AppPolicy`; this type only presents already-created workspaces as native
/// macOS window tabs.
@MainActor
final class RockxyWorkspaceWindowManager: NSObject {
    // MARK: Lifecycle

    override private init() {}

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

    func beginRenameForActiveWorkspace(coordinator: MainContentCoordinator) {
        guard let window = window(forWorkspaceID: coordinator.workspaceStore.activeWorkspaceID) ?? NSApp.keyWindow,
              let workspaceID = workspaceID(for: window) else {
            return
        }
        beginRename(window: window, workspaceID: workspaceID, coordinator: coordinator)
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
    private var tabInteractionMonitor: Any?
    private var renameSession: WorkspaceTabRenameSession?

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
        installTabInteractionMonitorIfNeeded()
        updateWindowTitles(coordinator: coordinator)
    }

    private func installTabInteractionMonitorIfNeeded() {
        guard tabInteractionMonitor == nil else {
            return
        }
        tabInteractionMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { @MainActor [weak self] event in
            self?.handleTabMouseEvent(event) ?? event
        }
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
        if renameSession?.windowKey == windowKey {
            renameSession?.cancel()
            renameSession = nil
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

    private func beginRename(window: NSWindow, workspaceID: UUID, coordinator: MainContentCoordinator) {
        guard let workspace = coordinator.workspaceStore.workspaces.first(where: { $0.id == workspaceID }) else {
            return
        }
        renameSession?.commit()
        syncWorkspaceOrderFromNativeTabs(around: window, coordinator: coordinator)
        renameSession = WorkspaceTabRenameSession(
            window: window,
            workspace: workspace,
            coordinator: coordinator,
            frame: editorFrame(for: window)
        ) { [weak self] in
            self?.renameSession = nil
        }
    }

    private func handleTabMouseEvent(_ event: NSEvent) -> NSEvent? {
        if let renameSession, !renameSession.contains(event: event) {
            renameSession.commit()
            self.renameSession = nil
        }

        guard let target = tabHitTarget(for: event) else {
            return event
        }

        switch event.type {
        case .leftMouseDown where event.clickCount == 2:
            target.window.makeKeyAndOrderFront(nil)
            beginRename(window: target.window, workspaceID: target.workspaceID, coordinator: target.coordinator)
            return nil
        case .rightMouseDown:
            showTabContextMenu(for: target, event: event)
            return nil
        default:
            return event
        }
    }

    private func tabHitTarget(for event: NSEvent) -> WorkspaceTabHitTarget? {
        guard let sourceWindow = event.window,
              sourceWindow.identifier == Self.mainWindowIdentifier,
              let coordinator,
              isLocationInTabStrip(event.locationInWindow, window: sourceWindow),
              let targetWindow = tabWindow(at: event.locationInWindow, in: sourceWindow),
              let workspaceID = workspaceID(for: targetWindow) else {
            return nil
        }
        return WorkspaceTabHitTarget(window: targetWindow, workspaceID: workspaceID, coordinator: coordinator)
    }

    private func showTabContextMenu(for target: WorkspaceTabHitTarget, event: NSEvent) {
        guard let view = event.window?.contentView else {
            return
        }

        let menu = NSMenu()
        let renameItem = NSMenuItem(
            title: String(localized: "Rename Tab"),
            action: #selector(handleRenameTabMenuItem(_:)),
            keyEquivalent: ""
        )
        renameItem.target = self
        renameItem.representedObject = target.workspaceID
        menu.addItem(renameItem)

        if let workspace = target.coordinator.workspaceStore.workspaces.first(where: { $0.id == target.workspaceID }),
           workspace.isClosable {
            let closeItem = NSMenuItem(
                title: String(localized: "Close Tab"),
                action: #selector(handleCloseTabMenuItem(_:)),
                keyEquivalent: ""
            )
            closeItem.target = self
            closeItem.representedObject = target.workspaceID
            menu.addItem(closeItem)
        }

        if target.coordinator.workspaceStore.canCreateWorkspace {
            menu.addItem(.separator())
            let newItem = NSMenuItem(
                title: String(localized: "New Tab"),
                action: #selector(handleNewTabMenuItem(_:)),
                keyEquivalent: ""
            )
            newItem.target = self
            menu.addItem(newItem)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func isLocationInTabStrip(_ location: NSPoint, window: NSWindow) -> Bool {
        let leftInset: CGFloat = 76
        let rightInset: CGFloat = 52
        let tabbedWindowCount = window.tabbedWindows?.count ?? 1
        let contentTop = window.contentLayoutRect.maxY
        return tabbedWindowCount > 1
            && location.y >= contentTop
            && location.y <= window.frame.height
            && location.x >= leftInset
            && location.x <= window.frame.width - rightInset
    }

    private func tabWindow(at location: NSPoint, in window: NSWindow) -> NSWindow? {
        let tabbedWindows = window.tabbedWindows ?? [window]
        guard !tabbedWindows.isEmpty else {
            return nil
        }
        let leftInset: CGFloat = 76
        let rightInset: CGFloat = 52
        let availableWidth = max(1, window.frame.width - leftInset - rightInset)
        let index = min(
            max(Int((location.x - leftInset) / (availableWidth / CGFloat(tabbedWindows.count))), 0),
            tabbedWindows.count - 1
        )
        return tabbedWindows[index]
    }

    private func editorFrame(for window: NSWindow) -> NSRect {
        let tabbedWindows = window.tabbedWindows ?? [window]
        let index = tabbedWindows.firstIndex(of: window) ?? 0
        let leftInset: CGFloat = 76
        let rightInset: CGFloat = 52
        let availableWidth = max(120, window.frame.width - leftInset - rightInset)
        let tabWidth = availableWidth / CGFloat(max(tabbedWindows.count, 1))
        let horizontalPadding: CGFloat = 12
        let width = max(86, min(tabWidth - horizontalPadding * 2, 260))
        let x = window.frame.minX + leftInset + tabWidth * CGFloat(index) + horizontalPadding
        let titlebarHeight = max(28, window.frame.height - window.contentLayoutRect.maxY)
        let y = window.frame.minY + window.contentLayoutRect.maxY + max(4, (titlebarHeight - 24) / 2)
        return NSRect(x: x, y: y, width: width, height: 24)
    }

    @objc private func handleRenameTabMenuItem(_ sender: NSMenuItem) {
        guard let coordinator,
              let workspaceID = sender.representedObject as? UUID,
              let window = window(forWorkspaceID: workspaceID) else {
            return
        }
        window.makeKeyAndOrderFront(nil)
        beginRename(window: window, workspaceID: workspaceID, coordinator: coordinator)
    }

    @objc private func handleCloseTabMenuItem(_ sender: NSMenuItem) {
        guard let workspaceID = sender.representedObject as? UUID,
              let window = window(forWorkspaceID: workspaceID),
              let coordinator else {
            return
        }
        window.makeKeyAndOrderFront(nil)
        coordinator.workspaceStore.selectWorkspace(id: workspaceID)
        closeCurrentWorkspaceTab(coordinator: coordinator)
    }

    @objc private func handleNewTabMenuItem(_ sender: NSMenuItem) {
        openNewWorkspaceTabFromNativeControl()
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

// MARK: - WorkspaceTabHitTarget

private struct WorkspaceTabHitTarget {
    let window: NSWindow
    let workspaceID: UUID
    let coordinator: MainContentCoordinator
}

// MARK: - WorkspaceTabRenameSession

@MainActor
private final class WorkspaceTabRenameSession: NSObject, NSTextFieldDelegate {
    // MARK: Lifecycle

    init(
        window: NSWindow,
        workspace: WorkspaceState,
        coordinator: MainContentCoordinator,
        frame: NSRect,
        onFinish: @escaping () -> Void
    ) {
        self.windowKey = ObjectIdentifier(window)
        self.workspace = workspace
        self.coordinator = coordinator
        self.originalTitle = workspace.title
        self.onFinish = onFinish

        let panel = WorkspaceTabRenamePanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating

        let field = WorkspaceTabRenameField(frame: NSRect(origin: .zero, size: frame.size))
        field.stringValue = workspace.title
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.alignment = .center
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.backgroundColor = .controlBackgroundColor
        field.textColor = .labelColor
        field.focusRingType = .default

        super.init()

        self.panel = panel
        self.field = field
        panel.onResignKey = { [weak self] in
            self?.commit()
        }
        field.delegate = self
        field.onCommit = { [weak self] in self?.commit() }
        field.onCancel = { [weak self] in self?.cancel() }
        panel.contentView = field

        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    // MARK: Internal

    let windowKey: ObjectIdentifier

    func contains(event: NSEvent) -> Bool {
        event.window === panel
    }

    func commit() {
        guard !isFinished else {
            return
        }
        isFinished = true
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        workspace.title = title.isEmpty ? originalTitle : title
        if let coordinator {
            RockxyWorkspaceWindowManager.shared.updateWindowTitles(coordinator: coordinator)
        }
        close()
    }

    func cancel() {
        guard !isFinished else {
            return
        }
        isFinished = true
        workspace.title = originalTitle
        if let coordinator {
            RockxyWorkspaceWindowManager.shared.updateWindowTitles(coordinator: coordinator)
        }
        close()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commit()
    }

    // MARK: Private

    private weak var coordinator: MainContentCoordinator?
    private let workspace: WorkspaceState
    private let originalTitle: String
    private let onFinish: () -> Void
    private var isFinished = false
    private var panel: WorkspaceTabRenamePanel!
    private var field: WorkspaceTabRenameField!

    private func close() {
        panel.parent?.removeChildWindow(panel)
        panel.close()
        onFinish()
    }
}

@MainActor
private final class WorkspaceTabRenamePanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
private final class WorkspaceTabRenameField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onCommit?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

private extension RockxyWorkspaceWindowManager {
    var currentCoordinator: MainContentCoordinator? {
        coordinator
    }
}
