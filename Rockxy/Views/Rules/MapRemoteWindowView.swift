import os
import SwiftUI

// Presents the Proxyman-style Map Remote management and editor windows.

// MARK: - MapRemoteEditorContext

struct MapRemoteEditorContext {
    var existingRule: ProxyRule?
    var draft: MapRemoteDraft?

    static let blank = MapRemoteEditorContext()
}

// MARK: - MapRemoteEditorStore

@MainActor @Observable
final class MapRemoteEditorStore {
    private init() {}

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
    var isFilterVisible = false
    var isToolEnabled: Bool
    var errorMessage: String?
    private var pendingRuleSyncTask: Task<Void, Never>?

    var mapRemoteRules: [ProxyRule] {
        allRules.filter { rule in
            if case .mapRemote = rule.action {
                return true
            }
            return false
        }
    }

    var filteredRules: [ProxyRule] {
        guard !searchText.isEmpty else {
            return mapRemoteRules
        }
        let query = searchText.lowercased()
        return mapRemoteRules.filter { rule in
            rule.name.lowercased().contains(query)
                || methodLabel(for: rule).lowercased().contains(query)
                || matchingRuleLabel(for: rule).lowercased().contains(query)
                || destinationLabel(for: rule).lowercased().contains(query)
        }
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

    func enableAll() {
        var updated = allRules
        for index in updated.indices {
            if case .mapRemote = updated[index].action {
                updated[index].isEnabled = true
            }
        }
        allRules = updated
        pendingRuleSyncTask = Task {
            await RulePolicyGate.shared.replaceAllRules(updated)
            allRules = await RuleEngine.shared.allRules
        }
    }

    func removeSelectedRules() {
        let idsToRemove = selectedRuleIDs
        guard !idsToRemove.isEmpty else {
            return
        }
        allRules.removeAll { idsToRemove.contains($0.id) }
        selectedRuleIDs.removeAll()
        let updated = allRules
        pendingRuleSyncTask = Task { await RulePolicyGate.shared.replaceAllRules(updated) }
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
        var result = ""
        if let scheme = config.scheme {
            result += "\(scheme)://"
        }
        if let host = config.host {
            result += host
        }
        if let port = config.port {
            result += ":\(port)"
        }
        if let path = config.path {
            if result.isEmpty {
                result += path
            } else {
                result += path.hasPrefix("/") ? path : "/\(path)"
            }
        }
        if let query = config.query {
            result += "?\(query)"
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
    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "MapRemoteWindowViewModel"
    )
    private static var defaultToolEnabled: Bool {
        UserDefaults.standard.object(forKey: toolEnabledKey) as? Bool ?? true
    }
}

// MARK: - MapRemoteWindowView

struct MapRemoteWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @State var viewModel = MapRemoteWindowViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tableContent
            localhostHint
            shortcutStrip
            bottomBar
        }
        .frame(width: 1_202, height: 640)
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingDraftIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .openMapRemoteWindow)) { _ in
            consumePendingDraftIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .alert(
            String(localized: "Map Remote"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK")) { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { viewModel.isToolEnabled },
                set: { viewModel.setToolEnabled($0) }
            )) {
                Text(String(localized: "Enable Map Remote Tool"))
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .padding(.top, 16)

            Text(String(localized: "Map Requests to different Host, Path, Post. Useful to map from Localhost ↔ Production."))
                .font(.system(size: 13))
            Text(String(localized: "Each request is checked against the rules from top to bottom, stopping when a match is found."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if viewModel.isFilterVisible {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Filter Map Remote rules"), text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        viewModel.searchText = ""
                        viewModel.isFilterVisible = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }

    private var tableContent: some View {
        Table(viewModel.filteredRules, selection: $viewModel.selectedRuleIDs) {
            TableColumn(String(localized: "Enabled")) { rule in
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { _ in viewModel.toggleRule(id: rule.id) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            .width(58)

            TableColumn(String(localized: "Name")) { rule in
                Text(rule.name.isEmpty ? String(localized: "Untitled") : rule.name)
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 210, ideal: 260)

            TableColumn(String(localized: "Method")) { rule in
                Text(viewModel.methodLabel(for: rule))
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(86)

            TableColumn(String(localized: "Matching Rule")) { rule in
                Text(viewModel.matchingRuleLabel(for: rule))
                    .lineLimit(1)
                    .help(rule.matchCondition.urlPattern ?? "<Missing URL>")
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 300, ideal: 320)

            TableColumn(String(localized: "To")) { rule in
                HStack(spacing: 6) {
                    Text(viewModel.destinationLabel(for: rule))
                        .lineLimit(1)
                        .help(viewModel.destinationLabel(for: rule))
                    if viewModel.preservesHost(for: rule) {
                        Text("H")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 360, ideal: 440)
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
                Text(String(localized: "Click \"+\" or ⌘N to add new entry"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
    }

    private var localhostHint: some View {
        Text(String(localized: "If your `localhost` requests don't show on Proxyman, please set domain aliases on /etc/hosts file"))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.top, 8)
    }

    private var shortcutStrip: some View {
        Text("New: ⌘N    Edit: ⌘↩    Delete: ⌘⌫    Duplicate: ⌘D    Toggle: ↵")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Button {
                    openNewEditor()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .regular))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)

                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1, height: 18)

                Button {
                    viewModel.removeSelectedRules()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .regular))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.selectedRuleIDs.isEmpty)
            }
            .foregroundStyle(.primary)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .frame(width: 43, height: 25)

            Button {
                viewModel.errorMessage = String(localized: "Map Remote checks rules from top to bottom and rewrites the first matching request to the configured destination.")
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                withAnimation {
                    viewModel.isFilterVisible.toggle()
                }
            } label: {
                Label(String(localized: "Filter"), systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)

            Menu {
                Button(String(localized: "New")) { openNewEditor() }
                    .keyboardShortcut("n", modifiers: .command)
                Button(String(localized: "Edit")) {
                    if let rule = viewModel.selectedRule {
                        openEditor(for: rule)
                    }
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(viewModel.selectedRule == nil)
                Button(String(localized: "Duplicate")) { viewModel.duplicateSelectedRule() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(viewModel.selectedRule == nil)
                Button(String(localized: "Toggle")) {
                    if let id = viewModel.selectedRuleIDs.first {
                        viewModel.toggleRule(id: id)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(viewModel.selectedRule == nil)
                Button(String(localized: "Toggle")) {
                    if let id = viewModel.selectedRuleIDs.first {
                        viewModel.toggleRule(id: id)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(viewModel.selectedRule == nil)
                Divider()
                Button(String(localized: "Enable All")) { viewModel.enableAll() }
                Divider()
                Button(String(localized: "Delete"), role: .destructive) {
                    viewModel.removeSelectedRules()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.selectedRuleIDs.isEmpty)
            } label: {
                HStack(spacing: 6) {
                    Text(String(localized: "More"))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.bordered)
            .fixedSize()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first {
            Button(String(localized: "Edit Rule")) {
                if let rule = viewModel.allRules.first(where: { $0.id == id }) {
                    openEditor(for: rule)
                }
            }
            Button(String(localized: "Duplicate")) {
                viewModel.selectedRuleIDs = [id]
                viewModel.duplicateSelectedRule()
            }
            Divider()
            Button(String(localized: "Delete Rule"), role: .destructive) {
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

// MARK: - MapRemoteEditorViewModel

@MainActor @Observable
final class MapRemoteEditorViewModel {
    // MARK: Internal

    var name = "Untitled"
    var urlText = ""
    var method: MapLocalHTTPMethod = .any
    var matchType: MapLocalMatchType = .wildcard
    var includeSubpaths = true
    var destScheme = ""
    var destHost = ""
    var destPort = ""
    var destPath = ""
    var destQuery = ""
    var preserveOriginalURL = false
    var preserveHost = false
    var errorMessage: String?

    private(set) var existingID: UUID?
    private(set) var originalRule: ProxyRule?
    private(set) var draft: MapRemoteDraft?
    private(set) var isLoaded = false

    var windowTitle: String {
        "Map Remote Editor: \(name.isEmpty ? "Untitled" : name)"
    }

    var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasAnyDestination
            && isPortValid
            && RegexValidator.compile(urlPatternForSaving()).isSuccess
    }

    var hasAnyDestination: Bool {
        !destScheme.isEmpty
            || !destHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !destPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !destPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !destQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var destinationPreviewString: String {
        let scheme = destScheme.isEmpty ? "https" : destScheme
        let host = destHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "example.com"
            : destHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = normalizedPath().isEmpty ? "/" : normalizedPath()

        var result = "\(scheme)://\(host)"
        if let port = parsedPort {
            result += ":\(port)"
        }
        result += path
        let query = destQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result += "?\(query)"
        }
        return result
    }

    func load(context: MapRemoteEditorContext) {
        existingID = context.existingRule?.id
        originalRule = context.existingRule
        draft = context.draft

        if let rule = context.existingRule {
            load(existingRule: rule)
        } else if let draft = context.draft {
            load(draft: draft)
        } else {
            loadBlank()
        }
        isLoaded = true
    }

    func tryParseDestinationURL(_ input: String) {
        guard input.contains("://"),
              let components = URLComponents(string: input),
              let host = components.host, !host.isEmpty else
        {
            return
        }

        destScheme = components.scheme?.lowercased() ?? ""
        destHost = host
        if let port = components.port {
            destPort = String(port)
        }
        if !components.path.isEmpty, components.path != "/" {
            destPath = String(components.path.drop(while: { $0 == "/" }))
        }
        if let query = components.percentEncodedQuery {
            destQuery = query
        }
    }

    func makeRule() -> ProxyRule? {
        guard isSaveEnabled else {
            errorMessage = String(localized: "Complete the matching rule and destination before saving.")
            return nil
        }

        var condition = originalRule?.matchCondition ?? RuleMatchCondition()
        condition.urlPattern = urlPatternForSaving()
        condition.method = method.ruleValue

        let config = MapRemoteConfiguration(
            scheme: destScheme.isEmpty ? nil : destScheme.lowercased(),
            host: nilIfBlank(destHost),
            port: parsedPort,
            path: nilIfBlank(normalizedPath()),
            query: nilIfBlank(destQuery),
            preserveOriginalURL: preserveOriginalURL,
            preserveHostHeader: preserveHost
        )

        return ProxyRule(
            id: existingID ?? UUID(),
            name: name,
            isEnabled: originalRule?.isEnabled ?? true,
            matchCondition: condition,
            action: .mapRemote(configuration: config),
            priority: originalRule?.priority ?? 0
        )
    }

    func urlPatternForSaving() -> String {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matchType == .wildcard else {
            return trimmed
        }
        return RulePatternBuilder.regexSource(
            rawPattern: trimmed,
            matchType: .wildcard,
            includeSubpaths: includeSubpaths
        )
    }

    // MARK: Private

    private var parsedPort: Int? {
        Int(destPort.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isPortValid: Bool {
        let trimmed = destPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        guard let port = Int(trimmed) else {
            return false
        }
        return (1 ... 65_535).contains(port)
    }

    private func loadBlank() {
        name = "Untitled"
        urlText = ""
        method = .any
        matchType = .wildcard
        includeSubpaths = true
        destScheme = ""
        destHost = ""
        destPort = ""
        destPath = ""
        destQuery = ""
        preserveOriginalURL = false
        preserveHost = false
    }

    private func load(draft: MapRemoteDraft) {
        loadBlank()
        name = draft.suggestedName.isEmpty ? "Untitled" : draft.suggestedName
        method = MapLocalHTTPMethod(ruleMethod: draft.sourceMethod)
        includeSubpaths = draft.origin == .domainQuickCreate
        if let sourceURL = draft.sourceURL {
            urlText = sourceURL.absoluteString
        } else {
            urlText = "https://\(draft.sourceHost)/*"
        }
    }

    private func load(existingRule rule: ProxyRule) {
        name = rule.name.isEmpty ? "Untitled" : rule.name
        let storedPattern = rule.matchCondition.urlPattern ?? ""
        if MapLocalPatternFormatter.prefersWildcardPresentation(storedPattern) {
            urlText = MapLocalPatternFormatter.readablePattern(storedPattern)
            matchType = .wildcard
        } else {
            urlText = storedPattern
            matchType = .regex
        }
        method = MapLocalHTTPMethod(ruleMethod: rule.matchCondition.method)
        includeSubpaths = false
        if case let .mapRemote(config) = rule.action {
            destScheme = config.scheme ?? ""
            destHost = config.host ?? ""
            destPort = config.port.map(String.init) ?? ""
            destPath = config.path.map { String($0.drop(while: { $0 == "/" })) } ?? ""
            destQuery = config.query ?? ""
            preserveOriginalURL = config.preserveOriginalURL
            preserveHost = config.preserveHostHeader
        }
    }

    private func normalizedPath() -> String {
        let trimmed = destPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - MapRemoteEditorWindowView

struct MapRemoteEditorWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editorStore = MapRemoteEditorStore.shared
    @State var viewModel = MapRemoteEditorViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            matchingRuleSection
            mapToSection
            actionBar
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: 834)
        .navigationTitle(viewModel.windowTitle)
        .onAppear { viewModel.load(context: editorStore.context) }
        .onChange(of: editorStore.draftVersion) { _, _ in
            viewModel.load(context: editorStore.context)
        }
        .alert(
            String(localized: "Map Remote"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK")) { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    private var matchingRuleSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Matching Rule"))
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 6) {
                labeledTextField(String(localized: "Name:"), placeholder: String(localized: "Untitled"), text: $viewModel.name)

                labeledTextField(String(localized: "Rule:"), placeholder: "/v1/*", text: $viewModel.urlText)

                HStack(spacing: 8) {
                    Spacer().frame(width: 70)
                    methodMenu
                    matchTypeMenu
                    Text(String(localized: "Support wildcard * and ?."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Test your Rule")) {}
                        .buttonStyle(.link)
                }

                HStack {
                    Spacer().frame(width: 70)
                    Toggle(String(localized: "Include all subpaths of this URL"), isOn: $viewModel.includeSubpaths)
                        .toggleStyle(.checkbox)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var mapToSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Map To"))
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Protocol:"))
                        .frame(width: 64, alignment: .trailing)
                    schemeMenu
                }

                labeledTextField(String(localized: "Host:"), placeholder: "", text: $viewModel.destHost)
                    .onChange(of: viewModel.destHost) { _, newValue in
                        viewModel.tryParseDestinationURL(newValue)
                    }

                HStack {
                    Text(String(localized: "Port:"))
                        .frame(width: 64, alignment: .trailing)
                    TextField("443", text: $viewModel.destPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }

                labeledTextField(String(localized: "Path:"), placeholder: "v2/api", text: $viewModel.destPath)
                labeledTextField(String(localized: "Query:"), placeholder: "id=123", text: $viewModel.destQuery)

                Text(String(localized: "Leave textfields blank to keep it unchanged from matched requests. Wildcard/Regex is not allowed."))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 78)
                Text(String(localized: "Hint: Paste your URL to the Host textfield to auto-parse each components (Host, Port, Path, Query)."))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 78)

                Divider()
                    .padding(.leading, 78)
                    .padding(.vertical, 4)

                Text(String(localized: "Advanced Settings:"))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.leading, 78)

                Toggle(String(localized: "Preserve the Original URL after matching with Map Remote"), isOn: $viewModel.preserveOriginalURL)
                    .toggleStyle(.checkbox)
                    .padding(.leading, 78)
                Text(String(localized: "The Request URL will be replaced with a new Map Remote URL."))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 78)

                Toggle(String(localized: "Preserve Host Header"), isOn: $viewModel.preserveHost)
                    .toggleStyle(.checkbox)
                    .padding(.leading, 78)
                    .padding(.top, 2)
                Text(String(localized: "The `Host` header of Requests are not changed."))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 78)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var actionBar: some View {
        HStack {
            Spacer()
            Button(String(localized: "Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 100)
            Button(viewModel.existingID == nil ? String(localized: "Add (⌘↩)") : String(localized: "Save (⌘↩)")) {
                saveAndClose()
            }
            .keyboardShortcut(.defaultAction)
            .frame(width: 100)
            .disabled(!viewModel.isSaveEnabled)
        }
        .padding(.top, 2)
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
            menuLabel(viewModel.method.rawValue, minWidth: 86)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    private var matchTypeMenu: some View {
        Menu {
            ForEach(MapLocalMatchType.allCases) { matchType in
                Button { viewModel.matchType = matchType } label: {
                    menuCheckmarkLabel(matchType.displayName, isSelected: viewModel.matchType == matchType)
                }
            }
        } label: {
            menuLabel(viewModel.matchType.displayName, minWidth: 128)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    private var schemeMenu: some View {
        Menu {
            Button { viewModel.destScheme = "" } label: {
                menuCheckmarkLabel(String(localized: "Keep Original"), isSelected: viewModel.destScheme.isEmpty)
            }
            Divider()
            Button { viewModel.destScheme = "http" } label: {
                menuCheckmarkLabel("http", isSelected: viewModel.destScheme == "http")
            }
            Button { viewModel.destScheme = "https" } label: {
                menuCheckmarkLabel("https", isSelected: viewModel.destScheme == "https")
            }
        } label: {
            menuLabel(viewModel.destScheme.isEmpty ? "http/https" : viewModel.destScheme, minWidth: 80)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    private func labeledTextField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .frame(width: 70, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
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

    private func menuLabel(_ title: String, minWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .frame(minWidth: minWidth)
    }

    private func saveAndClose() {
        guard let rule = viewModel.makeRule() else {
            return
        }
        if viewModel.existingID == nil {
            Task { await RulePolicyGate.shared.addRule(rule) }
        } else {
            Task { await RulePolicyGate.shared.updateRule(rule) }
        }
        dismiss()
    }
}

private extension Result where Success == NSRegularExpression, Failure == RegexValidator.ValidationError {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}
