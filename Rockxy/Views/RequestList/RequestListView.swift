import SwiftUI

// Renders the request list for traffic list presentation.

// MARK: - RequestListView

/// Tab-switching container that displays the active main tab content (traffic, logs, timeline,
/// errors, or performance). The traffic tab uses a SwiftUI `List` for the fallback/simple view;
/// the high-performance `RequestTableView` (NSTableView-backed) is used in `CenterContentView`.
struct RequestListView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            UtilitySegmentedHeader(width: 320) {
                Picker("View", selection: Binding(
                    get: { coordinator.activeMainTab },
                    set: { coordinator.activeMainTab = $0 }
                )) {
                    ForEach(MainTab.allCases, id: \.self) { tab in
                        Label(tab.displayName, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Protocol filter pills
            ProtocolFilterBar(activeFilters: Binding(
                get: { coordinator.filterCriteria.activeProtocolFilters },
                set: {
                    coordinator.filterCriteria.activeProtocolFilters = $0
                    coordinator.recomputeFilteredTransactions()
                }
            ))

            // Content based on active tab
            switch coordinator.activeMainTab {
            case .traffic:
                trafficListView
            case .logs:
                LogStreamView(coordinator: coordinator)
            case .timeline:
                RequestTimelineView(coordinator: coordinator)
            }
        }
    }

    // MARK: Private

    @ViewBuilder private var trafficListView: some View {
        if coordinator.filteredTransactions.isEmpty {
            ContentUnavailableView(
                "No Traffic",
                systemImage: "network.slash",
                description: Text("Start the proxy to capture network traffic")
            )
        } else {
            List(coordinator.filteredTransactions, selection: Binding(
                get: { coordinator.selectedTransaction?.id },
                set: { id in
                    coordinator.selectTransaction(
                        coordinator.transactions.first { $0.id == id }
                    )
                }
            )) { transaction in
                RequestRowView(transaction: transaction)
                    .tag(transaction.id)
            }
        }
    }
}

// MARK: - RequestRowView

/// Single row in the SwiftUI List fallback, showing method badge, host/path, status code, and duration.
struct RequestRowView: View {
    let transaction: HTTPTransaction

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(method: transaction.request.method)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.request.host)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Text(transaction.request.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let response = transaction.response {
                StatusCodeBadge(statusCode: response.statusCode)
            }

            if let timing = transaction.timingInfo {
                Text(DurationFormatter.format(seconds: timing.totalDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}
