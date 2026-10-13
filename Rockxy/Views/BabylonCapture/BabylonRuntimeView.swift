import SwiftUI

// MARK: - BabylonRuntimeSourceOption

/// A distinct source client present in the retained events, for the source filter.
private struct BabylonRuntimeSourceOption: Identifiable, Equatable {
    let clientID: String
    let name: String

    var id: String {
        clientID
    }
}

// MARK: - BabylonRuntimeView

/// Dense native event workspace for Babylon runtime traces: a selectable Table of
/// newest-first arrivals, a scrollable detail inspector, exact-kind/source filters,
/// Cmd-F search, a compact readiness banner, and a global in-memory clear.
struct BabylonRuntimeView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            readinessBanner
            Divider()
            filterBar
            Divider()
            HSplitView {
                tableContent
                    .frame(
                        minWidth: max(620, toolMetrics.bodyFontSize * 22),
                        minHeight: toolMetrics.tableRowHeight * 6
                    )
                detailInspector
                    .frame(
                        minWidth: max(280, toolMetrics.bodyFontSize * 10),
                        minHeight: toolMetrics.tableRowHeight * 6
                    )
            }
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(900, min(1_120, toolMetrics.bodyFontSize * 15 + 720)),
            minHeight: max(640, min(820, toolMetrics.bodyFontSize * 12 + 500))
        )
        .background {
            Button("") { searchIsFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
        .confirmationDialog(
            String(localized: "Clear Runtime Events?", bundle: RockxyLocalization.bundle),
            isPresented: $showsClearConfirmation
        ) {
            Button(String(localized: "Clear Events", bundle: RockxyLocalization.bundle), role: .destructive) {
                clearEvents()
            }
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {}
        } message: {
            Text(
                String(
                    localized: "This removes every captured runtime event from memory. HTTP traffic and Babylon pairing are not affected.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
        .onChange(of: filteredEventIDs) { _, ids in
            reconcileSelection(with: ids)
        }
        .onChange(of: availableSourceClientIDs) { _, ids in
            reconcileSourceFilter(with: ids)
        }
        .onAppear(perform: applyPendingFocus)
        .onChange(of: navigation.pendingFocus) { _, _ in
            applyPendingFocus()
        }
    }

    // MARK: Private

    @State private var store = BabylonRuntimeEventStore.shared
    @State private var receiver = BabylonCaptureReceiver.shared
    @State private var pairingStore = BabylonPairingStore.shared
    @State private var selection: BabylonRuntimeEvent.ID?
    @State private var selectedKind: BabylonRuntimePackageDTO.Kind?
    @State private var selectedSourceClientID: String?
    @State private var selectedTraceID: String?
    @State private var navigation = BabylonRuntimeNavigation.shared
    @State private var searchText = ""
    @State private var showsClearConfirmation = false
    @FocusState private var searchIsFocused: Bool
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var filter: BabylonRuntimeEventFilter {
        BabylonRuntimeEventFilter(
            kind: selectedKind,
            sourceClientID: selectedSourceClientID,
            traceID: selectedTraceID,
            searchText: searchText
        )
    }

    /// Newest-first retained events, then filtered (order preserved).
    private var filteredEvents: [BabylonRuntimeEvent] {
        filter.apply(to: Array(store.events.reversed()))
    }

    private var filteredEventIDs: [BabylonRuntimeEvent.ID] {
        filteredEvents.map(\.id)
    }

    private var selectedEvent: BabylonRuntimeEvent? {
        guard let selection else {
            return nil
        }
        return store.events.first { $0.id == selection }
    }

    private var availableSources: [BabylonRuntimeSourceOption] {
        var seen = Set<String>()
        var options: [BabylonRuntimeSourceOption] = []
        for event in store.events where seen.insert(event.source.clientID).inserted {
            options.append(BabylonRuntimeSourceOption(clientID: event.source.clientID, name: event.source.displayName))
        }
        let duplicateNames = Dictionary(grouping: options, by: \.name)
        return options
            .map { option in
                guard (duplicateNames[option.name]?.count ?? 0) > 1 else {
                    return option
                }
                return BabylonRuntimeSourceOption(
                    clientID: option.clientID,
                    name: "\(option.name) • \(option.clientID.suffix(8))"
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var availableSourceClientIDs: [String] {
        availableSources.map(\.clientID)
    }

    private var availability: BabylonPairingAvailability {
        BabylonPairingAvailability(
            listenerStatus: receiver.listenerStatus,
            hasToken: !pairingStore.token.isEmpty
        )
    }

    private var readinessIcon: String {
        switch availability {
        case .ready: "checkmark.circle.fill"
        case .starting: "hourglass"
        case .stopped: "stop.circle"
        case .waiting: "wifi.exclamationmark"
        case .tokenMissing: "key.slash"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var readinessColor: Color {
        switch availability {
        case .ready: .green
        case .starting,
             .stopped: .secondary
        case .waiting,
             .tokenMissing,
             .unavailable: .orange
        }
    }

    private var readinessMessage: String {
        switch availability {
        case .ready:
            String(
                localized: "Listener ready. Paired Babylon clients can stream runtime events to this Mac.",
                bundle: RockxyLocalization.bundle
            )
        case .starting:
            String(
                localized: "Waiting for the local Babylon listener to come online.",
                bundle: RockxyLocalization.bundle
            )
        case .stopped:
            String(
                localized: "Babylon capture is not running. Runtime events won't arrive until it starts.",
                bundle: RockxyLocalization.bundle
            )
        case .waiting:
            String(
                localized: "The listener is waiting for a viable network. Runtime events will resume automatically.",
                bundle: RockxyLocalization.bundle
            )
        case .tokenMissing:
            String(
                localized: "No pairing token. Generate one in Pairing before clients can stream runtime events.",
                bundle: RockxyLocalization.bundle
            )
        case .unavailable:
            String(
                localized: "The Babylon listener isn't running. Open Pairing to review and retry.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private var footerSummary: String {
        let total = store.events.count
        let shown = filteredEvents.count
        let base = filter.isActive
            ? String(AttributedString(
                localized: "\(shown) of ^[\(total) event](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
            : String(AttributedString(
                localized: "^[\(total) event](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        guard store.evictedEventCount > 0 else {
            return base
        }
        return base + String(localized: "  •  \(store.evictedEventCount) evicted", bundle: RockxyLocalization.bundle)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Runtime Events", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))
                Text(String(
                    localized: "Live trace, step, and mark events streamed from paired Babylon clients.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            searchField
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var searchField: some View {
        TextField(String(localized: "Search names, IDs, errors", bundle: RockxyLocalization.bundle), text: $searchText)
            .textFieldStyle(.roundedBorder)
            .font(toolMetrics.font())
            .frame(width: 240, height: toolMetrics.formControlHeight)
            .focused($searchIsFocused)
            .accessibilityLabel(String(localized: "Search runtime events", bundle: RockxyLocalization.bundle))
    }

    // MARK: - Readiness banner

    private var readinessBanner: some View {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Image(systemName: readinessIcon)
                .foregroundStyle(readinessColor)
                .font(.system(size: toolMetrics.compactIconFontSize))
                .accessibilityHidden(true)
            Text(readinessMessage)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(String(localized: "Open Pairing", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "babylonPairing")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Picker(String(localized: "Kind", bundle: RockxyLocalization.bundle), selection: $selectedKind) {
                Text(String(localized: "All Kinds", bundle: RockxyLocalization.bundle))
                    .tag(BabylonRuntimePackageDTO.Kind?.none)
                ForEach(BabylonRuntimePackageDTO.Kind.displayOrder, id: \.self) { kind in
                    Text(kind.displayTitle).tag(BabylonRuntimePackageDTO.Kind?.some(kind))
                }
            }
            .labelsHidden()
            .font(toolMetrics.font())
            .frame(width: 170)
            .frame(minHeight: toolMetrics.formControlHeight)

            Picker(String(localized: "Source", bundle: RockxyLocalization.bundle), selection: $selectedSourceClientID) {
                Text(String(localized: "All Sources", bundle: RockxyLocalization.bundle)).tag(String?.none)
                ForEach(availableSources) { source in
                    Text(source.name).tag(String?.some(source.clientID))
                }
            }
            .labelsHidden()
            .font(toolMetrics.font())
            .frame(width: 220)
            .frame(minHeight: toolMetrics.formControlHeight)
            .disabled(availableSources.isEmpty)

            if let selectedTraceID {
                traceFilterChip(selectedTraceID)
            }

            if filter.isActive {
                Button(String(localized: "Reset Filters", bundle: RockxyLocalization.bundle)) {
                    selectedKind = nil
                    selectedSourceClientID = nil
                    selectedTraceID = nil
                    searchText = ""
                }
                .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    // MARK: - Table

    private var tableContent: some View {
        Table(filteredEvents, selection: $selection) {
            TableColumn(
                Text(String(localized: "Kind", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { event in
                kindCell(for: event)
            }
            .width(min: max(120, toolMetrics.bodyFontSize * 6), ideal: max(150, toolMetrics.bodyFontSize * 8))

            TableColumn(
                Text(String(localized: "Name", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { event in
                Text(event.name.isEmpty ? String(localized: "Untitled", bundle: RockxyLocalization.bundle) : event.name)
                    .font(toolMetrics.font())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(event.name)
            }
            .width(min: max(180, toolMetrics.bodyFontSize * 9), ideal: max(280, toolMetrics.bodyFontSize * 13))

            TableColumn(
                Text(String(localized: "Source", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { event in
                Text(event.source.displayName)
                    .font(toolMetrics.font())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(event.source.displayName)
            }
            .width(min: max(140, toolMetrics.bodyFontSize * 7), ideal: max(200, toolMetrics.bodyFontSize * 10))

            TableColumn(
                Text(String(localized: "Received", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { event in
                Text(
                    event.receivedAt,
                    format: .dateTime.month(.abbreviated).day().hour().minute().second()
                )
                .font(toolMetrics.font(monospaced: true))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .width(max(150, toolMetrics.bodyFontSize * 7))

            TableColumn(
                Text(String(localized: "Duration", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { event in
                Text(durationText(for: event))
                    .font(toolMetrics.font(monospaced: true))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(max(88, toolMetrics.bodyFontSize * 4.6))

            TableColumn(
                Text(String(localized: "Outcome", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { event in
                outcomeCell(for: event)
            }
            .width(max(96, toolMetrics.bodyFontSize * 5))
        }
        .overlay {
            if filteredEvents.isEmpty {
                emptyState
            }
        }
        .font(toolMetrics.font())
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            filter.isActive
                ? String(localized: "No Matching Events", bundle: RockxyLocalization.bundle)
                : String(localized: "No Runtime Events", bundle: RockxyLocalization.bundle),
            systemImage: filter
                .isActive ? "line.3.horizontal.decrease.circle" : "point.3.connected.trianglepath.dotted",
            description: Text(
                filter.isActive
                    ? String(
                        localized: "Try a different kind, source, or search term.",
                        bundle: RockxyLocalization.bundle
                    )
                    : String(
                        localized: "Start a Babylon trace on a paired client to see runtime events here.",
                        bundle: RockxyLocalization.bundle
                    )
            )
        )
    }

    // MARK: - Detail inspector

    private var detailInspector: some View {
        Group {
            if let event = selectedEvent {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: toolMetrics.headerSpacing) {
                        if event.isContentTruncated {
                            truncationNotice(for: event)
                        }

                        detailSection(String(localized: "Overview", bundle: RockxyLocalization.bundle)) {
                            detailRow(
                                String(localized: "Kind", bundle: RockxyLocalization.bundle),
                                event.kind.displayTitle
                            )
                            detailRow(
                                String(localized: "Name", bundle: RockxyLocalization.bundle),
                                event.name.isEmpty ? "—" : event.name
                            )
                            detailRow(
                                String(localized: "Outcome", bundle: RockxyLocalization.bundle),
                                event.outcome.title
                            )
                            detailRow(
                                String(localized: "Source", bundle: RockxyLocalization.bundle),
                                event.source.displayName
                            )
                            detailRow(
                                String(localized: "Package ID", bundle: RockxyLocalization.bundle),
                                event.packageID,
                                monospaced: true
                            )
                            detailRow(
                                String(localized: "Source Client", bundle: RockxyLocalization.bundle),
                                event.source.clientID,
                                monospaced: true
                            )
                        }

                        detailSection(String(localized: "Identifiers", bundle: RockxyLocalization.bundle)) {
                            detailRow(
                                String(localized: "Runtime Session", bundle: RockxyLocalization.bundle),
                                event.sessionID,
                                monospaced: true
                            )
                            detailRow(
                                String(localized: "Trace", bundle: RockxyLocalization.bundle),
                                event.traceID ?? "—",
                                monospaced: true
                            )
                            detailRow(
                                String(localized: "Step", bundle: RockxyLocalization.bundle),
                                event.stepID ?? "—",
                                monospaced: true
                            )
                            detailRow(
                                String(localized: "Parent Step", bundle: RockxyLocalization.bundle),
                                event.parentStepID ?? "—",
                                monospaced: true
                            )
                        }

                        if let traceID = event.traceID {
                            traceActions(traceID: traceID, stepID: event.stepID)
                        }

                        detailSection(String(localized: "Timing", bundle: RockxyLocalization.bundle)) {
                            detailRow(
                                String(localized: "Received", bundle: RockxyLocalization.bundle),
                                timestampText(event.receivedAt)
                            )
                            detailRow(
                                String(localized: "Event Time", bundle: RockxyLocalization.bundle),
                                timestampText(event.createdAt)
                            )
                            detailRow(
                                String(localized: "Started", bundle: RockxyLocalization.bundle),
                                event.startedAt.map(timestampText) ?? "—"
                            )
                            detailRow(
                                String(localized: "Ended", bundle: RockxyLocalization.bundle),
                                event.endedAt.map(timestampText) ?? "—"
                            )
                            detailRow(
                                String(localized: "Duration", bundle: RockxyLocalization.bundle),
                                durationText(for: event)
                            )
                        }

                        if let errorMessage = event.errorMessage {
                            detailSection(String(localized: "Error", bundle: RockxyLocalization.bundle)) {
                                Text(errorMessage)
                                    .font(toolMetrics.font(monospaced: true))
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !event.metadata.isEmpty {
                            detailSection(String(localized: "Metadata", bundle: RockxyLocalization.bundle)) {
                                metadataGrid(for: event)
                            }
                        }
                    }
                    .padding(.horizontal, toolMetrics.contentHorizontalPadding)
                    .padding(.vertical, toolMetrics.formVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "No Event Selected", bundle: RockxyLocalization.bundle),
                    systemImage: "sidebar.right",
                    description: Text(
                        String(
                            localized: "Select a runtime event to inspect its identifiers, timing, and metadata.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Text(footerSummary)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(role: .destructive) {
                showsClearConfirmation = true
            } label: {
                Text(String(localized: "Clear Events", bundle: RockxyLocalization.bundle))
                    .frame(minWidth: toolMetrics.footerButtonWidth, minHeight: toolMetrics.footerControlHeight - 8)
            }
            .disabled(store.events.isEmpty)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private func kindCell(for event: BabylonRuntimeEvent) -> some View {
        HStack(spacing: 6) {
            Image(systemName: event.kind.symbolName)
                .font(.system(size: toolMetrics.smallIconFontSize))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(event.kind.displayTitle)
                .font(toolMetrics.font())
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(event.kind.displayTitle)
    }

    private func outcomeCell(for event: BabylonRuntimeEvent) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(outcomeColor(for: event.outcome))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(event.outcome.title)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(event.outcome.title)
    }

    /// The trace's requests in the traffic list, and this window narrowed to the same trace.
    private func traceActions(traceID: String, stepID: String?) -> some View {
        let stepCount = stepID.map { coordinator.babylonRequestCount(traceID: traceID, stepID: $0) }
        let traceCount = coordinator.babylonRequestCount(traceID: traceID)
        return detailSection(String(localized: "Related Traffic", bundle: RockxyLocalization.bundle)) {
            if let stepID, let stepCount {
                detailRow(
                    String(localized: "In This Step", bundle: RockxyLocalization.bundle),
                    requestCountText(stepCount)
                )
                Button(String(localized: "Show Step Requests", bundle: RockxyLocalization.bundle)) {
                    showRequests(traceID: traceID, stepID: stepID)
                }
                .controlSize(.small)
                .disabled(stepCount == 0)
                .accessibilityIdentifier("babylonRuntime.showStepRequests")
            }
            detailRow(
                String(localized: "In This Trace", bundle: RockxyLocalization.bundle),
                requestCountText(traceCount)
            )
            HStack(spacing: toolMetrics.controlSpacing) {
                Button(String(localized: "Show Trace Requests", bundle: RockxyLocalization.bundle)) {
                    showRequests(traceID: traceID, stepID: nil)
                }
                .disabled(traceCount == 0)
                .accessibilityIdentifier("babylonRuntime.showTraceRequests")
                if selectedTraceID != traceID {
                    Button(String(localized: "Show Only This Trace", bundle: RockxyLocalization.bundle)) {
                        selectedTraceID = traceID
                    }
                    .accessibilityIdentifier("babylonRuntime.filterToTrace")
                }
            }
            .controlSize(.small)
        }
    }

    private func requestCountText(_ count: Int) -> String {
        String(AttributedString(
            localized: "^[\(count) request](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }

    private func traceFilterChip(_ traceID: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .accessibilityHidden(true)
            Text(traceID)
                .font(toolMetrics.font(monospaced: true))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160)
            Button {
                selectedTraceID = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Show All Traces", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Show All Traces", bundle: RockxyLocalization.bundle))
        }
        .padding(.horizontal, 6)
        .frame(minHeight: toolMetrics.formControlHeight)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .help(String(localized: "Showing one trace", bundle: RockxyLocalization.bundle))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Trace \(traceID)", bundle: RockxyLocalization.bundle))
    }

    private func showRequests(traceID: String, stepID: String?) {
        openWindow(id: "main")
        coordinator.showBabylonTraceRequests(traceID: traceID, stepID: stepID)
    }

    /// Applies a "show in Runtime Events" request from the traffic inspector: narrow to the trace,
    /// clear filters that could hide it, and select the step (or the trace start).
    private func applyPendingFocus() {
        guard let focus = navigation.consume() else {
            return
        }
        selectedKind = nil
        selectedSourceClientID = nil
        searchText = ""
        selectedTraceID = focus.traceID
        selection = BabylonRuntimeNavigation.eventID(for: focus, in: store.events)
    }

    private func detailSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
            Text(title)
                .font(toolMetrics.tableHeaderFont())
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .frame(width: toolMetrics.formLabelWidth, alignment: .leading)
            Text(value)
                .font(toolMetrics.font(monospaced: monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadataGrid(for event: BabylonRuntimeEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(event.sortedMetadata, id: \.key) { pair in
                HStack(alignment: .firstTextBaseline, spacing: toolMetrics.controlSpacing) {
                    Text(pair.key)
                        .font(toolMetrics.secondaryFont(monospaced: true))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(width: toolMetrics.formLabelWidth, alignment: .leading)
                    Text(pair.value)
                        .font(toolMetrics.font(monospaced: true))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func truncationNotice(for event: BabylonRuntimeEvent) -> some View {
        let fields = event.truncatedFields
            .map(\.title)
            .sorted()
            .joined(separator: ", ")
        return Label(
            String(
                localized: "\(fields) shortened to Rockxy's in-memory safety limits.", bundle: RockxyLocalization.bundle
            ),
            systemImage: "ellipsis.circle"
        )
        .font(toolMetrics.secondaryFont())
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    private func durationText(for event: BabylonRuntimeEvent) -> String {
        guard let duration = event.duration else {
            return "—"
        }
        return DurationFormatter.format(seconds: duration)
    }

    private func timestampText(_ date: Date) -> String {
        date.formatted(
            .dateTime.year().month(.abbreviated).day().hour().minute().second().secondFraction(.fractional(3))
        )
    }

    private func outcomeColor(for outcome: BabylonRuntimeOutcome) -> Color {
        switch outcome {
        case .finished: .green
        case .failed: .red
        case .started: .blue
        case .informational: .secondary
        }
    }

    private func reconcileSelection(with ids: [BabylonRuntimeEvent.ID]) {
        guard let selection, !ids.contains(selection) else {
            return
        }
        self.selection = nil
    }

    private func reconcileSourceFilter(with ids: [String]) {
        guard let selectedSourceClientID, !ids.contains(selectedSourceClientID) else {
            return
        }
        self.selectedSourceClientID = nil
    }

    private func clearEvents() {
        selection = nil
        selectedSourceClientID = nil
        receiver.clearRuntimeEvents()
    }
}
