import SwiftUI

// MARK: - InspectorPanelView

/// Top-level payload inspector that hosts the URL bar and side-by-side request/response panes.
/// Shown below the request list when a transaction is selected.
struct InspectorPanelView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    /// The traffic pane to inspect; `nil` follows the focused pane.
    var workspace: WorkspaceState?
    var onOpenToolWindow: (String) -> Void = { _ in }

    var body: some View {
        let pane = workspace ?? coordinator.activeWorkspace
        VStack(spacing: 0) {
            if pane.selectedTransactionIDs.count > 1 {
                InspectorSelectionSummaryView(coordinator: coordinator, selectedIDs: pane.selectedTransactionIDs)
            } else if let transaction = pane.selectedTransaction {
                let highlightContext = coordinator.activeInspectorHighlightContext()
                InspectorURLBar(
                    transaction: transaction,
                    highlightContext: highlightContext,
                    onOpenDetachedInspector: {
                        DetachedInspectorStore.shared.present(
                            transaction: transaction,
                            highlightContext: highlightContext
                        )
                        openWindow(id: "detachedInspector")
                    }
                )
                Divider()
                HSplitView {
                    RequestInspectorView(
                        transaction: transaction,
                        coordinator: coordinator,
                        previewTabStore: coordinator.previewTabStore,
                        highlightContext: highlightContext
                    )
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    ResponseInspectorView(
                        transaction: transaction,
                        coordinator: coordinator,
                        previewTabStore: coordinator.previewTabStore,
                        highlightContext: highlightContext,
                        onOpenToolWindow: onOpenToolWindow
                    )
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                InspectorEmptyStateView(
                    requestSelectionDescription: String(
                        localized: "Select a request to inspect",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
}

// MARK: - InspectorSelectionSummaryView

private struct InspectorSelectionSummaryView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let selectedIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "Selection Summary", bundle: RockxyLocalization.bundle),
                systemImage: "square.stack.3d.up"
            )
            .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                summaryRow(
                    String(localized: "Selected", bundle: RockxyLocalization.bundle),
                    CountFormatter.format(transactions.count)
                )
                summaryRow(
                    String(localized: "Hosts", bundle: RockxyLocalization.bundle),
                    CountFormatter.format(Set(transactions.map(\.request.host)).count)
                )
                summaryRow(
                    String(localized: "Errors", bundle: RockxyLocalization.bundle),
                    CountFormatter.format(transactions.count { ($0.response?.statusCode ?? 0) >= 400 })
                )
                summaryRow(
                    String(localized: "Transferred", bundle: RockxyLocalization.bundle),
                    SizeFormatter.format(bytes: transferredBytes)
                )
            }
            Text(String(
                localized: "Select one request to inspect raw payload, or exactly two requests to compare.",
                bundle: RockxyLocalization.bundle
            ))
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Private

    private var transactions: [HTTPTransaction] {
        selectedIDs.compactMap(coordinator.transaction(for:))
    }

    private var transferredBytes: Int64 {
        transactions.reduce(0) { total, transaction in
            total + Int64(transaction.request.body?.count ?? 0) + Int64(transaction.response?.body?.count ?? 0)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
