import SwiftUI

// MARK: - NoiseControlManagerSheet

/// Workspace-scoped manager for traffic that should stay captured but remain out of the working set.
struct NoiseControlManagerSheet: View {
    // MARK: Lifecycle

    init(coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        suggestions = FocusSetEditorSuggestions(transactions: coordinator.transactions)
    }

    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            managerContent
            Divider()
            actionBar
        }
        .frame(width: 600, height: 570)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var sourceKind: CapturedValueKind = .domain
    @State private var sourceDraft = ""
    @State private var searchText = ""

    private let suggestions: FocusSetEditorSuggestions

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
            return String(localized: "Enter a source to mute.")
        }
        if sourceKind == .path, !candidateSource.title.hasPrefix("/") {
            return String(localized: "Path prefixes must start with /.")
        }
        if coordinator.activeWorkspace.mutedTrafficSources.contains(candidateSource) {
            return String(localized: "This source is already muted.")
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
        sourceKind == .domain ? String(localized: "example.com") : String(localized: "/analytics")
    }

    private var sourcePickerTitle: String {
        sourceKind == .domain
            ? String(localized: "Choose Domain to Mute")
            : String(localized: "Choose Path Prefix to Mute")
    }

    private var sourceSearchPrompt: String {
        sourceKind == .domain
            ? String(localized: "Search captured domains")
            : String(localized: "Search captured paths")
    }

    private var sourceHint: String {
        sourceKind == .domain
            ? String(localized: "Matches this domain and all of its subdomains.")
            : String(localized: "Matches this path and all child paths.")
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

    private var sheetHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Noise Control"))
                    .font(.headline)
                Text(String(localized: "Hide matching traffic in this workspace without stopping capture."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var managerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                addSourceGroup
                mutedSourcesGroup
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .controlSize(.regular)
    }

    private var addSourceGroup: some View {
        conditionGroup(
            title: String(localized: "Mute Source"),
            description: String(localized: "Hide matching traffic throughout this workspace. Capture continues.")
        ) {
            conditionRow(title: String(localized: "Source Type"), icon: "slider.horizontal.3") {
                Picker(String(localized: "Source Type"), selection: $sourceKind) {
                    Text(String(localized: "Domain")).tag(CapturedValueKind.domain)
                    Text(String(localized: "Path Prefix")).tag(CapturedValueKind.path)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            conditionDivider

            conditionRow(title: String(localized: "Pattern"), icon: sourceKind.systemImage) {
                HStack(alignment: .top, spacing: 8) {
                    CapturedTextSuggestionField(
                        text: $sourceDraft,
                        placeholder: sourcePlaceholder,
                        pickerTitle: sourcePickerTitle,
                        searchPrompt: sourceSearchPrompt,
                        emptySelectionTitle: String(localized: "No Selection"),
                        suggestions: currentSuggestions,
                        kind: sourceKind,
                        requestsInitialFocus: true
                    )
                    Button(String(localized: "Mute"), action: addSource)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(validationMessage != nil)
                }

                Text(sourceMessage)
                    .font(.caption)
                    .foregroundStyle(isSourceMessageError ? Color.orange : Color.secondary)
            }
        }
        .onChange(of: sourceKind) { _, _ in
            sourceDraft = ""
        }
    }

    private var mutedSourcesGroup: some View {
        conditionGroup(
            title: String(localized: "Muted Sources"),
            description: String(
                localized: "Focus Set exclusions apply only inside that Focus Set; these rules apply regardless of the active Focus Set."
            )
        ) {
            conditionRow(title: String(localized: "Filter"), icon: "magnifyingglass") {
                TextField(String(localized: "Filter muted sources"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            conditionDivider

            if filteredSources.isEmpty {
                Text(searchText.isEmpty
                    ? String(localized: "No muted sources. Add a domain or path prefix above.")
                    : String(localized: "No muted sources match this filter."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredSources) { source in
                        sourceRow(source)
                        if source.id != filteredSources.last?.id {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Label(String(localized: "\(allSources.count) muted sources"), systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(String(localized: "Unmute All"), role: .destructive) {
                coordinator.unmuteAllTrafficSources()
            }
            .disabled(allSources.isEmpty)
            Button(String(localized: "Done")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var conditionDivider: some View {
        Divider()
            .padding(.leading, 104)
    }

    private func sourceRow(_ source: MutedTrafficSource) -> some View {
        HStack(spacing: 9) {
            Image(systemName: source.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(source.title)
                Text(sourceKindLabel(source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(String(localized: "\(coordinator.mutedTransactionCount(for: source)) matches"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button(String(localized: "Unmute")) {
                coordinator.unmuteTrafficSource(source)
            }
        }
        .padding(.vertical, 8)
    }

    private func conditionGroup(
        title: String,
        description: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                content()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
    }

    private func conditionRow(
        title: String,
        icon: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 12) {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sourceKindLabel(_ source: MutedTrafficSource) -> String {
        switch source {
        case .host:
            String(localized: "Domain and subdomains")
        case .pathPrefix:
            String(localized: "Path prefix")
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
