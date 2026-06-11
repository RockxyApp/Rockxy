import SwiftUI

// Sheet presented from the sidebar to pin an app or domain as a favorite.
// Lists all apps and domains discovered from captured traffic, with search filtering.

// MARK: - AddFavoriteView

struct AddFavoriteView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Add favorite app or domain"))
                .font(.system(size: metrics.sidebarNavigationFontSize, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            searchField
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Divider()

            itemList
                .frame(minHeight: 300, maxHeight: 400)

            Divider()

            Text(String(localized: "Launch your app/domain to see it in the list"))
                .font(.system(size: metrics.sidebarSecondaryFontSize))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            bottomButtons
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 420)
    }

    // MARK: Private

    @State private var searchText = ""
    @State private var selectedItem: FavoriteCandidate?

    @State private var isAppsExpanded = true
    @State private var isDomainsExpanded = true
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var filteredApps: [AppCandidate] {
        let apps = buildAppCandidates()
        if searchText.isEmpty {
            return apps
        }
        let query = searchText.lowercased()
        return apps.filter { $0.name.lowercased().contains(query) }
    }

    private var filteredDomains: [DomainNode] {
        let domains = coordinator.domainTree
        if searchText.isEmpty {
            return domains
        }
        let query = searchText.lowercased()
        return domains.filter { $0.domain.lowercased().contains(query) }
    }

    private var isAddDisabledByQuota: Bool {
        guard let item = selectedItem else {
            return false
        }
        if case .domain = item {
            return coordinator.domainFavoriteCount >= coordinator.policy.maxDomainFavorites
        }
        return false
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: metrics.sidebarSecondaryFontSize))
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "Search app or domain (\u{2318}\u{21E7}F)"),
                text: $searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: metrics.sidebarNavigationFontSize))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: metrics.sidebarBadgeFontSize))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                appsDisclosure
                domainsDisclosure
            }
        }
    }

    private var appsDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosureHeader(
                label: String(localized: "Apps"),
                icon: "square.stack.3d.up.fill",
                count: filteredApps.count,
                isExpanded: $isAppsExpanded
            )

            if isAppsExpanded {
                ForEach(filteredApps) { app in
                    appRow(app)
                }
            }
        }
    }

    private var domainsDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosureHeader(
                label: String(localized: "Domains"),
                icon: "globe",
                count: filteredDomains.count,
                isExpanded: $isDomainsExpanded
            )

            if isDomainsExpanded {
                ForEach(filteredDomains) { node in
                    domainRow(node)
                }
            }
        }
    }

    private var bottomButtons: some View {
        HStack {
            Button(String(localized: "Cancel")) {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Menu {
                Button(String(localized: "Select All")) {
                    // Future: select all items
                }
                Button(String(localized: "Deselect All")) {
                    selectedItem = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "Select"))
                    Image(systemName: "chevron.down")
                        .font(.system(size: metrics.sidebarSectionHeaderFontSize))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(String(localized: "Add")) {
                addSelectedFavorite()
                isPresented = false
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedItem == nil || isAddDisabledByQuota)
        }
    }

    private func disclosureHeader(
        label: String,
        icon: String,
        count: Int,
        isExpanded: Binding<Bool>
    )
        -> some View
    {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: metrics.sidebarSectionHeaderFontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: icon)
                    .font(.system(size: metrics.sidebarSecondaryFontSize))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: metrics.sidebarNavigationFontSize, weight: .medium))
                Spacer()
                Text("\(count)")
                    .font(.system(size: metrics.sidebarSecondaryFontSize).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func appRow(_ app: AppCandidate) -> some View {
        let isSelected = selectedItem == .app(app.name)
        return Button {
            selectedItem = .app(app.name)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: metrics.sidebarSectionHeaderFontSize))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                AppIconView(name: app.name)
                Text(app.name)
                    .font(.system(size: metrics.sidebarNavigationFontSize))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.leading, 12)
            .padding(.vertical, 4)
            .frame(minHeight: metrics.sidebarRowHeight)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func domainRow(_ node: DomainNode) -> some View {
        let isSelected = selectedItem == .domain(node.domain)
        return Button {
            selectedItem = .domain(node.domain)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: metrics.sidebarSectionHeaderFontSize))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                Image(systemName: "globe")
                    .font(.system(size: metrics.sidebarSecondaryFontSize))
                    .foregroundStyle(.secondary)
                Text(node.domain)
                    .font(.system(size: metrics.sidebarNavigationFontSize))
                    .lineLimit(1)
                Spacer()
                if node.requestCount > 0 {
                    Text("\(node.requestCount)")
                        .font(.system(size: metrics.sidebarSecondaryFontSize).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.leading, 12)
            .padding(.vertical, 4)
            .frame(minHeight: metrics.sidebarRowHeight)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addSelectedFavorite() {
        guard let item = selectedItem else {
            return
        }
        switch item {
        case let .app(name):
            coordinator.addFavorite(.app(name: name, bundleId: nil))
        case let .domain(domain):
            coordinator.addFavorite(.domainNode(domain: domain))
        }
    }

    private func buildAppCandidates() -> [AppCandidate] {
        var appNames: Set<String> = []
        for transaction in coordinator.transactions {
            let name = transaction.clientApp ?? String(localized: "Unknown")
            appNames.insert(name)
        }
        return appNames.sorted().map { AppCandidate(name: $0) }
    }
}

// MARK: - FavoriteCandidate

/// Represents the user's selection in the add-favorite sheet before committing.
private enum FavoriteCandidate: Equatable {
    case app(String)
    case domain(String)
}

// MARK: - AppCandidate

private struct AppCandidate: Identifiable {
    let name: String

    var id: String {
        name
    }
}

// MARK: - AppIconView

private struct AppIconView: View {
    // MARK: Internal

    let name: String

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(gradient)
            .frame(width: iconSize, height: iconSize)
            .overlay {
                Text(letter)
                    .font(.system(size: max(11, metrics.sidebarSecondaryFontSize), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var iconSize: CGFloat {
        metrics.sidebarAppIconSize
    }

    private var letter: String {
        String(name.prefix(1)).uppercased()
    }

    private var gradient: LinearGradient {
        let colors = Theme.Sidebar.appIconGradient(for: name)
        return LinearGradient(
            colors: [colors.0, colors.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
