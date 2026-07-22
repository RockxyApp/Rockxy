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
        guard isContextDockVisible != isVisible else { return }
        withAnimation(.smooth(duration: 0.18)) {
            isContextDockVisible = isVisible
            workspaceStore.rememberContextDockVisibility(isVisible)
        }
    }

    func toggleInspectorBottom() {
        withAnimation(.smooth(duration: 0.18)) {
            let isVisible = inspectorLayout != .bottom
            inspectorLayout = isVisible ? .bottom : .hidden
            activeWorkspace.allowsAutomaticInspectorReveal = false
            workspaceStore.rememberBottomInspectorVisibility(isVisible)
        }
    }

    func hideInspector() {
        withAnimation(.smooth(duration: 0.18)) {
            inspectorLayout = .hidden
            activeWorkspace.allowsAutomaticInspectorReveal = false
            workspaceStore.rememberBottomInspectorVisibility(false)
        }
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
