import AppKit
import os
import SwiftUI

// Presents the map local window for rule editing and management.

// MARK: - MapLocalViewModel

@MainActor @Observable
final class MapLocalViewModel {
    // MARK: Internal

    var allRules: [ProxyRule] = []
    var searchText = ""
    var selectedRuleIDs: Set<UUID> = []
    var showEditSheet = false
    var editingRule: ProxyRule?
    var pendingDraft: MapLocalDraft?
    var errorMessage: String?

    var mapLocalRules: [ProxyRule] {
        allRules.filter {
            if case .mapLocal = $0.action {
                return true
            }
            return false
        }
    }

    var filteredRules: [ProxyRule] {
        guard !searchText.isEmpty else {
            return mapLocalRules
        }
        let query = searchText.lowercased()
        return mapLocalRules.filter { rule in
            rule.name.lowercased().contains(query)
                || (rule.matchCondition.urlPattern?.lowercased().contains(query) ?? false)
                || filePath(for: rule).lowercased().contains(query)
        }
    }

    var areAllEnabled: Bool {
        get {
            let locals = mapLocalRules
            return !locals.isEmpty && locals.allSatisfy(\.isEnabled)
        }
        set {
            var updated = allRules
            for index in updated.indices {
                if case .mapLocal = updated[index].action {
                    updated[index].isEnabled = newValue
                }
            }
            allRules = updated
            Task { await RuleSyncService.replaceAllRules(updated) }
        }
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

    func removeSelectedRules() {
        let idsToRemove = selectedRuleIDs
        allRules.removeAll { idsToRemove.contains($0.id) }
        selectedRuleIDs.removeAll()
        let updated = allRules
        Task { await RuleSyncService.replaceAllRules(updated) }
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        selectedRuleIDs.remove(id)
        Task { await RuleSyncService.removeRule(id: id) }
    }

    func beginEditing(_ rule: ProxyRule) {
        editingRule = rule
        showEditSheet = true
    }

    func beginAdding() {
        editingRule = nil
        showEditSheet = true
    }

    func updateFilePath(for ruleID: UUID, newPath: String) {
        guard let index = allRules.firstIndex(where: { $0.id == ruleID }),
              case let .mapLocal(_, statusCode, isDirectory) = allRules[index].action else
        {
            return
        }
        allRules[index].action = .mapLocal(filePath: newPath, statusCode: statusCode, isDirectory: isDirectory)
        let updatedRule = allRules[index]
        Task { await RuleSyncService.updateRule(updatedRule) }
    }

    func filePath(for rule: ProxyRule) -> String {
        if case let .mapLocal(path, _, _) = rule.action {
            return path
        }
        return ""
    }

    func statusCode(for rule: ProxyRule) -> String {
        if case let .mapLocal(_, statusCode, _) = rule.action {
            return "\(statusCode)"
        }
        return "200"
    }

    func isDirectory(for rule: ProxyRule) -> Bool {
        if case let .mapLocal(_, _, isDirectory) = rule.action {
            return isDirectory
        }
        return false
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MapLocalViewModel")
}

// MARK: - MapLocalWindowView

struct MapLocalWindowView: View {
    // MARK: Internal

    @State var viewModel = MapLocalViewModel()

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
        .frame(width: 800, height: 480)
        .sheet(isPresented: $viewModel.showEditSheet) {
            MapLocalEditSheet(
                existingRule: viewModel.editingRule,
                draft: viewModel.pendingDraft,
                onSave: { rule in
                    if viewModel.editingRule != nil {
                        viewModel.updateRule(rule)
                    } else {
                        viewModel.addRule(rule)
                    }
                    viewModel.pendingDraft = nil
                }
            )
        }
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingDraft() }
        .onReceive(NotificationCenter.default.publisher(for: .openMapLocalWindow)) { _ in
            consumePendingDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .alert(
            String(localized: "Error"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 {
                    viewModel.errorMessage = nil
                } }
            )
        ) {
            Button(String(localized: "OK")) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
    }

    // MARK: Private

    private var ruleCountLabel: String {
        let count = viewModel.mapLocalRules.count
        if count == 1 {
            return String(localized: "1 rule")
        }
        return String(localized: "\(count) rules")
    }

    private var infoBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(String(localized: "Intercept matching requests and serve responses from local files or directories."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $viewModel.areAllEnabled) {
                Text(String(localized: "Enable All"))
                    .font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer()

            TextField(String(localized: "Search"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            Button {
                viewModel.beginAdding()
            } label: {
                Label(String(localized: "Add Rule"), systemImage: "plus")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var tableContent: some View {
        if viewModel.filteredRules.isEmpty {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text(String(localized: "No Map Local Rules"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Right-click a captured request and choose \"Map Local...\", or click + below."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.green.opacity(0.4))
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Example"))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 5) {
                            Text("api.example.com/v2/users")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Text("~/mock/users.json")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.leading, 6)
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 12)
        } else {
            Table(viewModel.filteredRules, selection: $viewModel.selectedRuleIDs) {
                TableColumn(String(localized: "Enable")) { (rule: ProxyRule) in
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { _ in viewModel.toggleRule(id: rule.id) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                }
                .width(50)

                TableColumn(String(localized: "URL Pattern")) { rule in
                    Text(rule.matchCondition.urlPattern ?? "*")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .help(rule.matchCondition.urlPattern ?? "*")
                }
                .width(min: 150, ideal: 220)

                TableColumn(String(localized: "Local Path")) { rule in
                    let path = viewModel.filePath(for: rule)
                    let isDir = viewModel.isDirectory(for: rule)
                    HStack(spacing: 4) {
                        Image(systemName: isDir ? "folder.fill" : "doc.fill")
                            .foregroundStyle(isDir ? .blue : .secondary)
                            .font(.caption2)
                        Text(abbreviatedPath(path))
                            .lineLimit(1)
                            .help(path)
                        Spacer()
                        Button {
                            browseFile(for: rule.id)
                        } label: {
                            Text("…")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderless)
                        .help(isDir
                            ? String(localized: "Choose local directory")
                            : String(localized: "Choose local file"))
                    }
                }
                .width(min: 150, ideal: 200)

                TableColumn(String(localized: "Status Code")) { rule in
                    let code = viewModel.statusCode(for: rule)
                    Text(code)
                        .monospacedDigit()
                        .foregroundColor(code == "200" ? .primary : .orange)
                }
                .width(70)

                TableColumn(String(localized: "Comment")) { (rule: ProxyRule) in
                    Text(rule.name)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 120)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first {
                    Button(String(localized: "Edit Rule")) {
                        if let rule = viewModel.allRules.first(where: { $0.id == id }) {
                            viewModel.beginEditing(rule)
                        }
                    }
                    Divider()
                    Button(String(localized: "Delete Rule"), role: .destructive) {
                        viewModel.removeRule(id: id)
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first,
                   let rule = viewModel.allRules.first(where: { $0.id == id })
                {
                    viewModel.beginEditing(rule)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.beginAdding()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)

            Button {
                viewModel.removeSelectedRules()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedRuleIDs.isEmpty)

            Spacer()

            Text(ruleCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func consumePendingDraft() {
        guard let draft = MapLocalDraftStore.shared.consumePending() else {
            return
        }
        viewModel.pendingDraft = draft
        viewModel.editingRule = nil
        viewModel.showEditSheet = true
    }

    private func browseFile(for ruleID: UUID) {
        let rule = viewModel.allRules.first { $0.id == ruleID }
        let isDir = rule.map { viewModel.isDirectory(for: $0) } ?? false

        let panel = NSOpenPanel()
        panel.canChooseFiles = !isDir
        panel.canChooseDirectories = isDir
        panel.allowsMultipleSelection = false
        panel.message = isDir
            ? String(localized: "Select a local directory to serve files from")
            : String(localized: "Select a local file to serve for matched requests")

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.updateFilePath(for: ruleID, newPath: url.path(percentEncoded: false))
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        guard !path.isEmpty else {
            return "—"
        }
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        return "…/\(parent)/\(name)"
    }
}

// MARK: - MapLocalMatchMode

private enum MapLocalMatchMode: String, CaseIterable {
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

// MARK: - MapLocalMapToMode

private enum MapLocalMapToMode: String, CaseIterable {
    case localFile
    case localDirectory
    case snapshot

    // MARK: Internal

    var displayName: String {
        switch self {
        case .localFile: "Local File"
        case .localDirectory: "Directory"
        case .snapshot: "Snapshot"
        }
    }
}

// MARK: - MapLocalEditSheet

private struct MapLocalEditSheet: View {
    // MARK: Lifecycle

    init(
        existingRule: ProxyRule?,
        draft: MapLocalDraft? = nil,
        onSave: @escaping (ProxyRule) -> Void
    ) {
        self.onSave = onSave
        self.draft = draft
        self.existingID = existingRule?.id

        if let existingRule {
            _comment = State(initialValue: existingRule.name)
            _urlPattern = State(initialValue: existingRule.matchCondition.urlPattern ?? "")
            _priority = State(initialValue: existingRule.priority)
            _isEnabled = State(initialValue: existingRule.isEnabled)
            _matchMode = State(initialValue: .regexAdvanced)
            if case let .mapLocal(path, code, isDir) = existingRule.action {
                _filePath = State(initialValue: path)
                _statusCode = State(initialValue: code)
                _mapToMode = State(initialValue: isDir ? .localDirectory : .localFile)
            }
        } else if let draft {
            _comment = State(initialValue: draft.suggestedName)
            let defaultMode: MapLocalMatchMode = draft.origin == .domainQuickCreate
                ? .includeSubpaths : .exactPath
            _matchMode = State(initialValue: defaultMode)
            if let url = draft.sourceURL {
                _urlPattern = State(initialValue: Self.generatePattern(
                    from: url, mode: defaultMode
                ))
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
                mapToSection
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
        .frame(width: 540, height: 520)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""
    @State private var urlPattern = ""
    @State private var matchMode: MapLocalMatchMode = .exactPath
    @State private var mapToMode: MapLocalMapToMode = .localFile
    @State private var filePath = ""
    @State private var statusCode = 200
    @State private var priority = 0
    @State private var isEnabled = true
    @State private var regexError: String?

    private let draft: MapLocalDraft?
    private let existingID: UUID?
    private let statusCodeOptions = [200, 201, 204, 301, 302, 400, 403, 404, 500, 502, 503]

    private var isEditing: Bool {
        existingID != nil
    }

    private var isValid: Bool {
        guard !comment.isEmpty else {
            return false
        }
        if mapToMode == .snapshot {
            return draft?.hasResponseBody == true
        }
        guard !filePath.isEmpty else {
            return false
        }
        if matchMode == .regexAdvanced {
            return validateRegex(urlPattern)
        }
        return true
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
                ForEach(MapLocalMatchMode.allCases, id: \.self) { mode in
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
                regexError = nil
            }

            TextField(String(localized: "URL Pattern"), text: $urlPattern)
                .font(.system(.body, design: .monospaced))

            if matchMode == .regexAdvanced, let error = regexError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let draft, draft.sourceURL != nil {
                matchPreview
            }
        }
    }

    @ViewBuilder private var matchPreview: some View {
        let sourceURL = draft?.sourceURL?.absoluteString ?? ""
        let subpathURL = (draft?.sourceURL?.absoluteString ?? "") + "/123"
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
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Map To Section

    private var mapToSection: some View {
        Section(String(localized: "Map To")) {
            Picker(String(localized: "Mode"), selection: $mapToMode) {
                Text(MapLocalMapToMode.localFile.displayName).tag(MapLocalMapToMode.localFile)
                Text(MapLocalMapToMode.localDirectory.displayName).tag(MapLocalMapToMode.localDirectory)
                Text(MapLocalMapToMode.snapshot.displayName).tag(MapLocalMapToMode.snapshot)
                    .disabled(draft?.hasResponseBody != true)
            }
            .pickerStyle(.segmented)

            if mapToMode == .snapshot, draft?.hasResponseBody != true {
                Text(String(localized: "No captured response body available for this draft."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if mapToMode == .snapshot, draft?.hasResponseBody == true {
                let expectedPath = MapLocalSnapshotService.expectedSnapshotPath(
                    contentType: draft?.responseContentType,
                    requestURL: draft?.sourceURL
                )
                LabeledContent(String(localized: "Path")) {
                    Text(expectedPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(String(localized: "Snapshot will be saved when you click Add Rule."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if mapToMode != .snapshot {
                HStack {
                    TextField(
                        mapToMode == .localDirectory
                            ? String(localized: "Directory Path")
                            : String(localized: "File Path"),
                        text: $filePath
                    )
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                    Button(String(localized: "Browse…")) { choosePath() }
                }

                if filePath.isEmpty {
                    Text(String(localized: "Select a local file or directory"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !filePath.isEmpty, mapToMode != .snapshot {
                LabeledContent(String(localized: "Content-Type")) {
                    Text(MimeTypeResolver.mimeType(for: filePath))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Picker(String(localized: "Status Code"), selection: $statusCode) {
                ForEach(statusCodeOptions, id: \.self) { code in
                    Text("\(code)").tag(code)
                }
            }
            .pickerStyle(.menu)

            if mapToMode == .localDirectory {
                directoryResolutionHint
            }
        }
    }

    @ViewBuilder private var directoryResolutionHint: some View {
        let sourcePath = draft?.sourcePath ?? "/example/path"
        let dirDisplay = filePath.isEmpty ? "~/Projects/dist/" : filePath

        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Path Resolution"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Request: \(sourcePath)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Local: \(dirDisplay)\(sourcePath)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.green)
                }
                Text(String(localized: "Root path (/) falls back to index.html"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

    private static func escapeRegex(_ string: String) -> String {
        NSRegularExpression.escapedPattern(for: string)
    }

    private static func generatePattern(from url: URL, mode: MapLocalMatchMode) -> String {
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

    private static func generateDomainPattern(from host: String, mode: MapLocalMatchMode) -> String {
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

    private func choosePath() {
        let isDir = mapToMode == .localDirectory
        let panel = NSOpenPanel()
        panel.canChooseFiles = !isDir
        panel.canChooseDirectories = isDir
        panel.allowsMultipleSelection = false
        panel.message = isDir
            ? String(localized: "Select a local directory to serve files from")
            : String(localized: "Select a local file to serve for matched requests")

        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path(percentEncoded: false)
        }
    }

    private func saveRule() {
        var resolvedPath = filePath
        let isDir = mapToMode == .localDirectory

        if mapToMode == .snapshot, let draft {
            guard let result = MapLocalSnapshotService.saveSnapshot(
                responseBody: draft.responseBody,
                contentType: draft.responseContentType,
                requestURL: draft.sourceURL
            ) else {
                return
            }
            resolvedPath = result.path
        }

        let condition = RuleMatchCondition(
            urlPattern: urlPattern.isEmpty ? nil : urlPattern
        )
        let rule = ProxyRule(
            id: existingID ?? UUID(),
            name: comment,
            isEnabled: isEnabled,
            matchCondition: condition,
            action: .mapLocal(filePath: resolvedPath, statusCode: statusCode, isDirectory: isDir),
            priority: priority
        )
        onSave(rule)
        dismiss()
    }

    private func validateRegex(_ pattern: String) -> Bool {
        guard !pattern.isEmpty else {
            return false
        }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            regexError = nil
            return true
        } catch {
            regexError = String(localized: "Invalid regex: \(error.localizedDescription)")
            return false
        }
    }
}
