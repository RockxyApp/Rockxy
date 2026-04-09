import SwiftUI

/// Pool table showing candidate transactions for comparison.
/// Users assign Left/Right by clicking the L/R columns.
struct DiffCandidateTableView: View {
    // MARK: Internal

    @Bindable var viewModel: DiffViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.candidates.isEmpty {
                emptyState
            } else {
                Table(viewModel.candidates) {
                    TableColumn("L") { transaction in
                        Button {
                            viewModel.assignLeft(transaction)
                        } label: {
                            Image(systemName: viewModel.isLeft(transaction) ? "circle.fill" : "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(viewModel.isLeft(transaction) ? Color.accentColor : Color.secondary
                                    .opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .width(24)

                    TableColumn("R") { transaction in
                        Button {
                            viewModel.assignRight(transaction)
                        } label: {
                            Image(systemName: viewModel.isRight(transaction) ? "circle.fill" : "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(viewModel.isRight(transaction) ? Color.accentColor : Color.secondary
                                    .opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .width(24)

                    TableColumn(String(localized: "Method")) { transaction in
                        StatusBadge(method: transaction.request.method)
                    }
                    .width(50)

                    TableColumn(String(localized: "URL")) { transaction in
                        Text(transaction.request.url.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(transaction.request.url.absoluteString)
                    }

                    TableColumn(String(localized: "Client")) { transaction in
                        Text(transaction.clientApp ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(60)

                    TableColumn(String(localized: "Code")) { transaction in
                        Text(transaction.response.map { "\($0.statusCode)" } ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(statusColor(transaction.response?.statusCode))
                    }
                    .width(40)

                    TableColumn(String(localized: "Time")) { transaction in
                        Text(formatTime(transaction.timestamp))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(70)

                    TableColumn(String(localized: "Duration")) { transaction in
                        Text(formatDuration(transaction.timingInfo?.totalDuration))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(70)
                }
            }
        }
    }

    // MARK: Private

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text(String(localized: "No compare candidates yet"))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(
                String(localized: "Select two requests and choose \"Compare Selected\" to start a basic local compare.")
            )
            .font(.caption2)
            .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func statusColor(_ code: Int?) -> Color {
        guard let code else {
            return .secondary
        }
        switch code {
        case 200 ..< 300: return .green
        case 300 ..< 400: return .blue
        case 400 ..< 500: return .orange
        case 500...: return .red
        default: return .secondary
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else {
            return "—"
        }
        return String(format: "%.0fms", seconds * 1_000)
    }
}
