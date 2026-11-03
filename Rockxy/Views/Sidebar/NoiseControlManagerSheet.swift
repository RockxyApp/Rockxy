import SwiftUI

// MARK: - NoiseControlManagerSheet

/// Traffic Tab-scoped manager for traffic that should stay captured but remain out of the working set.
struct NoiseControlManagerSheet: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            managerContent
            actionBar
        }
        .font(toolMetrics.font())
        .frame(width: max(680, toolMetrics.fieldWidth(680)), height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("noiseControl.sheet")
        .task {
            // Three full scans and a sort over the capture. Done here rather than in `init`,
            // so re-initialising the sheet while traffic arrives does not repeat them.
            suggestions = FocusSetEditorSuggestions(transactions: coordinator.transactions)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.dismiss) private var dismiss
    @State private var sourceKind: CapturedValueKind = .domain
    @State private var sourceDraft = ""
    @State private var searchText = ""
    @State private var suggestions = FocusSetEditorSuggestions()

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var allSources: [MutedTrafficSource] {
        coordinator.activeWorkspace.mutedTrafficSources.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var filteredSources: [MutedTrafficSource] {
        SidebarSearchFilter.mutedSources(allSources, query: searchText)
    }

    private var candidateSource: MutedTrafficSource? {
        let value = sourceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        switch sourceKind {
        case .domain:
            let domain = DomainGrouping.normalizedHost(value)
            return domain.isEmpty ? nil : .host(domain)
        case .path:
            return .pathPrefix(value)
        case .application:
            return nil
        }
    }

    private var validationMessage: String? {
        guard let candidateSource else {
            return String(localized: "Enter a source to mute.", bundle: RockxyLocalization.bundle)
        }
        if sourceKind == .path, !candidateSource.title.hasPrefix("/") {
            return String(localized: "Path prefixes must start with /.", bundle: RockxyLocalization.bundle)
        }
        if coordinator.activeWorkspace.mutedTrafficSources.contains(candidateSource) {
            return String(localized: "This source is already muted.", bundle: RockxyLocalization.bundle)
        }
        return nil
    }

    private var currentSuggestions: [CapturedValueSuggestion] {
        switch sourceKind {
        case .domain:
            suggestions.domains
        case .path:
            suggestions.paths
        case .application:
            []
        }
    }

    private var sourcePlaceholder: String {
        sourceKind == .domain ? String(localized: "example.com", bundle: RockxyLocalization.bundle) : String(
            localized: "/analytics",
            bundle: RockxyLocalization.bundle
        )
    }

    private var sourcePickerTitle: String {
        sourceKind == .domain
            ? String(localized: "Choose Domain to Mute", bundle: RockxyLocalization.bundle)
            : String(localized: "Choose Path Prefix to Mute", bundle: RockxyLocalization.bundle)
    }

    private var sourceSearchPrompt: String {
        sourceKind == .domain
            ? String(localized: "Search captured domains", bundle: RockxyLocalization.bundle)
            : String(localized: "Search captured paths", bundle: RockxyLocalization.bundle)
    }

    private var sourceHint: String {
        sourceKind == .domain
            ? String(localized: "Matches this domain and all of its subdomains.", bundle: RockxyLocalization.bundle)
            : String(localized: "Matches this path and all child paths.", bundle: RockxyLocalization.bundle)
    }

    private var sourceMessage: String {
        sourceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? sourceHint
            : validationMessage ?? sourceHint
    }

    private var isSourceMessageError: Bool {
        !sourceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validationMessage != nil
    }

    private var mutedSourceCountLabel: String {
        String(AttributedString(
            localized: "^[\(allSources.count) muted source](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Noise Control", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))
                Text(
                    String(
                        localized: "Hide recurring traffic from the current Traffic Tab. Capture continues and no requests are deleted.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 20)

            TextField(String(localized: "Filter muted sources", bundle: RockxyLocalization.bundle), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: toolMetrics.fieldWidth(210), height: toolMetrics.formControlHeight)
                .accessibilityLabel(String(localized: "Filter muted sources", bundle: RockxyLocalization.bundle))
                .accessibilityIdentifier("noiseControl.filter")
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var managerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            addSourceGroup

            Divider()

            VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Muted Sources", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font(weight: .semibold))
                    Text(String(
                        localized: "Muted sources apply regardless of the active Focus Set.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                mutedSourcesTable
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .controlSize(.regular)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var addSourceGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Mute a Source", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .semibold))
                Text(String(
                    localized: "Choose a captured domain or path, or enter a pattern.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                conditionRow(title: String(localized: "Type", bundle: RockxyLocalization.bundle)) {
                    Picker(
                        String(localized: "Source Type", bundle: RockxyLocalization.bundle),
                        selection: $sourceKind
                    ) {
                        Text(String(localized: "Domain", bundle: RockxyLocalization.bundle))
                            .tag(CapturedValueKind.domain)
                        Text(String(localized: "Path Prefix", bundle: RockxyLocalization.bundle))
                            .tag(CapturedValueKind.path)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: toolMetrics.fieldWidth(250))
                }

                conditionRow(title: String(localized: "Pattern", bundle: RockxyLocalization.bundle)) {
                    HStack(alignment: .top, spacing: 8) {
                        CapturedTextSuggestionField(
                            text: $sourceDraft,
                            placeholder: sourcePlaceholder,
                            pickerTitle: sourcePickerTitle,
                            searchPrompt: sourceSearchPrompt,
                            emptySelectionTitle: String(localized: "No Selection", bundle: RockxyLocalization.bundle),
                            suggestions: currentSuggestions,
                            kind: sourceKind,
                            requestsInitialFocus: true
                        )
                        Button(String(localized: "Mute", bundle: RockxyLocalization.bundle), action: addSource)
                            .keyboardShortcut(.return, modifiers: [.command])
                            .rockxyGlassButtonStyle()
                            .disabled(validationMessage != nil)
                    }

                    Text(sourceMessage)
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(
                            isSourceMessageError ? Color.red : Color(nsColor: .tertiaryLabelColor)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .onChange(of: sourceKind) { _, _ in
            sourceDraft = ""
        }
    }

    private var mutedSourcesTable: some View {
        Table(filteredSources) {
            TableColumn(String(localized: "Source", bundle: RockxyLocalization.bundle)) { source in
                HStack(spacing: 7) {
                    Image(systemName: source.systemImage)
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                    Text(source.title)
                        .font(toolMetrics.font(monospaced: true))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(source.title)
                }
            }
            .width(min: 190, ideal: 250)

            TableColumn(String(localized: "Type", bundle: RockxyLocalization.bundle)) { source in
                Text(sourceKindLabel(source))
                    .foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 150)

            TableColumn(String(localized: "Matches", bundle: RockxyLocalization.bundle)) { source in
                Text(CountFormatter.format(coordinator.mutedTransactionCount(for: source)))
                    .font(toolMetrics.font(monospaced: true))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(60)

            TableColumn("") { source in
                Button {
                    coordinator.unmuteTrafficSource(source)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Unmute \(source.title)", bundle: RockxyLocalization.bundle))
                .accessibilityLabel(String(localized: "Unmute \(source.title)", bundle: RockxyLocalization.bundle))
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(32)
        }
        .overlay {
            if filteredSources.isEmpty {
                ContentUnavailableView(
                    searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? String(localized: "No Muted Sources", bundle: RockxyLocalization.bundle)
                        : String(localized: "No Matching Sources", bundle: RockxyLocalization.bundle),
                    systemImage: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "eye.slash"
                        : "magnifyingglass",
                    description: Text(
                        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? String(
                                localized: "Mute a domain or path prefix to keep recurring traffic out of this Traffic Tab.",
                                bundle: RockxyLocalization.bundle
                            )
                            : String(
                                localized: "Try a different domain or path prefix.",
                                bundle: RockxyLocalization.bundle
                            )
                    )
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var actionBar: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Label(mutedSourceCountLabel, systemImage: "eye.slash")
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            Spacer()
            Button(String(localized: "Unmute All", bundle: RockxyLocalization.bundle), role: .destructive) {
                coordinator.unmuteAllTrafficSources()
            }
            .rockxyGlassButtonStyle()
            .disabled(allSources.isEmpty)
            Button(String(localized: "Done", bundle: RockxyLocalization.bundle)) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private func conditionRow(
        title: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(toolMetrics.font(weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: toolMetrics.formLabelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sourceKindLabel(_ source: MutedTrafficSource) -> String {
        switch source {
        case .host:
            String(localized: "Domain and subdomains", bundle: RockxyLocalization.bundle)
        case .pathPrefix:
            String(localized: "Path prefix", bundle: RockxyLocalization.bundle)
        }
    }

    private func addSource() {
        guard validationMessage == nil, let candidateSource else {
            return
        }
        coordinator.muteTrafficSource(candidateSource)
        sourceDraft = ""
    }
}
