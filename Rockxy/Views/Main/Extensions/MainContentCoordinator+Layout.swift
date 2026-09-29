import SwiftUI

// Extends `MainContentCoordinator` with layout behavior for the main workspace.

// MARK: - MainContentCoordinator + Layout

/// Coordinator extension for the horizontal inspector and independent Context Dock.
extension MainContentCoordinator {
    // MARK: - Inspector Layout

    func toggleInspectorRight() {
        setContextDockVisible(!isContextDockVisible)
    }

    /// Applies Context Dock visibility from either toolbar commands or the native split item.
    func setContextDockVisible(_ isVisible: Bool) {
        guard isContextDockVisible != isVisible else {
            return
        }
        withAnimation(.smooth(duration: 0.18)) {
            isContextDockVisible = isVisible
            workspaceStore.rememberContextDockVisibility(isVisible)
        }
    }

    /// Content the bottom payload inspector can present for the current selection.
    var bottomInspectorContent: BottomInspectorContent {
        bottomInspectorContent(for: activeWorkspace)
    }

    func bottomInspectorContent(for workspace: WorkspaceState) -> BottomInspectorContent {
        BottomInspectorPresentation.content(
            selectedCount: workspace.selectedTransactionIDs.count,
            hasSingleSelection: workspace.selectedTransaction != nil
        )
    }

    /// Bottom-inspector visibility for one traffic pane, which may not have focus.
    func isBottomInspectorEffectivelyPresented(for workspace: WorkspaceState) -> Bool {
        BottomInspectorPresentation.isPresented(
            layout: workspace.inspectorLayout,
            content: bottomInspectorContent(for: workspace)
        )
    }

    /// Whether the current selection has something the bottom payload inspector can present.
    /// Drives control enablement and, crucially, distinguishes a collapse caused purely by
    /// losing the selection (must not persist a hidden preference) from a manual/native
    /// collapse the user actually intends to keep.
    var hasPayloadInspectorSelection: Bool {
        bottomInspectorContent != .none
    }

    /// Effective (derived) bottom-inspector visibility. Collapses when there is nothing to
    /// inspect so the request table reclaims the space, without touching the stored preference.
    var isBottomInspectorEffectivelyPresented: Bool {
        BottomInspectorPresentation.isPresented(layout: inspectorLayout, content: bottomInspectorContent)
    }

    /// Whether the bottom-inspector show/hide controls should be enabled. With nothing to
    /// inspect, toggling only flips a hidden preference with no visible result.
    var canToggleBottomInspector: Bool {
        BottomInspectorPresentation.allowsToggle(content: bottomInspectorContent)
    }

    func toggleInspectorBottom() {
        guard canToggleBottomInspector else {
            return
        }
        setBottomInspectorVisible(inspectorLayout != .bottom)
    }

    /// Applies bottom inspector visibility from toolbar commands or the native split item.
    func setBottomInspectorVisible(_ isVisible: Bool) {
        let layout: InspectorLayout = isVisible ? .bottom : .hidden
        guard inspectorLayout != layout || activeWorkspace.allowsAutomaticInspectorReveal else {
            return
        }
        withAnimation(.smooth(duration: 0.18)) {
            inspectorLayout = layout
            activeWorkspace.allowsAutomaticInspectorReveal = false
            workspaceStore.rememberBottomInspectorVisibility(isVisible)
        }
    }

    func hideInspector() {
        setBottomInspectorVisible(false)
    }

    func revealInspectorForSelectionIfNeeded() {
        guard activeWorkspace.allowsAutomaticInspectorReveal,
              inspectorLayout == .hidden else
        {
            return
        }
        withAnimation(.smooth(duration: 0.18)) {
            inspectorLayout = .bottom
        }
    }
}
