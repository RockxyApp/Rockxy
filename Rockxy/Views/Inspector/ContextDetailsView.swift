import SwiftUI

// MARK: - ContextDetailsView

/// Selection-aware request diagnostics shown in the Details tab of the Context Dock.
/// Raw request and response payloads remain in the horizontal inspector below the traffic table.
struct ContextDetailsView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        contextContent
            .background(Color.clear)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Inspector Details", bundle: RockxyLocalization.bundle))
    }

    /// Streams and long model calls run orders of magnitude past a host's median, where a
    /// "17,825% slower" figure stops being readable; switch to a multiplier past 3×.
    static func hostBaselineDetail(duration: TimeInterval, baseline: TimeInterval) -> String {
        let ratio = duration / baseline
        if ratio >= 3 {
            let multiplier = ratio >= 10
                ? DecimalFormatter.format(ratio, fractionDigits: 0)
                : DecimalFormatter.format(ratio, fractionDigits: 1)
            return String(
                localized: "About \(multiplier)× the session median of \(formatDuration(baseline)).",
                bundle: RockxyLocalization.bundle
            )
        }
        let percent = DecimalFormatter.percent(Double(Int((ratio - 1) * 100)))
        return String(
            localized: "About \(percent) slower than the session median of \(formatDuration(baseline)).",
            bundle: RockxyLocalization.bundle
        )
    }

    // MARK: Private

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

    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var isTimingExpanded = false
    @State private var isRelatedExpanded = false

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
        return SizeFormatter.format(bytes: bytes)
    }

    private var multiSelectionFields: [ContextTableField] {
        [
            ContextTableField(
                label: String(localized: "Requests", bundle: RockxyLocalization.bundle),
                value: CountFormatter.format(selectedTransactions.count)
            ),
            ContextTableField(
                label: String(localized: "Hosts", bundle: RockxyLocalization.bundle),
                value: CountFormatter.format(Set(selectedTransactions.map(\.request.host)).count)
            ),
            ContextTableField(
                label: String(localized: "Errors", bundle: RockxyLocalization.bundle),
                value: CountFormatter.format(selectedErrorCount),
                color: selectedErrorCount > 0 ? .red : .primary
            ),
            ContextTableField(
                label: String(localized: "Rules Hit", bundle: RockxyLocalization.bundle),
                value: CountFormatter.format(selectedTransactions.count { $0.matchedRuleID != nil })
            ),
            ContextTableField(
                label: String(localized: "Transferred", bundle: RockxyLocalization.bundle),
                value: selectedTransferredText
            ),
        ]
    }

    private var emptyStateCopy: ContextDockEmptyStateCopy {
        ContextDockEmptyStateCopy(
            ContextDockEmptyState.resolve(
                hasCapturedTraffic: !coordinator.transactions.isEmpty,
                hasVisibleResults: !coordinator.filteredTransactions.isEmpty,
                isCapturing: coordinator.proxyDisplayState.hasCaptureSessionContext
            )
        )
    }

    @ViewBuilder private var contextContent: some View {
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
        let copy = emptyStateCopy
        return VStack(spacing: 0) {
            InspectorEmptyStateView(
                copy.title,
                systemImage: copy.systemImage,
                description: copy.description
            )

            WorkspaceFooterBar(horizontalPadding: 12) {
                HStack {
                    Label(
                        coordinator.proxyDisplayState.captureTitle,
                        systemImage: coordinator.proxyDisplayState.captureSystemImage
                    )
                    Spacer()
                }
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var multiSelectionContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ContextInspectorFieldTable(
                        title: String(localized: "Selection", bundle: RockxyLocalization.bundle),
                        fields: multiSelectionFields
                    )

                    Text(String(
                        localized: "Select one request to inspect payload and timing details.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            WorkspaceFooterBar(horizontalPadding: 10) {
                HStack(spacing: 8) {
                    Button {
                        let transactions = selectedTransactions
                        guard transactions.count == 2 else {
                            return
                        }
                        coordinator.compareTransactions(transactions[0], transactions[1])
                    } label: {
                        Label(
                            String(localized: "Compare", bundle: RockxyLocalization.bundle),
                            systemImage: "arrow.left.arrow.right"
                        )
                    }
                    .disabled(selectedTransactions.count != 2)
                    Spacer()
                    Button {
                        coordinator.presentSelectedExport(format: .har)
                    } label: {
                        Label(
                            String(localized: "Export Selection", bundle: RockxyLocalization.bundle),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .disabled(selectedTransactions.isEmpty)
                }
                .controlSize(.small)
            }
        }
    }

    private func singleSelectionContent(_ transaction: HTTPTransaction) -> some View {
        VStack(spacing: 0) {
            selectionHeader(transaction)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ruleImpactSection(transaction)
                    overviewSection(transaction)
                    payloadSection(transaction)
                    insightSection(transaction)
                    timingSection(transaction)
                    relatedSection(transaction)
                    notesSection(transaction)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            singleSelectionActionBar(transaction)
        }
    }

    private func selectionHeader(_ transaction: HTTPTransaction) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(statusColor(for: transaction))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(transaction.request.method)
                        .font(.system(size: metrics.secondaryFontSize, weight: .semibold, design: .monospaced))
                    Text(transaction.response.map { String($0.statusCode) } ?? String(
                        localized: "Pending",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(.system(size: metrics.secondaryFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor(for: transaction))
                }
                Text(transaction.request.host)
                    .font(.system(size: metrics.primaryFontSize, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(transaction.request.path)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func overviewSection(_ transaction: HTTPTransaction) -> some View {
        // A connection or stream that is still open has no final duration; tick its running
        // time once a second, as the WebSocket inspector does, and stay paused otherwise.
        TimelineView(.animation(minimumInterval: 1, paused: !transaction.isRunning)) { context in
            ContextInspectorFieldTable(
                title: String(localized: "Details", bundle: RockxyLocalization.bundle),
                fields: overviewFields(transaction, now: context.date)
            )
        }
    }

    private func insightSection(_ transaction: HTTPTransaction) -> some View {
        let values = insights(for: transaction)
        return ContextInspectorTable(title: String(localized: "Insights", bundle: RockxyLocalization.bundle)) {
            ForEach(Array(values.enumerated()), id: \.element.id) { index, insight in
                if index > 0 {
                    Divider()
                }
                ContextInspectorInsightRow(
                    systemImage: insight.systemImage,
                    title: insight.title,
                    detail: insight.detail,
                    color: insight.color
                )
            }
        }
    }

    @ViewBuilder
    private func timingSection(_ transaction: HTTPTransaction) -> some View {
        if let timing = transaction.timingInfo {
            let phases = timingPhases(timing)
            let slowest = phases.max { $0.duration < $1.duration }
            ContextInspectorDisclosureTable(
                title: String(localized: "Timing", bundle: RockxyLocalization.bundle),
                isExpanded: $isTimingExpanded,
                summary: formatDuration(timing.totalDuration)
            ) {
                if let slowest {
                    ContextInspectorFieldRow(field: ContextTableField(
                        label: String(localized: "Slowest Phase", bundle: RockxyLocalization.bundle),
                        value: slowest.title,
                        monospaced: false
                    ))
                    Divider()
                }
                ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                    if index > 0 {
                        Divider()
                    }
                    ContextInspectorFieldRow(field: ContextTableField(
                        label: phase.title,
                        value: phaseDurationText(phase.duration, total: timing.totalDuration)
                    ))
                }
            }
        }
    }

    private func payloadSection(_ transaction: HTTPTransaction) -> some View {
        ContextInspectorTable(title: String(localized: "Payload", bundle: RockxyLocalization.bundle)) {
            ContextInspectorFieldRow(field: ContextTableField(
                label: String(localized: "Request", bundle: RockxyLocalization.bundle),
                value: payloadSummary(body: transaction.request.body, contentType: transaction.request.contentType)
            ))
            Divider()
            ContextInspectorFieldRow(field: ContextTableField(
                label: String(localized: "Response", bundle: RockxyLocalization.bundle),
                value: payloadSummary(
                    body: transaction.response?.body,
                    contentType: transaction.response?.contentType
                )
            ))
            Divider()
            ContextInspectorFieldRow(field: ContextTableField(
                label: String(localized: "Request Headers", bundle: RockxyLocalization.bundle),
                value: CountFormatter.format(transaction.request.headers.count)
            ))
            Divider()
            ContextInspectorFieldRow(field: ContextTableField(
                label: String(localized: "Response Headers", bundle: RockxyLocalization.bundle),
                value: CountFormatter.format(transaction.response?.headers.count ?? 0)
            ))
            if transaction.response?.bodyTruncated == true {
                Divider()
                ContextInspectorFullRow {
                    Label(
                        String(
                            localized: "Response body was truncated during capture",
                            bundle: RockxyLocalization.bundle
                        ),
                        systemImage: "scissors"
                    )
                    .font(.system(size: metrics.metadataFontSize))
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private func relatedSection(_ transaction: HTTPTransaction) -> some View {
        let related = Array(relatedTransactions(to: transaction).prefix(6))
        return ContextInspectorDisclosureTable(
            title: String(localized: "Related Requests", bundle: RockxyLocalization.bundle),
            isExpanded: $isRelatedExpanded,
            summary: related.isEmpty ? nil : CountFormatter.format(related.count)
        ) {
            if related.isEmpty {
                ContextInspectorFullRow {
                    Text(String(
                        localized: "No other requests to this host in the current session.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(.system(size: metrics.metadataFontSize))
                    .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(related.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    relatedRequestRow(item, reference: transaction)
                }
            }
        }
    }

    private func relatedRequestRow(_ item: HTTPTransaction, reference: HTTPTransaction) -> some View {
        Button {
            coordinator.selectedTransactionIDs = [item.id]
            coordinator.selectTransaction(item)
        } label: {
            ContextInspectorFullRow {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor(for: item))
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.request.path)
                            .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(relativeTimeText(item.timestamp, from: reference.timestamp))
                            .font(.system(size: metrics.metadataFontSize))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Text(item.response.map { String($0.statusCode) } ?? "—")
                        .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                        .foregroundStyle(statusColor(for: item))
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }

    private func ruleImpactSection(_ transaction: HTTPTransaction) -> some View {
        ContextInspectorTable(title: String(localized: "Rule Impact", bundle: RockxyLocalization.bundle)) {
            if transaction.matchedRuleID != nil {
                ContextInspectorFieldRow(field: ContextTableField(
                    label: String(localized: "Rule", bundle: RockxyLocalization.bundle),
                    value: transaction.matchedRuleName ?? String(
                        localized: "Rule matched",
                        bundle: RockxyLocalization.bundle
                    ),
                    monospaced: false,
                    color: .green
                ))
                if let summary = transaction.matchedRuleActionSummary {
                    Divider()
                    ContextInspectorFieldRow(field: ContextTableField(
                        label: String(localized: "Action", bundle: RockxyLocalization.bundle),
                        value: summary,
                        monospaced: false
                    ))
                }
                if let pattern = transaction.matchedRulePattern {
                    Divider()
                    ContextInspectorFieldRow(field: ContextTableField(
                        label: String(localized: "Pattern", bundle: RockxyLocalization.bundle),
                        value: pattern
                    ))
                }
                if let target = matchedRuleNavigationTarget(transaction), let windowID = target.windowID {
                    Divider()
                    openRuleActionRow(windowID: windowID, help: target.openHelp)
                }
            }
            if !transaction.appliedScriptNames.isEmpty {
                if transaction.matchedRuleID != nil {
                    Divider()
                }
                ContextInspectorFieldRow(field: ContextTableField(
                    label: String(localized: "Scripts", bundle: RockxyLocalization.bundle),
                    value: transaction.appliedScriptNames.joined(separator: ", "),
                    monospaced: false,
                    color: .green
                ))
                Divider()
                openRuleActionRow(windowID: "scriptingList", help: nil)
            }
            if transaction.matchedRuleID == nil, transaction.appliedScriptNames.isEmpty {
                ContextInspectorFullRow {
                    Label(
                        String(localized: "No rule modified this request", bundle: RockxyLocalization.bundle),
                        systemImage: "minus.circle"
                    )
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func openRuleActionRow(windowID: String, help: String?) -> some View {
        Button {
            openWindow(id: windowID)
        } label: {
            ContextInspectorFullRow {
                HStack(spacing: 6) {
                    Label(
                        String(localized: "Open Rule", bundle: RockxyLocalization.bundle),
                        systemImage: "arrow.up.forward.app"
                    )
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: metrics.metadataFontSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help(help ?? String(localized: "Open the rule's editor window", bundle: RockxyLocalization.bundle))
    }

    private func notesSection(_ transaction: HTTPTransaction) -> some View {
        ContextInspectorTable(title: String(localized: "Notes", bundle: RockxyLocalization.bundle)) {
            ContextInspectorFullRow {
                ContextNotesEditor(coordinator: coordinator, transaction: transaction)
            }
        }
    }

    private func singleSelectionActionBar(_ transaction: HTTPTransaction) -> some View {
        WorkspaceFooterBar(horizontalPadding: 10) {
            HStack(spacing: 8) {
                Button {
                    coordinator.replayTransaction(transaction)
                } label: {
                    Label(
                        String(localized: "Replay", bundle: RockxyLocalization.bundle),
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(transaction.webSocketConnection != nil)
                .help(transaction.webSocketConnection == nil
                    ? String(localized: "Replay this request", bundle: RockxyLocalization.bundle)
                    : String(
                        localized: "WebSocket transactions cannot be replayed as HTTP requests",
                        bundle: RockxyLocalization.bundle
                    ))

                Button {
                    coordinator.togglePin(for: transaction)
                } label: {
                    Image(systemName: transaction.isPinned ? "pin.slash" : "pin")
                }
                .help(transaction
                    .isPinned ? String(localized: "Unpin Evidence", bundle: RockxyLocalization.bundle) : String(
                        localized: "Pin Evidence",
                        bundle: RockxyLocalization.bundle
                    ))

                Spacer(minLength: 0)

                Button {
                    coordinator.createBreakpointRule(for: transaction)
                } label: {
                    Label(
                        String(localized: "Create Rule", bundle: RockxyLocalization.bundle),
                        systemImage: "plus.circle"
                    )
                }
            }
            .controlSize(.small)
        }
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        DurationFormatter.format(seconds: duration)
    }

    private func overviewFields(_ transaction: HTTPTransaction, now: Date) -> [ContextTableField] {
        var fields: [ContextTableField] = [
            ContextTableField(
                label: String(localized: "Outcome", bundle: RockxyLocalization.bundle),
                value: outcomeText(for: transaction),
                color: statusColor(for: transaction)
            ),
            ContextTableField(
                label: String(localized: "Application", bundle: RockxyLocalization.bundle),
                value: transaction.clientApp ?? String(localized: "Unknown", bundle: RockxyLocalization.bundle),
                monospaced: false
            ),
            ContextTableField(
                label: String(localized: "Protocol", bundle: RockxyLocalization.bundle),
                value: transaction.request.httpVersion
            ),
            ContextTableField(
                label: String(localized: "Transport", bundle: RockxyLocalization.bundle),
                value: transportText(for: transaction)
            ),
            ContextTableField(
                label: String(localized: "Duration", bundle: RockxyLocalization.bundle),
                value: durationText(for: transaction, now: now)
            ),
            ContextTableField(
                label: String(localized: "Transferred", bundle: RockxyLocalization.bundle),
                value: transferredText(for: transaction)
            ),
        ]
        if let sourcePort = transaction.sourcePort {
            fields.append(ContextTableField(
                label: String(localized: "Source Port", bundle: RockxyLocalization.bundle),
                value: String(sourcePort)
            ))
        }
        return fields
    }

    /// Resolves the live matched rule so "Open Rule" routes to the correct existing tool window.
    /// Returns `nil` when the rule was deleted or has no dedicated window, so the button hides
    /// instead of routing to a wrong surface.
    private func matchedRuleNavigationTarget(_ transaction: HTTPTransaction) -> MatchedRuleNavigationTarget? {
        guard let id = transaction.matchedRuleID,
              let rule = coordinator.rules.first(where: { $0.id == id }) else
        {
            return nil
        }
        return MatchedRuleNavigationTarget(action: rule.action)
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
                title: String(localized: "No unusual behavior detected", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Status, timing, payload, and rule checks look normal.",
                    bundle: RockxyLocalization.bundle
                ),
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
                title: String(localized: "HTTP error \(status)", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Inspect the response payload and nearby requests to this host.",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "exclamationmark.triangle.fill",
                color: .red
            ))
        } else if transaction.state == .failed {
            values.append(ContextInsight(
                id: "transport-error",
                title: String(localized: "Transport failed", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "No successful response was captured for this request.",
                    bundle: RockxyLocalization.bundle
                ),
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
            values.append(ContextInsight(
                id: "host-baseline",
                title: String(localized: "Slower than this host's recent requests", bundle: RockxyLocalization.bundle),
                detail: Self.hostBaselineDetail(duration: duration, baseline: baseline),
                systemImage: "chart.line.uptrend.xyaxis",
                color: .orange
            ))
        } else if duration >= 1 {
            values.append(ContextInsight(
                id: "slow",
                title: String(localized: "Slow request", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Total duration is \(formatDuration(duration)).",
                    bundle: RockxyLocalization.bundle
                ),
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
                title: String(localized: "Server wait dominates", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Time to first byte accounts for most of the request duration.",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "server.rack",
                color: .orange
            ))
        } else if timing.contentTransfer / timing.totalDuration >= 0.6, timing.contentTransfer >= 0.25 {
            values.append(ContextInsight(
                id: "transfer",
                title: String(localized: "Content transfer dominates", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Payload transfer accounts for most of the request duration.",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "arrow.down.circle",
                color: .orange
            ))
        }
    }

    private func appendProtocolInsights(for transaction: HTTPTransaction, to values: inout [ContextInsight]) {
        if transaction.webSocketConnection != nil {
            values.append(ContextInsight(
                id: "websocket",
                title: String(localized: "WebSocket connection", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Use the horizontal inspector to review individual frames.",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "arrow.left.arrow.right",
                color: .blue
            ))
        }
        if let graphQL = transaction.graphQLInfo {
            let operation = graphQL.operationName ?? String(
                localized: "Unnamed operation",
                bundle: RockxyLocalization.bundle
            )
            values.append(ContextInsight(
                id: "graphql",
                title: String(
                    localized: "GraphQL \(graphQL.operationType.rawValue)",
                    bundle: RockxyLocalization.bundle
                ),
                detail: operation,
                systemImage: "point.3.connected.trianglepath.dotted",
                color: .purple
            ))
        }
        if transaction.matchedRuleID != nil {
            values.append(ContextInsight(
                id: "rule",
                title: String(localized: "A rule affected this request", bundle: RockxyLocalization.bundle),
                detail: transaction.matchedRuleActionSummary ?? String(
                    localized: "Review Rule Impact above.",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "wand.and.stars",
                color: .green
            ))
        }
    }

    private func appendCaptureInsights(for transaction: HTTPTransaction, to values: inout [ContextInsight]) {
        if transaction.response?.bodyTruncated == true {
            values.append(ContextInsight(
                id: "truncated",
                title: String(localized: "Response body is incomplete", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "The captured response exceeded the configured buffer limit.",
                    bundle: RockxyLocalization.bundle
                ),
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
                title: String(localized: "Repeated host errors", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "\(relatedErrors) nearby requests to this host also failed.",
                    bundle: RockxyLocalization.bundle
                ),
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
            TimingPhase(
                id: "dns",
                title: String(localized: "DNS", bundle: RockxyLocalization.bundle),
                duration: timing.dnsLookup
            ),
            TimingPhase(
                id: "connect",
                title: String(localized: "Connect", bundle: RockxyLocalization.bundle),
                duration: timing.tcpConnection
            ),
            TimingPhase(
                id: "tls",
                title: String(localized: "TLS", bundle: RockxyLocalization.bundle),
                duration: timing.tlsHandshake
            ),
            TimingPhase(
                id: "wait",
                title: String(localized: "Server Wait", bundle: RockxyLocalization.bundle),
                duration: timing.timeToFirstByte
            ),
            TimingPhase(
                id: "transfer",
                title: String(localized: "Transfer", bundle: RockxyLocalization.bundle),
                duration: timing.contentTransfer
            ),
        ]
    }

    private func outcomeText(for transaction: HTTPTransaction) -> String {
        if let response = transaction.response {
            return "\(response.statusCode) \(response.statusMessage)"
        }
        return transaction.state == .failed ? String(localized: "Failed", bundle: RockxyLocalization.bundle) : String(
            localized: "Pending",
            bundle: RockxyLocalization.bundle
        )
    }

    private func transportText(for transaction: HTTPTransaction) -> String {
        transaction.request.url.scheme?.uppercased() ?? String(localized: "Unknown", bundle: RockxyLocalization.bundle)
    }

    private func payloadSummary(body: Data?, contentType: ContentType?) -> String {
        let size = SizeFormatter.format(bytes: body?.count ?? 0)
        guard let contentType else {
            return size
        }
        return "\(contentType.rawValue) · \(size)"
    }

    private func durationText(for transaction: HTTPTransaction, now: Date) -> String {
        guard let duration = transaction.displayDuration(at: now) else {
            return String(localized: "Unavailable", bundle: RockxyLocalization.bundle)
        }
        return formatDuration(duration)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        Self.formatDuration(duration)
    }

    private func phaseDurationText(_ duration: TimeInterval, total: TimeInterval) -> String {
        // Truncated, not rounded: the phases of one request are read as a column, and rounding
        // each of them up lets the column sum past 100%.
        let percentage = total > 0 ? Int((duration / total) * 100) : 0
        return "\(formatDuration(duration)) · \(DecimalFormatter.percent(Double(percentage)))"
    }

    private func transferredText(for transaction: HTTPTransaction) -> String {
        var bytes = Int64(transaction.request.body?.count ?? 0)
            + Int64(transaction.response?.body?.count ?? 0)
        // A WebSocket moves its payload in frames after the bodiless upgrade exchange.
        if let connection = transaction.webSocketConnection {
            bytes += Int64(connection.totalPayloadSize)
        }
        return SizeFormatter.format(bytes: bytes)
    }

    private func relativeTimeText(_ timestamp: Date, from reference: Date) -> String {
        let difference = timestamp.timeIntervalSince(reference)
        let direction = difference < 0 ? String(localized: "before", bundle: RockxyLocalization.bundle) : String(
            localized: "after",
            bundle: RockxyLocalization.bundle
        )
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

// MARK: - ContextNotesEditor

/// Compact Notes editor for the Context Dock. Routes every edit through the coordinator's note seam
/// (`updateNoteDraft`) so whitespace is normalized, the Library's Notes collection stays in sync, and
/// persistence is debounced instead of rewriting the transaction row on every keystroke. Its own
/// `@State` seeds from the selection because the enclosing single-selection content carries
/// `.id(transaction.id)`; `onDisappear` flushes any pending write when the selection changes.
private struct ContextNotesEditor: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let transaction: HTTPTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text(String(localized: "Add a note about this request…", bundle: RockxyLocalization.bundle))
                        .font(.system(size: metrics.primaryFontSize))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $noteText)
                    .font(.system(size: metrics.primaryFontSize))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 52, maxHeight: 108)
                    .padding(.horizontal, 1)
                    .accessibilityLabel(String(localized: "Request note", bundle: RockxyLocalization.bundle))
            }
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            )

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(action: saveNote) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!isDirty)
                .help(String(localized: "Save Note", bundle: RockxyLocalization.bundle))
                .accessibilityLabel(String(localized: "Save Note", bundle: RockxyLocalization.bundle))
            }
        }
        .onAppear {
            noteText = transaction.comment ?? ""
            lastExplicitlySavedNote = MainContentCoordinator.normalizedNote(noteText)
        }
        .onChange(of: noteText) { _, newValue in
            coordinator.updateNoteDraft(newValue, for: transaction)
        }
        .onDisappear {
            coordinator.flushNotePersistence(for: transaction)
        }
    }

    // MARK: Private

    @State private var noteText = ""
    @State private var lastExplicitlySavedNote: String?
    @Environment(\.appUIDisplayMetrics) private var metrics

    /// Tracks changes since the user's last explicit save. Inline editing still keeps the existing
    /// debounce and selection-change safety, while this state gives the Save action a stable lifecycle
    /// even though the coordinator updates the in-memory transaction immediately.
    private var isDirty: Bool {
        MainContentCoordinator.normalizedNote(noteText) != lastExplicitlySavedNote
    }

    /// Commits the current draft immediately, cancelling the debounced write so the note is
    /// persisted right away instead of waiting on the autosave timer.
    private func saveNote() {
        coordinator.setNote(noteText, for: transaction)
        lastExplicitlySavedNote = MainContentCoordinator.normalizedNote(noteText)
    }
}
