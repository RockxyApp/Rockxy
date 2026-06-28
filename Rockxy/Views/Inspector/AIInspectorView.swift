import SwiftUI

// MARK: - AIInspectorView

/// Native response-inspector tab for captured AI model traffic.
///
/// The view renders from a bounded detector snapshot so switching selected transactions
/// cannot leave stale parser output in the inspector.
struct AIInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let inspection {
                VStack(spacing: 0) {
                    summaryStrip(inspection)
                    Divider()
                    HSplitView {
                        eventList(inspection)
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                        detailPane(inspection)
                            .frame(minWidth: 280, maxWidth: .infinity)
                    }
                }
            } else {
                InspectorEmptyStateView(
                    String(localized: "No AI Metadata"),
                    systemImage: "sparkles",
                    description: String(localized: "This response does not look like captured AI model traffic.")
                )
            }
        }
        .task(id: transaction.id) {
            await loadInspection()
        }
    }

    // MARK: Private

    @State private var inspection: AIInspection?
    @State private var selectedEventID: String?
    @State private var filter: AIInspectorEventFilter = .all
    @State private var isLoading = true
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var selectedEvent: AIEventSummary? {
        guard let inspection else {
            return nil
        }
        if let selectedEventID,
           let event = inspection.events.first(where: { $0.id == selectedEventID })
        {
            return event
        }
        return inspection.events.first
    }

    private func loadInspection() async {
        isLoading = true
        let snapshot = AITrafficSnapshot(transaction: transaction)
        let transactionID = transaction.id
        let detected = await Task.detached(priority: .userInitiated) {
            AITrafficDetector.detect(snapshot: snapshot)
        }.value

        guard transaction.id == transactionID else {
            return
        }
        inspection = detected
        selectedEventID = detected?.events.first?.id
        isLoading = false
    }

    private func summaryStrip(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 18) {
                summaryItem(String(localized: "Provider"), value: inspection.provider.displayName)
                summaryItem(String(localized: "Model"), value: inspection.model ?? String(localized: "Unavailable"))
                summaryItem(String(localized: "Finish"), value: finishLabel(for: inspection))
                summaryItem(String(localized: "Confidence"), value: confidenceLabel(for: inspection))
            }

            Text(unavailableSummary(for: inspection))
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
    }

    private func summaryItem(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: metrics.secondaryFontSize, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func eventList(_ inspection: AIInspection) -> some View {
        VStack(spacing: 0) {
            Picker(selection: $filter) {
                Text(String(localized: "All")).tag(AIInspectorEventFilter.all)
                Text(String(localized: "Stream")).tag(AIInspectorEventFilter.stream)
                Text(String(localized: "Tools")).tag(AIInspectorEventFilter.tools)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            let events = filteredEvents(inspection.events)
            if events.isEmpty {
                InspectorEmptyStateView(
                    String(localized: "No Events"),
                    systemImage: "list.bullet",
                    description: String(localized: "No captured events match this filter.")
                )
            } else {
                List(events, selection: $selectedEventID) { event in
                    eventRow(event)
                        .tag(event.id)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func eventRow(_ event: AIEventSummary) -> some View {
        HStack(spacing: 6) {
            severityDot(event.severity)
            Text(event.title)
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(event.offsetLabel)
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                .foregroundStyle(event.severity == .error ? .red : .secondary)
                .lineLimit(1)
        }
    }

    private func severityDot(_ severity: AIEventSeverity) -> some View {
        Circle()
            .fill(severity == .error ? Color.red : Color.accentColor)
            .frame(width: 7, height: 7)
    }

    private func detailPane(_ inspection: AIInspection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                timingSection(inspection)
                usageSection(inspection)
                toolChainSection(inspection)
                retrievalSection(inspection)
                warningSection(inspection)
                selectedEventSection
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timingSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Timing and Stream"))
            HStack(spacing: 14) {
                metadataPair(String(localized: "Duration"), value: durationLabel(inspection.duration))
                metadataPair(String(localized: "Streaming"), value: inspection.isStreaming ? String(localized: "Yes") : String(localized: "No"))
                metadataPair(String(localized: "Events"), value: "\(inspection.events.count)")
            }
            streamBars(inspection.events)
            Text(String(localized: "SSE cadence is shown from captured events. Token boundaries stay unavailable unless the provider exposes them."))
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(.secondary)
        }
    }

    private func streamBars(_ events: [AIEventSummary]) -> some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(events.prefix(18).enumerated()), id: \.element.id) { index, event in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(event.category == .tool ? Color.orange : Color.accentColor)
                    .frame(width: 8, height: CGFloat(10 + ((index * 7) % 24)))
                    .help(event.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 48, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder private func usageSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Usage"))
            if let usage = inspection.usage {
                HStack(spacing: 16) {
                    metadataPair(String(localized: "Input"), value: tokenLabel(usage.inputTokens))
                    metadataPair(String(localized: "Cached"), value: tokenLabel(usage.cachedTokens))
                    metadataPair(String(localized: "Output"), value: tokenLabel(usage.outputTokens))
                    metadataPair(String(localized: "Total"), value: "\(usage.totalTokens)")
                }
                tokenBar(usage)
            } else {
                unavailableText(String(localized: "Usage fields were not present in the captured provider response."))
            }
        }
    }

    private func tokenBar(_ usage: AIUsage) -> some View {
        GeometryReader { proxy in
            let input = CGFloat(usage.inputTokens ?? 0)
            let cached = CGFloat(usage.cachedTokens ?? 0)
            let output = CGFloat(usage.outputTokens ?? 0)
            let total = max(CGFloat(usage.totalTokens), 1)
            let width = proxy.size.width

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.purple)
                    .frame(width: width * input / total)
                Rectangle()
                    .fill(Color.blue.opacity(0.65))
                    .frame(width: width * cached / total)
                Rectangle()
                    .fill(Color.green)
                    .frame(width: width * output / total)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 10)
    }

    private func toolChainSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Tool Chain"))
            if inspection.toolCalls.isEmpty {
                unavailableText(String(localized: "No tool-call payloads were visible in the captured traffic."))
            } else {
                ForEach(Array(inspection.toolCalls.enumerated()), id: \.offset) { index, tool in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: metrics.metadataFontSize, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(tool.name)
                            .font(.system(size: metrics.metadataFontSize, weight: .medium, design: .monospaced))
                        Spacer()
                        Text(tool.state.displayName)
                            .font(.system(size: metrics.metadataFontSize))
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
    }

    private func retrievalSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Retrieval"))
            if inspection.retrieval.isEmpty {
                unavailableText(String(localized: "No retrieval or embedding result was visible for this selected transaction."))
            } else {
                ForEach(Array(inspection.retrieval.enumerated()), id: \.offset) { _, match in
                    HStack {
                        Text(match.source)
                            .font(.system(size: metrics.metadataFontSize, weight: .medium, design: .monospaced))
                        Spacer()
                        Text(scoreLabel(match.score))
                            .foregroundStyle(.secondary)
                        Text(match.risk)
                            .foregroundStyle(match.risk.contains("sensitive") ? .red : .secondary)
                    }
                    .font(.system(size: metrics.metadataFontSize))
                    Divider()
                }
            }
        }
    }

    private func warningSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Warnings"))
            if inspection.warnings.isEmpty {
                unavailableText(String(localized: "No AI-specific warning was detected from visible traffic fields."))
            } else {
                ForEach(Array(inspection.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning.message, systemImage: warning.severity == .error ? "exclamationmark.triangle" : "lock.shield")
                        .font(.system(size: metrics.metadataFontSize, weight: .medium))
                        .foregroundStyle(warning.severity == .error ? .red : .orange)
                }
            }
        }
    }

    @ViewBuilder private var selectedEventSection: some View {
        if let selectedEvent {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(String(localized: "Selected Event"))
                Text(selectedEvent.detail)
                    .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.down")
                .font(.system(size: metrics.badgeFontSize))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
        }
    }

    private func metadataPair(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .font(.system(size: metrics.metadataFontSize, design: .monospaced))
    }

    private func unavailableText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: metrics.metadataFontSize))
            .foregroundStyle(.secondary)
    }

    private func filteredEvents(_ events: [AIEventSummary]) -> [AIEventSummary] {
        switch filter {
        case .all:
            events
        case .stream:
            events.filter { $0.category == .stream }
        case .tools:
            events.filter { $0.category == .tool }
        }
    }

    private func durationLabel(_ duration: TimeInterval?) -> String {
        duration.map { DurationFormatter.format(seconds: $0) } ?? String(localized: "Unavailable")
    }

    private func tokenLabel(_ value: Int?) -> String {
        value.map(String.init) ?? String(localized: "Unavailable")
    }

    private func scoreLabel(_ score: Double?) -> String {
        guard let score else {
            return String(localized: "Unavailable")
        }
        return String(format: "%.2f", score)
    }

    private func finishLabel(for inspection: AIInspection) -> String {
        if inspection.events.contains(where: { $0.title.lowercased().contains("completed") }) {
            return String(localized: "completed")
        }
        if let status = inspection.httpStatusCode, status >= 400 {
            return "HTTP \(status)"
        }
        return String(localized: "Unavailable")
    }

    private func confidenceLabel(for inspection: AIInspection) -> String {
        inspection.events.contains(where: { $0.category == .stream || $0.category == .tool })
            ? String(localized: "observed + derived")
            : String(localized: "observed")
    }

    private func unavailableSummary(for inspection: AIInspection) -> String {
        if inspection.unavailableFields.isEmpty {
            return String(localized: "All displayed values come from visible captured traffic.")
        }
        return String(localized: "Unavailable: \(inspection.unavailableFields.joined(separator: ", ")). Missing fields are not inferred.")
    }
}

// MARK: - AIInspectorEventFilter

private enum AIInspectorEventFilter: Hashable {
    case all
    case stream
    case tools
}
