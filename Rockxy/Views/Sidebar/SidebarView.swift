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
        if let icon = Self.resolvedIcon(for: name, size: iconSize) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(gradient)
                .frame(width: iconSize, height: iconSize)
                .overlay {
                    Text(letter)
                        .font(.system(size: max(11, metrics.sidebarSecondaryFontSize), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
        }
    }

    // MARK: Private

    private struct IconCacheKey: Hashable {
        let name: String
        let size: Int
    }

    private static var iconCache: [String: NSImage] = [:]
    private static var resizedIconCache: [IconCacheKey: NSImage] = [:]
    private static var missingIconNames: Set<String> = []

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

    private static func resolvedIcon(for name: String, size: CGFloat) -> NSImage? {
        let cacheKey = IconCacheKey(name: name, size: Int(size.rounded()))
        if let cached = resizedIconCache[cacheKey] {
            return cached
        }
        guard let source = resolveIconSource(for: name),
              let icon = source.copy() as? NSImage else
        {
            return nil
        }
        icon.size = NSSize(width: size, height: size)
        resizedIconCache[cacheKey] = icon
        return icon
    }

    private static func resolveIconSource(for name: String) -> NSImage? {
        guard !name.isEmpty,
              !missingIconNames.contains(name) else
        {
            return nil
        }
        if let cached = iconCache[name] {
            return cached
        }

        if let bundleID = bundleIDMap[name],
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            iconCache[name] = icon
            return icon
        }

        for path in ["/Applications/\(name).app", "/System/Applications/\(name).app"] {
            if FileManager.default.fileExists(atPath: path) {
                let icon = NSWorkspace.shared.icon(forFile: path)
                iconCache[name] = icon
                return icon
            }
        }

        for app in NSWorkspace.shared.runningApplications {
            if app.localizedName == name, let icon = app.icon {
                iconCache[name] = icon
                return icon
            }
        }

        missingIconNames.insert(name)
        return nil
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        navigatorChrome
            .sheet(isPresented: $isAddFavoritePresented) {
                AddFavoriteView(
                    coordinator: coordinator,
                    isPresented: $isAddFavoritePresented
                )
            }
            .sheet(item: $editingFocusSet) { focusSet in
                FocusSetEditorSheet(
                    initialValue: focusSet,
                    transactions: coordinator.transactions,
                    isCreating: !coordinator.activeWorkspace.focusSets.contains { $0.id == focusSet.id },
                    onSave: saveFocusSetFromSidebar
                )
            }
            .sheet(isPresented: $isMutedSourcesPresented) {
                NoiseControlManagerSheet(coordinator: coordinator)
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
    @State private var editingFocusSet: FocusSet?
    @State private var isMutedSourcesPresented = false
    @State private var expandedFocusSetIDs: Set<UUID> = []
    @State private var isAppsExpanded = SidebarDisclosureDefaults.appsExpanded
    @State private var isDomainsExpanded = SidebarDisclosureDefaults.domainsExpanded
    @State private var isPinnedExpanded = false
    @State private var isSavedExpanded = false
    @State private var isNotesExpanded = false
    @State private var expandedAppNames: Set<String> = []
    @State private var expandedDomainNodeIDs: Set<String> = []
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var sidebarBinding: Binding<SidebarItem?> {
        Binding(
            get: { coordinator.sidebarSelection },
            set: { coordinator.selectSidebarItem($0) }
        )
    }

    private var navigatorModeBinding: Binding<FocusNavigatorMode> {
        Binding(
            get: { coordinator.focusNavigatorMode },
            set: { coordinator.focusNavigatorMode = $0 }
        )
    }

    private var appNodes: [AppInfo] {
        SidebarSearchFilter.apps(coordinator.appNodes, query: sidebarFilterText)
    }

    private var domainTree: [DomainNode] {
        SidebarSearchFilter.domainTree(coordinator.domainTree, query: sidebarFilterText)
    }

    private var pinnedTransactions: [HTTPTransaction] {
        SidebarSearchFilter.transactions(coordinator.allPinnedTransactions, query: sidebarFilterText)
    }

    private var savedTransactions: [HTTPTransaction] {
        SidebarSearchFilter.transactions(coordinator.allSavedTransactions, query: sidebarFilterText)
    }

    private var notesTransactions: [HTTPTransaction] {
        SidebarSearchFilter.transactions(coordinator.allNotesTransactions, query: sidebarFilterText)
    }

    private var filteredFavorites: [SidebarItem] {
        SidebarSearchFilter.favorites(coordinator.favorites, query: sidebarFilterText)
    }

    private var visibleSignals: [TrafficSignal] {
        SidebarSearchFilter.trafficSignals(TrafficSignal.allCases, query: sidebarFilterText)
    }

    private var sidebarNavigationFont: Font {
        .system(size: metrics.sidebarNavigationFontSize)
    }

    private var sidebarIconFont: Font {
        .system(size: metrics.sidebarIconFontSize)
    }

    @ViewBuilder private var navigatorChrome: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            navigatorList
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .safeAreaBar(edge: .top, spacing: 0) {
                    navigatorPicker
                }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    sidebarBottomBar
                }
        } else {
            legacyNavigatorChrome
        }
        #else
        legacyNavigatorChrome
        #endif
    }

    private var legacyNavigatorChrome: some View {
        VStack(spacing: 0) {
            navigatorPicker
            Divider()
            navigatorList
            Divider()
            sidebarBottomBar
        }
    }

    private var navigatorPicker: some View {
        WorkspaceModeSegmentedControl(
            selection: navigatorModeBinding,
            segments: FocusNavigatorMode.allCases.map { mode in
                WorkspaceModeSegment(
                    value: mode,
                    title: mode.title,
                    systemImage: mode.systemImage
                )
            },
            accessibilityLabel: String(localized: "Navigator", bundle: RockxyLocalization.bundle)
        )
        .workspaceModeSwitcherStyle()
    }

    @ViewBuilder private var navigatorList: some View {
        switch coordinator.focusNavigatorMode {
        case .browse:
            browseList
        case .focus:
            FocusSidebarList(
                coordinator: coordinator,
                filterText: sidebarFilterText,
                editingFocusSet: $editingFocusSet,
                isMutedSourcesPresented: $isMutedSourcesPresented,
                expandedFocusSetIDs: $expandedFocusSetIDs
            )
        case .library:
            libraryList
        }
    }

    private var sidebarBottomBar: some View {
        SidebarBottomBar(
            filterText: $sidebarFilterText,
            isAddFavoritePresented: $isAddFavoritePresented
        )
    }

    // MARK: - Sections

    private var browseList: some View {
        List(selection: sidebarBinding) {
            SidebarInsightsSection(coordinator: coordinator)
            allSection
            signalsSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .font(.system(size: metrics.sidebarNavigationFontSize))
    }

    private var libraryList: some View {
        List(selection: sidebarBinding) {
            favoritesSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .font(.system(size: metrics.sidebarNavigationFontSize))
    }

    private var signalsSection: some View {
        Section {
            ForEach(visibleSignals) { signal in
                signalRow(signal)
            }
        } header: {
            Text(String(localized: "Signals", bundle: RockxyLocalization.bundle))
        } footer: {
            if let activeSignal = coordinator.activeWorkspace.activeTrafficSignal {
                Text(activeSignal.explanation)
                    .font(.system(size: metrics.sidebarSecondaryFontSize))
            }
        }
    }

    private var favoritesSection: some View {
        Section {
            DisclosureGroup(isExpanded: searchAwareExpansionBinding(for: $isPinnedExpanded)) {
                let pinned = pinnedTransactions
                if pinned.isEmpty {
                    Text(
                        SidebarSearchFilter.hasQuery(sidebarFilterText)
                            ? String(localized: "No matching pinned items", bundle: RockxyLocalization.bundle)
                            : String(localized: "No pinned items", bundle: RockxyLocalization.bundle)
                    )
                    .foregroundStyle(.secondary)
                    .font(.system(size: metrics.sidebarSecondaryFontSize))
                    .frame(minHeight: metrics.sidebarRowHeight, alignment: .center)
                } else {
                    ForEach(pinned) { transaction in
                        Label {
                            Text(transaction.request.host + transaction.request.path)
                                .font(sidebarNavigationFont)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "pin.fill")
                                .font(sidebarIconFont)
                                .foregroundStyle(.orange)
                        }
                        .font(sidebarNavigationFont)
                        .tag(SidebarItem.pinnedTransaction(id: transaction.id))
                        .frame(minHeight: metrics.sidebarRowHeight)
                        .contextMenu {
                            favoriteTransactionContextMenu(transaction, section: .pinned)
                        }
                    }
                }
            } label: {
                Label(String(localized: "Pinned", bundle: RockxyLocalization.bundle), systemImage: "pin.fill")
                    .badge(pinnedTransactions.count)
                    .tag(SidebarItem.allPinned)
                    .frame(minHeight: metrics.sidebarRowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.selectSidebarItem(.allPinned) }
            }

            DisclosureGroup(isExpanded: searchAwareExpansionBinding(for: $isSavedExpanded)) {
                let saved = savedTransactions
                if saved.isEmpty {
                    Text(
                        SidebarSearchFilter.hasQuery(sidebarFilterText)
                            ? String(localized: "No matching saved items", bundle: RockxyLocalization.bundle)
                            : String(localized: "No saved items", bundle: RockxyLocalization.bundle)
                    )
                    .foregroundStyle(.secondary)
                    .font(.system(size: metrics.sidebarSecondaryFontSize))
                    .frame(minHeight: metrics.sidebarRowHeight, alignment: .center)
                } else {
                    ForEach(saved) { transaction in
                        Label {
                            Text(transaction.request.host + transaction.request.path)
                                .font(sidebarNavigationFont)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "tray.full.fill")
                                .font(sidebarIconFont)
                        }
                        .font(sidebarNavigationFont)
                        .tag(SidebarItem.savedTransaction(id: transaction.id))
                        .frame(minHeight: metrics.sidebarRowHeight)
                        .contextMenu {
                            favoriteTransactionContextMenu(transaction, section: .saved)
                        }
                    }
                }
            } label: {
                Label(String(localized: "Saved", bundle: RockxyLocalization.bundle), systemImage: "tray.full.fill")
                    .badge(savedTransactions.count)
                    .tag(SidebarItem.allSaved)
                    .frame(minHeight: metrics.sidebarRowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.selectSidebarItem(.allSaved) }
            }

            DisclosureGroup(isExpanded: searchAwareExpansionBinding(for: $isNotesExpanded)) {
                let notes = notesTransactions
                if notes.isEmpty {
                    Text(
                        SidebarSearchFilter.hasQuery(sidebarFilterText)
                            ? String(localized: "No matching notes", bundle: RockxyLocalization.bundle)
                            : String(localized: "No notes", bundle: RockxyLocalization.bundle)
                    )
                    .foregroundStyle(.secondary)
                    .font(.system(size: metrics.sidebarSecondaryFontSize))
                    .frame(minHeight: metrics.sidebarRowHeight, alignment: .center)
                } else {
                    ForEach(notes) { transaction in
                        Label {
                            Text(transaction.request.host + transaction.request.path)
                                .font(sidebarNavigationFont)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "note.text")
                                .font(sidebarIconFont)
                        }
                        .font(sidebarNavigationFont)
                        .tag(SidebarItem.noteTransaction(id: transaction.id))
                        .frame(minHeight: metrics.sidebarRowHeight)
                        .contextMenu {
                            favoriteTransactionContextMenu(transaction, section: .notes)
                        }
                    }
                }
            } label: {
                Label(String(localized: "Notes", bundle: RockxyLocalization.bundle), systemImage: "note.text")
                    .badge(notesTransactions.count)
                    .tag(SidebarItem.allNotes)
                    .frame(minHeight: metrics.sidebarRowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.selectSidebarItem(.allNotes) }
            }

            ForEach(filteredFavorites, id: \.self) { item in
                favoriteRow(item)
            }
        } header: {
            Text(String(localized: "Favorites", bundle: RockxyLocalization.bundle))
                .foregroundStyle(Theme.Sidebar.favoritesHeader)
                .font(.system(size: metrics.sidebarSectionHeaderFontSize, weight: .semibold))
        }
        .headerProminence(.increased)
    }

    private var allSection: some View {
        Section {
            DisclosureGroup(isExpanded: searchAwareExpansionBinding(for: $isAppsExpanded)) {
                ForEach(appNodes) { app in
                    DisclosureGroup(isExpanded: appExpansionBinding(for: app.name)) {
                        ForEach(app.domains, id: \.self) { domain in
                            domainLabel(domain, requestCount: 0)
                        }
                    } label: {
                        Label {
                            Text(app.name)
                                .font(sidebarNavigationFont)
                        } icon: {
                            AppIconView(name: app.name)
                        }
                        .font(sidebarNavigationFont)
                        .badge(app.requestCount)
                        .tag(SidebarItem.app(name: app.name, bundleId: nil))
                        .frame(minHeight: metrics.sidebarRowHeight)
                        .contextMenu { appContextMenu(app) }
                    }
                }
            } label: {
                Label(
                    String(localized: "Apps", bundle: RockxyLocalization.bundle),
                    systemImage: "square.stack.3d.up.fill"
                )
                .badge(appNodes.count)
                .tag(SidebarItem.allApps)
                .frame(minHeight: metrics.sidebarRowHeight)
                .contentShape(Rectangle())
                .onTapGesture { coordinator.selectSidebarItem(.allApps) }
            }

            DisclosureGroup(isExpanded: searchAwareExpansionBinding(for: $isDomainsExpanded)) {
                ForEach(domainTree) { node in
                    domainRow(node)
                }
            } label: {
                Label(String(localized: "Domains", bundle: RockxyLocalization.bundle), systemImage: "globe")
                    .badge(
                        SidebarSearchFilter.hasQuery(sidebarFilterText)
                            ? SidebarSearchFilter.domainMatchCount(
                                coordinator.domainTree,
                                query: sidebarFilterText
                            )
                            : coordinator.totalDomainCount
                    )
                    .tag(SidebarItem.allDomains)
                    .frame(minHeight: metrics.sidebarRowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.selectSidebarItem(.allDomains) }
            }
        } header: {
            Text(String(localized: "All", bundle: RockxyLocalization.bundle))
                .foregroundStyle(Theme.Sidebar.sectionHeader)
                .font(.system(size: metrics.sidebarSectionHeaderFontSize, weight: .semibold))
        }
        .headerProminence(.increased)
    }

    private func signalRow(_ signal: TrafficSignal) -> some View {
        let isActive = coordinator.activeWorkspace.activeTrafficSignal == signal
        return Button {
            coordinator.toggleTrafficSignal(signal)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: signal.systemImage)
                    .frame(width: 16)
                Text(signal.title)
                Spacer(minLength: 8)
                Text(CountFormatter.format(coordinator.trafficSignalCount(signal)))
                    .font(.system(size: metrics.sidebarBadgeFontSize).monospacedDigit())
                    .foregroundStyle(.secondary)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: metrics.sidebarBadgeFontSize, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        .help(isActive
            ? String(localized: "Clear the \(signal.title) filter. \(signal.explanation)", bundle: RockxyLocalization.bundle)
            : String(localized: "Show \(signal.title) traffic. \(signal.explanation)", bundle: RockxyLocalization.bundle))
    }

    @ViewBuilder
    private func favoriteRow(_ item: SidebarItem) -> some View {
        switch item {
        case let .domainNode(domain):
            Label {
                HStack(spacing: 4) {
                    Text(domain)
                        .font(sidebarNavigationFont)
                    if coordinator.isSSLProxyingEnabled(for: domain) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: metrics.sidebarBadgeFontSize))
                            .foregroundStyle(.green)
                    }
                }
            } icon: {
                Image(systemName: "globe")
                    .font(sidebarIconFont)
            }
            .font(sidebarNavigationFont)
            .tag(item)
            .frame(minHeight: metrics.sidebarRowHeight)
            .contextMenu { domainContextMenu(domain) }
        case let .domainPath(domain, pathPrefix):
            Label {
                Text("\(domain)\(pathPrefix)")
                    .font(sidebarNavigationFont)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "link")
                    .font(sidebarIconFont)
            }
            .font(sidebarNavigationFont)
            .tag(item)
            .frame(minHeight: metrics.sidebarRowHeight)
            .contextMenu { domainContextMenu(domain, pathPrefix: pathPrefix) }
        case let .app(name, _):
            Label {
                Text(name)
                    .font(sidebarNavigationFont)
            } icon: {
                AppIconView(name: name)
            }
            .font(sidebarNavigationFont)
            .tag(item)
            .frame(minHeight: metrics.sidebarRowHeight)
            .contextMenu {
                if let app = coordinator.appNodes.first(where: { $0.name == name }) {
                    appContextMenu(app)
                }
            }
        default:
            EmptyView()
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
                    .font(sidebarNavigationFont)
                    .foregroundStyle(node.kind == .path ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if coordinator.isSSLProxyingEnabled(for: node.selectionDomain), node.kind != .path {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: metrics.sidebarBadgeFontSize))
                        .foregroundStyle(.green)
                }

                if node.errorCount > 0 {
                    Label(CountFormatter.format(node.errorCount), systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: metrics.sidebarBadgeFontSize))
                        .foregroundStyle(.orange)
                        .help(String(AttributedString(
                            localized: "^[\(node.errorCount) failed or error response](inflect: true)",
                            bundle: RockxyLocalization.bundle,
                            locale: RockxyLocalization.locale
                        ).characters))
                }
            }
        } icon: {
            Image(systemName: domainIconName(for: node.kind))
                .font(sidebarIconFont)
                .foregroundStyle(node.kind == .path ? .secondary : .primary)
        }
        .font(sidebarNavigationFont)
        .badge(node.requestCount)
        .tag(sidebarItem(for: node))
        .frame(minHeight: metrics.sidebarRowHeight)
        .contextMenu { domainContextMenu(node.selectionDomain, pathPrefix: node.pathPrefix) }
        .help(domainHelpText(for: node))
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
                isPinned ? String(localized: "Unpin", bundle: RockxyLocalization.bundle) : String(localized: "Pin", bundle: RockxyLocalization.bundle),
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
            Label(
                String(localized: "Open in New Tab", bundle: RockxyLocalization.bundle),
                systemImage: "plus.rectangle.on.rectangle"
            )
        }
        .disabled(!coordinator.workspaceStore.canCreateWorkspace)

        Divider()

        if coordinator.isSSLProxyingEnabled(for: domain) {
            Button {
                coordinator.disableSSLProxyingForDomain(domain)
            } label: {
                Label(
                    String(localized: "Tunnel This Host", bundle: RockxyLocalization.bundle),
                    systemImage: "lock.shield"
                )
            }
        } else {
            Button {
                coordinator.enableSSLProxyingForDomain(domain)
            } label: {
                Label(
                    String(localized: "Decrypt This Host", bundle: RockxyLocalization.bundle),
                    systemImage: "lock.shield"
                )
            }
            .disabled(coordinator.sslProxyingHostDecryptBlockedReason(for: domain) != nil)
            .help(coordinator.sslProxyingHostDecryptBlockedReason(for: domain) ?? "")
        }

        SidebarOpenHTTPSDecryptionButton()

        if coordinator.isInBypassList(domain) {
            Button {
                coordinator.removeFromBypassList(domain)
            } label: {
                Label(
                    String(localized: "Remove from Full Proxy Bypass", bundle: RockxyLocalization.bundle),
                    systemImage: "arrow.uturn.right"
                )
            }
        } else {
            Button {
                coordinator.addToBypassList(domain)
            } label: {
                Label(
                    String(localized: "Add to Full Proxy Bypass", bundle: RockxyLocalization.bundle),
                    systemImage: "arrow.uturn.right"
                )
            }
        }

        Button {
            coordinator.sortDomainTreeAlphabetically()
        } label: {
            Label(
                String(localized: "Sort by Alphabet", bundle: RockxyLocalization.bundle),
                systemImage: "textformat.abc"
            )
        }

        Button {
            coordinator.muteTrafficSource(.host(domain))
            coordinator.focusNavigatorMode = .focus
        } label: {
            Label(String(localized: "Mute Source", bundle: RockxyLocalization.bundle), systemImage: "eye.slash")
        }

        Divider()

        Menu {
            Button {
                coordinator.createBreakpointRuleForDomain(domain)
            } label: {
                Label(String(localized: "Breakpoint", bundle: RockxyLocalization.bundle), systemImage: "pause.circle")
            }

            Divider()

            Button {
                coordinator.createMapLocalRuleForDomain(domain)
            } label: {
                Label(String(localized: "Map Local", bundle: RockxyLocalization.bundle), systemImage: "doc")
            }
            Button {
                coordinator.createMapRemoteRuleForDomain(domain)
            } label: {
                Label(
                    String(localized: "Map Remote", bundle: RockxyLocalization.bundle),
                    systemImage: "arrow.triangle.swap"
                )
            }

            Divider()

            Button {
                coordinator.createBlockRuleForDomain(domain)
            } label: {
                Label(String(localized: "Block", bundle: RockxyLocalization.bundle), systemImage: "nosign")
            }
            Button {
                coordinator.createAllowListRuleForDomain(domain)
            } label: {
                Label(
                    String(localized: "Create Allow List Rule…", bundle: RockxyLocalization.bundle),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }

            Divider()

            Button {
                coordinator.createNetworkConditionsRuleForDomain(domain)
            } label: {
                Label(
                    String(localized: "Network Conditions", bundle: RockxyLocalization.bundle),
                    systemImage: "wifi.exclamationmark"
                )
            }
        } label: {
            Label(String(localized: "Tools", bundle: RockxyLocalization.bundle), systemImage: "wrench")
        }

        SidebarExportMenu(
            copyTitle: pathPrefix == nil
                ? String(localized: "Copy Domain", bundle: RockxyLocalization.bundle)
                : String(localized: "Copy Path Filter", bundle: RockxyLocalization.bundle),
            copy: { coordinator.copyDomainToClipboard(pathPrefix.map { "\(domain)\($0)" } ?? domain) },
            export: { coordinator.exportTransactionsForDomain(domain, pathPrefix: pathPrefix, format: $0) }
        )

        Divider()

        Button(role: .destructive) {
            coordinator.removeDomainFromSidebar(domain, pathPrefix: pathPrefix)
        } label: {
            Label(String(localized: "Delete", bundle: RockxyLocalization.bundle), systemImage: "trash")
        }
    }

    @ViewBuilder
    private func favoriteTransactionContextMenu(
        _ transaction: HTTPTransaction,
        section: FavoriteTransactionSection
    )
        -> some View
    {
        let model = FavoriteTransactionContextMenuModel(
            transaction: transaction,
            section: section
        )

        Button {
            coordinator.openFavoriteTransactionInNewTab(transaction, from: section)
        } label: {
            Label(
                String(localized: "Open in New Tab", bundle: RockxyLocalization.bundle),
                systemImage: "plus.rectangle.on.rectangle"
            )
        }
        .disabled(!coordinator.workspaceStore.canCreateWorkspace)

        Button {
            coordinator.copyURL(for: transaction)
        } label: {
            Label(String(localized: "Copy URL", bundle: RockxyLocalization.bundle), systemImage: "doc.on.doc")
        }

        Button {
            coordinator.copyCURL(for: transaction)
        } label: {
            Label(String(localized: "Copy cURL", bundle: RockxyLocalization.bundle), systemImage: "terminal")
        }

        Divider()

        FavoriteTransactionHTTPSBehaviorMenu(
            coordinator: coordinator,
            transaction: transaction,
            canConfigureHost: model.canConfigureHost,
            hostConfigurationDisabledReason: model.hostConfigurationDisabledReason
        )

        Menu {
            favoriteTransactionToolsMenu(transaction, options: model.tools)
        } label: {
            Label(String(localized: "Tools", bundle: RockxyLocalization.bundle), systemImage: "wrench.and.screwdriver")
        }

        Menu {
            favoriteTransactionExportMenu(transaction, options: model.exports)
        } label: {
            Label(String(localized: "Export", bundle: RockxyLocalization.bundle), systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            coordinator.removeFavoriteTransaction(transaction, from: section)
        } label: {
            Label(model.deleteTitle, systemImage: "trash")
        }
    }

    private func favoriteTransactionToolsMenu(
        _ transaction: HTTPTransaction,
        options: [FavoriteTransactionMenuOption<FavoriteTransactionToolAction>]
    )
        -> some View
    {
        ForEach(options, id: \.action) { option in
            if option.action == .mapLocal || option.action == .blockList
                || option.action == .networkConditions
            {
                Divider()
            }

            Button {
                performFavoriteTransactionTool(option.action, for: transaction)
            } label: {
                Label(option.title, systemImage: option.systemImage)
            }
            .disabled(!option.isEnabled)
            .help(option.disabledReason ?? "")
        }
    }

    private func favoriteTransactionExportMenu(
        _ transaction: HTTPTransaction,
        options: [FavoriteTransactionMenuOption<FavoriteTransactionExportFormat>]
    )
        -> some View
    {
        ForEach(options, id: \.action) { option in
            if option.action == .requestBody {
                Divider()
            }

            Button {
                coordinator.exportFavoriteTransaction(transaction, as: option.action)
            } label: {
                Label(option.title, systemImage: option.systemImage)
            }
            .disabled(!option.isEnabled)
            .help(option.disabledReason ?? "")
        }
    }

    @ViewBuilder
    private func appContextMenu(_ app: AppInfo) -> some View {
        let item = SidebarItem.app(name: app.name, bundleId: app.identity?.bundleIdentifier)
        let isPinned = coordinator.isFavorite(item)
        let hasApplicationRule = app.identity.map { identity in
            SSLProxyingManager.shared.applicationRules.contains {
                $0.applicationIdentifier == identity.identifier
            }
        } ?? false

        Button {
            coordinator.toggleSidebarFavorite(item)
        } label: {
            Label(
                isPinned ? String(localized: "Unpin", bundle: RockxyLocalization.bundle) : String(localized: "Pin", bundle: RockxyLocalization.bundle),
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
            Label(
                String(localized: "Open in New Tab", bundle: RockxyLocalization.bundle),
                systemImage: "plus.rectangle.on.rectangle"
            )
        }
        .disabled(!coordinator.workspaceStore.canCreateWorkspace)

        Divider()

        if let identity = app.identity {
            Menu {
                Button {
                    coordinator.setSSLProxyingFromInspector(for: identity, listType: .include)
                } label: {
                    Label(
                        String(localized: "Decrypt All HTTPS", bundle: RockxyLocalization.bundle),
                        systemImage: "lock.open"
                    )
                }

                Button {
                    coordinator.setSSLProxyingFromInspector(for: identity, listType: .exclude)
                } label: {
                    Label(
                        String(localized: "Tunnel All HTTPS", bundle: RockxyLocalization.bundle),
                        systemImage: "lock"
                    )
                }

                if hasApplicationRule {
                    Divider()
                    Button {
                        coordinator.disableSSLProxyingForApp(app)
                    } label: {
                        Label(
                            String(localized: "Remove Application Rule", bundle: RockxyLocalization.bundle),
                            systemImage: "trash"
                        )
                    }
                }

                Divider()

                Button {
                    NotificationCenter.default.post(name: .openSSLProxyingList, object: nil)
                } label: {
                    Label(
                        String(localized: "Open HTTPS Decryption", bundle: RockxyLocalization.bundle),
                        systemImage: "slider.horizontal.3"
                    )
                }
            } label: {
                Label(
                    String(localized: "HTTPS Behavior", bundle: RockxyLocalization.bundle),
                    systemImage: "lock.shield"
                )
            }
        } else {
            Button {
                coordinator.enableSSLProxyingForObservedHosts(app)
            } label: {
                Label(
                    String(localized: "Decrypt Observed Hosts", bundle: RockxyLocalization.bundle),
                    systemImage: "lock.shield"
                )
            }
            .help(String(
                localized: "Creates host rules that apply to these domains in every application.",
                bundle: RockxyLocalization.bundle
            ))
        }

        Button {
            coordinator.sortAppNodesAlphabetically()
        } label: {
            Label(
                String(localized: "Sort by Alphabet", bundle: RockxyLocalization.bundle),
                systemImage: "textformat.abc"
            )
        }

        Button {
            for domain in app.domains {
                coordinator.muteTrafficSource(.host(domain))
            }
            coordinator.focusNavigatorMode = .focus
        } label: {
            Label(String(localized: "Mute App Sources", bundle: RockxyLocalization.bundle), systemImage: "eye.slash")
        }

        Divider()

        SidebarExportMenu(
            copyTitle: String(localized: "Copy App Name", bundle: RockxyLocalization.bundle),
            copy: { coordinator.copyDomainToClipboard(app.name) },
            export: { coordinator.exportTransactionsForApp(app.name, format: $0) }
        )

        Divider()

        Button(role: .destructive) {
            coordinator.removeAppFromSidebar(app.name)
        } label: {
            Label(String(localized: "Delete", bundle: RockxyLocalization.bundle), systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private func domainRow(_ node: DomainNode) -> AnyView {
        if node.children.isEmpty {
            AnyView(domainLabel(node))
        } else {
            AnyView(
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

    private func domainExpansionBinding(for nodeID: String) -> Binding<Bool> {
        Binding {
            SidebarSearchFilter.hasQuery(sidebarFilterText) || expandedDomainNodeIDs.contains(nodeID)
        } set: { isExpanded in
            if isExpanded {
                expandedDomainNodeIDs.insert(nodeID)
            } else {
                expandedDomainNodeIDs.remove(nodeID)
            }
        }
    }

    private func appExpansionBinding(for appName: String) -> Binding<Bool> {
        Binding {
            SidebarSearchFilter.hasQuery(sidebarFilterText) || expandedAppNames.contains(appName)
        } set: { isExpanded in
            if isExpanded {
                expandedAppNames.insert(appName)
            } else {
                expandedAppNames.remove(appName)
            }
        }
    }

    private func saveFocusSetFromSidebar(_ focusSet: FocusSet) {
        expandedFocusSetIDs.insert(focusSet.id)
        coordinator.saveFocusSet(focusSet)
    }

    private func searchAwareExpansionBinding(for binding: Binding<Bool>) -> Binding<Bool> {
        Binding {
            SidebarSearchFilter.hasQuery(sidebarFilterText) || binding.wrappedValue
        } set: { isExpanded in
            binding.wrappedValue = isExpanded
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

    private func performFavoriteTransactionTool(
        _ action: FavoriteTransactionToolAction,
        for transaction: HTTPTransaction
    ) {
        switch action {
        case .breakpoint:
            coordinator.createBreakpointRule(for: transaction)
        case .mapLocal:
            coordinator.createMapLocalRule(for: transaction)
        case .mapRemote:
            coordinator.createMapRemoteRule(for: transaction)
        case .blockList:
            coordinator.createBlockRule(for: transaction)
        case .allowList:
            coordinator.createAllowListRule(for: transaction)
        case .networkConditions:
            coordinator.createNetworkConditionsRule(for: transaction)
        }
    }
}

// MARK: - SidebarDisclosureDefaults

enum SidebarDisclosureDefaults {
    static let appsExpanded = true
    static let domainsExpanded = true
}
