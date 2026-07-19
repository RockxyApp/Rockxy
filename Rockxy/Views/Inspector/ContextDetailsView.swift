import SwiftUI

/// Selection-aware request diagnostics shown in the Details tab of the Context Dock.
/// Raw request and response payloads remain in the horizontal inspector below the traffic table.
struct ContextDetailsView: View {
    let coordinator: MainContentCoordinator

    var body: some View {
        contextContent
            .background(Color(nsColor: .controlBackgroundColor))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Inspector Details"))
    }

    private struct ContextInsight: Identifiable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
        let color: Color
    }

    private struct TimingPhase: Identifiable {
        let id: String
        let title: String
        let duration: TimeInterval
    }

    @ViewBuilder
    private var contextContent: some View {
        if selectedTransactions.count > 1 {
            multiSelectionContent
        } else if let transaction = coordinator.selectedTransaction {
            singleSelectionContent(transaction)
                .id(transaction.id)
        } else {
            noSelectionContent
        }
    }

    private var noSelectionContent: some View {
        VStack(spacing: 0) {
            ContentUnavailableView {
                Label(String(localized: "No Selection"), systemImage: "cursorarrow.click.2")
            } description: {
                Text(coordinator.isProxyRunning
                    ? String(localized: "Select a request to see diagnostics and related traffic.")
                    : String(localized: "Start capture, then select a request to inspect its context."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Label(
                    coordinator.isProxyRunning
                        ? String(localized: "Capture Running")
                        : String(localized: "Capture Stopped"),
                    systemImage: coordinator.isProxyRunning ? "record.circle" : "stop.circle"
                )
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func singleSelectionContent(_ transaction: HTTPTransaction) -> some View {
        VStack(spacing: 0) {
            selectionHeader(transaction)
            Divider()

            List {
                overviewSection(transaction)
                insightSection(transaction)
                timingSection(transaction)
                payloadSection(transaction)
                relatedSection(transaction)
                toolsSection(transaction)
            }
            .listStyle(.inset)

            Divider()
            singleSelectionActionBar(transaction)
        }
    }

    private func selectionHeader(_ transaction: HTTPTransaction) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(statusColor(for: transaction))
                .frame(width: 9, height: 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(transaction.request.method)
                        .font(.caption.weight(.semibold).monospaced())
                    Text(transaction.response.map { String($0.statusCode) } ?? String(localized: "Pending"))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(statusColor(for: transaction))
                }
                Text(transaction.request.host)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(transaction.request.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func overviewSection(_ transaction: HTTPTransaction) -> some View {
        Section(String(localized: "Overview")) {
            nativeValueRow(String(localized: "Outcome"), outcomeText(for: transaction), color: statusColor(for: transaction))
            nativeValueRow(String(localized: "Application"), transaction.clientApp ?? String(localized: "Unknown"))
            nativeValueRow(String(localized: "Protocol"), transaction.request.httpVersion)
            nativeValueRow(String(localized: "Transport"), transportText(for: transaction))
            nativeValueRow(String(localized: "Duration"), durationText(for: transaction))
            nativeValueRow(String(localized: "Transferred"), transferredText(for: transaction))
            if let sourcePort = transaction.sourcePort {
                nativeValueRow(String(localized: "Source Port"), String(sourcePort))
            }
        }
    }

    private func insightSection(_ transaction: HTTPTransaction) -> some View {
        Section(String(localized: "Insights")) {
            ForEach(insights(for: transaction)) { insight in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: insight.systemImage)
                        .foregroundStyle(insight.color)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(.subheadline.weight(.medium))
                        Text(insight.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowBackground(insight.color.opacity(0.08))
            }
        }
    }

    @ViewBuilder
    private func timingSection(_ transaction: HTTPTransaction) -> some View {
        if let timing = transaction.timingInfo {
            let phases = timingPhases(timing)
            let slowest = phases.max { $0.duration < $1.duration }
            Section(String(localized: "Timing")) {
                if let slowest {
                    nativeValueRow(String(localized: "Slowest Phase"), slowest.title)
                }
                ForEach(phases) { phase in
                    LabeledContent(phase.title) {
                        Text(phaseDurationText(phase.duration, total: timing.totalDuration))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func payloadSection(_ transaction: HTTPTransaction) -> some View {
        Section(String(localized: "Payload")) {
            nativeValueRow(
                String(localized: "Request"),
                payloadSummary(body: transaction.request.body, contentType: transaction.request.contentType)
            )
            nativeValueRow(
                String(localized: "Response"),
                payloadSummary(body: transaction.response?.body, contentType: transaction.response?.contentType)
            )
            nativeValueRow(String(localized: "Request Headers"), "\(transaction.request.headers.count)")
            nativeValueRow(String(localized: "Response Headers"), "\(transaction.response?.headers.count ?? 0)")
            if transaction.response?.bodyTruncated == true {
                Label(String(localized: "Response body was truncated during capture"), systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func relatedSection(_ transaction: HTTPTransaction) -> some View {
        let related = relatedTransactions(to: transaction)
        return Section(String(localized: "Related Requests")) {
            if related.isEmpty {
                Text(String(localized: "No other requests to this host in the current session."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(related.prefix(6)) { item in
                    Button {
                        coordinator.selectedTransactionIDs = [item.id]
                        coordinator.selectTransaction(item)
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(statusColor(for: item))
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.request.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(relativeTimeText(item.timestamp, from: transaction.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            Text(item.response.map { String($0.statusCode) } ?? "—")
                                .monospacedDigit()
                                .foregroundStyle(statusColor(for: item))
                        }
                        .font(.caption)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toolsSection(_ transaction: HTTPTransaction) -> some View {
        Section(String(localized: "Rules & Tools")) {
            if transaction.matchedRuleID != nil {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.matchedRuleName ?? String(localized: "Rule matched"))
                        if let summary = transaction.matchedRuleActionSummary {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
                        }
                        if let pattern = transaction.matchedRulePattern {
                            Text(pattern).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        }
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } else {
                Label(String(localized: "No rule modified this request"), systemImage: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func singleSelectionActionBar(_ transaction: HTTPTransaction) -> some View {
        HStack(spacing: 8) {
            Button {
                coordinator.replayTransaction(transaction)
            } label: {
                Label(String(localized: "Replay"), systemImage: "arrow.clockwise")
            }
            .disabled(transaction.webSocketConnection != nil)
            .help(transaction.webSocketConnection == nil
                ? String(localized: "Replay this request")
                : String(localized: "WebSocket transactions cannot be replayed as HTTP requests"))

            Button {
                coordinator.togglePin(for: transaction)
            } label: {
                Image(systemName: transaction.isPinned ? "pin.slash" : "pin")
            }
            .help(transaction.isPinned ? String(localized: "Unpin Evidence") : String(localized: "Pin Evidence"))

            Spacer(minLength: 0)

            Button {
                coordinator.createBreakpointRule(for: transaction)
            } label: {
                Label(String(localized: "Create Rule"), systemImage: "plus.circle")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var multiSelectionContent: some View {
        VStack(spacing: 0) {
            List {
                Section(String(localized: "Selection")) {
                    nativeValueRow(String(localized: "Requests"), "\(selectedTransactions.count)")
                    nativeValueRow(
                        String(localized: "Hosts"),
                        "\(Set(selectedTransactions.map { $0.request.host }).count)"
                    )
                    nativeValueRow(
                        String(localized: "Errors"),
                        "\(selectedErrorCount)",
                        color: selectedErrorCount > 0 ? .red : .secondary
                    )
                    nativeValueRow(
                        String(localized: "Rules Hit"),
                        "\(selectedTransactions.count { $0.matchedRuleID != nil })"
                    )
                    nativeValueRow(String(localized: "Transferred"), selectedTransferredText)
                }

                Section(String(localized: "Inspector")) {
                    Text(String(localized: "Select one request to inspect payload and timing details."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)

            Divider()
            HStack(spacing: 8) {
                Button {
                    NotificationCenter.default.post(name: .openDiffWindow, object: nil)
                } label: {
                    Label(String(localized: "Compare"), systemImage: "arrow.left.arrow.right")
                }
                .disabled(selectedTransactions.count != 2)
                Spacer()
                Button {
                    coordinator.presentExport(format: .har)
                } label: {
                    Label(String(localized: "Export Selection"), systemImage: "square.and.arrow.up")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var selectedTransactions: [HTTPTransaction] {
        coordinator.resolveSelectedTransactions()
    }

    private var selectedErrorCount: Int {
        selectedTransactions.count { ($0.response?.statusCode ?? 0) >= 400 || $0.state == .failed }
    }

    private var selectedTransferredText: String {
        let bytes = selectedTransactions.reduce(Int64(0)) { partial, transaction in
            partial + Int64(transaction.request.body?.count ?? 0)
                + Int64(transaction.response?.body?.count ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func insights(for transaction: HTTPTransaction) -> [ContextInsight] {
        var values: [ContextInsight] = []
        appendOutcomeInsight(for: transaction, to: &values)
        appendTimingInsights(for: transaction, to: &values)
        appendProtocolInsights(for: transaction, to: &values)
        appendCaptureInsights(for: transaction, to: &values)

        if values.isEmpty {
            values.append(ContextInsight(
                id: "healthy",
                title: String(localized: "No unusual behavior detected"),
                detail: String(localized: "Status, timing, payload, and rule checks look normal."),
                systemImage: "checkmark.circle",
                color: .secondary
            ))
        }
        return values
    }

    private func appendOutcomeInsight(for transaction: HTTPTransaction, to values: inout [ContextInsight]) {
        if let status = transaction.response?.statusCode, status >= 400 {
            values.append(ContextInsight(
                id: "http-error",
                title: String(localized: "HTTP error \(status)"),
                detail: String(localized: "Inspect the response payload and nearby requests to this host."),
                systemImage: "exclamationmark.triangle.fill",
                color: .red
            ))
        } else if transaction.state == .failed {
            values.append(ContextInsight(
                id: "transport-error",
                title: String(localized: "Transport failed"),
                detail: String(localized: "No successful response was captured for this request."),
                systemImage: "xmark.octagon.fill",
                color: .red
            ))
        }
    }

    private func appendTimingInsights(for transaction: HTTPTransaction, to values: inout [ContextInsight]) {
        guard let duration = transaction.timingInfo?.totalDuration ?? transaction.measuredDuration else {
            return
        }
        if let baseline = hostDurationBaseline(for: transaction), duration > baseline * 1.5, duration - baseline > 0.1 {
            let percent = Int(((duration / baseline) - 1) * 100)
            values.append(ContextInsight(
                id: "host-baseline",
                title: String(localized: "Slower than this host's recent requests"),
                detail: String(localized: "About \(percent)% slower than the session median of \(formatDuration(baseline))."),
                systemImage: "chart.line.uptrend.xyaxis",
                color: .orange
            ))
        } else if duration >= 1 {
            values.append(ContextInsight(
                id: "slow",
                title: String(localized: "Slow request"),
                detail: String(localized: "Total duration is \(formatDuration(duration))."),
                systemImage: "hourglass",
                color: .orange
            ))
        }

        guard let timing = transaction.timingInfo, timing.totalDuration > 0 else {
            return
        }
        if timing.timeToFirstByte / timing.totalDuration >= 0.6, timing.timeToFirstByte >= 0.25 {
            values.append(ContextInsight(
                id: "ttfb",
                title: String(localized: "Server wait dominates"),
                detail: String(localized: "Time to first byte accounts for most of the request duration."),
                systemImage: "server.rack",
                color: .orange
            ))
        } else if timing.contentTransfer / timing.totalDuration >= 0.6, timing.contentTransfer >= 0.25 {
            values.append(ContextInsight(
                id: "transfer",
                title: String(localized: "Content transfer dominates"),
                detail: String(localized: "Payload transfer accounts for most of the request duration."),
                systemImage: "arrow.down.circle",
                color: .orange
            ))
        }
    }

    private func appendProtocolInsights(for transaction: HTTPTransaction, to values: inout [ContextInsight]) {
        if transaction.webSocketConnection != nil {
            values.append(ContextInsight(
                id: "websocket",
                title: String(localized: "WebSocket connection"),
                detail: String(localized: "Use the horizontal inspector to review individual frames."),
                systemImage: "arrow.left.arrow.right",
                color: .blue
            ))
        }
        if let graphQL = transaction.graphQLInfo {
            let operation = graphQL.operationName ?? String(localized: "Unnamed operation")
            values.append(ContextInsight(
                id: "graphql",
                title: String(localized: "GraphQL \(graphQL.operationType.rawValue)"),
                detail: operation,
                systemImage: "point.3.connected.trianglepath.dotted",
                color: .purple
            ))
        }
        if transaction.matchedRuleID != nil {
            values.append(ContextInsight(
                id: "rule",
                title: String(localized: "A rule affected this request"),
                detail: transaction.matchedRuleActionSummary ?? String(localized: "Review Rules & Tools below."),
                systemImage: "wand.and.stars",
                color: .green
            ))
        }
    }

    private func appendCaptureInsights(for transaction: HTTPTransaction, to values: inout [ContextInsight]) {
        if transaction.response?.bodyTruncated == true {
            values.append(ContextInsight(
                id: "truncated",
                title: String(localized: "Response body is incomplete"),
                detail: String(localized: "The captured response exceeded the configured buffer limit."),
                systemImage: "scissors",
                color: .orange
            ))
        }
        let relatedErrors = relatedTransactions(to: transaction).count {
            ($0.response?.statusCode ?? 0) >= 400 || $0.state == .failed
        }
        if relatedErrors >= 2 {
            values.append(ContextInsight(
                id: "repeated-errors",
                title: String(localized: "Repeated host errors"),
                detail: String(localized: "\(relatedErrors) nearby requests to this host also failed."),
                systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                color: .red
            ))
        }
    }

    private func relatedTransactions(to transaction: HTTPTransaction) -> [HTTPTransaction] {
        coordinator.transactions
            .filter { $0.id != transaction.id && $0.request.host == transaction.request.host }
            .sorted {
                abs($0.timestamp.timeIntervalSince(transaction.timestamp))
                    < abs($1.timestamp.timeIntervalSince(transaction.timestamp))
            }
    }

    private func hostDurationBaseline(for transaction: HTTPTransaction) -> TimeInterval? {
        let values = relatedTransactions(to: transaction)
            .prefix(20)
            .compactMap { $0.timingInfo?.totalDuration ?? $0.measuredDuration }
            .sorted()
        guard !values.isEmpty else {
            return nil
        }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    private func timingPhases(_ timing: TimingInfo) -> [TimingPhase] {
        [
            TimingPhase(id: "dns", title: String(localized: "DNS"), duration: timing.dnsLookup),
            TimingPhase(id: "connect", title: String(localized: "Connect"), duration: timing.tcpConnection),
            TimingPhase(id: "tls", title: String(localized: "TLS"), duration: timing.tlsHandshake),
            TimingPhase(id: "wait", title: String(localized: "Server Wait"), duration: timing.timeToFirstByte),
            TimingPhase(id: "transfer", title: String(localized: "Transfer"), duration: timing.contentTransfer),
        ]
    }

    private func nativeValueRow(_ label: String, _ value: String, color: Color = .secondary) -> some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.caption)
    }

    private func outcomeText(for transaction: HTTPTransaction) -> String {
        if let response = transaction.response {
            return "\(response.statusCode) \(response.statusMessage)"
        }
        return transaction.state == .failed ? String(localized: "Failed") : String(localized: "Pending")
    }

    private func transportText(for transaction: HTTPTransaction) -> String {
        transaction.request.url.scheme?.uppercased() ?? String(localized: "Unknown")
    }

    private func payloadSummary(body: Data?, contentType: ContentType?) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(body?.count ?? 0), countStyle: .file)
        guard let contentType else {
            return size
        }
        return "\(contentType.rawValue) · \(size)"
    }

    private func durationText(for transaction: HTTPTransaction) -> String {
        guard let duration = transaction.timingInfo?.totalDuration ?? transaction.measuredDuration else {
            return String(localized: "Unavailable")
        }
        return formatDuration(duration)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1_000)
        }
        return String(format: "%.2f s", duration)
    }

    private func phaseDurationText(_ duration: TimeInterval, total: TimeInterval) -> String {
        let percentage = total > 0 ? Int((duration / total) * 100) : 0
        return "\(formatDuration(duration)) · \(percentage)%"
    }

    private func transferredText(for transaction: HTTPTransaction) -> String {
        let bytes = Int64(transaction.request.body?.count ?? 0)
            + Int64(transaction.response?.body?.count ?? 0)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func relativeTimeText(_ timestamp: Date, from reference: Date) -> String {
        let difference = timestamp.timeIntervalSince(reference)
        let direction = difference < 0 ? String(localized: "before") : String(localized: "after")
        return "\(formatDuration(abs(difference))) \(direction)"
    }

    private func statusColor(for transaction: HTTPTransaction) -> Color {
        guard let status = transaction.response?.statusCode else {
            return transaction.state == .failed ? .red : .secondary
        }
        switch status {
        case 200 ..< 300: return .green
        case 300 ..< 400: return .blue
        case 400 ..< 500: return .orange
        case 500...: return .red
        default: return .secondary
        }
    }
}
