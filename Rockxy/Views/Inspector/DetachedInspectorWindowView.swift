import SwiftUI

// Standalone Inspector window that mirrors the main horizontal request/response
// inspector for one pinned transaction, or for the main window's selection when
// Follow Selection is on.

// MARK: - DetachedInspectorWindowView

/// Detached Inspector window. Adopts the latest requested selection on appear and
/// whenever the handoff store re-targets it, then renders the URL bar plus the same
/// side-by-side request/response inspector as the main window. The selection is held
/// as a strong `@State` reference so main-window selection changes or live-buffer
/// eviction never blank this window; it keeps live-updating its pinned transaction.
struct DetachedInspectorWindowView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if let selection {
                HStack(spacing: 0) {
                    InspectorURLBar(
                        transaction: selection.transaction,
                        highlightContext: selection.highlightContext
                    )
                    Toggle(
                        String(localized: "Follow Selection", bundle: RockxyLocalization.bundle),
                        isOn: $followsSelection
                    )
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .help(String(
                        localized: "Show the request selected in the main window instead of keeping this one",
                        bundle: RockxyLocalization.bundle
                    ))
                }
                Divider()
                HSplitView {
                    RequestInspectorView(
                        transaction: selection.transaction,
                        coordinator: coordinator,
                        previewTabStore: coordinator.previewTabStore,
                        highlightContext: selection.highlightContext
                    )
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    ResponseInspectorView(
                        transaction: selection.transaction,
                        coordinator: coordinator,
                        previewTabStore: coordinator.previewTabStore,
                        highlightContext: selection.highlightContext,
                        onOpenToolWindow: { id in openWindow(id: id) }
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
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .onAppear {
            adoptLatestSelection()
        }
        .onChange(of: DetachedInspectorStore.shared.version) {
            adoptLatestSelection()
        }
        .onChange(of: coordinator.selectedTransaction?.id) {
            followMainSelection()
        }
        .onChange(of: followsSelection) {
            followMainSelection()
        }
        .onDisappear {
            guard let selection else {
                return
            }
            DetachedInspectorStore.shared.dismiss(selectionID: selection.id)
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow

    @State private var selection: DetachedInspectorSelection?
    @AppStorage(RockxyIdentity.current.defaultsKey("detachedInspector.followsSelection"))
    private var followsSelection = false

    /// Retargets to the main window's selected request while Follow Selection is on. An empty
    /// or multi-row selection keeps the current request rather than blanking the window.
    private func followMainSelection() {
        guard followsSelection,
              coordinator.selectedTransactionIDs.count <= 1,
              let transaction = coordinator.selectedTransaction,
              transaction.id != selection?.transaction.id else
        {
            return
        }
        selection = DetachedInspectorSelection(
            transaction: transaction,
            highlightContext: coordinator.activeInspectorHighlightContext()
        )
    }

    private func adoptLatestSelection() {
        guard let requested = DetachedInspectorStore.shared.requestedSelection else {
            return
        }
        selection = requested
    }
}
