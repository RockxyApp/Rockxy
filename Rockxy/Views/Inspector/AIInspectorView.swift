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
                    if inspection.kind == .session {
                        sessionPane(inspection)
                    } else {
                        HSplitView {
                            eventList(inspection)
                                .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                            detailPane(inspection)
                                .frame(minWidth: 280, maxWidth: .infinity)
                        }
                    }
                }
            } else {
                InspectorEmptyStateView(
                    String(localized: "No AI Metadata", bundle: RockxyLocalization.bundle),
                    systemImage: "sparkles",
                    description: String(
                        localized: "This response does not look like captured AI model traffic.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
        }
        .task(id: transaction.inspectionKey) {
            await loadInspection()
        }
    }

    // MARK: Private

    private static let truncatedFinishReasons: Set<String> = [
        "length",
        "max_tokens",
        "max_output_tokens",
        "incomplete (max_output_tokens)",
    ]

    @State private var inspection: AIInspection?
    @State private var selectedEventID: String?
    @State private var filter: AIInspectorEventFilter = .all
    @State private var isLoading = true
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var unavailableLabel: String {
        String(localized: "Unavailable", bundle: RockxyLocalization.bundle)
    }

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

    private var sessionTransportLabel: String {
        if transaction.webSocketConnection != nil || transaction.request.url.scheme?.lowercased() == "wss" {
            return String(localized: "WebSocket / TLS", bundle: RockxyLocalization.bundle)
        }
        if transaction.request.method.caseInsensitiveCompare("CONNECT") == .orderedSame {
            return String(localized: "CONNECT / TLS", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "HTTPS / TLS", bundle: RockxyLocalization.bundle)
    }

    @ViewBuilder private var selectedEventSection: some View {
        if let selectedEvent {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    sectionHeader(String(localized: "Selected Event", bundle: RockxyLocalization.bundle))
                    Text(selectedEvent.offsetLabel)
                        .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(SizeFormatter.format(bytes: selectedEvent.byteCount))
                        .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(selectedEvent.detail)
                    .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: Summary

    private func summaryStrip(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                badge(inspection.kind.displayName, color: inspection.kind == .session ? .teal : .accentColor)
                if inspection.kind == .session {
                    badge(String(localized: "TLS only", bundle: RockxyLocalization.bundle), color: .orange)
                } else if inspection.isStreaming {
                    badge(streamBadgeLabel(inspection), color: .blue)
                }
                if !inspection.invokedToolCalls.isEmpty {
                    badge(String(localized: "Tool", bundle: RockxyLocalization.bundle), color: .orange)
                }
                if let status = inspection.httpStatusCode, status >= 400 {
                    badge("HTTP \(String(status))", color: .red)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170, maximum: 320), alignment: .leading)],
                alignment: .leading,
                spacing: 4
            ) {
                summaryItem(
                    String(localized: "Provider", bundle: RockxyLocalization.bundle),
                    value: inspection.provider.displayName
                )
                summaryItem(
                    String(localized: "Model", bundle: RockxyLocalization.bundle),
                    value: inspection.model ?? unavailableLabel
                )
                if let servedModel = inspection.servedModel {
                    summaryItem(String(localized: "Served", bundle: RockxyLocalization.bundle), value: servedModel)
                }
                summaryItem(
                    String(localized: "Finish", bundle: RockxyLocalization.bundle),
                    value: finishLabel(for: inspection)
                )
                if let requestID = inspection.requestID {
                    summaryItem(String(localized: "Request ID", bundle: RockxyLocalization.bundle), value: requestID)
                }
                summaryItem(
                    String(localized: "Evidence", bundle: RockxyLocalization.bundle),
                    value: evidenceLabel(for: inspection)
                )
            }

            Text(unavailableSummary(for: inspection))
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
    }

    private func summaryItem(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.secondary)
                .fixedSize()
            Text(value)
                .font(.system(size: metrics.secondaryFontSize, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
        }
        .accessibilityElement(children: .combine)
    }

    private func sessionPane(_ inspection: AIInspection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Captured app session", bundle: RockxyLocalization.bundle))
                            .font(.system(size: metrics.primaryFontSize, weight: .semibold))
                        metadataPair(
                            String(localized: "App", bundle: RockxyLocalization.bundle),
                            value: transaction.clientApp ?? String(
                                localized: "Unknown",
                                bundle: RockxyLocalization.bundle
                            )
                        )
                        metadataPair(
                            String(localized: "Host", bundle: RockxyLocalization.bundle),
                            value: transaction.request.host
                        )
                        metadataPair(
                            String(localized: "Transport", bundle: RockxyLocalization.bundle),
                            value: sessionTransportLabel
                        )
                    }
                }

                warningCard(
                    title: String(localized: "Body unavailable", bundle: RockxyLocalization.bundle),
                    message: String(
                        localized: "Rockxy can identify this AI app session, but model, tokens, and tools need decrypted API evidence.",
                        bundle: RockxyLocalization.bundle
                    ),
                    color: .orange
                )

                sectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(String(localized: "Suggested Check", bundle: RockxyLocalization.bundle))
                        Text(String(
                            localized: "Enable HTTPS Decryption for this host, or capture SDK traffic with HTTPS_PROXY when debugging local apps.",
                            bundle: RockxyLocalization.bundle
                        ))
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Event list

    private func eventList(_ inspection: AIInspection) -> some View {
        VStack(spacing: 0) {
            Picker(selection: $filter) {
                Text(String(localized: "All", bundle: RockxyLocalization.bundle)).tag(AIInspectorEventFilter.all)
                Text(String(localized: "Stream", bundle: RockxyLocalization.bundle)).tag(AIInspectorEventFilter.stream)
                Text(String(localized: "Tools", bundle: RockxyLocalization.bundle)).tag(AIInspectorEventFilter.tools)
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
                    String(localized: "No Events", bundle: RockxyLocalization.bundle),
                    systemImage: "list.bullet",
                    description: String(
                        localized: "No captured events match this filter.",
                        bundle: RockxyLocalization.bundle
                    )
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
            severityDot(event)
            Text(event.title)
                .font(.system(size: metrics.metadataFontSize, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if let preview = eventPreview(event) {
                Text(preview)
                    .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(event.offsetLabel)
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                .foregroundStyle(event.severity == .error ? .red : .secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: event))
    }

    private func severityDot(_ event: AIEventSummary) -> some View {
        Circle()
            .fill(eventColor(event))
            .frame(width: 7, height: 7)
    }

    // MARK: Detail pane

    private func detailPane(_ inspection: AIInspection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                debugFocusSection(inspection)
                timingSection(inspection)
                usageSection(inspection)
                assembledOutputSection(inspection)
                toolChainSection(inspection)
                retrievalSection(inspection)
                warningSection(inspection)
                selectedEventSection
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func debugFocusSection(_ inspection: AIInspection) -> some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    sectionHeader(String(localized: "Debug Focus", bundle: RockxyLocalization.bundle))
                    badge(aiDebugFocusLabel(inspection), color: aiDebugFocusColor(inspection))
                    Spacer(minLength: 0)
                }
                metadataPair(
                    String(localized: "Outcome", bundle: RockxyLocalization.bundle),
                    value: aiDebugOutcome(inspection)
                )
                metadataPair(
                    String(localized: "Next Check", bundle: RockxyLocalization.bundle),
                    value: aiDebugNextCheck(inspection)
                )
            }
        }
    }

    private func timingSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Timing and Stream", bundle: RockxyLocalization.bundle))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120, maximum: 220), alignment: .leading)],
                alignment: .leading,
                spacing: 4
            ) {
                metadataPair(
                    String(localized: "Duration", bundle: RockxyLocalization.bundle),
                    value: durationLabel(inspection.duration)
                )
                metadataPair(
                    String(localized: "Streaming", bundle: RockxyLocalization.bundle),
                    value: streamingLabel(inspection)
                )
                metadataPair(
                    String(localized: "Events", bundle: RockxyLocalization.bundle),
                    value: CountFormatter.format(inspection.events.count)
                )
            }
            if let diagnostics = transaction.streamDiagnostics {
                streamTimingGrid(diagnostics)
            }
            if inspection.isStreaming,
               inspection.events.contains(where: { $0.category == .stream || $0.category == .tool })
            {
                streamBars(inspection.events)
                Text(transaction.streamDiagnostics == nil
                    ? String(
                        localized: "Bars show each captured event's payload size in stream order. Per-event arrival timing is not recorded.",
                        bundle: RockxyLocalization.bundle
                    )
                    : String(
                        localized: "Bars show each captured event's payload size in stream order. Times above were measured by Rockxy as events arrived.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(.system(size: metrics.metadataFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Arrival timing measured live by the proxy for an SSE stream.
    private func streamTimingGrid(_ diagnostics: StreamDiagnostics) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120, maximum: 220), alignment: .leading)],
            alignment: .leading,
            spacing: 4
        ) {
            metadataPair(
                String(localized: "First Event", bundle: RockxyLocalization.bundle),
                value: durationLabel(diagnostics.firstEventTime)
            )
            metadataPair(
                String(localized: "Longest Gap", bundle: RockxyLocalization.bundle),
                value: durationLabel(diagnostics.maxInterEventGap)
            )
            metadataPair(
                String(localized: "Stream End", bundle: RockxyLocalization.bundle),
                value: streamOutcomeLabel(diagnostics.outcome)
            )
            metadataPair(
                String(localized: "Events Seen", bundle: RockxyLocalization.bundle),
                value: CountFormatter.format(diagnostics.eventCount)
            )
        }
        .accessibilityIdentifier("aiInspector.streamTiming")
    }

    private func streamOutcomeLabel(_ outcome: StreamTerminalOutcome) -> String {
        switch outcome {
        case .completedWithTerminalMarker:
            String(localized: "Completed", bundle: RockxyLocalization.bundle)
        case .endedWithoutTerminalMarker:
            String(localized: "Ended without a final event", bundle: RockxyLocalization.bundle)
        case .transportInterrupted:
            String(localized: "Interrupted", bundle: RockxyLocalization.bundle)
        case .timedOut:
            String(localized: "Timed out", bundle: RockxyLocalization.bundle)
        }
    }

    private func streamBars(_ events: [AIEventSummary]) -> some View {
        let shown = Array(events.prefix(48))
        let largest = max(shown.map(\.byteCount).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(shown) { event in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(eventColor(event))
                    .frame(width: 6, height: max(3, 34 * CGFloat(event.byteCount) / CGFloat(largest)))
                    .help("\(event.offsetLabel) \(event.title) · \(SizeFormatter.format(bytes: event.byteCount))")
            }
            if events.count > shown.count {
                Text("+\(CountFormatter.format(events.count - shown.count))")
                    .font(.system(size: metrics.badgeFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 48, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(AttributedString(
            localized: "Stream event sizes, ^[\(events.count) event](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters))
    }

    private func usageSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Usage", bundle: RockxyLocalization.bundle))
            if let usage = inspection.usage {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96, maximum: 180), alignment: .leading)],
                    alignment: .leading,
                    spacing: 4
                ) {
                    metadataPair(
                        String(localized: "Input", bundle: RockxyLocalization.bundle),
                        value: tokenLabel(usage.inputTokens)
                    )
                    metadataPair(
                        String(localized: "Cached", bundle: RockxyLocalization.bundle),
                        value: tokenLabel(usage.cachedTokens)
                    )
                    metadataPair(
                        String(localized: "Output", bundle: RockxyLocalization.bundle),
                        value: tokenLabel(usage.outputTokens)
                    )
                    if let reasoning = usage.reasoningTokens {
                        metadataPair(
                            String(localized: "Reasoning", bundle: RockxyLocalization.bundle),
                            value: CountFormatter.format(reasoning)
                        )
                    }
                    metadataPair(
                        String(localized: "Total", bundle: RockxyLocalization.bundle),
                        value: CountFormatter.format(usage.totalTokens)
                    )
                }
                tokenBar(usage)
                tokenLegend(usage)
            } else {
                unavailableText(String(
                    localized: "Usage fields were not present in the captured provider response.",
                    bundle: RockxyLocalization.bundle
                ))
            }
        }
    }

    /// Cached tokens are a subset of input tokens, so the bar splits input into its
    /// uncached and cached parts before appending output.
    private func tokenBar(_ usage: AIUsage) -> some View {
        GeometryReader { proxy in
            let input = CGFloat(usage.inputTokens ?? 0)
            let cached = min(CGFloat(usage.cachedTokens ?? 0), input)
            let output = CGFloat(usage.outputTokens ?? 0)
            let total = max(CGFloat(usage.totalTokens), input + output, 1)
            let width = proxy.size.width

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.purple)
                    .frame(width: width * (input - cached) / total)
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
        .accessibilityHidden(true)
    }

    private func tokenLegend(_ usage: AIUsage) -> some View {
        HStack(spacing: 12) {
            legendSwatch(.purple, String(localized: "Input", bundle: RockxyLocalization.bundle))
            if (usage.cachedTokens ?? 0) > 0 {
                legendSwatch(.blue.opacity(0.65), String(localized: "Cached", bundle: RockxyLocalization.bundle))
            }
            legendSwatch(.green, String(localized: "Output", bundle: RockxyLocalization.bundle))
        }
        .font(.system(size: metrics.badgeFontSize))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }

    @ViewBuilder
    private func assembledOutputSection(_ inspection: AIInspection) -> some View {
        if let output = inspection.assembledOutput {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    sectionHeader(String(localized: "Assembled Output", bundle: RockxyLocalization.bundle))
                    Spacer(minLength: 0)
                    Text(String(AttributedString(
                        localized: "^[\(output.count) character](inflect: true)",
                        bundle: RockxyLocalization.bundle,
                        locale: RockxyLocalization.locale
                    ).characters))
                        .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(output)
                    .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                Text(assembledOutputCaption(inspection))
                    .font(.system(size: metrics.metadataFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toolChainSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Tool Chain", bundle: RockxyLocalization.bundle))
            if inspection.toolCalls.isEmpty {
                unavailableText(String(
                    localized: "No tool declarations or tool-call payloads were visible in the captured traffic.",
                    bundle: RockxyLocalization.bundle
                ))
            } else {
                ForEach(Array(inspection.toolCalls.enumerated()), id: \.offset) { index, tool in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 10) {
                            Text(String(index + 1))
                                .font(.system(size: metrics.metadataFontSize, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            Text(tool.name)
                                .font(.system(size: metrics.metadataFontSize, weight: .medium, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            badge(toolStateLabel(tool.state), color: toolStateColor(tool.state))
                        }
                        if let arguments = tool.argumentsPreview, !arguments.isEmpty {
                            Text(arguments)
                                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                                .padding(.leading, 28)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Divider()
                }
            }
        }
    }

    private func retrievalSection(_ inspection: AIInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Retrieval", bundle: RockxyLocalization.bundle))
            if inspection.retrieval.isEmpty {
                unavailableText(String(
                    localized: "No retrieval or embedding result was visible for this selected transaction.",
                    bundle: RockxyLocalization.bundle
                ))
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
            sectionHeader(String(localized: "Warnings", bundle: RockxyLocalization.bundle))
            if inspection.warnings.isEmpty {
                unavailableText(String(
                    localized: "No AI-specific warning was detected from visible traffic fields.",
                    bundle: RockxyLocalization.bundle
                ))
            } else {
                ForEach(Array(inspection.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning.message, systemImage: warningSymbol(warning.severity))
                        .font(.system(size: metrics.metadataFontSize, weight: .medium))
                        .foregroundStyle(warningColor(warning.severity))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func warningCard(title: String, message: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
            Text(message)
                .font(.system(size: metrics.metadataFontSize))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.35), lineWidth: 0.5)
        }
    }

    private func sectionCard(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
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
        .accessibilityAddTraits(.isHeader)
    }

    private func metadataPair(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
                .fixedSize()
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: metrics.metadataFontSize, design: .monospaced))
        .accessibilityElement(children: .combine)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: metrics.badgeFontSize, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func unavailableText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: metrics.metadataFontSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func eventPreview(_ event: AIEventSummary) -> String? {
        guard let preview = event.preview?
            .replacingOccurrences(of: "\n", with: "⏎")
            .trimmingCharacters(in: .whitespaces),
            !preview.isEmpty else
        {
            return nil
        }
        return preview.count > 80 ? String(preview.prefix(80)) + "…" : preview
    }

    private func accessibilityLabel(for event: AIEventSummary) -> String {
        var parts = [event.offsetLabel, event.title]
        if let preview = eventPreview(event) {
            parts.append(preview)
        }
        if event.severity == .error {
            parts.append(String(localized: "error", bundle: RockxyLocalization.bundle))
        }
        return parts.joined(separator: ", ")
    }

    private func eventColor(_ event: AIEventSummary) -> Color {
        if event.severity == .error {
            return .red
        }
        return event.category == .tool ? .orange : .accentColor
    }

    private func assembledOutputCaption(_ inspection: AIInspection) -> String {
        if inspection.isStreaming {
            return String(
                localized: "Reassembled from captured stream deltas; the client may apply its own post-processing.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(localized: "Text read from the captured response body.", bundle: RockxyLocalization.bundle)
    }

    private func warningSymbol(_ severity: AIWarningSeverity) -> String {
        switch severity {
        case .error: "exclamationmark.triangle"
        case .retry: "arrow.clockwise"
        case .redaction: "lock.shield"
        }
    }

    private func warningColor(_ severity: AIWarningSeverity) -> Color {
        switch severity {
        case .error: .red
        case .retry: .blue
        case .redaction: .orange
        }
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

    // MARK: Labels

    private func streamBadgeLabel(_ inspection: AIInspection) -> String {
        switch inspection.streamTransport {
        case .sse: String(localized: "SSE stream", bundle: RockxyLocalization.bundle)
        case .ndjson: String(localized: "NDJSON stream", bundle: RockxyLocalization.bundle)
        case .none: String(localized: "Stream", bundle: RockxyLocalization.bundle)
        }
    }

    private func streamingLabel(_ inspection: AIInspection) -> String {
        guard inspection.isStreaming else {
            return String(localized: "No", bundle: RockxyLocalization.bundle)
        }
        switch inspection.streamTransport {
        case .sse: return "SSE"
        case .ndjson: return "NDJSON"
        case .none: return String(localized: "Requested", bundle: RockxyLocalization.bundle)
        }
    }

    private func toolStateLabel(_ state: AIToolCallState) -> String {
        switch state {
        case .declared: String(localized: "declared", bundle: RockxyLocalization.bundle)
        case .streaming: String(localized: "streaming", bundle: RockxyLocalization.bundle)
        case .completed: String(localized: "called", bundle: RockxyLocalization.bundle)
        case .partial: String(localized: "partial", bundle: RockxyLocalization.bundle)
        }
    }

    private func toolStateColor(_ state: AIToolCallState) -> Color {
        switch state {
        case .declared: .secondary
        case .streaming,
             .partial: .blue
        case .completed: .orange
        }
    }

    private func aiDebugFocusLabel(_ inspection: AIInspection) -> String {
        if inspection.warnings.contains(where: { $0.severity == .error }) {
            return String(localized: "Provider Error", bundle: RockxyLocalization.bundle)
        }
        if inspection.isStreaming, !inspection.invokedToolCalls.isEmpty {
            return String(localized: "Streaming Tool", bundle: RockxyLocalization.bundle)
        }
        if inspection.isStreaming {
            return String(localized: "Streaming", bundle: RockxyLocalization.bundle)
        }
        if !inspection.invokedToolCalls.isEmpty {
            return String(localized: "Tool Call", bundle: RockxyLocalization.bundle)
        }
        if !inspection.retrieval.isEmpty {
            return String(localized: "Retrieval", bundle: RockxyLocalization.bundle)
        }
        if inspection.usage == nil {
            return String(localized: "Metadata Sparse", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "Completion", bundle: RockxyLocalization.bundle)
    }

    private func aiDebugFocusColor(_ inspection: AIInspection) -> Color {
        if inspection.warnings.contains(where: { $0.severity == .error }) {
            return .red
        }
        if !inspection.invokedToolCalls.isEmpty {
            return .orange
        }
        if inspection.isStreaming {
            return .blue
        }
        if !inspection.retrieval.isEmpty {
            return .green
        }
        return .secondary
    }

    private func aiDebugOutcome(_ inspection: AIInspection) -> String {
        if let warning = inspection.warnings.first(where: { $0.severity == .error }) {
            return warning.message
        }
        if let statusCode = transaction.response?.statusCode,
           statusCode >= 400
        {
            return String(localized: "HTTP \(statusCode) from provider", bundle: RockxyLocalization.bundle)
        }
        if inspection.isStreaming {
            return String(
                localized: "\(inspection.events.count) captured stream events, finish \(finishLabel(for: inspection))",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(localized: "Finish \(finishLabel(for: inspection))", bundle: RockxyLocalization.bundle)
    }

    private func aiDebugNextCheck(_ inspection: AIInspection) -> String {
        if inspection.warnings.contains(where: { $0.severity == .error }) {
            return String(
                localized: "Check provider error body, request id, auth, rate-limit headers, and retry timing.",
                bundle: RockxyLocalization.bundle
            )
        }
        if let finish = inspection.finishReason, Self.truncatedFinishReasons.contains(finish.lowercased()) {
            return String(
                localized: "The model stopped at the output limit; raise max tokens or shorten the prompt before comparing outputs.",
                bundle: RockxyLocalization.bundle
            )
        }
        if inspection.isStreaming, !inspection.invokedToolCalls.isEmpty {
            return String(
                localized: "Filter Tools and verify partial arguments, final tool call state, and stream completion.",
                bundle: RockxyLocalization.bundle
            )
        }
        if inspection.isStreaming {
            return String(
                localized: "Check event count, final event, interruption signs, and first-token/overall duration.",
                bundle: RockxyLocalization.bundle
            )
        }
        if !inspection.invokedToolCalls.isEmpty {
            return String(
                localized: "Verify declared tool name, arguments, completion state, and app-side tool result follow-up.",
                bundle: RockxyLocalization.bundle
            )
        }
        if !inspection.retrieval.isEmpty {
            return String(
                localized: "Review retrieved sources, score, and sensitive-data risk before sharing traces.",
                bundle: RockxyLocalization.bundle
            )
        }
        if inspection.usage == nil {
            return String(
                localized: "Confirm provider adapter, response body visibility, and whether usage is omitted by this endpoint.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "Compare model, tokens, finish reason, and latency against adjacent retries.",
            bundle: RockxyLocalization.bundle
        )
    }

    private func durationLabel(_ duration: TimeInterval?) -> String {
        duration.map { DurationFormatter.format(seconds: $0) } ?? unavailableLabel
    }

    private func tokenLabel(_ value: Int?) -> String {
        value.map(CountFormatter.format) ?? unavailableLabel
    }

    private func scoreLabel(_ score: Double?) -> String {
        guard let score else {
            return unavailableLabel
        }
        return DecimalFormatter.format(score, fractionDigits: 2)
    }

    private func finishLabel(for inspection: AIInspection) -> String {
        if let finishReason = inspection.finishReason {
            return finishReason
        }
        if let status = inspection.httpStatusCode, status >= 400 {
            return "HTTP \(String(status))"
        }
        return unavailableLabel
    }

    private func confidenceLabel(for inspection: AIInspection) -> String {
        inspection.events.contains(where: { $0.category == .stream || $0.category == .tool })
            ? String(localized: "observed + derived", bundle: RockxyLocalization.bundle)
            : String(localized: "observed", bundle: RockxyLocalization.bundle)
    }

    private func evidenceLabel(for inspection: AIInspection) -> String {
        if inspection.evidence.isEmpty {
            return confidenceLabel(for: inspection)
        }
        return inspection.evidence.joined(separator: ", ")
    }

    private func unavailableSummary(for inspection: AIInspection) -> String {
        if inspection.unavailableFields.isEmpty {
            return String(
                localized: "All displayed values come from visible captured traffic.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "Unavailable: \(inspection.unavailableFields.joined(separator: ", ")). Missing fields are not inferred.",
            bundle: RockxyLocalization.bundle
        )
    }
}

// MARK: - AIInspectorEventFilter

private enum AIInspectorEventFilter: Hashable {
    case all
    case stream
    case tools
}

private extension AITrafficSignalKind {
    var displayName: String {
        switch self {
        case .api:
            String(localized: "AI API", bundle: RockxyLocalization.bundle)
        case .session:
            String(localized: "AI Session", bundle: RockxyLocalization.bundle)
        case .heuristic:
            String(localized: "Likely AI", bundle: RockxyLocalization.bundle)
        case .none:
            String(localized: "AI", bundle: RockxyLocalization.bundle)
        }
    }
}
