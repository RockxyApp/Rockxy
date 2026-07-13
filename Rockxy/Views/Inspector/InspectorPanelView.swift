import SwiftUI

/// Top-level inspector panel that hosts the URL bar and the request/response split view.
/// Shown in the rightmost column when a transaction is selected in the request list.
struct InspectorPanelView: View {
    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.selectedTransactionIDs.count > 1 {
                InspectorSelectionSummaryView(coordinator: coordinator)
            } else if let transaction = coordinator.selectedTransaction {
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

private struct InspectorSelectionSummaryView: View {
    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Selection Summary"), systemImage: "square.stack.3d.up")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                summaryRow(String(localized: "Selected"), "\(transactions.count)")
                summaryRow(String(localized: "Hosts"), "\(Set(transactions.map { $0.request.host }).count)")
                summaryRow(String(localized: "Errors"), "\(transactions.count { ($0.response?.statusCode ?? 0) >= 400 })")
                summaryRow(
                    String(localized: "Transferred"),
                    ByteCountFormatter.string(fromByteCount: transferredBytes, countStyle: .file)
                )
            }
            Text(String(localized: "Select one request to inspect raw payload, or exactly two requests to compare."))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var transactions: [HTTPTransaction] {
        coordinator.selectedTransactionIDs.compactMap(coordinator.transaction(for:))
    }

    private var transferredBytes: Int64 {
        transactions.reduce(0) { total, transaction in
            total + Int64(transaction.request.body?.count ?? 0) + Int64(transaction.response?.body?.count ?? 0)
        }
    }

    @ViewBuilder
    private func summaryRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
