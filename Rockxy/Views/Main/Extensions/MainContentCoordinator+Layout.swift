import SwiftUI

// Extends `MainContentCoordinator` with layout behavior for the main workspace.

// MARK: - MainContentCoordinator + Layout

/// Coordinator extension for the horizontal inspector and independent Context Dock.
extension MainContentCoordinator {
    // MARK: - Inspector Layout

    func toggleInspectorRight() {
        withAnimation(.smooth(duration: 0.18)) {
            isContextDockVisible.toggle()
        }
    }

    func toggleInspectorBottom() {
        withAnimation(.smooth(duration: 0.18)) {
            inspectorLayout = (inspectorLayout == .bottom) ? .hidden : .bottom
        }
    }
}
