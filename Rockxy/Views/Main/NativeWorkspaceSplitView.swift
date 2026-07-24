import AppKit
import SwiftUI

// MARK: - NativeWorkspaceSplitView

/// Hosts the source list, workspace, and Context Dock in one native root split.
///
/// Keeping both utility columns as semantic `NSSplitViewItem` instances lets their
/// materials and dividers participate in the full-size unified titlebar exactly like
/// native Mac source lists and inspectors.
struct NativeWorkspaceSplitView<Sidebar: View, Workspace: View, Inspector: View>:
    NSViewControllerRepresentable
{
    // MARK: Lifecycle

    init(
        isSidebarPresented: Binding<Bool>,
        isInspectorPresented: Binding<Bool>,
        autosaveName: String,
        sidebarMinimumWidth: CGFloat,
        sidebarIdealWidth: CGFloat,
        sidebarMaximumWidth: CGFloat,
        workspaceMinimumWidth: CGFloat,
        inspectorMinimumWidth: CGFloat,
        inspectorIdealWidth: CGFloat,
        inspectorMaximumWidth: CGFloat,
        toolbarConfiguration: NativeWorkspaceToolbarConfiguration? = nil,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder workspace: @escaping () -> Workspace,
        @ViewBuilder inspector: @escaping () -> Inspector
    ) {
        _isSidebarPresented = isSidebarPresented
        _isInspectorPresented = isInspectorPresented
        self.autosaveName = autosaveName
        self.sidebarMinimumWidth = sidebarMinimumWidth
        self.sidebarIdealWidth = sidebarIdealWidth
        self.sidebarMaximumWidth = sidebarMaximumWidth
        self.workspaceMinimumWidth = workspaceMinimumWidth
        self.inspectorMinimumWidth = inspectorMinimumWidth
        self.inspectorIdealWidth = inspectorIdealWidth
        self.inspectorMaximumWidth = inspectorMaximumWidth
        self.toolbarConfiguration = toolbarConfiguration
        self.sidebar = sidebar
        self.workspace = workspace
        self.inspector = inspector
    }

    // MARK: Internal

    @Binding var isSidebarPresented: Bool
    @Binding var isInspectorPresented: Bool

    let autosaveName: String
    let sidebarMinimumWidth: CGFloat
    let sidebarIdealWidth: CGFloat
    let sidebarMaximumWidth: CGFloat
    let workspaceMinimumWidth: CGFloat
    let inspectorMinimumWidth: CGFloat
    let inspectorIdealWidth: CGFloat
    let inspectorMaximumWidth: CGFloat
    let toolbarConfiguration: NativeWorkspaceToolbarConfiguration?
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let workspace: () -> Workspace
    @ViewBuilder let inspector: () -> Inspector

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSViewController(context: Context) -> NativeWorkspaceSplitViewController {
        let sidebarController = hostingController(content: sidebar)
        let workspaceController = hostingController(content: workspace)
        let inspectorController = hostingController(content: inspector)

        context.coordinator.recordInitialPresentation(
            sidebar: isSidebarPresented,
            inspector: isInspectorPresented
        )

        let controller = NativeWorkspaceSplitViewController()
        controller.toolbarConfiguration = toolbarConfiguration
        controller.configure(
            sidebarController: sidebarController,
            workspaceController: workspaceController,
            inspectorController: inspectorController,
            isSidebarPresented: isSidebarPresented,
            isInspectorPresented: isInspectorPresented,
            layout: NativeWorkspaceSplitLayout(
                autosaveName: autosaveName,
                sidebarMinimumWidth: sidebarMinimumWidth,
                sidebarIdealWidth: sidebarIdealWidth,
                sidebarMaximumWidth: sidebarMaximumWidth,
                workspaceMinimumWidth: workspaceMinimumWidth,
                inspectorMinimumWidth: inspectorMinimumWidth,
                inspectorIdealWidth: inspectorIdealWidth,
                inspectorMaximumWidth: inspectorMaximumWidth
            )
        )
        updateVisibilityCallbacks(on: controller)
        return controller
    }

    func updateNSViewController(
        _ controller: NativeWorkspaceSplitViewController,
        context: Context
    ) {
        updateVisibilityCallbacks(on: controller)
        if context.coordinator.shouldApplySidebarPresentation(isSidebarPresented) {
            controller.setSidebarPresented(isSidebarPresented, animated: true)
        }
        if context.coordinator.shouldApplyInspectorPresentation(isInspectorPresented) {
            controller.setInspectorPresented(isInspectorPresented, animated: true)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController: NativeWorkspaceSplitViewController,
        context: Context
    ) -> CGSize? {
        let naturalWidth = sidebarIdealWidth + workspaceMinimumWidth + inspectorIdealWidth
        let resolved = proposal.replacingUnspecifiedDimensions(
            by: CGSize(width: naturalWidth, height: MainWindowLayoutMetrics.defaultHeight)
        )
        guard resolved.width.isFinite, resolved.height.isFinite else {
            return nil
        }
        return resolved
    }

    // MARK: Private

    private func hostingController<Content: View>(
        content: @escaping () -> Content
    ) -> NSHostingController<NativeWorkspaceDeferredContent<Content>> {
        let controller = NSHostingController(
            rootView: NativeWorkspaceDeferredContent(content: content)
        )
        controller.sizingOptions = []
        return controller
    }

    private func updateVisibilityCallbacks(on controller: NativeWorkspaceSplitViewController) {
        let sidebarPresentation = $isSidebarPresented
        controller.onSidebarVisibilityChanged = { isVisible in
            guard sidebarPresentation.wrappedValue != isVisible else {
                return
            }
            sidebarPresentation.wrappedValue = isVisible
        }

        let inspectorPresentation = $isInspectorPresented
        controller.onInspectorVisibilityChanged = { isVisible in
            guard inspectorPresentation.wrappedValue != isVisible else {
                return
            }
            inspectorPresentation.wrappedValue = isVisible
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        func recordInitialPresentation(sidebar: Bool, inspector: Bool) {
            lastAppliedSidebarPresentation = sidebar
            lastAppliedInspectorPresentation = inspector
        }

        func shouldApplySidebarPresentation(_ isPresented: Bool) -> Bool {
            guard lastAppliedSidebarPresentation != isPresented else {
                return false
            }
            lastAppliedSidebarPresentation = isPresented
            return true
        }

        func shouldApplyInspectorPresentation(_ isPresented: Bool) -> Bool {
            guard lastAppliedInspectorPresentation != isPresented else {
                return false
            }
            lastAppliedInspectorPresentation = isPresented
            return true
        }

        private var lastAppliedSidebarPresentation: Bool?
        private var lastAppliedInspectorPresentation: Bool?
    }
}

// MARK: - NativeWorkspaceDeferredContent

struct NativeWorkspaceDeferredContent<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
    }
}

// MARK: - NativeWorkspaceSplitLayout

struct NativeWorkspaceSplitLayout {
    let autosaveName: String
    let sidebarMinimumWidth: CGFloat
    let sidebarIdealWidth: CGFloat
    let sidebarMaximumWidth: CGFloat
    let workspaceMinimumWidth: CGFloat
    let inspectorMinimumWidth: CGFloat
    let inspectorIdealWidth: CGFloat
    let inspectorMaximumWidth: CGFloat
}

// MARK: - NativeWorkspaceSplitViewController

@MainActor
final class NativeWorkspaceSplitViewController: NSSplitViewController {
    // MARK: Internal

    var onSidebarVisibilityChanged: ((Bool) -> Void)?
    var onInspectorVisibilityChanged: ((Bool) -> Void)?

    var isSidebarPresented: Bool {
        sidebarItem.map { !$0.isCollapsed } ?? false
    }

    var isInspectorPresented: Bool {
        inspectorItem.map { !$0.isCollapsed } ?? false
    }

    func configure(
        sidebarController: NSViewController,
        workspaceController: NSViewController,
        inspectorController: NSViewController,
        isSidebarPresented: Bool,
        isInspectorPresented: Bool,
        layout: NativeWorkspaceSplitLayout
    ) {
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = layout.sidebarMinimumWidth
        sidebarItem.maximumThickness = layout.sidebarMaximumWidth
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .useConstraints
        sidebarItem.isSpringLoaded = true
        sidebarItem.holdingPriority = .defaultHigh

        let workspaceItem = NSSplitViewItem(viewController: workspaceController)
        workspaceItem.minimumThickness = layout.workspaceMinimumWidth
        workspaceItem.canCollapse = false
        workspaceItem.holdingPriority = .defaultLow

        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorController)
        inspectorItem.minimumThickness = layout.inspectorMinimumWidth
        inspectorItem.maximumThickness = layout.inspectorMaximumWidth
        inspectorItem.canCollapse = true
        inspectorItem.collapseBehavior = .useConstraints
        inspectorItem.isSpringLoaded = true
        inspectorItem.holdingPriority = .defaultHigh

        addSplitViewItem(sidebarItem)
        addSplitViewItem(workspaceItem)
        addSplitViewItem(inspectorItem)

        let autosave = NSSplitView.AutosaveName(layout.autosaveName)
        hasAutosavedFrames = UserDefaults.standard.object(
            forKey: "NSSplitView Subview Frames \(autosave)"
        ) != nil
        splitView.autosaveName = autosave

        self.sidebarItem = sidebarItem
        self.inspectorItem = inspectorItem
        self.sidebarIdealWidth = layout.sidebarIdealWidth
        self.inspectorIdealWidth = layout.inspectorIdealWidth
        requestedSidebarVisibility = isSidebarPresented
        requestedInspectorVisibility = isInspectorPresented
        pendingInitialSidebarVisibility = isSidebarPresented
        pendingInitialInspectorVisibility = isInspectorPresented
        observeCollapseState(of: sidebarItem, isSidebar: true)
        observeCollapseState(of: inspectorItem, isSidebar: false)
        setSidebarPresented(isSidebarPresented, animated: false)
        setInspectorPresented(isInspectorPresented, animated: false)
    }

    func setSidebarPresented(_ isPresented: Bool, animated: Bool) {
        requestedSidebarVisibility = isPresented
        set(item: sidebarItem, presented: isPresented, animated: animated)
    }

    func setInspectorPresented(_ isPresented: Bool, animated: Bool) {
        requestedInspectorVisibility = isPresented
        set(item: inspectorItem, presented: isPresented, animated: animated)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        installWindowChromeIfNeeded()
        guard !didApplyInitialLayout else {
            return
        }
        didApplyInitialLayout = true

        if !hasAutosavedFrames {
            if pendingInitialSidebarVisibility == true {
                splitView.setPosition(sidebarIdealWidth, ofDividerAt: 0)
            }
            if pendingInitialInspectorVisibility == true,
               splitView.bounds.width > sidebarIdealWidth + inspectorIdealWidth
            {
                splitView.setPosition(
                    splitView.bounds.width - inspectorIdealWidth,
                    ofDividerAt: 1
                )
            }
        }

        if let pendingInitialSidebarVisibility {
            self.pendingInitialSidebarVisibility = nil
            setSidebarPresented(pendingInitialSidebarVisibility, animated: false)
        }
        if let pendingInitialInspectorVisibility {
            self.pendingInitialInspectorVisibility = nil
            setInspectorPresented(pendingInitialInspectorVisibility, animated: false)
        }
        isApplyingInitialState = false
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installWindowChromeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.installWindowChromeIfNeeded()
        }
    }

    // MARK: Private

    private func installWindowChromeIfNeeded() {
        guard let window = view.window else {
            return
        }
        NativeWorkspaceWindowChrome.configure(
            window,
            workspaceSplitController: self,
            toolbarConfiguration: toolbarConfiguration
        )
    }

    private func set(item: NSSplitViewItem?, presented: Bool, animated: Bool) {
        guard let item, item.isCollapsed == presented else {
            return
        }

        if animated, view.window != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                item.animator().isCollapsed = !presented
            }
        } else {
            item.isCollapsed = !presented
        }
    }

    private func observeCollapseState(of item: NSSplitViewItem, isSidebar: Bool) {
        let observation = item.observe(\.isCollapsed, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.splitItemVisibilityDidChange(isSidebar: isSidebar)
            }
        }
        collapseObservations.append(observation)
    }

    private func splitItemVisibilityDidChange(isSidebar: Bool) {
        guard !isApplyingInitialState else {
            return
        }

        if isSidebar {
            let isVisible = isSidebarPresented
            guard isVisible != requestedSidebarVisibility else {
                return
            }
            requestedSidebarVisibility = isVisible
            onSidebarVisibilityChanged?(isVisible)
        } else {
            let isVisible = isInspectorPresented
            guard isVisible != requestedInspectorVisibility else {
                return
            }
            requestedInspectorVisibility = isVisible
            onInspectorVisibilityChanged?(isVisible)
        }
    }

    private weak var sidebarItem: NSSplitViewItem?
    private weak var inspectorItem: NSSplitViewItem?
    var toolbarConfiguration: NativeWorkspaceToolbarConfiguration?
    private var collapseObservations: [NSKeyValueObservation] = []
    private var sidebarIdealWidth: CGFloat = 250
    private var inspectorIdealWidth: CGFloat = 380
    private var requestedSidebarVisibility = true
    private var requestedInspectorVisibility = false
    private var pendingInitialSidebarVisibility: Bool?
    private var pendingInitialInspectorVisibility: Bool?
    private var hasAutosavedFrames = false
    private var didApplyInitialLayout = false
    private var isApplyingInitialState = true
}
