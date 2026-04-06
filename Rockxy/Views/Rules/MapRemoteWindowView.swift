import os
import SwiftUI

// Presents the map remote window for rule editing and management.

// MARK: - MapRemoteWindowViewModel

@MainActor @Observable
final class MapRemoteWindowViewModel {
    // MARK: Internal

    private(set) var allRules: [ProxyRule] = []
    var searchText = ""

    var mapRemoteRules: [ProxyRule] {
        let remote = allRules.filter { rule in
            if case .mapRemote = rule.action {
                return true
            }
            return false
        }
        guard !searchText.isEmpty else {
            return remote
        }
        return remote.filter { rule in
            rule.name.localizedCaseInsensitiveContains(searchText)
                || (rule.matchCondition.urlPattern ?? "").localizedCaseInsensitiveContains(searchText)
                || destinationSummary(for: rule).localizedCaseInsensitiveContains(searchText)
        }
    }

    var ruleCount: Int {
        mapRemoteRules.count
    }

    func refreshFromEngine() async {
        allRules = await RuleEngine.shared.allRules
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
        }
    }

    func toggleRule(id: UUID) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index].isEnabled.toggle()
        Task { await RuleSyncService.toggleRule(id: id) }
    }

    func enableAll() {
        var updated = allRules
        for index in updated.indices {
            if case .mapRemote = updated[index].action {
                updated[index].isEnabled = true
            }
        }
        allRules = updated
        Task { await RuleSyncService.replaceAllRules(updated) }
    }

    func addRule(_ rule: ProxyRule) {
        allRules.append(rule)
        Task { await RuleSyncService.addRule(rule) }
    }

    func updateRule(_ rule: ProxyRule) {
        guard let index = allRules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        allRules[index] = rule
        Task { await RuleSyncService.updateRule(rule) }
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        Task { await RuleSyncService.removeRule(id: id) }
    }

    func destinationSummary(for rule: ProxyRule) -> String {
        if case let .mapRemote(config) = rule.action {
            return config.destinationSummary
        }
        return ""
    }

    func preservesHost(for rule: ProxyRule) -> Bool {
        if case let .mapRemote(config) = rule.action {
            return config.preserveHostHeader
        }
        return false
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MapRemoteWindowViewModel")
}

// MARK: - MapRemoteWindowView

struct MapRemoteWindowView: View {
    // MARK: Internal

    @State var viewModel = MapRemoteWindowViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            infoBar
            Divider()
            tableContent
            Divider()
            bottomBar
        }
        .frame(width: 880, height: 480)
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingDraft() }
        .onReceive(NotificationCenter.default.publisher(for: .openMapRemoteWindow)) { _ in
            consumePendingDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(isPresented: $showEditSheet) {
            MapRemoteEditSheet(
                existingRule: editingRule,
                draft: pendingDraft,
                onSave: { rule in
                    if editingRule != nil {
                        viewModel.updateRule(rule)
                    } else {
                        viewModel.addRule(rule)
                    }
                    pendingDraft = nil
                }
            )
        }
    }

    // MARK: Private

    @State private var selectedRuleID: UUID?
    @State private var showEditSheet = false
    @State private var editingRule: ProxyRule?
    @State private var pendingDraft: MapRemoteDraft?

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.enableAll()
            } label: {
                Text(String(localized: "Enable All"))
                    .font(.callout)
            }

            Spacer()

            TextField(String(localized: "Search"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            Button {
                pendingDraft = nil
                editingRule = nil
                showEditSheet = true
            } label: {
                Label(String(localized: "Add Rule"), systemImage: "plus")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var tableContent: some View {
        if viewModel.mapRemoteRules.isEmpty {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text(String(localized: "No Map Remote Rules"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(
                    String(localized: "Right-click a captured request and choose \"Map Remote...\", or click + below.")
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green.opacity(0.4))
                        .frame(width: 2, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Example"))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 5) {
                            Text("api.prod.example.com")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Text("api.staging.example.com")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.leading, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 12)
        } else {
            Table(viewModel.mapRemoteRules, selection: $selectedRuleID) {
                TableColumn("") { rule in
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { _ in viewModel.toggleRule(id: rule.id) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .width(40)

                TableColumn(String(localized: "Name")) { rule in
                    Text(rule.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .opacity(rule.isEnabled ? 1.0 : 0.5)
                }
                .width(min: 100, ideal: 140)

                TableColumn(String(localized: "Source Pattern")) { rule in
                    Text(rule.matchCondition.urlPattern ?? "*")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .help(rule.matchCondition.urlPattern ?? "*")
                        .opacity(rule.isEnabled ? 1.0 : 0.5)
                }
                .width(min: 160, ideal: 200)

                TableColumn("") { (_: ProxyRule) in
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .width(20)

                TableColumn(String(localized: "Destination")) { rule in
                    Text(viewModel.destinationSummary(for: rule))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.purple)
                        .lineLimit(1)
                        .help(viewModel.destinationSummary(for: rule))
                        .opacity(rule.isEnabled ? 1.0 : 0.5)
                }

                TableColumn("") { rule in
                    if viewModel.preservesHost(for: rule) {
                        Text("H")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
                .width(30)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first {
                    Button(String(localized: "Edit")) {
                        editingRule = viewModel.allRules.first { $0.id == id }
                        pendingDraft = nil
                        showEditSheet = true
                    }
                    Divider()
                    Button(String(localized: "Delete"), role: .destructive) {
                        viewModel.removeRule(id: id)
                        selectedRuleID = nil
                    }
                }
            }
        }
    }

    private var infoBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized: "Redirect matching requests to different servers. Blank destination fields keep the original value."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                pendingDraft = nil
                editingRule = nil
                showEditSheet = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)

            Button {
                guard let id = selectedRuleID else {
                    return
                }
                viewModel.removeRule(id: id)
                selectedRuleID = nil
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(selectedRuleID == nil)

            Spacer()

            Text(
                "\(viewModel.ruleCount) \(viewModel.ruleCount == 1 ? String(localized: "rule") : String(localized: "rules"))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func consumePendingDraft() {
        guard let draft = MapRemoteDraftStore.shared.consumePending() else {
            return
        }
        pendingDraft = draft
        editingRule = nil
        showEditSheet = true
    }
}

// MARK: - MapRemoteMatchMode

private enum MapRemoteMatchMode: String, CaseIterable {
    case exactPath
    case includeSubpaths
    case regexAdvanced

    // MARK: Internal

    var displayName: String {
        switch self {
        case .exactPath: "Exact Path"
        case .includeSubpaths: "Subpaths"
        case .regexAdvanced: "Regex"
        }
    }
}

// MARK: - MapRemoteEditSheet

private struct MapRemoteEditSheet: View {
    // MARK: Lifecycle

    init(
        existingRule: ProxyRule?,
        draft: MapRemoteDraft? = nil,
        onSave: @escaping (ProxyRule) -> Void
    ) {
        self.onSave = onSave
        self.draft = draft
        self.existingID = existingRule?.id

        if let existingRule {
            _comment = State(initialValue: existingRule.name)
            _urlPattern = State(initialValue: existingRule.matchCondition.urlPattern ?? "")
            _matchMode = State(initialValue: .regexAdvanced)
            if case let .mapRemote(config) = existingRule.action {
                _destScheme = State(initialValue: config.scheme ?? "")
                _destHost = State(initialValue: config.host ?? "")
                _destPort = State(initialValue: config.port.map(String.init) ?? "")
                _destPath = State(initialValue: config.path ?? "")
                _destQuery = State(initialValue: config.query ?? "")
                _preserveHost = State(initialValue: config.preserveHostHeader)
            }
            _isEnabled = State(initialValue: existingRule.isEnabled)
            _priority = State(initialValue: existingRule.priority)
        } else if let draft {
            _comment = State(initialValue: draft.suggestedName)
            let defaultMode: MapRemoteMatchMode = draft.origin == .domainQuickCreate
                ? .includeSubpaths : .exactPath
            _matchMode = State(initialValue: defaultMode)
            if let url = draft.sourceURL {
                _urlPattern = State(initialValue: Self.generatePattern(from: url, mode: defaultMode))
            } else {
                _urlPattern = State(initialValue: Self.generateDomainPattern(
                    from: draft.sourceHost, mode: defaultMode
                ))
            }
        }
    }

    // MARK: Internal

    let onSave: (ProxyRule) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                matchingRuleSection
                mapRemoteSection
                advancedSection
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? String(localized: "Save") : String(localized: "Add Rule")) {
                    saveRule()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 600, height: 540)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""
    @State private var urlPattern = ""
    @State private var matchMode: MapRemoteMatchMode = .exactPath
    @State private var destScheme = ""
    @State private var destHost = ""
    @State private var destPort = ""
    @State private var destPath = ""
    @State private var destQuery = ""
    @State private var preserveHost = false
    @State private var isEnabled = true
    @State private var priority = 0
    @State private var urlParseConfirm = false

    private let draft: MapRemoteDraft?
    private let existingID: UUID?

    private var isEditing: Bool {
        existingID != nil
    }

    private var hasAnyDestination: Bool {
        !destScheme.isEmpty || !destHost.isEmpty || !destPort.isEmpty
            || !destPath.isEmpty || !destQuery.isEmpty
    }

    private var isValid: Bool {
        guard !comment.isEmpty else {
            return false
        }
        guard hasAnyDestination else {
            return false
        }
        if matchMode == .regexAdvanced {
            guard !urlPattern.isEmpty else {
                return false
            }
            guard (try? NSRegularExpression(pattern: urlPattern)) != nil else {
                return false
            }
        }
        return true
    }

    private var destinationPreviewString: String {
        let sourceURL = draft?.sourceURL ?? URL(string: "https://example.com/path")
        let scheme = destScheme.isEmpty ? (sourceURL?.scheme ?? "https") : destScheme
        let host = destHost.isEmpty ? (sourceURL?.host ?? "example.com") : destHost
        let port = Int(destPort)
        let path = destPath.isEmpty ? (sourceURL?.path ?? "/") : destPath
        let query = destQuery.isEmpty ? sourceURL?.query : destQuery

        var result = "\(scheme)://\(host)"
        if let port {
            result += ":\(port)"
        }
        result += path
        if let query {
            result += "?\(query)"
        }
        return result
    }

    // MARK: - Matching Rule Section

    private var matchingRuleSection: some View {
        Section(String(localized: "Matching Rule")) {
            TextField(String(localized: "Name"), text: $comment)

            if let draft, let url = draft.sourceURL {
                LabeledContent(String(localized: "Source")) {
                    Text("\(draft.sourceMethod ?? "GET") \(url.absoluteString)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Picker(String(localized: "Match"), selection: $matchMode) {
                ForEach(MapRemoteMatchMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: matchMode) { _, newMode in
                if let draft, let url = draft.sourceURL {
                    urlPattern = Self.generatePattern(from: url, mode: newMode)
                } else if let draft {
                    urlPattern = Self.generateDomainPattern(from: draft.sourceHost, mode: newMode)
                }
            }

            TextField(String(localized: "URL Pattern"), text: $urlPattern)
                .font(.system(.body, design: .monospaced))

            if let draft, draft.sourceURL != nil {
                matchPreview
            }
        }
    }

    @ViewBuilder private var matchPreview: some View {
        let sourceURL = draft?.sourceURL?.absoluteString ?? ""
        let subpathURL = sourceURL + "/123"
        let siblingURL = {
            guard let url = draft?.sourceURL else {
                return ""
            }
            return url.deletingLastPathComponent().appendingPathComponent("other").absoluteString
        }()

        VStack(alignment: .leading, spacing: 2) {
            previewLine(url: sourceURL, matches: testMatch(sourceURL))
            previewLine(url: subpathURL, matches: testMatch(subpathURL))
            previewLine(url: siblingURL, matches: testMatch(siblingURL))
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Map Remote Section

    private var mapRemoteSection: some View {
        Section(String(localized: "Map Remote")) {
            Text(String(localized: "Leave fields blank to keep the original request value."))
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack {
                Text(String(localized: "Protocol"))
                    .frame(width: 65, alignment: .leading)
                Picker("", selection: $destScheme) {
                    Text(String(localized: "Keep Original")).tag("")
                    Text("http").tag("http")
                    Text("https").tag("https")
                }
                .labelsHidden()
                .frame(width: 140)
            }

            HStack {
                Text(String(localized: "Host"))
                    .frame(width: 65, alignment: .leading)
                TextField(String(localized: "Destination host"), text: $destHost)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: destHost) { _, newValue in
                        tryParseURL(newValue)
                    }
            }

            HStack {
                Text(String(localized: "Port"))
                    .frame(width: 65, alignment: .leading)
                TextField(String(localized: "Default"), text: $destPort)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 130)
            }

            HStack {
                Text(String(localized: "Path"))
                    .frame(width: 65, alignment: .leading)
                TextField(String(localized: "Keep original path"), text: $destPath)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text(String(localized: "Query"))
                    .frame(width: 65, alignment: .leading)
                TextField(String(localized: "Keep original query"), text: $destQuery)
                    .font(.system(.body, design: .monospaced))
            }

            if urlParseConfirm {
                Text(String(localized: "URL parsed into components"))
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if !hasAnyDestination {
                Text(String(localized: "At least one destination field is required"))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if hasAnyDestination {
                destinationPreview
            }
        }
    }

    private var destinationPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Destination Preview"))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(destinationPreviewString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.purple)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section(String(localized: "Advanced")) {
            Toggle(String(localized: "Preserve Host Header"), isOn: $preserveHost)
            Text(
                String(
                    localized: "Send the original Host header to the destination server. Useful when the backend validates the Host header."
                )
            )
            .font(.caption)
            .foregroundStyle(.tertiary)

            if preserveHost, !destHost.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    let originalHost = draft?.sourceHost ?? "original-host"
                    Text(String(localized: "Request will connect to \(destHost) but send Host: \(originalHost)"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private func previewLine(url: String, matches: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: matches ? "checkmark.circle" : "xmark.circle")
                .font(.system(size: 9))
                .foregroundStyle(matches ? .green : .red)
            Text(url)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Pattern Helpers

    private static func escapeRegex(_ string: String) -> String {
        NSRegularExpression.escapedPattern(for: string)
    }

    private static func generatePattern(from url: URL, mode: MapRemoteMatchMode) -> String {
        let scheme = url.scheme ?? "https"
        let host = escapeRegex(url.host ?? "")
        let path = escapeRegex(url.path)
        switch mode {
        case .exactPath:
            return "^\(scheme)://\(host)\(path)$"
        case .includeSubpaths:
            return "^\(scheme)://\(host)\(path).*"
        case .regexAdvanced:
            return "\(scheme)://\(host)\(path)"
        }
    }

    private static func generateDomainPattern(from host: String, mode: MapRemoteMatchMode) -> String {
        let escapedHost = escapeRegex(host)
        switch mode {
        case .exactPath:
            return "^https://\(escapedHost)/?$"
        case .includeSubpaths:
            return "^https://\(escapedHost)/.*"
        case .regexAdvanced:
            return ".*\(escapedHost).*"
        }
    }

    private func testMatch(_ url: String) -> Bool {
        guard !urlPattern.isEmpty else {
            return false
        }
        return url.range(of: urlPattern, options: .regularExpression) != nil
    }

    private func tryParseURL(_ input: String) {
        guard input.contains("://"),
              let components = URLComponents(string: input),
              let host = components.host, !host.isEmpty else
        {
            urlParseConfirm = false
            return
        }

        destScheme = components.scheme ?? ""
        destHost = host
        if let port = components.port {
            destPort = String(port)
        }
        if !components.path.isEmpty, components.path != "/" {
            destPath = components.path
        }
        if let query = components.query {
            destQuery = query
        }
        urlParseConfirm = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            urlParseConfirm = false
        }
    }

    private func saveRule() {
        let condition = RuleMatchCondition(
            urlPattern: urlPattern.isEmpty ? nil : urlPattern
        )
        let config = MapRemoteConfiguration(
            scheme: destScheme.isEmpty ? nil : destScheme,
            host: destHost.isEmpty ? nil : destHost,
            port: Int(destPort),
            path: destPath.isEmpty ? nil : destPath,
            query: destQuery.isEmpty ? nil : destQuery,
            preserveHostHeader: preserveHost
        )
        let rule = ProxyRule(
            id: existingID ?? UUID(),
            name: comment,
            isEnabled: isEnabled,
            matchCondition: condition,
            action: .mapRemote(configuration: config),
            priority: priority
        )
        onSave(rule)
        dismiss()
    }
}
