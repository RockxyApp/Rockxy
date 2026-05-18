import AppKit
import os
import SwiftUI

// Presents the Proxyman-style Map Local management and editor windows.

// MARK: - MapLocalHTTPMethod

enum MapLocalHTTPMethod: String, CaseIterable, Identifiable {
    case any = "ANY"
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
    case trace = "TRACE"

    var id: String { rawValue }

    init(ruleMethod: String?) {
        guard let ruleMethod,
              let method = Self(rawValue: ruleMethod.uppercased()) else
        {
            self = .any
            return
        }
        self = method
    }

    var ruleValue: String? {
        self == .any ? nil : rawValue
    }
}

// MARK: - MapLocalMatchType

enum MapLocalMatchType: String, CaseIterable, Identifiable {
    case wildcard
    case regex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wildcard: "Use Wildcard"
        case .regex: "Use Regex"
        }
    }
}

// MARK: - MapLocalTargetMode

enum MapLocalTargetMode: String, CaseIterable, Identifiable {
    case localFile
    case localDirectory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localFile: "Local File"
        case .localDirectory: "Local Directory"
        }
    }
}

// MARK: - MapLocalDelayPreset

enum MapLocalDelayPreset: String, CaseIterable, Identifiable {
    case none
    case oneSecond
    case twoSeconds
    case threeSeconds
    case fiveSeconds
    case tenSeconds
    case thirtySeconds
    case sixtySeconds
    case random
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "No Delay"
        case .oneSecond: "1 second"
        case .twoSeconds: "2 seconds"
        case .threeSeconds: "3 seconds"
        case .fiveSeconds: "5 seconds"
        case .tenSeconds: "10 seconds"
        case .thirtySeconds: "30 seconds"
        case .sixtySeconds: "60 seconds"
        case .random: "Random (1-15s)"
        case .custom: "Custom"
        }
    }

    var delayMs: Int {
        switch self {
        case .none: 0
        case .oneSecond: 1_000
        case .twoSeconds: 2_000
        case .threeSeconds: 3_000
        case .fiveSeconds: 5_000
        case .tenSeconds: 10_000
        case .thirtySeconds: 30_000
        case .sixtySeconds: 60_000
        case .random: -1
        case .custom: 0
        }
    }

    static func from(delayMs: Int) -> Self {
        switch delayMs {
        case 0: .none
        case 1_000: .oneSecond
        case 2_000: .twoSeconds
        case 3_000: .threeSeconds
        case 5_000: .fiveSeconds
        case 10_000: .tenSeconds
        case 30_000: .thirtySeconds
        case 60_000: .sixtySeconds
        case -1: .random
        default: .custom
        }
    }
}

// MARK: - MapLocalEditorContext

struct MapLocalEditorContext {
    var existingRule: ProxyRule?
    var draft: MapLocalDraft?

    static let blank = MapLocalEditorContext()
}

// MARK: - MapLocalEditorStore

@MainActor @Observable
final class MapLocalEditorStore {
    private init() {}

    static let shared = MapLocalEditorStore()

    private(set) var context = MapLocalEditorContext.blank
    var draftVersion: UInt64 = 0

    func openNew(draft: MapLocalDraft? = nil) {
        context = MapLocalEditorContext(existingRule: nil, draft: draft)
        draftVersion &+= 1
    }

    func openExisting(_ rule: ProxyRule) {
        context = MapLocalEditorContext(existingRule: rule, draft: nil)
        draftVersion &+= 1
    }
}

// MARK: - MapLocalViewModel

@MainActor @Observable
final class MapLocalViewModel {
    // MARK: Internal

    var allRules: [ProxyRule] = []
    var searchText = ""
    var selectedRuleIDs: Set<UUID> = []
    var isFilterVisible = false
    var isToolEnabled: Bool
    var errorMessage: String?

    init(isToolEnabled: Bool? = nil) {
        self.isToolEnabled = isToolEnabled ?? Self.defaultToolEnabled
    }

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
                || methodLabel(for: rule).lowercased().contains(query)
                || filePath(for: rule).lowercased().contains(query)
        }
    }

    var selectedRule: ProxyRule? {
        guard let id = selectedRuleIDs.first else {
            return nil
        }
        return allRules.first { $0.id == id }
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
            Task {
                await RulePolicyGate.shared.replaceAllRules(updated)
                allRules = await RuleEngine.shared.allRules
            }
        }
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
        Task { await RulePolicyGate.shared.setMapLocalToolEnabled(enabled) }
    }

    func toggleRule(id: UUID) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index].isEnabled.toggle()
        Task {
            let accepted = await RulePolicyGate.shared.toggleRule(id: id)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
            }
        }
    }

    func addRule(_ rule: ProxyRule) {
        allRules.append(rule)
        selectedRuleIDs = [rule.id]
        Task {
            let accepted = await RulePolicyGate.shared.addRule(rule)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
            }
        }
    }

    func updateRule(_ rule: ProxyRule) {
        guard let index = allRules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        allRules[index] = rule
        Task { await RulePolicyGate.shared.updateRule(rule) }
    }

    func removeSelectedRules() {
        let idsToRemove = selectedRuleIDs
        guard !idsToRemove.isEmpty else {
            return
        }
        allRules.removeAll { idsToRemove.contains($0.id) }
        selectedRuleIDs.removeAll()
        let updated = allRules
        Task { await RulePolicyGate.shared.replaceAllRules(updated) }
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        selectedRuleIDs.remove(id)
        Task { await RulePolicyGate.shared.removeRule(id: id) }
    }

    func duplicateSelectedRule() {
        guard var rule = selectedRule else {
            return
        }
        rule = ProxyRule(
            name: "\(rule.name) Copy",
            isEnabled: rule.isEnabled,
            matchCondition: rule.matchCondition,
            action: rule.action,
            priority: rule.priority
        )
        addRule(rule)
    }

    func createNewFolderPlaceholder() {
        let rule = ProxyRule(
            name: "New Folder",
            isEnabled: false,
            matchCondition: RuleMatchCondition(urlPattern: nil),
            action: .mapLocal(filePath: "", isDirectory: true)
        )
        addRule(rule)
    }

    func filePath(for rule: ProxyRule) -> String {
        if case let .mapLocal(path, _, _, _) = rule.action {
            return path
        }
        return ""
    }

    func methodLabel(for rule: ProxyRule) -> String {
        rule.matchCondition.method?.uppercased() ?? "ANY"
    }

    func matchingRuleLabel(for rule: ProxyRule) -> String {
        guard let pattern = rule.matchCondition.urlPattern, !pattern.isEmpty else {
            return "<Missing URL>"
        }
        if pattern.contains(".*") || pattern.contains("\\.") {
            return "Wildcard: \(readablePattern(pattern))"
        }
        return pattern
    }

    func mapFromLabel(for rule: ProxyRule) -> String {
        let prefix = isDirectory(for: rule) ? "Directory: " : "File: "
        let path = filePath(for: rule)
        return prefix + (path.isEmpty ? "<Missing Path>" : abbreviatedPath(path))
    }

    func isDirectory(for rule: ProxyRule) -> Bool {
        if case let .mapLocal(_, _, isDirectory, _) = rule.action {
            return isDirectory
        }
        return false
    }

    func delayLabel(for rule: ProxyRule) -> String {
        if case let .mapLocal(_, _, _, delayMs) = rule.action, delayMs != 0 {
            return MapLocalDelayPreset.from(delayMs: delayMs).displayName
        }
        return ""
    }

    // MARK: Private

    private static let toolEnabledKey = "mapLocalToolEnabled"
    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MapLocalViewModel")
    private static var defaultToolEnabled: Bool {
        UserDefaults.standard.object(forKey: toolEnabledKey) as? Bool ?? true
    }

    private func readablePattern(_ pattern: String) -> String {
        pattern
            .replacingOccurrences(of: #"^https?://"#, with: "https://", options: .regularExpression)
            .replacingOccurrences(of: #"\\."#, with: ".")
            .replacingOccurrences(of: #"\.\*"#, with: "*", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "^$"))
    }

    private func abbreviatedPath(_ path: String) -> String {
        guard !path.isEmpty else {
            return "<Missing Path>"
        }
        let maxLength = 78
        guard path.count > maxLength else {
            return path
        }
        let suffix = path.suffix(maxLength - 3)
        return "...\(suffix)"
    }
}

// MARK: - MapLocalWindowView

struct MapLocalWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @State var viewModel = MapLocalViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tableContent
            shortcutStrip
            bottomBar
        }
        .frame(width: 1_024, height: 570)
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingDraftIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .openMapLocalWindow)) { _ in
            consumePendingDraftIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .alert(
            String(localized: "Map Local"),
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
                Text(String(localized: "Enable Map Local Tool"))
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .padding(.top, 16)

            Text(String(localized: "Map a Response with a Local File or Directory. Support Status Code, Headers and Body."))
                .font(.system(size: 13))
            Text(String(localized: "Each request is checked against the rules from top to bottom, stopping when a match is found."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if viewModel.isFilterVisible {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Filter Map Local rules"), text: $viewModel.searchText)
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
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var tableContent: some View {
        Table(viewModel.filteredRules, selection: $viewModel.selectedRuleIDs) {
            TableColumn(String(localized: "Name")) { rule in
                HStack(spacing: 7) {
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { _ in viewModel.toggleRule(id: rule.id) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    Text(rule.name.isEmpty ? String(localized: "Untitled") : rule.name)
                        .lineLimit(1)
                }
            }
            .width(min: 190, ideal: 220)

            TableColumn(String(localized: "Method")) { rule in
                Text(viewModel.methodLabel(for: rule))
                    .lineLimit(1)
            }
            .width(86)

            TableColumn(String(localized: "Matching Rule")) { rule in
                Text(viewModel.matchingRuleLabel(for: rule))
                    .lineLimit(1)
                    .help(rule.matchCondition.urlPattern ?? "<Missing URL>")
            }
            .width(min: 260, ideal: 320)

            TableColumn(String(localized: "Map from")) { rule in
                HStack(spacing: 6) {
                    Text(viewModel.mapFromLabel(for: rule))
                        .lineLimit(1)
                        .help(viewModel.filePath(for: rule))
                    if !viewModel.delayLabel(for: rule).isEmpty {
                        Text(viewModel.delayLabel(for: rule))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 360, ideal: 500)
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
                    String(localized: "No Map Local Rules"),
                    systemImage: "folder.badge.gearshape",
                    description: Text(String(localized: "Click + or create a rule from a captured request."))
                )
            }
        }
        .padding(.horizontal, 18)
    }

    private var shortcutStrip: some View {
        Text("New: ⌘N    Edit: ⌘↩    Delete: ⌘⌫    Duplicate: ⌘D    Toggle: ↵")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
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
            .overlay(
                Rectangle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .frame(width: 37, height: 19)

            Button(String(localized: "New Folder")) {
                viewModel.createNewFolderPlaceholder()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button {
                viewModel.errorMessage = String(localized: "Map Local checks rules from top to bottom and returns the first matching local response.")
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
                .keyboardShortcut(.return, modifiers: .command)
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
        .padding(.horizontal, 18)
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

    private func openNewEditor(draft: MapLocalDraft? = nil) {
        MapLocalEditorStore.shared.openNew(draft: draft)
        openWindow(id: "mapLocalEditor")
    }

    private func openEditor(for rule: ProxyRule) {
        MapLocalEditorStore.shared.openExisting(rule)
        openWindow(id: "mapLocalEditor")
    }

    private func consumePendingDraftIfNeeded() {
        guard let draft = MapLocalDraftStore.shared.consumePending() else {
            return
        }
        openNewEditor(draft: draft)
    }
}

// MARK: - MapLocalEditorViewModel

@MainActor @Observable
final class MapLocalEditorViewModel {
    // MARK: Internal

    var name = "Untitled"
    var urlText = ""
    var method: MapLocalHTTPMethod = .any
    var matchType: MapLocalMatchType = .wildcard
    var includeSubpaths = false
    var delayPreset: MapLocalDelayPreset = .none
    var customDelaySeconds = 15
    var targetMode: MapLocalTargetMode = .localFile
    var localFileEnabled = true
    var localDirectoryEnabled = false
    var filePath = ""
    var directoryPath = ""
    var httpMessageText = MapLocalHTTPMessage.defaultMessage(statusCode: 200)
    var autoSave = true
    var errorMessage: String?

    private(set) var existingID: UUID?
    private(set) var originalRule: ProxyRule?
    private(set) var draft: MapLocalDraft?
    private(set) var isLoaded = false

    var windowTitle: String {
        "Map Local Editor: \(name.isEmpty ? "Untitled" : name)"
    }

    var selectedPath: String {
        targetMode == .localDirectory ? directoryPath : filePath
    }

    var isDirectoryValid: Bool {
        guard !directoryPath.isEmpty else {
            return false
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isTargetValid
            && RegexValidator.compile(urlPatternForSaving()).isSuccess
    }

    var delayMs: Int {
        if delayPreset == .custom {
            return max(0, customDelaySeconds) * 1_000
        }
        return delayPreset.delayMs
    }

    func load(context: MapLocalEditorContext) {
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

    func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = targetMode == .localFile
        panel.canChooseDirectories = targetMode == .localDirectory
        panel.allowsMultipleSelection = false
        panel.message = targetMode == .localDirectory
            ? String(localized: "Select a local directory to serve files from")
            : String(localized: "Select a local file to serve for matched requests")

        if panel.runModal() == .OK, let url = panel.url {
            if targetMode == .localDirectory {
                directoryPath = url.path(percentEncoded: false)
                localDirectoryEnabled = true
            } else {
                filePath = url.path(percentEncoded: false)
                localFileEnabled = true
                httpMessageText = MapLocalHTTPMessage.message(statusCode: statusCodeFromText(), filePath: filePath)
            }
        }
    }

    func showSelectedPathInFinder() {
        let path = selectedPath
        guard !path.isEmpty else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openSelectedPath(with app: MapLocalExternalEditor) {
        let path = selectedPath
        guard !path.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        if let bundleID = app.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init()) { _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func makeRule() -> ProxyRule? {
        guard isSaveEnabled else {
            errorMessage = String(localized: "Complete the matching rule and local target before saving.")
            return nil
        }

        do {
            if targetMode == .localFile {
                try saveLocalFileIfNeeded()
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        var condition = originalRule?.matchCondition ?? RuleMatchCondition()
        condition.urlPattern = urlPatternForSaving()
        condition.method = method.ruleValue

        return ProxyRule(
            id: existingID ?? UUID(),
            name: name,
            isEnabled: originalRule?.isEnabled ?? true,
            matchCondition: condition,
            action: .mapLocal(
                filePath: targetMode == .localDirectory ? directoryPath : filePath,
                statusCode: statusCodeFromText(),
                isDirectory: targetMode == .localDirectory,
                delayMs: delayMs
            ),
            priority: originalRule?.priority ?? 0
        )
    }

    func urlPatternForSaving() -> String {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matchType == .wildcard else {
            return trimmed
        }
        let pattern = includeSubpaths && !trimmed.hasSuffix("*") ? "\(trimmed)*" : trimmed
        return Self.wildcardToRegex(pattern)
    }

    // MARK: Private

    private var isTargetValid: Bool {
        switch targetMode {
        case .localFile:
            return localFileEnabled && !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .localDirectory:
            return localDirectoryEnabled && isDirectoryValid
        }
    }

    private func loadBlank() {
        name = "Untitled"
        urlText = ""
        method = .any
        matchType = .wildcard
        includeSubpaths = false
        delayPreset = .none
        customDelaySeconds = 15
        targetMode = .localFile
        localFileEnabled = true
        localDirectoryEnabled = false
        filePath = Self.defaultMapLocalFilePath()
        directoryPath = ""
        httpMessageText = MapLocalHTTPMessage.defaultMessage(statusCode: 200)
    }

    private func load(draft: MapLocalDraft) {
        loadBlank()
        name = draft.suggestedName.isEmpty ? "Untitled" : draft.suggestedName
        method = MapLocalHTTPMethod(ruleMethod: draft.sourceMethod)
        includeSubpaths = draft.origin == .domainQuickCreate
        if let sourceURL = draft.sourceURL {
            urlText = sourceURL.absoluteString
        } else {
            urlText = "https://\(draft.sourceHost)/*"
        }
        if let body = draft.responseBody, !body.isEmpty {
            let status = 200
            let contentType = draft.responseContentType ?? "application/json; charset=utf-8"
            let bodyText = String(data: body, encoding: .utf8) ?? ""
            httpMessageText = MapLocalHTTPMessage.message(statusCode: status, contentType: contentType, body: bodyText)
        }
    }

    private func load(existingRule rule: ProxyRule) {
        name = rule.name.isEmpty ? "Untitled" : rule.name
        urlText = rule.matchCondition.urlPattern ?? ""
        method = MapLocalHTTPMethod(ruleMethod: rule.matchCondition.method)
        matchType = .regex
        includeSubpaths = false
        if case let .mapLocal(path, statusCode, isDirectory, delayMs) = rule.action {
            targetMode = isDirectory ? .localDirectory : .localFile
            filePath = isDirectory ? "" : path
            directoryPath = isDirectory ? path : ""
            localFileEnabled = !isDirectory
            localDirectoryEnabled = isDirectory
            delayPreset = MapLocalDelayPreset.from(delayMs: delayMs)
            if delayPreset == .custom {
                customDelaySeconds = max(0, delayMs / 1_000)
            }
            httpMessageText = MapLocalHTTPMessage.message(statusCode: statusCode, filePath: path)
        }
    }

    private func statusCodeFromText() -> Int {
        MapLocalHTTPMessage.parse(httpMessageText).statusCode
    }

    private func saveLocalFileIfNeeded() throws {
        let parsed = MapLocalHTTPMessage.parse(httpMessageText)
        let url = URL(fileURLWithPath: filePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(parsed.body.utf8).write(to: url, options: .atomic)
    }

    private static func defaultMapLocalFilePath() -> String {
        let directory = RockxyIdentity.current
            .appSupportDirectory()
            .appendingPathComponent("map-local", isDirectory: true)
        return directory
            .appendingPathComponent("default_message_\(UUID().uuidString.prefix(8)).json")
            .path
    }

    private static func wildcardToRegex(_ pattern: String) -> String {
        var result = ""
        for char in pattern {
            switch char {
            case "*":
                result += ".*"
            case "?":
                result += "."
            default:
                result += NSRegularExpression.escapedPattern(for: String(char))
            }
        }
        return result
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

// MARK: - MapLocalEditorWindowView

struct MapLocalEditorWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editorStore = MapLocalEditorStore.shared
    @State var viewModel = MapLocalEditorViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            matchingRuleSection
            mapToSection
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: 960, height: 640)
        .navigationTitle(viewModel.windowTitle)
        .onAppear { viewModel.load(context: editorStore.context) }
        .onChange(of: editorStore.draftVersion) { _, _ in
            viewModel.load(context: editorStore.context)
        }
        .alert(
            String(localized: "Map Local"),
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
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Matching Rule"))
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "Name:"))
                        .frame(width: 70, alignment: .trailing)
                    TextField(String(localized: "Untitled"), text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text(String(localized: "URL:"))
                        .frame(width: 70, alignment: .trailing)
                    TextField("api.proxyman.com/v1/*", text: $viewModel.urlText)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Spacer().frame(width: 70)
                    methodMenu
                    matchTypeMenu
                    Text(String(localized: "Support wildcard * and ?."))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Test your Rule")) {}
                        .buttonStyle(.link)
                }

                HStack {
                    Spacer().frame(width: 70)
                    Toggle(String(localized: "Include all subpaths of this URL"), isOn: $viewModel.includeSubpaths)
                        .toggleStyle(.checkbox)
                }

                Divider()
                    .padding(.leading, 70)

                HStack(spacing: 12) {
                    Spacer().frame(width: 70)
                    Text(String(localized: "Advanced Settings:"))
                        .font(.system(size: 13, weight: .semibold))
                }
                HStack(spacing: 10) {
                    Text(String(localized: "Delay Response:"))
                        .frame(width: 140, alignment: .trailing)
                    delayMenu
                    if viewModel.delayPreset == .custom {
                        Stepper(
                            String(localized: "\(viewModel.customDelaySeconds) seconds"),
                            value: $viewModel.customDelaySeconds,
                            in: 0 ... 300
                        )
                        .frame(width: 160)
                    }
                }
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var mapToSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Map To"))
                .font(.system(size: 15))

            VStack(spacing: 0) {
                Picker("", selection: $viewModel.targetMode) {
                    Text(MapLocalTargetMode.localFile.displayName).tag(MapLocalTargetMode.localFile)
                    Text(MapLocalTargetMode.localDirectory.displayName).tag(MapLocalTargetMode.localDirectory)
                }
                .pickerStyle(.segmented)
                .frame(width: 230)
                .offset(y: -22)

                if viewModel.targetMode == .localFile {
                    localFileSection
                } else {
                    localDirectorySection
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor).opacity(0.35)))
        }
    }

    private var localFileSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(String(localized: "Enable Local File"), isOn: $viewModel.localFileEnabled)
                .toggleStyle(.checkbox)
            Text("File: \(viewModel.filePath)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 7) {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                Text(String(localized: "Map Response with HTTP Message format (Saved)"))
                    .foregroundStyle(.secondary)
            }

            ScriptCodeEditor(text: $viewModel.httpMessageText)
                .frame(minHeight: 210)
                .overlay(Rectangle().stroke(Color(nsColor: .separatorColor).opacity(0.3)))

            HStack(spacing: 10) {
                Button(String(localized: "Select Local File")) { viewModel.choosePath() }
                Text(String(localized: "Accept HTTP Message Format or Local File"))
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.errorMessage = String(localized: """
                    Paste an HTTP response message or plain body. Rockxy saves the body to the local file and uses the status line for the response code.
                    """)
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                Spacer()
                gearMenu
                Button(String(localized: "Save ⌘S")) { saveAndClose() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!viewModel.isSaveEnabled)
            }
        }
        .offset(y: -12)
    }

    private var localDirectorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(String(localized: "Enable Local Directory"), isOn: $viewModel.localDirectoryEnabled)
                .toggleStyle(.checkbox)

            HStack {
                Text(String(localized: "Directory Path:"))
                TextField("", text: $viewModel.directoryPath)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isDirectoryValid ? .green : .red)
                    .frame(width: 10, height: 10)
                Text(viewModel.isDirectoryValid
                    ? String(localized: "Directory Found")
                    : String(localized: "Directory Not Found!"))
                .foregroundStyle(.secondary)
            }
            .padding(.leading, 205)

            HStack(spacing: 12) {
                Spacer().frame(width: 200)
                Button(String(localized: "Select Directory")) { viewModel.choosePath() }
                Button(String(localized: "Show in Finder")) { viewModel.showSelectedPathInFinder() }
                    .disabled(!viewModel.isDirectoryValid)
            }

            HStack(spacing: 12) {
                Spacer().frame(width: 200)
                Text(String(localized: "Support map from Root or Sub-Directories"))
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.errorMessage = String(localized: """
                    Directory mode maps request subpaths into the selected local directory. Root requests fall back to index.html when present.
                    """)
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button(String(localized: "Save ⌘S")) { saveAndClose() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!viewModel.isSaveEnabled)
            }
            Spacer(minLength: 80)
        }
        .offset(y: -6)
    }

    private var methodMenu: some View {
        Menu {
            Picker("", selection: $viewModel.method) {
                ForEach(MapLocalHTTPMethod.allCases) { method in
                    Text(method.rawValue).tag(method)
                }
            }
        } label: {
            menuLabel(viewModel.method.rawValue)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var matchTypeMenu: some View {
        Menu {
            Picker("", selection: $viewModel.matchType) {
                Text(MapLocalMatchType.wildcard.displayName).tag(MapLocalMatchType.wildcard)
                Text(MapLocalMatchType.regex.displayName).tag(MapLocalMatchType.regex)
                Divider()
                Menu(String(localized: "Advanced")) {
                    Button(String(localized: "Use Regex")) { viewModel.matchType = .regex }
                    Button(String(localized: "Use Wildcard")) { viewModel.matchType = .wildcard }
                }
            }
        } label: {
            menuLabel(viewModel.matchType.displayName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var delayMenu: some View {
        Menu {
            Picker("", selection: $viewModel.delayPreset) {
                ForEach(MapLocalDelayPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
        } label: {
            menuLabel(viewModel.delayPreset.displayName, minWidth: 132)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var gearMenu: some View {
        Menu {
            Toggle(String(localized: "Auto-Save"), isOn: $viewModel.autoSave)
            Divider()
            Button(String(localized: "Show in Finder...")) { viewModel.showSelectedPathInFinder() }
            Divider()
            ForEach(MapLocalExternalEditor.allCases) { editor in
                Button(editor.displayName) { viewModel.openSelectedPath(with: editor) }
            }
        } label: {
            Label(String(localized: "Settings"), systemImage: "gearshape.fill")
                .labelStyle(.iconOnly)
                .frame(width: 54)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func menuLabel(_ title: String, minWidth: CGFloat = 90) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .frame(minWidth: minWidth)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

// MARK: - MapLocalExternalEditor

enum MapLocalExternalEditor: String, CaseIterable, Identifiable {
    case code
    case cursor
    case textEdit
    case xcode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .code: "Code"
        case .cursor: "Cursor"
        case .textEdit: "TextEdit"
        case .xcode: "Xcode"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .code: "com.microsoft.VSCode"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .textEdit: "com.apple.TextEdit"
        case .xcode: "com.apple.dt.Xcode"
        }
    }
}

// MARK: - MapLocalHTTPMessage

enum MapLocalHTTPMessage {
    static func defaultMessage(statusCode: Int) -> String {
        message(statusCode: statusCode, contentType: "application/json; charset=utf-8", body: "{\n  \"status\": \"ok\"\n}")
    }

    static func message(statusCode: Int, filePath: String) -> String {
        let body = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? "{\n  \"status\": \"ok\"\n}"
        return message(statusCode: statusCode, contentType: MimeTypeResolver.mimeType(for: filePath), body: body)
    }

    static func message(statusCode: Int, contentType: String, body: String) -> String {
        let status = HTTPURLResponse.localizedString(forStatusCode: statusCode).uppercased()
        return "HTTP/1.1 \(statusCode) \(status)\nContent-Type: \(contentType)\n\n\(body)"
    }

    static func parse(_ text: String) -> (statusCode: Int, body: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let statusCode = lines.first
            .flatMap { line in
                line.split(separator: " ").dropFirst().first.flatMap { Int($0) }
            } ?? 200

        if let range = normalized.range(of: "\n\n") {
            return (statusCode, String(normalized[range.upperBound...]))
        }
        return (statusCode, normalized)
    }
}
