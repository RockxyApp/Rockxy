import SwiftUI

// MARK: - ContextDockView

/// Native two-tab shell for request diagnostics and the conversational AI workflow.
struct ContextDockView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceModeSegmentedControl(
                selection: selectedTab,
                segments: [
                    WorkspaceModeSegment(
                        value: ContextDockTab.details,
                        title: String(localized: "Details", bundle: RockxyLocalization.bundle),
                        systemImage: "doc.text.magnifyingglass"
                    ),
                    WorkspaceModeSegment(
                        value: ContextDockTab.aiAssistant,
                        title: String(localized: "Investigate", bundle: RockxyLocalization.bundle),
                        systemImage: "sparkles"
                    ),
                ],
                accessibilityLabel: String(localized: "Inspector", bundle: RockxyLocalization.bundle)
            )
            .workspaceModeSwitcherStyle()

            Divider()

            switch coordinator.activeWorkspace.contextDockTab {
            case .details:
                ContextDetailsView(coordinator: coordinator)
            case .aiAssistant:
                AIAssistantDockView(coordinator: coordinator, onOpenSettings: onOpenSettings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Inspector", bundle: RockxyLocalization.bundle))
    }

    // MARK: Private

    private var selectedTab: Binding<ContextDockTab> {
        Binding(
            get: { coordinator.activeWorkspace.contextDockTab },
            set: { tab in
                guard coordinator.activeWorkspace.contextDockTab != tab else {
                    return
                }
                // Segmented-control callbacks can arrive during the native inspector's constraint pass.
                // Publish the content swap on the next run-loop turn so both tab roots keep
                // a stable inspector size while AppKit finishes the current layout.
                DispatchQueue.main.async { [weak coordinator] in
                    coordinator?.activeWorkspace.contextDockTab = tab
                }
            }
        )
    }
}
