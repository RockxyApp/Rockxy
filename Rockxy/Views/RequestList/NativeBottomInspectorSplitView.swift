import AppKit
import SwiftUI

// MARK: - NativeBottomInspectorSplitView

/// Hosts the request table and payload inspector in a native horizontal split-view controller.
///
/// The controller remains mounted while its bottom item collapses, preserving table identity,
/// selection, scroll position, and transaction-scoped inspector state across toolbar toggles.
struct NativeBottomInspectorSplitView<Primary: View, Inspector: View>: NSViewControllerRepresentable {
    // MARK: Lifecycle

    init(
        isInspectorPresented: Binding<Bool>,
        autosaveName: String,
        primaryMinimumHeight: CGFloat,
        inspectorMinimumHeight: CGFloat,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder inspector: @escaping () -> Inspector
    ) {
        _isInspectorPresented = isInspectorPresented
        self.autosaveName = autosaveName
        self.primaryMinimumHeight = primaryMinimumHeight
        self.inspectorMinimumHeight = inspectorMinimumHeight
        self.primary = primary
        self.inspector = inspector
    }

    // MARK: Internal

    @Binding var isInspectorPresented: Bool

    let autosaveName: String
    let primaryMinimumHeight: CGFloat
    let inspectorMinimumHeight: CGFloat
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let inspector: () -> Inspector

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSViewController(context: Context) -> NativeBottomInspectorSplitViewController {
        let primaryController = NSHostingController(rootView: primary())
        let inspectorController = NSHostingController(rootView: inspector())

        // Prevent SwiftUI ideal sizes from propagating through NSSplitViewController and
        // resizing the containing workspace window.
        primaryController.sizingOptions = []
        inspectorController.sizingOptions = []

        context.coordinator.primaryController = primaryController
        context.coordinator.inspectorController = inspectorController

        let controller = NativeBottomInspectorSplitViewController()
        controller.configure(
            primaryController: primaryController,
            inspectorController: inspectorController,
            isInspectorPresented: isInspectorPresented,
            autosaveName: autosaveName,
            primaryMinimumHeight: primaryMinimumHeight,
            inspectorMinimumHeight: inspectorMinimumHeight
        )
        updateVisibilityCallback(on: controller)
        return controller
    }

    func updateNSViewController(
        _ controller: NativeBottomInspectorSplitViewController,
        context: Context
    ) {
        context.coordinator.primaryController?.rootView = primary()
        context.coordinator.inspectorController?.rootView = inspector()
        updateVisibilityCallback(on: controller)
        controller.setInspectorPresented(isInspectorPresented, animated: true)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController: NativeBottomInspectorSplitViewController,
        context: Context
    ) -> CGSize? {
        NativeBottomInspectorSplitSizing.resolve(
            proposal,
            naturalHeight: primaryMinimumHeight + inspectorMinimumHeight
        )
    }

    // MARK: Private

    private func updateVisibilityCallback(on controller: NativeBottomInspectorSplitViewController) {
        let presentation = $isInspectorPresented
        controller.onInspectorVisibilityChanged = { isVisible in
            guard presentation.wrappedValue != isVisible else { return }
            presentation.wrappedValue = isVisible
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        var primaryController: NSHostingController<Primary>?
        var inspectorController: NSHostingController<Inspector>?
    }
}

// MARK: - NativeBottomInspectorSplitSizing

enum NativeBottomInspectorSplitSizing {
    static func resolve(_ proposal: ProposedViewSize, naturalHeight: CGFloat) -> CGSize? {
        let resolved = proposal.replacingUnspecifiedDimensions(
            by: CGSize(width: 800, height: naturalHeight)
        )
        guard resolved.width.isFinite, resolved.height.isFinite else { return nil }
        return resolved
    }
}

// MARK: - NativeBottomInspectorSplitViewController

@MainActor
final class NativeBottomInspectorSplitViewController: NSSplitViewController {
    // MARK: Internal

    var onInspectorVisibilityChanged: ((Bool) -> Void)?

    var isInspectorPresented: Bool {
        inspectorItem.map { !$0.isCollapsed } ?? false
    }

    func configure(
        primaryController: NSViewController,
        inspectorController: NSViewController,
        isInspectorPresented: Bool,
        autosaveName: String,
        primaryMinimumHeight: CGFloat,
        inspectorMinimumHeight: CGFloat
    ) {
        splitView.isVertical = false
        splitView.dividerStyle = .thin

        let primaryItem = NSSplitViewItem(viewController: primaryController)
        primaryItem.minimumThickness = primaryMinimumHeight
        primaryItem.canCollapse = false
        primaryItem.holdingPriority = .defaultLow

        let inspectorItem = NSSplitViewItem(viewController: inspectorController)
        inspectorItem.minimumThickness = inspectorMinimumHeight
        inspectorItem.canCollapse = true
        inspectorItem.collapseBehavior = .useConstraints
        inspectorItem.isSpringLoaded = true
        inspectorItem.holdingPriority = .defaultHigh

        addSplitViewItem(primaryItem)
        addSplitViewItem(inspectorItem)

        // AppKit restores divider position only after both items belong to the split controller.
        splitView.autosaveName = NSSplitView.AutosaveName(autosaveName)
        self.inspectorItem = inspectorItem
        requestedInspectorVisibility = isInspectorPresented
        pendingInitialVisibility = isInspectorPresented
        observeCollapseState(of: inspectorItem)
        setInspectorPresented(isInspectorPresented, animated: false)
    }

    func setInspectorPresented(_ isPresented: Bool, animated: Bool) {
        requestedInspectorVisibility = isPresented
        guard let inspectorItem, inspectorItem.isCollapsed == isPresented else { return }

        if animated, view.window != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                inspectorItem.animator().isCollapsed = !isPresented
            }
        } else {
            inspectorItem.isCollapsed = !isPresented
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let pendingInitialVisibility else { return }
        self.pendingInitialVisibility = nil
        setInspectorPresented(pendingInitialVisibility, animated: false)
        isApplyingInitialState = false
    }

    // MARK: Private

    private func observeCollapseState(of item: NSSplitViewItem) {
        collapseObservation = item.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
            let isVisible = !item.isCollapsed
            DispatchQueue.main.async { [weak self] in
                self?.inspectorVisibilityDidChange(isVisible)
            }
        }
    }

    private func inspectorVisibilityDidChange(_ isVisible: Bool) {
        guard !isApplyingInitialState else { return }
        guard isVisible != requestedInspectorVisibility else { return }
        requestedInspectorVisibility = isVisible
        onInspectorVisibilityChanged?(isVisible)
    }

    private weak var inspectorItem: NSSplitViewItem?
    private var collapseObservation: NSKeyValueObservation?
    private var requestedInspectorVisibility = false
    private var pendingInitialVisibility: Bool?
    private var isApplyingInitialState = true
}
