import SwiftUI

// Sidebar context-menu action that shows an app or domain in the split-view pane beside the
// current traffic, reusing that pane when it is already open.

struct OpenInSplitViewButton: View {
    let coordinator: MainContentCoordinator
    let filter: FilterCriteria

    var body: some View {
        Button {
            coordinator.showTrafficSplitView(filter: filter)
        } label: {
            Label(
                String(localized: "Open in Split View", bundle: RockxyLocalization.bundle),
                systemImage: "rectangle.split.2x1"
            )
        }
    }
}
