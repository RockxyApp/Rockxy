import SwiftUI

/// Top-level inspector panel that hosts the URL bar and the request/response split view.
/// Shown in the rightmost column when a transaction is selected in the request list.
struct InspectorPanelView: View {
    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if let transaction = coordinator.selectedTransaction {
                InspectorURLBar(transaction: transaction)
                Divider()
                HSplitView {
                    RequestInspectorView(
                        transaction: transaction,
                        previewTabStore: coordinator.previewTabStore
                    )
                    .frame(minWidth: 250)
                    ResponseInspectorView(
                        transaction: transaction,
                        coordinator: coordinator,
                        previewTabStore: coordinator.previewTabStore
                    )
                    .frame(minWidth: 250)
                }
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sidebar.right",
                    description: Text("Select a request to inspect")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
