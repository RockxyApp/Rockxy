import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AddSSLAppDomainSheet

/// Panel for browsing observed apps and domains from captured traffic,
/// then adding selected items as SSL proxying rules.
///
/// - Apps section shows each app with its observed domains as expandable children.
///   Selecting an app and tapping Add adds all of that app's observed domains.
/// - Domains section shows all observed domains flat.
///   Selecting a domain and tapping Add adds that single domain.
///
/// Data comes from `TrafficDomainSnapshot`, populated by `MainContentCoordinator`
/// on each traffic batch. No fake/guessed domains are generated.
struct AddSSLAppDomainSheet: View {
    // MARK: Lifecycle

    init(onAdd: @escaping ([String]) -> Void) {
        self.onAdd = onAdd
    }

    // MARK: Internal

    let onAdd: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            searchSection
            Divider()
            listSection
            footerHint
            Divider()
            buttonBar
        }
        .font(toolMetrics.font())
        .frame(width: max(500, toolMetrics.fieldWidth(500)), height: max(520, toolMetrics.bodyFontSize * 28 + 156))
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
        guard let selected = selectedItem else {
            return true
        }
        if case let .app(name) = selected {
            return snapshot.domains(forApp: name).isEmpty
        }
        return false
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Text(String(localized: "Add favorite app or domain"))
                .font(toolMetrics.font(weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var searchSection: some View {
        HStack {
            TextField(
                String(localized: "Search app or domain"),
                text: $searchText,
                prompt: Text(String(localized: "Search app or domain (⌘⇧F)"))
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
    }

    private var appsSection: some View {
        Section {
            ForEach(filteredApps) { app in
                DisclosureGroup {
                    ForEach(app.domains, id: \.self) { domain in
                        HStack(spacing: 8) {
                            Image(systemName: "circle.slash")
                                .font(toolMetrics.secondaryFont())
                                .foregroundStyle(.tertiary)
                            Text(domain)
                                .font(toolMetrics.secondaryFont())
                                .lineLimit(1)
                        }
                        .tag(PickerItem.domain(domain))
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
            HStack {
                Image(systemName: "folder.fill")
                    .font(toolMetrics.secondaryFont())
                Text(String(localized: "Apps"))
                    .font(toolMetrics.secondaryFont(weight: .semibold))
                Spacer()
                Text("\(filteredApps.count)")
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
    }

    private var domainsSection: some View {
        Section {
            ForEach(filteredDomains, id: \.self) { domain in
                HStack(spacing: 8) {
                    Image(systemName: "circle.slash")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.tertiary)
                    Text(domain)
                        .font(toolMetrics.secondaryFont())
                        .lineLimit(1)
                }
                .tag(PickerItem.domain(domain))
            }
        } header: {
            HStack {
                Image(systemName: "globe")
                    .font(toolMetrics.secondaryFont())
                Text(String(localized: "Domains"))
                    .font(toolMetrics.secondaryFont(weight: .semibold))
                Spacer()
                Text("\(filteredDomains.count)")
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
    }

    private var footerHint: some View {
        HStack {
            Spacer()
            Text(String(localized: "Launch your app/domain to see it in the list"))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var buttonBar: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Menu {
                Button(String(localized: "App…")) {
                    selectAllDomainsForFirstApp()
                }
                Button(String(localized: "Domain…")) {
                    selectFirstDomain()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "Select"))
                    Image(systemName: "chevron.down")
                        .font(toolMetrics.metadataFont())
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(String(localized: "Add")) {
                addSelectedItem()
            }
            .disabled(addButtonDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func selectAllDomainsForFirstApp() {
        if let first = filteredApps.first {
            selectedItem = .app(first.name)
        }
    }

    private func selectFirstDomain() {
        if let first = filteredDomains.first {
            selectedItem = .domain(first)
        }
    }

    private func addSelectedItem() {
        guard let selected = selectedItem else {
            return
        }
        switch selected {
        case let .app(name):
            let appDomains = snapshot.domains(forApp: name)
            guard !appDomains.isEmpty else {
                return
            }
            onAdd(appDomains)
            dismiss()
        case let .domain(domain):
            onAdd([domain])
            dismiss()
        }
    }
}
