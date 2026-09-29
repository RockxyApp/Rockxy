import AppKit
import SwiftUI

// Presents the native Map Remote management and editor windows.

// MARK: - MapRemoteEditorContext

struct MapRemoteEditorContext {
    static let blank = MapRemoteEditorContext()

    var existingRule: ProxyRule?
    var draft: MapRemoteDraft?
}

// MARK: - MapRemoteEditorStore

@MainActor @Observable
final class MapRemoteEditorStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = MapRemoteEditorStore()

    private(set) var context = MapRemoteEditorContext.blank
    var draftVersion: UInt64 = 0

    func openNew(draft: MapRemoteDraft? = nil) {
        context = MapRemoteEditorContext(existingRule: nil, draft: draft)
        draftVersion &+= 1
    }

    func openExisting(_ rule: ProxyRule) {
        context = MapRemoteEditorContext(existingRule: rule, draft: nil)
        draftVersion &+= 1
    }
}

// MARK: - MapRemoteWindowViewModel

@MainActor @Observable
final class MapRemoteWindowViewModel {
    // MARK: Lifecycle

    init(isToolEnabled: Bool? = nil) {
        self.isToolEnabled = isToolEnabled ?? Self.defaultToolEnabled
    }

    // MARK: Internal

    var allRules: [ProxyRule] = []
    var searchText = ""
    var selectedRuleIDs: Set<UUID> = []
    var isToolEnabled: Bool

    var mapRemoteRules: [ProxyRule] {
        allRules.filter { rule in
            if case .mapRemote = rule.action {
                return true
            }
            return false
        }
    }

    var filteredRules: [ProxyRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return mapRemoteRules
        }
        return mapRemoteRules.filter { rule in
            rule.name.lowercased().contains(query)
                || (rule.matchCondition.sourceURLPattern?.lowercased().contains(query) ?? false)
                || (rule.matchCondition.urlPattern?.lowercased().contains(query) ?? false)
                || methodLabel(for: rule).lowercased().contains(query)
                || destinationLabel(for: rule).lowercased().contains(query)
        }
    }

    var ruleCount: Int {
        mapRemoteRules.count
    }

    var activeRuleCount: Int {
        mapRemoteRules.filter(\.isEnabled).count
    }

    var selectedRule: ProxyRule? {
        guard let id = selectedRuleIDs.first else {
            return nil
        }
        return allRules.first { $0.id == id }
    }

    func refreshFromEngine() async {
        allRules = await RuleEngine.shared.allRules
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
            selectedRuleIDs = selectedRuleIDs.filter { id in
                rules.contains { $0.id == id }
            }
        }
    }

    func setToolEnabled(_ enabled: Bool) {
        isToolEnabled = enabled
        pendingRuleSyncTask = Task {
            await RulePolicyGate.shared.setMapRemoteToolEnabled(enabled)
        }
    }

    func toggleRule(id: UUID) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index].isEnabled.toggle()
        pendingRuleSyncTask = Task {
            let accepted = await RulePolicyGate.shared.toggleRule(id: id)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
            }
        }
    }

    func removeSelectedRules() {
        let idsToRemove = selectedRuleIDs
        guard !idsToRemove.isEmpty else {
            return
        }
        allRules.removeAll { idsToRemove.contains($0.id) }
        selectedRuleIDs.removeAll()
        pendingRuleSyncTask = Task {
            await RulePolicyGate.shared.removeRules(ids: idsToRemove)
            allRules = await RuleEngine.shared.allRules
        }
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        selectedRuleIDs.remove(id)
        pendingRuleSyncTask = Task { await RulePolicyGate.shared.removeRule(id: id) }
    }

    func duplicateSelectedRule() {
        guard let selectedRule else {
            return
        }
        let rule = ProxyRule(
            name: "\(selectedRule.name) Copy",
            isEnabled: selectedRule.isEnabled,
            matchCondition: selectedRule.matchCondition,
            action: selectedRule.action,
            priority: selectedRule.priority
        )
        allRules.append(rule)
        selectedRuleIDs = [rule.id]
        pendingRuleSyncTask = Task {
            let accepted = await RulePolicyGate.shared.addRule(rule)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
            }
        }
    }

    func waitForPendingRuleSync() async {
        await pendingRuleSyncTask?.value
    }

    func methodLabel(for rule: ProxyRule) -> String {
        rule.matchCondition.method?.uppercased() ?? "ANY"
    }

    func matchingRuleLabel(for rule: ProxyRule) -> String {
        if let sourcePattern = rule.matchCondition.sourceURLPattern, !sourcePattern.isEmpty {
            let prefix = rule.matchCondition.matchType == .regex ? "Regex: " : "Wildcard: "
            return prefix + sourcePattern
        }
        guard let pattern = rule.matchCondition.urlPattern, !pattern.isEmpty else {
            return "<Missing URL>"
        }
        if MapLocalPatternFormatter.prefersWildcardPresentation(pattern) {
            return "Wildcard: \(MapLocalPatternFormatter.readablePattern(pattern))"
        }
        return "Regex: \(pattern)"
    }

    func destinationLabel(for rule: ProxyRule) -> String {
        guard case let .mapRemote(config) = rule.action else {
            return ""
        }
        guard let host = config.host, !host.isEmpty else {
            var overrides: [String] = []
            if let scheme = config.scheme {
                overrides.append("Protocol \(scheme.uppercased())")
            }
            if let port = config.port {
                overrides.append("Port \(port)")
            }
            if let path = config.path, !config.preserveOriginalURL {
                overrides.append("Path \(path)")
            }
            if let query = config.query, !config.preserveOriginalURL {
                overrides.append("Query \(query)")
            }
            if config.preserveOriginalURL {
                overrides.append("Original target")
            }
            overrides.append("Original host")
            return overrides.joined(separator: " · ")
        }
        var result = ""
        if let scheme = config.scheme {
            result += "\(scheme)://"
        }
        let displayHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        result += displayHost
        if let port = config.port {
            result += ":\(port)"
        }
        if let path = config.path, !config.preserveOriginalURL {
            if result.isEmpty {
                result += path
            } else {
                result += path.hasPrefix("/") ? path : "/\(path)"
            }
        }
        if let query = config.query, !config.preserveOriginalURL {
            result += "?\(query)"
        }
        if config.preserveOriginalURL {
            result += " · Original target"
        }
        return result.isEmpty ? "—" : result
    }

    func preservesHost(for rule: ProxyRule) -> Bool {
        if case let .mapRemote(config) = rule.action {
            return config.preserveHostHeader
        }
        return false
    }

    // MARK: Private

    private static let toolEnabledKey = "mapRemoteToolEnabled"

    private static var defaultToolEnabled: Bool {
        UserDefaults.standard.object(forKey: toolEnabledKey) as? Bool ?? true
    }

    private var pendingRuleSyncTask: Task<Void, Never>?
}

// MARK: - MapRemoteWindowView

struct MapRemoteWindowView: View {
    // MARK: Internal

    @State var viewModel = MapRemoteWindowViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            infoBanner
            Divider()
            tableContent
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(900, toolMetrics.bodyFontSize * 30 + 520),
            minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)
        )
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingDraftIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .openMapRemoteWindow)) { _ in
            consumePendingDraftIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footerHint: String {
        let countText = isSearching
            ? String(AttributedString(
                localized: "\(viewModel.filteredRules.count) of ^[\(viewModel.ruleCount) rule](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
            : String(AttributedString(
                localized: "^[\(viewModel.ruleCount) rule](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        return "\(countText) · ⌘N \(String(localized: "New Rule", bundle: RockxyLocalization.bundle)) · ⌘↩ \(String(localized: "Edit", bundle: RockxyLocalization.bundle))"
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(
                    String(localized: "Enable Map Remote", bundle: RockxyLocalization.bundle),
                    isOn: Binding(
                        get: { viewModel.isToolEnabled },
                        set: { viewModel.setToolEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font(weight: .medium))

                Text(String(
                    localized: "Rewrite matching requests to a different host, port, path, or query.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }

            Spacer()

            TextField(String(localized: "Search rules", bundle: RockxyLocalization.bundle), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(width: 240, height: toolMetrics.formControlHeight)
                .accessibilityLabel(String(localized: "Search Map Remote rules", bundle: RockxyLocalization.bundle))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized:
                    """
                    Map Remote participates in Rockxy's global first-match rule order. Blank fields keep matched request \
                    components; changing Protocol with a blank Port uses the new protocol's default.
                    """, bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var tableContent: some View {
        Table(viewModel.filteredRules, selection: $viewModel.selectedRuleIDs) {
            TableColumn(String(localized: "Enabled", bundle: RockxyLocalization.bundle)) { rule in
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { _ in viewModel.toggleRule(id: rule.id) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(
                    String(
                        localized: "Enable \(rule.name.isEmpty ? "Untitled" : rule.name)",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
            .width(62)

            TableColumn(String(localized: "Name", bundle: RockxyLocalization.bundle)) { rule in
                Text(rule.name.isEmpty ? String(localized: "Untitled", bundle: RockxyLocalization.bundle) : rule.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rule.name)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 150, ideal: 190)

            TableColumn(String(localized: "Method", bundle: RockxyLocalization.bundle)) { rule in
                Text(viewModel.methodLabel(for: rule))
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(76)

            TableColumn(String(localized: "Matching Rule", bundle: RockxyLocalization.bundle)) { rule in
                Text(viewModel.matchingRuleLabel(for: rule))
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(viewModel.matchingRuleLabel(for: rule))
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 220, ideal: 300)

            TableColumn(String(localized: "Remote Destination", bundle: RockxyLocalization.bundle)) { rule in
                HStack(spacing: 6) {
                    Text(viewModel.destinationLabel(for: rule))
                        .font(toolMetrics.font(monospaced: true))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(viewModel.destinationLabel(for: rule))
                    if viewModel.preservesHost(for: rule) {
                        preserveHostBadge
                    }
                }
                .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 280, ideal: 420)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            tableContextMenu(ids: ids)
        } primaryAction: { ids in
            guard let id = ids.first,
                  let rule = viewModel.allRules.first(where: { $0.id == id }) else
            {
                return
            }
            openEditor(for: rule)
        }
        .overlay {
            if viewModel.filteredRules.isEmpty {
                ContentUnavailableView(
                    isSearching
                        ? String(localized: "No matching rules", bundle: RockxyLocalization.bundle)
                        : String(localized: "No Map Remote rules", bundle: RockxyLocalization.bundle),
                    systemImage: isSearching ? "magnifyingglass" : "arrow.triangle.branch",
                    description: Text(
                        isSearching
                            ? String(
                                localized: "Try a different name, method, URL, or destination.",
                                bundle: RockxyLocalization.bundle
                            )
                            : String(
                                localized: "Click \"+\" or press ⌘N to create a rule.",
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
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    private var preserveHostBadge: some View {
        Text(String(localized: "Host kept", bundle: RockxyLocalization.bundle))
            .font(toolMetrics.metadataFont(weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.14))
            .clipShape(Capsule())
            .help(String(
                localized: "The Host header is preserved from the original request.",
                bundle: RockxyLocalization.bundle
            ))
            .accessibilityLabel(String(localized: "Host header preserved", bundle: RockxyLocalization.bundle))
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            addRemoveControl

            Text(footerHint)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Spacer()

            moreMenu

            Text(
                viewModel.isToolEnabled
                    ? "\(viewModel.activeRuleCount) \(String(localized: "ACTIVE", bundle: RockxyLocalization.bundle))"
                    : String(localized: "MAP REMOTE OFF", bundle: RockxyLocalization.bundle)
            )
            .font(toolMetrics.metadataFont(weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .rockxyChipStyle(tint: .green, isActive: viewModel.isToolEnabled)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                openNewEditor()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help(String(localized: "New Rule", bundle: RockxyLocalization.bundle))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 18)

            Button {
                viewModel.removeSelectedRules()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleIDs.isEmpty)
            .help(String(localized: "Remove Selected Rules", bundle: RockxyLocalization.bundle))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(
            width: max(43, toolMetrics.compactButtonSize * 2 + 1),
            height: toolMetrics.footerControlHeight
        )
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New Rule", bundle: RockxyLocalization.bundle)) { openNewEditor() }
                .keyboardShortcut("n", modifiers: .command)
            Button(String(localized: "Edit Rule", bundle: RockxyLocalization.bundle)) {
                if let rule = viewModel.selectedRule {
                    openEditor(for: rule)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.selectedRule == nil)
            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                viewModel.duplicateSelectedRule()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel.selectedRule == nil)
            Button(String(localized: "Toggle Enabled", bundle: RockxyLocalization.bundle)) {
                if let id = viewModel.selectedRuleIDs.first {
                    viewModel.toggleRule(id: id)
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(viewModel.selectedRule == nil)
            Divider()
            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                viewModel.removeSelectedRules()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleIDs.isEmpty)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More", bundle: RockxyLocalization.bundle))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .rockxyGlassButtonStyle()
        .fixedSize()
    }

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first {
            Button(String(localized: "Edit Rule", bundle: RockxyLocalization.bundle)) {
                if let rule = viewModel.allRules.first(where: { $0.id == id }) {
                    openEditor(for: rule)
                }
            }
            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                viewModel.selectedRuleIDs = [id]
                viewModel.duplicateSelectedRule()
            }
            Divider()
            Button(String(localized: "Delete Rule", bundle: RockxyLocalization.bundle), role: .destructive) {
                viewModel.removeRule(id: id)
            }
        }
    }

    private func openNewEditor(draft: MapRemoteDraft? = nil) {
        MapRemoteEditorStore.shared.openNew(draft: draft)
        openWindow(id: "mapRemoteEditor")
    }

    private func openEditor(for rule: ProxyRule) {
        MapRemoteEditorStore.shared.openExisting(rule)
        openWindow(id: "mapRemoteEditor")
    }

    private func consumePendingDraftIfNeeded() {
        guard let draft = MapRemoteDraftStore.shared.consumePending() else {
            return
        }
        openNewEditor(draft: draft)
    }
}

// MARK: - MapRemoteEditorWindowView

struct MapRemoteEditorWindowView: View {
    // MARK: Internal

    @State var viewModel = MapRemoteEditorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing + 3) {
                    Text(editorTitle)
                        .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))

                    if let provenance = quickCreateProvenance {
                        provenanceBanner(provenance)
                    }

                    ruleDetailsSection
                    remoteDestinationSection
                }
                .padding(.horizontal, toolMetrics.formHorizontalPadding)
                .padding(.vertical, toolMetrics.formVerticalPadding)
            }

            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496))
        .frame(height: max(660, toolMetrics.bodyFontSize * 20 + 400))
        .navigationTitle(viewModel.windowTitle)
        .onAppear {
            viewModel.load(context: editorStore.context)
            focusDestinationHostIfNeeded()
        }
        .onChange(of: editorStore.draftVersion) { _, _ in
            viewModel.load(context: editorStore.context)
            focusDestinationHostIfNeeded()
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var editorStore = MapRemoteEditorStore.shared
    @FocusState private var isDestinationHostFocused: Bool

    private var editorTitle: String {
        viewModel.existingID == nil
            ? String(localized: "New Map Remote Rule", bundle: RockxyLocalization.bundle)
            : String(localized: "Edit Map Remote Rule", bundle: RockxyLocalization.bundle)
    }

    private var quickCreateProvenance: String? {
        guard let draft = viewModel.draft else {
            return nil
        }
        if let sourceURL = draft.sourceURL {
            return String(
                localized: "Created from \(draft.sourceMethod ?? "ANY") \(sourceURL.absoluteString)",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(localized: "Created from domain \(draft.sourceHost)", bundle: RockxyLocalization.bundle)
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var ruleDetailsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Rule Details", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                    fieldGroup(String(localized: "Name", bundle: RockxyLocalization.bundle)) {
                        TextField(
                            String(localized: "Untitled", bundle: RockxyLocalization.bundle),
                            text: $viewModel.name
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(String(localized: "Rule name", bundle: RockxyLocalization.bundle))
                    }
                    .frame(width: max(250, toolMetrics.fieldWidth(250)))

                    fieldGroup(String(localized: "URL pattern", bundle: RockxyLocalization.bundle)) {
                        TextField("https://example.com/api/*", text: $viewModel.urlText)
                            .textFieldStyle(.roundedBorder)
                            .font(toolMetrics.font())
                            .accessibilityLabel(String(localized: "URL pattern", bundle: RockxyLocalization.bundle))
                    }
                    .frame(maxWidth: .infinity)
                }

                if let validationMessage = viewModel.urlValidationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.red)
                }

                HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
                    inlineField(String(localized: "Method", bundle: RockxyLocalization.bundle)) {
                        methodMenu
                    }
                    inlineField(String(localized: "Match type", bundle: RockxyLocalization.bundle)) {
                        matchTypeMenu
                    }
                    if viewModel.matchType == .wildcard {
                        Text(String(localized: "Supports * and ?.", bundle: RockxyLocalization.bundle))
                            .font(toolMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if viewModel.matchType == .wildcard {
                    Toggle(
                        String(localized: "Include all subpaths of this URL", bundle: RockxyLocalization.bundle),
                        isOn: $viewModel.includeSubpaths
                    )
                    .toggleStyle(.checkbox)
                    .font(toolMetrics.font())
                }

                inlineField(String(localized: "GraphQL Operation", bundle: RockxyLocalization.bundle)) {
                    TextField(
                        String(localized: "Any operation", bundle: RockxyLocalization.bundle),
                        text: $viewModel.graphQLOperationName
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: max(220, toolMetrics.fieldWidth(220)))
                    .accessibilityLabel(String(
                        localized: "GraphQL operation name to match",
                        bundle: RockxyLocalization.bundle
                    ))
                    .help(String(
                        localized: "Redirect only GraphQL requests with this exact operation name. Leave empty to redirect every request to the URL.",
                        bundle: RockxyLocalization.bundle
                    ))
                }
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var remoteDestinationSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Remote Destination", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
                    inlineField(String(localized: "Protocol", bundle: RockxyLocalization.bundle)) {
                        schemeMenu
                    }
                    Spacer()
                }

                HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                    fieldGroup(String(localized: "Host", bundle: RockxyLocalization.bundle)) {
                        TextField(
                            String(localized: "Keep original", bundle: RockxyLocalization.bundle),
                            text: $viewModel.destHost
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .focused($isDestinationHostFocused)
                        .accessibilityLabel(String(
                            localized: "Destination host",
                            bundle: RockxyLocalization.bundle
                        ))
                    }
                    .frame(maxWidth: .infinity)

                    fieldGroup(String(localized: "Port", bundle: RockxyLocalization.bundle)) {
                        TextField(
                            String(localized: "Automatic", bundle: RockxyLocalization.bundle),
                            text: $viewModel.destPort
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .accessibilityLabel(String(
                            localized: "Destination port",
                            bundle: RockxyLocalization.bundle
                        ))
                    }
                    .frame(width: toolMetrics.fieldWidth(90))
                }

                if let schemeError = viewModel.schemeValidationMessage {
                    validationLabel(schemeError)
                }
                if let hostError = viewModel.hostValidationMessage {
                    validationLabel(hostError)
                }
                if let portError = viewModel.portValidationMessage {
                    validationLabel(portError)
                }
                if let destinationError = viewModel.destinationValidationMessage {
                    validationLabel(destinationError)
                }

                fieldGroup(String(localized: "Path", bundle: RockxyLocalization.bundle)) {
                    TextField(
                        String(localized: "Keep original", bundle: RockxyLocalization.bundle),
                        text: $viewModel.destPath
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font())
                    .accessibilityLabel(String(localized: "Destination path", bundle: RockxyLocalization.bundle))
                }

                fieldGroup(String(localized: "Query", bundle: RockxyLocalization.bundle)) {
                    TextField(
                        String(localized: "Keep original", bundle: RockxyLocalization.bundle),
                        text: $viewModel.destQuery
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font())
                    .accessibilityLabel(String(localized: "Destination query", bundle: RockxyLocalization.bundle))
                }

                Text(
                    String(
                        localized: "Blank fields keep the matched request component. If Protocol changes while Port is blank, Rockxy uses the new protocol's default port.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Divider()

                fullURLRow
                if viewModel.hasAnyDestination {
                    destinationSummaryRow
                }

                Divider()

                Toggle(
                    String(localized: "Keep original request path and query", bundle: RockxyLocalization.bundle),
                    isOn: $viewModel.preserveOriginalURL
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font())
                .accessibilityHint(
                    String(
                        localized: "Forwards the original request target while connecting to the remote destination.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                Text(
                    String(
                        localized:
                        "The destination protocol, host, and port still choose the remote server. Path and query overrides are ignored while this is enabled.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    String(localized: "Preserve Host header", bundle: RockxyLocalization.bundle),
                    isOn: $viewModel.preserveHost
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font())
                .accessibilityHint(
                    String(
                        localized: "Keeps the request's Host header even when the destination host changes.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                Text(
                    String(
                        localized:
                        "The Host header stays as the original request sent it. The destination host, DNS lookup, and TLS server name still use the rewritten host above.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var fullURLRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Fill from full URL", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
            HStack(spacing: toolMetrics.controlSpacing) {
                TextField("https://staging.example.com:8443/v2?debug=1", text: $viewModel.destinationURLPaste)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font())
                    .frame(height: toolMetrics.formControlHeight)
                    .onSubmit { applyPastedURL() }
                    .accessibilityLabel(String(localized: "Full destination URL", bundle: RockxyLocalization.bundle))
                Button(String(localized: "Fill fields", bundle: RockxyLocalization.bundle)) { applyPastedURL() }
                    .frame(height: toolMetrics.formControlHeight)
                    .disabled(viewModel.destinationURLPaste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let parseError = viewModel.urlParseError {
                Label(parseError, systemImage: "exclamationmark.triangle.fill")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
            }
            if let confirmation = viewModel.urlFillConfirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.green)
            }
        }
    }

    private var destinationSummaryRow: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "arrow.right.circle")
                .foregroundStyle(.secondary)
            Text(viewModel.destinationSummary)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var methodMenu: some View {
        Menu {
            ForEach(Array(MapLocalEditorMenuContent.methodSections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { method in
                    Button { viewModel.method = method } label: {
                        menuCheckmarkLabel(method.rawValue, isSelected: viewModel.method == method)
                    }
                }
                if index < MapLocalEditorMenuContent.methodSections.count - 1 {
                    Divider()
                }
            }
        } label: {
            dataEntryMenuLabel(viewModel.method.rawValue, width: toolMetrics.menuWidth(90))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: toolMetrics.menuWidth(90))
        .accessibilityLabel(String(localized: "Request method", bundle: RockxyLocalization.bundle))
    }

    private var matchTypeMenu: some View {
        Menu {
            ForEach(MapLocalMatchType.allCases) { matchType in
                Button { viewModel.matchType = matchType } label: {
                    menuCheckmarkLabel(matchType.displayName, isSelected: viewModel.matchType == matchType)
                }
            }
        } label: {
            dataEntryMenuLabel(viewModel.matchType.displayName, width: toolMetrics.menuWidth(150))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: toolMetrics.menuWidth(150))
        .accessibilityLabel(String(localized: "Match type", bundle: RockxyLocalization.bundle))
    }

    private var schemeMenu: some View {
        Menu {
            Button { viewModel.destScheme = "" } label: {
                menuCheckmarkLabel(
                    String(localized: "Keep Original", bundle: RockxyLocalization.bundle),
                    isSelected: viewModel.destScheme.isEmpty
                )
            }
            Divider()
            Button { viewModel.destScheme = "http" } label: {
                menuCheckmarkLabel("http", isSelected: viewModel.destScheme == "http")
            }
            Button { viewModel.destScheme = "https" } label: {
                menuCheckmarkLabel("https", isSelected: viewModel.destScheme == "https")
            }
        } label: {
            dataEntryMenuLabel(
                viewModel.destScheme
                    .isEmpty ? String(localized: "Keep Original", bundle: RockxyLocalization.bundle) : viewModel
                    .destScheme,
                width: toolMetrics.menuWidth(150)
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: toolMetrics.menuWidth(150))
        .accessibilityLabel(String(localized: "Destination protocol", bundle: RockxyLocalization.bundle))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage = viewModel.errorMessage {
                validationLabel(errorMessage)
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isSaving)

                Button {
                    saveAndClose()
                } label: {
                    footerButtonLabel(
                        viewModel.isSaving
                            ? String(localized: "Saving…", bundle: RockxyLocalization.bundle)
                            : viewModel.existingID == nil
                            ? String(localized: "Add", bundle: RockxyLocalization.bundle)
                            : String(localized: "Save", bundle: RockxyLocalization.bundle)
                    )
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .disabled(!viewModel.isSaveEnabled || viewModel.isSaving)
            }
        }
        .padding(.horizontal, toolMetrics.formHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    private func provenanceBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
            Text(message)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(message)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        }
    }

    private func menuCheckmarkLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    private func dataEntryMenuLabel(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(toolMetrics.font())
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .frame(width: width, height: toolMetrics.formControlHeight, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }

    private func inlineField(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func fieldGroup(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                width: max(64, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 3),
                height: max(16, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
            )
    }

    private func validationLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func applyPastedURL() {
        if viewModel.applyDestinationURL(viewModel.destinationURLPaste) {
            viewModel.destinationURLPaste = ""
        }
    }

    private func saveAndClose() {
        Task {
            if await viewModel.save() {
                dismiss()
            }
        }
    }

    private func focusDestinationHostIfNeeded() {
        guard viewModel.existingID == nil, viewModel.draft != nil else {
            return
        }
        Task { @MainActor in
            await Task.yield()
            isDestinationHostFocused = true
        }
    }
}
