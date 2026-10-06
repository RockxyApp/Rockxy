import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AddSSLAppDomainSheet

/// Panel for browsing apps and domains observed in captured traffic, then adding
/// selected hosts as HTTPS decryption rules with an explicit behavior.
///
/// - Apps section shows each app with its observed domains as expandable children.
///   Choosing an app adds all of that app's currently observed hosts.
/// - Domains section shows all observed domains flat. Choosing a domain adds it.
///
/// Rules match by host, so an added rule applies to those hosts for every client,
/// not only the app they were observed from. Data comes from `TrafficDomainSnapshot`;
/// no guessed hosts are generated.
struct AddSSLAppDomainSheet: View {
    // MARK: Lifecycle

    init(
        existingRules: [SSLProxyingRule],
        onAdd: @escaping ([String], SSLProxyingListType) -> Void
    ) {
        self.existingRules = existingRules
        self.onAdd = onAdd
    }

    // MARK: Internal

    let existingRules: [SSLProxyingRule]
    let onAdd: ([String], SSLProxyingListType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            behaviorSection
            searchSection
            Divider()
            listSection
            footerHint
            Divider()
            buttonBar
        }
        .font(toolMetrics.font())
        .frame(width: max(520, toolMetrics.fieldWidth(520)), height: max(540, toolMetrics.bodyFontSize * 28 + 176))
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onChange(of: searchText) { _, _ in
            reconcileSelection()
        }
    }

    // MARK: Private

    private enum PickerItem: Hashable {
        case app(String)
        case domain(String)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    @State private var searchText = ""
    @State private var selectedItem: PickerItem?
    @State private var listType: SSLProxyingListType = .include
    @FocusState private var isSearchFocused: Bool

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var snapshot: TrafficDomainSnapshot {
        TrafficDomainSnapshot.shared
    }

    private var filteredApps: [AppInfo] {
        let apps = snapshot.appEntries
        guard !searchText.isEmpty else {
            return apps
        }
        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText)
                || app.domains.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var filteredDomains: [String] {
        let domains = snapshot.domains
        guard !searchText.isEmpty else {
            return domains
        }
        return domains.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var addButtonDisabled: Bool {
        newDomainsForSelection.isEmpty
    }

    private var selectedDomains: [String] {
        guard let selectedItem else {
            return []
        }
        switch selectedItem {
        case let .app(name):
            return snapshot.domains(forApp: name)
        case let .domain(domain):
            return [domain]
        }
    }

    private var newDomainsForSelection: [String] {
        var seen = Set(
            existingRules
                .filter { $0.listType == listType }
                .map { $0.domain.lowercased() }
        )
        return selectedDomains.filter { seen.insert($0.lowercased()).inserted }
    }

    private var duplicateCount: Int {
        selectedDomains.count - newDomainsForSelection.count
    }

    private var overlapCount: Int {
        let oppositeDomains = Set(
            existingRules
                .filter { $0.listType != listType }
                .map { $0.domain.lowercased() }
        )
        return newDomainsForSelection.count { oppositeDomains.contains($0.lowercased()) }
    }

    private var hasObservedTraffic: Bool {
        !snapshot.appEntries.isEmpty || !snapshot.domains.isEmpty
    }

    private var hasFilteredResults: Bool {
        !filteredApps.isEmpty || !filteredDomains.isEmpty
    }

    private var addButtonTitle: String {
        let count = newDomainsForSelection.count
        return count > 1
            ? String(localized: "Add \(count)", bundle: RockxyLocalization.bundle)
            : String(localized: "Add", bundle: RockxyLocalization.bundle)
    }

    private var selectionSummary: String {
        guard selectedItem != nil else {
            return String(
                localized: "Choose an app or host to preview what will be added.",
                bundle: RockxyLocalization.bundle
            )
        }
        let newCount = newDomainsForSelection.count
        var parts = [String(localized: "\(newCount) new", bundle: RockxyLocalization.bundle)]
        if duplicateCount > 0 {
            parts.append(String(AttributedString(
                localized: "^[\(duplicateCount) duplicate](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters))
        }
        if overlapCount > 0 {
            parts.append(
                String(AttributedString(
                    localized: "^[\(overlapCount) overlap](inflect: true); Tunnel Without Decryption takes priority",
                    bundle: RockxyLocalization.bundle,
                    locale: RockxyLocalization.locale
                ).characters)
            )
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "Add Observed Domains", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))
            Text(
                String(
                    localized:
                    "Choosing an app adds the hosts it has contacted so far. Rules apply to those hosts for every client.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var behaviorSection: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "Behavior", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
            Picker("", selection: $listType) {
                Text(SSLProxyingListViewModel.behaviorLabel(for: .include))
                    .tag(SSLProxyingListType.include)
                Text(SSLProxyingListViewModel.behaviorLabel(for: .exclude))
                    .tag(SSLProxyingListType.exclude)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel(String(localized: "Rule behavior", bundle: RockxyLocalization.bundle))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var searchSection: some View {
        HStack {
            TextField(
                String(localized: "Search app or domain", bundle: RockxyLocalization.bundle),
                text: $searchText,
                prompt: Text(String(localized: "Search app or domain", bundle: RockxyLocalization.bundle))
            )
            .textFieldStyle(.roundedBorder)
            .font(toolMetrics.font())
            .frame(minHeight: toolMetrics.formControlHeight)
            .focused($isSearchFocused)
            .onAppear { isSearchFocused = true }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var listSection: some View {
        List(selection: $selectedItem) {
            appsSection
            domainsSection
        }
        .listStyle(.sidebar)
        .overlay {
            if !hasFilteredResults {
                ContentUnavailableView(
                    hasObservedTraffic
                        ? String(localized: "No Matching Observed Hosts", bundle: RockxyLocalization.bundle)
                        : String(localized: "No Observed Hosts Yet", bundle: RockxyLocalization.bundle),
                    systemImage: hasObservedTraffic ? "magnifyingglass" : "network.slash",
                    description: Text(
                        hasObservedTraffic
                            ? String(
                                localized: "Try a different app or host search.",
                                bundle: RockxyLocalization.bundle
                            )
                            : String(
                                localized: "Capture traffic from an app or website, then return here.",
                                bundle: RockxyLocalization.bundle
                            )
                    )
                )
            }
        }
    }

    private var appsSection: some View {
        Section {
            ForEach(filteredApps) { app in
                DisclosureGroup {
                    ForEach(app.domains, id: \.self) { domain in
                        domainRow(domain)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "app.fill")
                            .font(toolMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                        Text(app.name)
                            .font(toolMetrics.secondaryFont())
                            .lineLimit(1)
                    }
                    .tag(PickerItem.app(app.name))
                }
            }
        } header: {
            sectionHeader(
                String(localized: "Apps", bundle: RockxyLocalization.bundle),
                systemImage: "square.grid.2x2",
                count: filteredApps.count
            )
        }
    }

    private var domainsSection: some View {
        Section {
            ForEach(filteredDomains, id: \.self) { domain in
                domainRow(domain)
            }
        } header: {
            sectionHeader(
                String(localized: "Domains", bundle: RockxyLocalization.bundle),
                systemImage: "globe",
                count: filteredDomains.count
            )
        }
    }

    private var footerHint: some View {
        HStack {
            Spacer()
            Text(selectionSummary)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(overlapCount > 0 ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var buttonBar: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Button {
                dismiss()
            } label: {
                footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                addSelectedItem()
            } label: {
                footerButtonLabel(addButtonTitle)
            }
            .keyboardShortcut(.defaultAction)
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(addButtonDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func domainRow(_ domain: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.tertiary)
            Text(domain)
                .font(toolMetrics.secondaryFont())
                .lineLimit(1)
        }
        .tag(PickerItem.domain(domain))
    }

    private func sectionHeader(_ title: String, systemImage: String, count: Int) -> some View {
        HStack {
            Image(systemName: systemImage)
                .font(toolMetrics.secondaryFont())
            Text(title)
                .font(toolMetrics.secondaryFont(weight: .semibold))
            Spacer()
            Text(CountFormatter.format(count))
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary)
                .clipShape(Capsule())
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(width: max(80, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 2))
    }

    private func addSelectedItem() {
        add(newDomainsForSelection)
    }

    private func add(_ domains: [String]) {
        guard !domains.isEmpty else {
            return
        }
        onAdd(domains, listType)
        dismiss()
    }

    private func reconcileSelection() {
        guard let selectedItem else {
            return
        }
        let isVisible: Bool = switch selectedItem {
        case let .app(name):
            filteredApps.contains { $0.name == name }
        case let .domain(domain):
            filteredDomains.contains(domain)
                || filteredApps.contains { $0.domains.contains(domain) }
        }
        if !isVisible {
            self.selectedItem = nil
        }
    }
}
