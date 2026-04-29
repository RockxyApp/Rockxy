@preconcurrency import AppKit
import os

// MARK: - RockxyWorkspaceWindowManager

/// AppKit-backed workspace tab coordinator for Rockxy's main window.
///
/// Capacity and edition behavior remain owned by `WorkspaceStore` and
/// `AppPolicy`. This type only presents existing workspaces in a native
/// titlebar accessory and routes user interaction back to the shared store.
@MainActor
final class RockxyWorkspaceWindowManager: NSObject {
    // MARK: Lifecycle

    override private init() {}

    // MARK: Internal

    static let shared = RockxyWorkspaceWindowManager()

    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("main")
    static let tabbingIdentifier = "\(RockxyIdentity.current.logSubsystem).mainWorkspace"

    var canCreateWorkspaceTab: Bool {
        coordinator?.workspaceStore.canCreateWorkspace == true
    }

    var canRenameWorkspaceTab: Bool {
        guard let coordinator else {
            return false
        }
        return coordinator.workspaceStore.workspaces.contains {
            $0.id == coordinator.workspaceStore.activeWorkspaceID
        }
    }

    func registerPrimaryWindow(_ window: NSWindow, coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        primaryWindow = window
        configure(window)
        installObserversIfNeeded(for: window)
        updateTabAccessory()
        updateWindowTitles(coordinator: coordinator)
    }

    func openWorkspaceTab(coordinator: MainContentCoordinator, workspaceID: UUID) {
        guard coordinator.workspaceStore.workspaces.contains(where: { $0.id == workspaceID }) else {
            return
        }
        self.coordinator = coordinator
        coordinator.workspaceStore.selectWorkspace(id: workspaceID)
        updateTabAccessory()
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

    func closeCurrentWorkspaceTab(coordinator: MainContentCoordinator) {
        let workspaceID = coordinator.workspaceStore.activeWorkspaceID
        closeWorkspace(workspaceID)
    }

    func selectWorkspaceTab(at index: Int, coordinator: MainContentCoordinator) {
        guard index >= 0, index < coordinator.workspaceStore.workspaces.count else {
            return
        }
        self.coordinator = coordinator
        coordinator.workspaceStore.selectWorkspace(at: index)
        updateTabAccessory()
        updateWindowTitles(coordinator: coordinator)
    }

    func selectPreviousWorkspaceTab(coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        coordinator.workspaceStore.selectPreviousWorkspace()
        updateTabAccessory()
        updateWindowTitles(coordinator: coordinator)
    }

    func selectNextWorkspaceTab(coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        coordinator.workspaceStore.selectNextWorkspace()
        updateTabAccessory()
        updateWindowTitles(coordinator: coordinator)
    }

    func handleWindowDidBecomeKey(_ window: NSWindow) {
        guard window === primaryWindow else {
            return
        }
        updateTabAccessory()
        if let coordinator {
            updateWindowTitles(coordinator: coordinator)
        }
    }

    func handleWindowWillClose(_ window: NSWindow) {
        guard window === primaryWindow else {
            return
        }
        removeAccessory(for: window)
        removeObservers(for: window)
        primaryWindow = nil
        coordinator = nil
    }

    func updateWindowTitles(coordinator: MainContentCoordinator) {
        primaryWindow?.title = coordinator.workspaceStore.activeWorkspace.title
    }

    func beginRenameForActiveWorkspace(coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        beginInlineRename(workspaceID: coordinator.workspaceStore.activeWorkspaceID)
    }

    func beginRenameForCurrentWorkspace() {
        guard let coordinator else {
            return
        }
        beginInlineRename(workspaceID: coordinator.workspaceStore.activeWorkspaceID)
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

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "WorkspaceTabs")

    private weak var coordinator: MainContentCoordinator?
    private weak var primaryWindow: NSWindow?
    private var accessoryControllers: [ObjectIdentifier: WorkspaceTabBarAccessoryController] = [:]
    private var observersByWindow: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    private func configure(_ window: NSWindow) {
        window.identifier = Self.mainWindowIdentifier
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.collectionBehavior.insert([.fullScreenPrimary, .managed])
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

    private func removeObservers(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard let observers = observersByWindow.removeValue(forKey: key) else {
            return
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateTabAccessory(forceVisible: Bool = false) {
        guard let window = primaryWindow,
              let coordinator else {
            return
        }

        let shouldShow = forceVisible || coordinator.workspaceStore.workspaces.count > 1
        guard shouldShow else {
            removeAccessory(for: window)
            return
        }

        let controller = accessoryController(for: window)
        controller.update(coordinator: coordinator)
    }

    private func accessoryController(for window: NSWindow) -> WorkspaceTabBarAccessoryController {
        let key = ObjectIdentifier(window)
        if let controller = accessoryControllers[key] {
            return controller
        }

        let controller = WorkspaceTabBarAccessoryController(manager: self)
        accessoryControllers[key] = controller
        window.addTitlebarAccessoryViewController(controller)
        return controller
    }

    private func removeAccessory(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard let controller = accessoryControllers.removeValue(forKey: key) else {
            return
        }
        controller.endEditing(commit: true)
        if let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === controller }) {
            window.removeTitlebarAccessoryViewController(at: index)
        }
    }

    private func beginInlineRename(workspaceID: UUID) {
        guard let window = primaryWindow,
              let coordinator,
              coordinator.workspaceStore.workspaces.contains(where: { $0.id == workspaceID }) else {
            return
        }

        updateTabAccessory(forceVisible: true)
        let controller = accessoryController(for: window)
        controller.update(coordinator: coordinator)
        controller.beginRename(workspaceID: workspaceID)
    }

    fileprivate func selectWorkspace(_ workspaceID: UUID) {
        guard let coordinator,
              coordinator.workspaceStore.workspaces.contains(where: { $0.id == workspaceID }) else {
            return
        }
        coordinator.workspaceStore.selectWorkspace(id: workspaceID)
        updateTabAccessory()
        updateWindowTitles(coordinator: coordinator)
    }

    fileprivate func closeWorkspace(_ workspaceID: UUID) {
        guard let coordinator,
              let workspace = coordinator.workspaceStore.workspaces.first(where: { $0.id == workspaceID }),
              workspace.isClosable else {
            return
        }
        coordinator.workspaceStore.closeWorkspace(id: workspaceID)
        updateTabAccessory()
        updateWindowTitles(coordinator: coordinator)
    }

    fileprivate func createWorkspace() {
        openNewWorkspaceTabFromNativeControl()
    }

    fileprivate func renameWorkspace(_ workspaceID: UUID, to title: String) {
        guard let coordinator,
              coordinator.workspaceStore.workspaces.contains(where: { $0.id == workspaceID }) else {
            return
        }
        coordinator.workspaceStore.renameWorkspace(id: workspaceID, to: title)
        updateTabAccessory(forceVisible: coordinator.workspaceStore.workspaces.count > 1)
        updateWindowTitles(coordinator: coordinator)
    }

    @discardableResult
    fileprivate func moveWorkspace(_ workspaceID: UUID, toInsertionIndex insertionIndex: Int) -> Bool {
        guard let coordinator,
              let sourceIndex = coordinator.workspaceStore.workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return false
        }

        var destinationIndex = insertionIndex
        if destinationIndex > sourceIndex {
            destinationIndex -= 1
        }
        destinationIndex = min(max(destinationIndex, 0), coordinator.workspaceStore.workspaces.count - 1)
        guard destinationIndex != sourceIndex else {
            return false
        }
        coordinator.workspaceStore.moveWorkspace(from: sourceIndex, to: destinationIndex)
        updateTabAccessory()
        updateWindowTitles(coordinator: coordinator)
        return true
    }
}

// MARK: - WorkspaceTabBarAccessoryController

@MainActor
private final class WorkspaceTabBarAccessoryController: NSTitlebarAccessoryViewController {
    // MARK: Lifecycle

    init(manager: RockxyWorkspaceWindowManager) {
        tabBarView = WorkspaceTabBarView(manager: manager)
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .bottom
        view = tabBarView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WorkspaceTabBarAccessoryController does not support NSCoder init")
    }

    // MARK: Internal

    func update(coordinator: MainContentCoordinator) {
        tabBarView.update(coordinator: coordinator)
    }

    func beginRename(workspaceID: UUID) {
        tabBarView.beginRename(workspaceID: workspaceID)
    }

    func endEditing(commit: Bool) {
        tabBarView.endEditing(commit: commit)
    }

    // MARK: Private

    private let tabBarView: WorkspaceTabBarView
}

// MARK: - WorkspaceTabBarView

@MainActor
private final class WorkspaceTabBarView: NSView, NSTextFieldDelegate {
    // MARK: Lifecycle

    init(manager: RockxyWorkspaceWindowManager) {
        self.manager = manager
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: Self.barHeight))
        autoresizingMask = [.width]
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WorkspaceTabBarView does not support NSCoder init")
    }

    // MARK: Internal

    override var isFlipped: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.barHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let nextTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = nextTrackingArea
        addTrackingArea(nextTrackingArea)
    }

    override func layout() {
        super.layout()
        stopTabFrameAnimation(snapToTarget: true)
        recalculateFrames()
        if let editingWorkspaceID,
           let field = editField,
           let frame = tabFrames[editingWorkspaceID] {
            field.frame = editorFrame(in: frame)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        recalculateFrames()
        drawBackground()
        drawSeparator()
        drawTabs()
        drawAddButton()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hoverID = workspaceID(at: point)
        let addHovered = addButtonFrame.contains(point)
        if hoverID != hoveredWorkspaceID || addHovered != isAddButtonHovered {
            hoveredWorkspaceID = hoverID
            isAddButtonHovered = addHovered
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredWorkspaceID = nil
        isAddButtonHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if commitEditingIfNeeded(forClickAt: point) {
            return
        }

        if addButtonFrame.contains(point) {
            manager.createWorkspace()
            return
        }

        if let closeID = closeWorkspaceID(at: point) {
            manager.closeWorkspace(closeID)
            return
        }

        guard let workspaceID = workspaceID(at: point) else {
            return
        }
        mouseDownWorkspaceID = workspaceID
        mouseDownPoint = point
        manager.selectWorkspace(workspaceID)
    }

    override func mouseDragged(with event: NSEvent) {
        guard editField == nil,
              let mouseDownWorkspaceID,
              let mouseDownPoint else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        if draggingWorkspaceID == nil,
           distance(from: mouseDownPoint, to: point) >= Self.dragThreshold {
            draggingWorkspaceID = mouseDownWorkspaceID
        }

        guard let draggingWorkspaceID else {
            return
        }

        draggingPoint = point
        let insertionIndex = insertionIndex(at: point)
        dropInsertionIndex = insertionIndex
        if insertionIndex != lastAppliedInsertionIndex {
            lastAppliedInsertionIndex = insertionIndex
            if manager.moveWorkspace(draggingWorkspaceID, toInsertionIndex: insertionIndex) {
                recalculateFrames()
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let draggingWorkspaceID {
            let insertionIndex = dropInsertionIndex ?? insertionIndex(at: point)
            clearDragState()
            manager.moveWorkspace(draggingWorkspaceID, toInsertionIndex: insertionIndex)
            return
        }

        defer {
            mouseDownWorkspaceID = nil
            mouseDownPoint = nil
        }
        guard event.clickCount == 2,
              let workspaceID = workspaceID(at: point),
              workspaceID == mouseDownWorkspaceID else {
            return
        }
        beginRename(workspaceID: workspaceID)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if commitEditingIfNeeded(forClickAt: point) {
            return
        }
        guard let workspaceID = workspaceID(at: point),
              let coordinator else {
            return
        }

        let menu = NSMenu()
        let renameItem = NSMenuItem(
            title: String(localized: "Rename Tab"),
            action: #selector(renameTabFromMenu(_:)),
            keyEquivalent: ""
        )
        renameItem.target = self
        renameItem.representedObject = workspaceID
        menu.addItem(renameItem)

        if coordinator.workspaceStore.workspaces.first(where: { $0.id == workspaceID })?.isClosable == true {
            let closeItem = NSMenuItem(
                title: String(localized: "Close Tab"),
                action: #selector(closeTabFromMenu(_:)),
                keyEquivalent: ""
            )
            closeItem.target = self
            closeItem.representedObject = workspaceID
            menu.addItem(closeItem)
        }

        if coordinator.workspaceStore.canCreateWorkspace {
            menu.addItem(.separator())
            let newItem = NSMenuItem(
                title: String(localized: "New Tab"),
                action: #selector(newTabFromMenu(_:)),
                keyEquivalent: ""
            )
            newItem.target = self
            menu.addItem(newItem)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func update(coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        let previousFrames = currentTabFramesForDrawing()
        recalculateFrames()
        animateTabFrameChanges(from: previousFrames, to: tabFrames)
        needsDisplay = true
    }

    func beginRename(workspaceID: UUID) {
        guard let coordinator,
              let workspace = coordinator.workspaceStore.workspaces.first(where: { $0.id == workspaceID }) else {
            return
        }

        recalculateFrames()
        guard let tabFrame = tabFrames[workspaceID] else {
            return
        }

        endEditing(commit: true)
        editingWorkspaceID = workspaceID
        originalTitle = workspace.title

        let field = WorkspaceInlineTabTextField(frame: editorFrame(in: tabFrame))
        field.stringValue = workspace.title
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.alignment = .center
        field.delegate = self
        field.onCommit = { [weak self] in self?.endEditing(commit: true) }
        field.onCancel = { [weak self] in self?.endEditing(commit: false) }
        editField = field
        addSubview(field)
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
        }
        installEditingMonitor()
        needsDisplay = true
    }

    func endEditing(commit: Bool) {
        guard let editingWorkspaceID,
              let field = editField else {
            return
        }
        removeEditingMonitor()

        let fallbackTitle = originalTitle
        let committedTitle: String
        if commit {
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            committedTitle = trimmed.isEmpty ? fallbackTitle : trimmed
        } else {
            committedTitle = fallbackTitle
        }

        self.editingWorkspaceID = nil
        originalTitle = ""
        editField = nil
        field.removeFromSuperview()
        manager.renameWorkspace(editingWorkspaceID, to: committedTitle)
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        endEditing(commit: true)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            endEditing(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(commit: false)
            return true
        default:
            return false
        }
    }

    // MARK: Private

    private static let barHeight: CGFloat = 36
    private static let leftInset: CGFloat = 74
    private static let rightInset: CGFloat = 12
    private static let minimumTabWidth: CGFloat = 82
    private static let maximumTabWidth: CGFloat = 220
    private static let addButtonSize: CGFloat = 28
    private static let dragThreshold: CGFloat = 4
    private static let reorderAnimationDuration: TimeInterval = 0.16

    private weak var manager: RockxyWorkspaceWindowManager!
    private weak var coordinator: MainContentCoordinator?
    private var trackingArea: NSTrackingArea?
    private var tabFrames: [UUID: NSRect] = [:]
    private var closeFrames: [UUID: NSRect] = [:]
    private var addButtonFrame = NSRect.zero
    private var presentedTabFrames: [UUID: NSRect] = [:]
    private var tabAnimationStartFrames: [UUID: NSRect] = [:]
    private var tabAnimationTargetFrames: [UUID: NSRect] = [:]
    private var tabAnimationStartDate = Date()
    private var tabAnimationTimer: Timer?
    private var hoveredWorkspaceID: UUID?
    private var isAddButtonHovered = false
    private var mouseDownWorkspaceID: UUID?
    private var mouseDownPoint: NSPoint?
    private var draggingWorkspaceID: UUID?
    private var draggingPoint: NSPoint?
    private var dropInsertionIndex: Int?
    private var lastAppliedInsertionIndex: Int?
    private var editingWorkspaceID: UUID?
    private var originalTitle = ""
    private var editField: WorkspaceInlineTabTextField?
    private var editMonitor: Any?

    private func recalculateFrames() {
        guard let coordinator else {
            tabFrames.removeAll()
            closeFrames.removeAll()
            addButtonFrame = .zero
            return
        }

        let workspaces = coordinator.workspaceStore.workspaces
        let addX = max(Self.leftInset, bounds.maxX - Self.rightInset - Self.addButtonSize - 8)
        addButtonFrame = NSRect(
            x: addX,
            y: 4,
            width: Self.addButtonSize,
            height: Self.addButtonSize
        )

        let availableWidth = max(
            Self.minimumTabWidth,
            addButtonFrame.minX - Self.leftInset - 6
        )
        let tabWidth = min(
            Self.maximumTabWidth,
            max(Self.minimumTabWidth, availableWidth / CGFloat(max(workspaces.count, 1)))
        )

        tabFrames.removeAll(keepingCapacity: true)
        closeFrames.removeAll(keepingCapacity: true)

        for (index, workspace) in workspaces.enumerated() {
            let frame = NSRect(
                x: Self.leftInset + CGFloat(index) * tabWidth,
                y: 4,
                width: tabWidth,
                height: Self.barHeight - 8
            )
            tabFrames[workspace.id] = frame
            if workspace.isClosable {
                closeFrames[workspace.id] = NSRect(
                    x: frame.maxX - 26,
                    y: frame.midY - 7,
                    width: 14,
                    height: 14
                )
            }
        }
    }

    private func drawBackground() {
        NSColor.clear.setFill()
        bounds.fill()

        let stripWidth = max(0, addButtonFrame.minX - Self.leftInset - 4)
        guard stripWidth > 0 else {
            return
        }

        let stripRect = NSRect(
            x: Self.leftInset - 8,
            y: 4,
            width: stripWidth + 8,
            height: 28
        )
        let path = NSBezierPath(roundedRect: stripRect, xRadius: 14, yRadius: 14)
        tabBarFillColor.setFill()
        path.fill()
    }

    private func drawSeparator() {
        NSColor.separatorColor.withAlphaComponent(isDarkAppearance ? 0.20 : 0.16).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    private func drawTabs() {
        guard let coordinator else {
            return
        }

        let workspaces = coordinator.workspaceStore.workspaces
        let activeWorkspaceID = coordinator.workspaceStore.activeWorkspaceID
        for workspace in workspaces where workspace.id != activeWorkspaceID {
            drawWorkspaceTab(workspace, activeWorkspaceID: activeWorkspaceID)
        }
        for workspace in workspaces where workspace.id == activeWorkspaceID {
            drawWorkspaceTab(workspace, activeWorkspaceID: activeWorkspaceID)
        }

        if let draggingWorkspaceID,
           let draggingPoint,
           let workspace = workspaces.first(where: { $0.id == draggingWorkspaceID }),
           let sourceFrame = tabFrames[draggingWorkspaceID] {
            drawDragGhost(workspace.title, sourceFrame: sourceFrame, at: draggingPoint)
        }

        if let dropInsertionIndex {
            drawInsertionMarker(at: dropInsertionIndex)
        }
    }

    private func drawWorkspaceTab(_ workspace: WorkspaceState, activeWorkspaceID: UUID) {
        guard let frame = currentFrame(for: workspace.id) else {
            return
        }
        let isActive = workspace.id == activeWorkspaceID
        let isDragging = workspace.id == draggingWorkspaceID
        drawTabBackground(in: frame, isActive: isActive, isHovered: workspace.id == hoveredWorkspaceID)
        if editingWorkspaceID != workspace.id {
            drawTitle(
                workspace.title,
                in: titleFrame(for: frame, workspace: workspace),
                isActive: isActive,
                alpha: isDragging ? 0.28 : 1
            )
        }
        if workspace.isClosable,
           isActive || workspace.id == hoveredWorkspaceID,
           !isDragging {
            let closeFrame = closeFrame(in: frame)
            drawCloseGlyph(in: closeFrame, isActive: isActive, isHovered: workspace.id == hoveredWorkspaceID)
        }
        drawInactiveDividerIfNeeded(after: workspace, frame: frame, isActive: isActive)
    }

    private func drawTabBackground(in frame: NSRect, isActive: Bool, isHovered: Bool) {
        let rect = frame.insetBy(dx: 0.5, dy: 0)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        if isActive {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = NSSize(width: 0, height: -0.5)
            shadow.shadowColor = NSColor.black.withAlphaComponent(isDarkAppearance ? 0.20 : 0.055)
            shadow.set()
            selectedTabFillColor.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            selectedTabStrokeColor.setStroke()
            path.lineWidth = 0.7
            path.stroke()
        } else if isHovered {
            hoverTabFillColor.setFill()
            path.fill()
        }
    }

    private func drawTitle(_ title: String, in frame: NSRect, isActive: Bool, alpha: CGFloat = 1) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isActive ? .medium : .regular),
            .foregroundColor: (isActive ? NSColor.labelColor : NSColor.secondaryLabelColor).withAlphaComponent(alpha),
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: title, attributes: attributes)
        let textHeight = attributed.size().height
        attributed.draw(in: NSRect(
            x: frame.minX,
            y: frame.midY - textHeight / 2,
            width: frame.width,
            height: textHeight + 2
        ))
    }

    private func drawInactiveDividerIfNeeded(after workspace: WorkspaceState, frame: NSRect, isActive: Bool) {
        guard let coordinator,
              !isActive,
              workspace.id != hoveredWorkspaceID,
              workspace.id != draggingWorkspaceID,
              let index = coordinator.workspaceStore.workspaces.firstIndex(where: { $0.id == workspace.id }),
              index < coordinator.workspaceStore.workspaces.count - 1 else {
            return
        }

        let nextWorkspace = coordinator.workspaceStore.workspaces[index + 1]
        guard nextWorkspace.id != coordinator.workspaceStore.activeWorkspaceID,
              nextWorkspace.id != hoveredWorkspaceID,
              nextWorkspace.id != draggingWorkspaceID else {
            return
        }

        dividerColor.setFill()
        NSRect(x: frame.maxX - 0.5, y: frame.minY + 6, width: 1, height: frame.height - 12).fill()
    }

    private func drawCloseGlyph(in frame: NSRect, isActive: Bool, isHovered: Bool) {
        if isHovered {
            let hoverPath = NSBezierPath(ovalIn: frame.insetBy(dx: -1, dy: -1))
            NSColor.labelColor.withAlphaComponent(isDarkAppearance ? 0.16 : 0.08).setFill()
            hoverPath.fill()
        }

        let color = isActive ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.35
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: frame.minX + 4, y: frame.minY + 4))
        path.line(to: NSPoint(x: frame.maxX - 4, y: frame.maxY - 4))
        path.move(to: NSPoint(x: frame.maxX - 4, y: frame.minY + 4))
        path.line(to: NSPoint(x: frame.minX + 4, y: frame.maxY - 4))
        path.stroke()
    }

    private func drawAddButton() {
        let canCreate = coordinator?.workspaceStore.canCreateWorkspace == true
        let path = NSBezierPath(ovalIn: addButtonFrame)
        let fillAlpha: CGFloat = {
            if !canCreate {
                return isDarkAppearance ? 0.08 : 0.04
            }
            return isAddButtonHovered ? (isDarkAppearance ? 0.22 : 0.12) : (isDarkAppearance ? 0.14 : 0.075)
        }()
        NSColor.labelColor.withAlphaComponent(fillAlpha).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(canCreate ? (isDarkAppearance ? 0.22 : 0.12) : 0.10).setStroke()
        path.lineWidth = 0.7
        path.stroke()

        (canCreate ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setStroke()
        let plus = NSBezierPath()
        plus.lineWidth = 1.55
        plus.lineCapStyle = .round
        plus.move(to: NSPoint(x: addButtonFrame.midX - 5, y: addButtonFrame.midY))
        plus.line(to: NSPoint(x: addButtonFrame.midX + 5, y: addButtonFrame.midY))
        plus.move(to: NSPoint(x: addButtonFrame.midX, y: addButtonFrame.midY - 5))
        plus.line(to: NSPoint(x: addButtonFrame.midX, y: addButtonFrame.midY + 5))
        plus.stroke()
    }

    private func drawDragGhost(_ title: String, sourceFrame: NSRect, at point: NSPoint) {
        let width = sourceFrame.width
        let rect = NSRect(
            x: min(max(Self.leftInset, point.x - width / 2), bounds.maxX - Self.rightInset - Self.addButtonSize - width - 10),
            y: sourceFrame.minY,
            width: width,
            height: sourceFrame.height
        )
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 0), xRadius: 14, yRadius: 14)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(isDarkAppearance ? 0.26 : 0.10)
        shadow.set()
        selectedTabFillColor.withAlphaComponent(0.95).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        selectedTabStrokeColor.setStroke()
        path.lineWidth = 0.7
        path.stroke()
        drawTitle(title, in: rect.insetBy(dx: 12, dy: 0), isActive: true)
    }

    private func drawInsertionMarker(at insertionIndex: Int) {
        guard let markerX = insertionMarkerX(for: insertionIndex) else {
            return
        }
        let markerRect = NSRect(x: markerX - 1, y: 8, width: 2, height: Self.barHeight - 16)
        let path = NSBezierPath(roundedRect: markerRect, xRadius: 1, yRadius: 1)
        NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
        path.fill()
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var tabBarFillColor: NSColor {
        if isDarkAppearance {
            return NSColor.windowBackgroundColor.withAlphaComponent(0.24)
        }
        return NSColor.windowBackgroundColor.withAlphaComponent(0.58)
    }

    private var selectedTabFillColor: NSColor {
        if isDarkAppearance {
            return NSColor.controlBackgroundColor.withAlphaComponent(0.84)
        }
        return NSColor.textBackgroundColor.withAlphaComponent(0.92)
    }

    private var selectedTabStrokeColor: NSColor {
        if isDarkAppearance {
            return NSColor.white.withAlphaComponent(0.14)
        }
        return NSColor.white.withAlphaComponent(0.82)
    }

    private var hoverTabFillColor: NSColor {
        NSColor.labelColor.withAlphaComponent(isDarkAppearance ? 0.08 : 0.045)
    }

    private var dividerColor: NSColor {
        NSColor.separatorColor.withAlphaComponent(isDarkAppearance ? 0.20 : 0.22)
    }

    private func titleFrame(for frame: NSRect, workspace: WorkspaceState) -> NSRect {
        let leftPadding: CGFloat = 12
        let rightPadding: CGFloat = workspace.isClosable ? 30 : 12
        return NSRect(
            x: frame.minX + leftPadding,
            y: frame.minY,
            width: max(1, frame.width - leftPadding - rightPadding),
            height: frame.height
        )
    }

    private func editorFrame(in tabFrame: NSRect) -> NSRect {
        let leftPadding: CGFloat = 12
        let hasCloseButton = editingWorkspaceID.map { closeFrames[$0] != nil } ?? false
        let rightPadding: CGFloat = hasCloseButton ? 30 : 12
        return NSRect(
            x: tabFrame.minX + leftPadding,
            y: tabFrame.minY,
            width: max(1, tabFrame.width - leftPadding - rightPadding),
            height: tabFrame.height
        )
        .insetBy(dx: 0, dy: 4)
    }

    private func workspaceID(at point: NSPoint) -> UUID? {
        tabFrames.first { $0.value.contains(point) }?.key
    }

    private func closeWorkspaceID(at point: NSPoint) -> UUID? {
        closeFrames.first { $0.value.contains(point) }?.key
    }

    private func closeFrame(in tabFrame: NSRect) -> NSRect {
        NSRect(
            x: tabFrame.maxX - 26,
            y: tabFrame.midY - 7,
            width: 14,
            height: 14
        )
    }

    private func insertionIndex(at point: NSPoint) -> Int {
        guard let coordinator else {
            return 0
        }

        for (index, workspace) in coordinator.workspaceStore.workspaces.enumerated() {
            guard let frame = tabFrames[workspace.id] else {
                continue
            }
            if point.x < frame.midX {
                return index
            }
        }
        return coordinator.workspaceStore.workspaces.count
    }

    private func insertionMarkerX(for insertionIndex: Int) -> CGFloat? {
        guard let coordinator,
              !coordinator.workspaceStore.workspaces.isEmpty else {
            return nil
        }

        if insertionIndex <= 0,
           let first = coordinator.workspaceStore.workspaces.first,
           let frame = tabFrames[first.id] {
            return frame.minX + 2
        }

        if insertionIndex >= coordinator.workspaceStore.workspaces.count,
           let last = coordinator.workspaceStore.workspaces.last,
           let frame = tabFrames[last.id] {
            return frame.maxX - 2
        }

        let workspace = coordinator.workspaceStore.workspaces[insertionIndex]
        return tabFrames[workspace.id]?.minX
    }

    private func clearDragState() {
        draggingWorkspaceID = nil
        draggingPoint = nil
        dropInsertionIndex = nil
        lastAppliedInsertionIndex = nil
        mouseDownWorkspaceID = nil
        mouseDownPoint = nil
        needsDisplay = true
    }

    private func distance(from lhs: NSPoint, to rhs: NSPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return sqrt(dx * dx + dy * dy)
    }

    private func currentFrame(for workspaceID: UUID) -> NSRect? {
        presentedTabFrames[workspaceID] ?? tabFrames[workspaceID]
    }

    private func currentTabFramesForDrawing() -> [UUID: NSRect] {
        presentedTabFrames.isEmpty ? tabFrames : presentedTabFrames
    }

    private func animateTabFrameChanges(from previousFrames: [UUID: NSRect], to targetFrames: [UUID: NSRect]) {
        guard !previousFrames.isEmpty,
              !targetFrames.isEmpty else {
            stopTabFrameAnimation(snapToTarget: true)
            return
        }

        let commonIDs = Set(previousFrames.keys).intersection(targetFrames.keys)
        let shouldAnimate = commonIDs.contains { workspaceID in
            guard let previous = previousFrames[workspaceID],
                  let target = targetFrames[workspaceID] else {
                return false
            }
            return abs(previous.minX - target.minX) > 0.5 || abs(previous.width - target.width) > 0.5
        }

        guard shouldAnimate else {
            return
        }

        tabAnimationTimer?.invalidate()
        tabAnimationStartDate = Date()
        tabAnimationTargetFrames = targetFrames
        tabAnimationStartFrames = Dictionary(uniqueKeysWithValues: targetFrames.map { workspaceID, targetFrame in
            (workspaceID, previousFrames[workspaceID] ?? targetFrame)
        })
        presentedTabFrames = tabAnimationStartFrames

        let timer = Timer(
            timeInterval: 1 / 60,
            target: self,
            selector: #selector(advanceTabFrameAnimation(_:)),
            userInfo: nil,
            repeats: true
        )
        tabAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func advanceTabFrameAnimation(_ timer: Timer) {
        let elapsed = Date().timeIntervalSince(tabAnimationStartDate)
        let progress = min(1, elapsed / Self.reorderAnimationDuration)
        let easedProgress = 1 - pow(1 - progress, 3)

        presentedTabFrames = Dictionary(uniqueKeysWithValues: tabAnimationTargetFrames.map { workspaceID, targetFrame in
            let startFrame = tabAnimationStartFrames[workspaceID] ?? targetFrame
            return (workspaceID, interpolate(from: startFrame, to: targetFrame, progress: easedProgress))
        })
        needsDisplay = true

        if progress >= 1 {
            stopTabFrameAnimation(snapToTarget: true)
        }
    }

    private func stopTabFrameAnimation(snapToTarget: Bool) {
        tabAnimationTimer?.invalidate()
        tabAnimationTimer = nil
        tabAnimationStartFrames.removeAll(keepingCapacity: true)
        tabAnimationTargetFrames.removeAll(keepingCapacity: true)
        if snapToTarget {
            presentedTabFrames.removeAll(keepingCapacity: true)
        }
    }

    private func interpolate(from startFrame: NSRect, to targetFrame: NSRect, progress: CGFloat) -> NSRect {
        NSRect(
            x: startFrame.minX + (targetFrame.minX - startFrame.minX) * progress,
            y: startFrame.minY + (targetFrame.minY - startFrame.minY) * progress,
            width: startFrame.width + (targetFrame.width - startFrame.width) * progress,
            height: startFrame.height + (targetFrame.height - startFrame.height) * progress
        )
    }

    private func commitEditingIfNeeded(forClickAt point: NSPoint) -> Bool {
        guard let field = editField else {
            return false
        }
        if field.frame.contains(point) {
            return false
        }
        endEditing(commit: true)
        return true
    }

    private func installEditingMonitor() {
        removeEditingMonitor()
        editMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] nsEvent in
            guard let self else {
                return nsEvent
            }
            nonisolated(unsafe) let event = nsEvent
            nonisolated(unsafe) var handledEvent: NSEvent?
            MainActor.assumeIsolated {
                handledEvent = self.handleEditingMonitorEvent(event)
            }
            return handledEvent
        }
    }

    private func removeEditingMonitor() {
        if let editMonitor {
            NSEvent.removeMonitor(editMonitor)
            self.editMonitor = nil
        }
    }

    private func handleEditingMonitorEvent(_ event: NSEvent) -> NSEvent? {
        guard let field = editField else {
            return event
        }
        if event.window === window {
            let point = convert(event.locationInWindow, from: nil)
            if field.frame.contains(point) {
                return event
            }
        }
        endEditing(commit: true)
        return event
    }

    @objc private func renameTabFromMenu(_ sender: NSMenuItem) {
        guard let workspaceID = sender.representedObject as? UUID else {
            return
        }
        beginRename(workspaceID: workspaceID)
    }

    @objc private func closeTabFromMenu(_ sender: NSMenuItem) {
        guard let workspaceID = sender.representedObject as? UUID else {
            return
        }
        manager.closeWorkspace(workspaceID)
    }

    @objc private func newTabFromMenu(_ sender: NSMenuItem) {
        manager.createWorkspace()
    }
}

// MARK: - WorkspaceInlineTabTextField

@MainActor
private final class WorkspaceInlineTabTextField: NSTextField {
    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = true
        isBezeled = true
        bezelStyle = .roundedBezel
        drawsBackground = true
        backgroundColor = .controlBackgroundColor
        textColor = .labelColor
        focusRingType = .none
        lineBreakMode = .byTruncatingMiddle
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WorkspaceInlineTabTextField does not support NSCoder init")
    }

    // MARK: Internal

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
