import os
import SwiftUI

// Sidebar navigation for the main window, organized into Favorites, All (apps + domains),
// and Analytics sections. Drives content filtering via `MainContentCoordinator` selection.

// MARK: - AppIconView

/// Renders an app icon: real NSWorkspace icon if available, otherwise a gradient monogram fallback.
private struct AppIconView: View {
    // MARK: Internal

    let name: String

    var body: some View {
        if let icon = Self.resolveIcon(for: name) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(gradient)
                .frame(width: 20, height: 20)
                .overlay {
                    Text(letter)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
        }
    }

    // MARK: Private

    private static var iconCache: [String: NSImage] = [:]

    private static let bundleIDMap: [String: String] = [
        "Chrome": "com.google.Chrome",
        "Safari": "com.apple.Safari",
        "Firefox": "org.mozilla.firefox",
        "Slack": "com.tinyspeck.slackmacgap",
        "Xcode": "com.apple.dt.Xcode",
        "Spotify": "com.spotify.client",
        "Discord": "com.hnc.Discord",
        "Arc": "company.thebrowser.Browser",
        "Brave Browser": "com.brave.Browser",
        "Microsoft Edge": "com.microsoft.edgemac",
        "Figma": "com.figma.Desktop",
        "Postman": "com.postmanlabs.mac",
    ]

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

    private static func resolveIcon(for name: String) -> NSImage? {
        if let cached = iconCache[name] {
            return cached
        }

        if let bundleID = bundleIDMap[name],
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 20, height: 20)
            iconCache[name] = icon
            return icon
        }

        for path in ["/Applications/\(name).app", "/System/Applications/\(name).app"] {
            if FileManager.default.fileExists(atPath: path) {
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 20, height: 20)
                iconCache[name] = icon
                return icon
            }
        }

        for app in NSWorkspace.shared.runningApplications {
            if app.localizedName == name, let icon = app.icon {
                icon.size = NSSize(width: 20, height: 20)
                iconCache[name] = icon
                return icon
            }
        }

        return nil
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            List(selection: sidebarBinding) {
                favoritesSection
                allSection
            }
            .listStyle(.sidebar)

            SidebarBottomBar(
                filterText: $sidebarFilterText,
                isAddFavoritePresented: $isAddFavoritePresented
            )
        }
        .sheet(isPresented: $isAddFavoritePresented) {
            AddFavoriteView(
                coordinator: coordinator,
                isPresented: $isAddFavoritePresented
            )
        }
        .background(
            // Keep the sidebar invalidated when SSL proxying presentation changes.
            EmptyView().id(coordinator.sslProxyingRefreshToken)
        )
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "SidebarView")

    // MARK: Private — State

    @State private var sidebarFilterText = ""
    @State private var isAddFavoritePresented = false
    @State private var expandedDomainNodeIDs: Set<String> = []

    private var sidebarBinding: Binding<SidebarItem?> {
        Binding(
            get: { coordinator.sidebarSelection },
            set: { coordinator.selectSidebarItem($0) }
        )
    }

    private var appNodes: [AppInfo] {
        coordinator.appNodes
    }

    private var totalDomainCount: Int {
        coordinator.domainTree.reduce(0) { $0 + $1.requestCount }
    }

    // MARK: - Sections

    private var favoritesSection: some View {
        Section {
            DisclosureGroup {
                let pinned = coordinator.allPinnedTransactions
                if pinned.isEmpty {
                    Text(String(localized: "No pinned items"))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(pinned) { transaction in
                        Label {
                            Text(transaction.request.host + transaction.request.path)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "pin.fill")
                                .foregroundStyle(.orange)
                        }
                        .tag(SidebarItem.pinnedTransaction(id: transaction.id))
                    }
                }
            } label: {
                Label(String(localized: "Pinned"), systemImage: "pin.fill")
                    .badge(coordinator.allPinnedTransactions.count)
                    .tag(SidebarItem.allPinned)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.selectSidebarItem(.allPinned) }
            }

            DisclosureGroup {
                let saved = coordinator.allSavedTransactions
                if saved.isEmpty {
                    Text(String(localized: "No saved items"))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(saved) { transaction in
                        Label {
                            Text(transaction.request.host + transaction.request.path)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "tray.full.fill")
                        }
                        .tag(SidebarItem.savedTransaction(id: transaction.id))
                    }
                }
            } label: {
                Label(String(localized: "Saved"), systemImage: "tray.full.fill")
                    .badge(coordinator.allSavedTransactions.count)
                    .tag(SidebarItem.allSaved)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.selectSidebarItem(.allSaved) }
            }

            ForEach(coordinator.favorites, id: \.self) { item in
                favoriteRow(item)
            }
        } header: {
            Text(String(localized: "Favorites"))
                .foregroundStyle(Theme.Sidebar.favoritesHeader)
        }
        .headerProminence(.increased)
    }

    private var allSection: some View {
        Section {
            DisclosureGroup {
                ForEach(appNodes) { app in
                    DisclosureGroup {
                        ForEach(app.domains, id: \.self) { domain in
                            domainLabel(domain, requestCount: 0)
                        }
                    } label: {
                        Label {
                            Text(app.name)
                        } icon: {
                            AppIconView(name: app.name)
                        }
                        .badge(app.requestCount)
                        .tag(SidebarItem.app(name: app.name, bundleId: nil))
                        .contextMenu { appContextMenu(app) }
                    }
                }
            } label: {
                Label(String(localized: "Apps"), systemImage: "square.stack.3d.up.fill")
                    .badge(appNodes.count)
                    .tag(SidebarItem.allApps)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.selectSidebarItem(.allApps) }
            }

            DisclosureGroup {
                ForEach(coordinator.domainTree) { node in
                    domainRow(node)
                }
            } label: {
                Label(String(localized: "Domains"), systemImage: "globe")
                    .badge(totalDomainCount)
                    .tag(SidebarItem.allDomains)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.selectSidebarItem(.allDomains) }
            }
        } header: {
            Text(String(localized: "All"))
                .foregroundStyle(Theme.Sidebar.sectionHeader)
        }
        .headerProminence(.increased)
    }

    @ViewBuilder
    private func favoriteRow(_ item: SidebarItem) -> some View {
        switch item {
        case let .domainNode(domain):
            Label {
                HStack(spacing: 4) {
                    Text(domain)
                    if coordinator.isSSLProxyingEnabled(for: domain) {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            } icon: {
                Image(systemName: "globe")
            }
            .tag(item)
            .contextMenu { domainContextMenu(domain) }
        case let .domainPath(domain, pathPrefix):
            Label {
                Text("\(domain)\(pathPrefix)")
                    .lineLimit(1)
            } icon: {
                Image(systemName: "link")
            }
            .tag(item)
            .contextMenu { domainContextMenu(domain, pathPrefix: pathPrefix) }
        case let .app(name, _):
            Label {
                Text(name)
            } icon: {
                AppIconView(name: name)
            }
            .tag(item)
            .contextMenu {
                if let app = coordinator.appNodes.first(where: { $0.name == name }) {
                    appContextMenu(app)
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func domainRow(_ node: DomainNode) -> AnyView {
        if node.children.isEmpty {
            return AnyView(domainLabel(node))
        } else {
            return AnyView(
                DisclosureGroup(isExpanded: domainExpansionBinding(for: node.id)) {
                    ForEach(node.children) { child in
                        domainRow(child)
                    }
                } label: {
                    domainLabel(node)
                }
            )
        }
    }

    private func domainLabel(_ domain: String, requestCount: Int) -> some View {
        domainLabel(
            DomainNode(
                id: domain,
                domain: domain,
                requestCount: requestCount,
                children: [],
                filterDomain: domain
            )
        )
    }

    private func domainLabel(_ node: DomainNode) -> some View {
        Label {
            HStack(spacing: 5) {
                Text(node.domain)
                    .foregroundStyle(node.kind == .path ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if coordinator.isSSLProxyingEnabled(for: node.selectionDomain), node.kind != .path {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                if node.errorCount > 0 {
                    Label("\(node.errorCount)", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help(String(localized: "\(node.errorCount) failed or error responses"))
                }
            }
        } icon: {
            Image(systemName: domainIconName(for: node.kind))
                .foregroundStyle(node.kind == .path ? .secondary : .primary)
        }
        .badge(node.requestCount)
        .tag(sidebarItem(for: node))
        .contextMenu { domainContextMenu(node.selectionDomain, pathPrefix: node.pathPrefix) }
        .help(domainHelpText(for: node))
    }

    private func domainExpansionBinding(for nodeID: String) -> Binding<Bool> {
        Binding {
            expandedDomainNodeIDs.contains(nodeID)
        } set: { isExpanded in
            if isExpanded {
                expandedDomainNodeIDs.insert(nodeID)
            } else {
                expandedDomainNodeIDs.remove(nodeID)
            }
        }
    }

    private func sidebarItem(for node: DomainNode) -> SidebarItem {
        if let pathPrefix = node.pathPrefix {
            return .domainPath(domain: node.selectionDomain, pathPrefix: pathPrefix)
        }
        return .domainNode(domain: node.selectionDomain)
    }

    private func domainIconName(for kind: DomainNode.Kind) -> String {
        switch kind {
        case .domain:
            "globe"
        case .host:
            "network"
        case .path:
            "link"
        }
    }

    private func domainHelpText(for node: DomainNode) -> String {
        if let pathPrefix = node.pathPrefix {
            return "\(node.selectionDomain)\(pathPrefix)"
        }
        return node.selectionDomain
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func domainContextMenu(_ domain: String, pathPrefix: String? = nil) -> some View {
        let item = pathPrefix.map { SidebarItem.domainPath(domain: domain, pathPrefix: $0) }
            ?? SidebarItem.domainNode(domain: domain)
        let isPinned = coordinator.isFavorite(item)

        Button {
            coordinator.toggleSidebarFavorite(item)
        } label: {
            Label(
                isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                systemImage: isPinned ? "pin.slash" : "pin"
            )
        }

        Button {
            guard coordinator.workspaceStore.canCreateWorkspace else {
                return
            }
            var filter = FilterCriteria.empty
            filter.sidebarDomain = domain
            filter.sidebarPathPrefix = pathPrefix
            let title = pathPrefix.map { "\(domain)\($0)" } ?? domain
            let ws = coordinator.workspaceStore.createWorkspace(title: title, filter: filter)
            RockxyWorkspaceWindowManager.shared.openWorkspaceTab(coordinator: coordinator, workspaceID: ws.id)
            RockxyWorkspaceWindowManager.shared.prepareWorkspaceContent(ws, coordinator: coordinator)
        } label: {
            Label(String(localized: "Open in New Tab"), systemImage: "plus.rectangle.on.rectangle")
        }
        .disabled(!coordinator.workspaceStore.canCreateWorkspace)

        Divider()

        if coordinator.isSSLProxyingEnabled(for: domain) {
            Button {
                coordinator.disableSSLProxyingForDomain(domain)
            } label: {
                Label(String(localized: "Disable SSL Proxying"), systemImage: "lock.shield")
            }
        } else {
            Button {
                coordinator.enableSSLProxyingForDomain(domain)
            } label: {
                Label(String(localized: "Enable SSL Proxying"), systemImage: "lock.shield")
            }
        }

        if coordinator.isInBypassList(domain) {
            Button {
                coordinator.removeFromBypassList(domain)
            } label: {
                Label(String(localized: "Remove from Bypass Proxy List"), systemImage: "arrow.uturn.right")
            }
        } else {
            Button {
                coordinator.addToBypassList(domain)
            } label: {
                Label(String(localized: "Add to Bypass Proxy List"), systemImage: "arrow.uturn.right")
            }
        }

        Button {
            coordinator.sortDomainTreeAlphabetically()
        } label: {
            Label(String(localized: "Sort by Alphabet"), systemImage: "textformat.abc")
        }

        Divider()

        Menu {
            Button {
                coordinator.createBreakpointRuleForDomain(domain)
            } label: {
                Label(String(localized: "Breakpoint"), systemImage: "pause.circle")
            }

            Divider()

            Button {
                coordinator.createMapLocalRuleForDomain(domain)
            } label: {
                Label(String(localized: "Map Local"), systemImage: "doc")
            }
            Button {
                coordinator.createMapRemoteRuleForDomain(domain)
            } label: {
                Label(String(localized: "Map Remote"), systemImage: "arrow.triangle.swap")
            }

            Divider()

            Button {
                coordinator.createBlockRuleForDomain(domain)
            } label: {
                Label(String(localized: "Block"), systemImage: "nosign")
            }
            Button {
                coordinator.createAllowListRuleForDomain(domain)
            } label: {
                Label(
                    String(localized: "Create Allow List Rule…"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }

            Divider()

            Button {
                coordinator.createNetworkConditionsRuleForDomain(domain)
            } label: {
                Label(String(localized: "Network Conditions"), systemImage: "wifi.exclamationmark")
            }
        } label: {
            Label(String(localized: "Tools"), systemImage: "wrench")
        }

        Menu {
            Button {
                coordinator.copyDomainToClipboard(pathPrefix.map { "\(domain)\($0)" } ?? domain)
            } label: {
                Label(
                    pathPrefix == nil ? String(localized: "Copy Domain") : String(localized: "Copy Path Filter"),
                    systemImage: "doc.on.doc"
                )
            }
            Button {
                coordinator.exportTransactionsForDomain(domain, pathPrefix: pathPrefix)
            } label: {
                Label(String(localized: "Export Transactions"), systemImage: "square.and.arrow.up")
            }
        } label: {
            Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            coordinator.removeDomainFromSidebar(domain, pathPrefix: pathPrefix)
        } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
        }
    }

    @ViewBuilder
    private func appContextMenu(_ app: AppInfo) -> some View {
        let item = SidebarItem.app(name: app.name, bundleId: nil)
        let isPinned = coordinator.isFavorite(item)
        let isSSLProxyingEnabledForApp = coordinator.isSSLProxyingFullyEnabled(forAppNamed: app.name)

        Button {
            coordinator.toggleSidebarFavorite(item)
        } label: {
            Label(
                isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                systemImage: isPinned ? "pin.slash" : "pin"
            )
        }

        Button {
            guard coordinator.workspaceStore.canCreateWorkspace else {
                return
            }
            var filter = FilterCriteria.empty
            filter.sidebarApp = app.name
            let ws = coordinator.workspaceStore.createWorkspace(title: app.name, filter: filter)
            RockxyWorkspaceWindowManager.shared.openWorkspaceTab(coordinator: coordinator, workspaceID: ws.id)
            RockxyWorkspaceWindowManager.shared.prepareWorkspaceContent(ws, coordinator: coordinator)
        } label: {
            Label(String(localized: "Open in New Tab"), systemImage: "plus.rectangle.on.rectangle")
        }
        .disabled(!coordinator.workspaceStore.canCreateWorkspace)

        Divider()

        if isSSLProxyingEnabledForApp {
            Button {
                coordinator.disableSSLProxyingForApp(app)
            } label: {
                Label(String(localized: "Disable SSL Proxying"), systemImage: "lock.shield")
            }
        } else {
            Button {
                coordinator.enableSSLProxyingForApp(app)
            } label: {
                Label(String(localized: "Enable SSL Proxying"), systemImage: "lock.shield")
            }
        }

        Button {
            coordinator.sortAppNodesAlphabetically()
        } label: {
            Label(String(localized: "Sort by Alphabet"), systemImage: "textformat.abc")
        }

        Divider()

        Menu {
            Button {
                coordinator.copyDomainToClipboard(app.name)
            } label: {
                Label(String(localized: "Copy App Name"), systemImage: "doc.on.doc")
            }
            Button {
                coordinator.exportTransactionsForApp(app.name)
            } label: {
                Label(String(localized: "Export Transactions"), systemImage: "square.and.arrow.up")
            }
        } label: {
            Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            coordinator.removeAppFromSidebar(app.name)
        } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
        }
    }
}
