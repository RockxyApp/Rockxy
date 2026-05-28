import SwiftUI

/// Top-level inspector panel that hosts the URL bar and the request/response split view.
/// Shown in the rightmost column when a transaction is selected in the request list.
struct InspectorPanelView: View {
    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if let transaction = coordinator.selectedTransaction {
                let highlightContext = coordinator.activeInspectorHighlightContext()
                InspectorURLBar(transaction: transaction, highlightContext: highlightContext)
                Divider()
                HSplitView {
                    RequestInspectorView(
                        transaction: transaction,
                        previewTabStore: coordinator.previewTabStore,
                        highlightContext: highlightContext
                    )
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    ResponseInspectorView(
                        transaction: transaction,
                        coordinator: coordinator,
                        previewTabStore: coordinator.previewTabStore,
                        highlightContext: highlightContext
                    )
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
