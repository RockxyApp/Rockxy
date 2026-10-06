import Foundation
import os

// MARK: - ScriptConsoleLogLevel

/// Console log level for editor-side filtering, bound to the console eye-icon menu.
enum ScriptConsoleLogLevel: String, CaseIterable, Identifiable {
    case errors
    case warnings
    case userLogs
    case system

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .errors: String(localized: "Errors", bundle: RockxyLocalization.bundle)
        case .warnings: String(localized: "Warnings", bundle: RockxyLocalization.bundle)
        case .userLogs: String(localized: "User Logs", bundle: RockxyLocalization.bundle)
        case .system: String(localized: "System", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ScriptEditorStatusTone

enum ScriptEditorStatusTone: Equatable {
    case neutral
    case success
    case warning
    case error
}

// MARK: - ScriptEditorContentState

/// What the editor window should render. Intent-dependent windows start
/// `awaitingIntent`; a load transitions through `loading` to `editing`.
enum ScriptEditorContentState: Equatable {
    case awaitingIntent
    case loading
    case editing
}

// MARK: - ScriptEditorSwitchDecision

/// User's choice in the native "unsaved changes" three-way prompt when a new
/// load intent arrives while the current draft is dirty.
enum ScriptEditorSwitchDecision: Equatable {
    case saveAndSwitch
    case discard
    case cancel
}

// MARK: - ScriptConsoleEmptyState

/// Distinguishes a genuinely empty console from one whose entries are all
/// hidden by the active level filter.
enum ScriptConsoleEmptyState: Equatable {
    /// Entries exist and at least one passes the active filter.
    case populated
    /// No entries have ever been recorded.
    case empty
    /// Entries exist but the active level filter hides every one of them.
    case filtered
}

// MARK: - ScriptRuleTestOutcome

/// Result of testing the current matching rule against a sample URL. Keeps an
/// invalid pattern distinct from a legitimate "no match" so the UI can be honest.
enum ScriptRuleTestOutcome: Equatable {
    case match
    case noMatch
    case invalidPattern
}

// MARK: - ScriptMatchPatternMode

/// Pattern-mode for matching rule URL (popover in the Matching Rule header row).
enum ScriptMatchPatternMode: String, CaseIterable, Identifiable {
    case wildcard
    case regex
    case advanced

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .wildcard: String(localized: "Use Wildcard", bundle: RockxyLocalization.bundle)
        case .regex: String(localized: "Use Regex", bundle: RockxyLocalization.bundle)
        case .advanced: String(localized: "Advanced", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ScriptMatchMethod

/// HTTP method options for the Matching Rule method popup.
enum ScriptMatchMethod: String, CaseIterable, Identifiable {
    case any
    case get
    case post
    case put
    case delete
    case patch
    case head
    case options
    case trace
    case query

    // MARK: Lifecycle

    init(persisted: String?) {
        guard let p = persisted?.uppercased() else {
            self = .any
            return
        }
        self = Self.allCases.first(where: { $0.label == p }) ?? .any
    }

    // MARK: Internal

    var id: String {
        rawValue
    }

    /// How it renders in the popup + on the list column ("Any" → nil on save).
    var label: String {
        switch self {
        case .any: "ANY"
        case .get: "GET"
        case .post: "POST"
        case .put: "PUT"
        case .delete: "DELETE"
        case .patch: "PATCH"
        case .head: "HEAD"
        case .options: "OPTIONS"
        case .trace: "TRACE"
        case .query: "QUERY"
        }
    }

    /// Persisted value in `matchCondition.method`. "Any" means "no method filter" (nil).
    var persistedValue: String? {
        switch self {
        case .any: nil
        default: label
        }
    }
}

// MARK: - ScriptEditorDraft

/// An equatable snapshot of every user-editable field in the Script Editor.
/// Comparing the live draft against a persisted baseline yields truthful dirty
/// state, and capturing the exact draft written during a save lets the async
/// completion baseline only what it actually persisted.
struct ScriptEditorDraft: Equatable {
    /// The clean-slate draft matching a freshly constructed view model.
    static let initialDefault = ScriptEditorDraft(
        name: "",
        urlPattern: "",
        method: .any,
        patternMode: .wildcard,
        includeSubpaths: false,
        runOnRequest: true,
        runOnResponse: true,
        runAsMock: false,
        code: ScriptTemplates.defaultSource,
        graphQLOperationName: ""
    )

    var name: String
    var urlPattern: String
    var method: ScriptMatchMethod
    var patternMode: ScriptMatchPatternMode
    var includeSubpaths: Bool
    var runOnRequest: Bool
    var runOnResponse: Bool
    var runAsMock: Bool
    var code: String
    var graphQLOperationName: String
}

// MARK: - ScriptEditorViewModel

@MainActor
@Observable
final class ScriptEditorViewModel {
    // MARK: Lifecycle

    init(
        pluginManager: ScriptPluginManager = PluginManager.shared.scriptManager,
        policyGate: ScriptPolicyGate? = nil,
        pluginsDirectory: URL? = nil
    ) {
        self.pluginManager = pluginManager
        self.policyGate = policyGate
        self.pluginsDirectoryOverride = pluginsDirectory
        installRuntimeConsoleObserver()
    }

    // MARK: Internal

    /// Loaded plugin state
    private(set) var pluginID: String?

    // Matching Rule fields
    var name: String = ""
    var urlPattern: String = ""
    var method: ScriptMatchMethod = .any
    var patternMode: ScriptMatchPatternMode = .wildcard
    var includeSubpaths: Bool = false
    /// Limits the script to GraphQL requests with this operation name; empty matches any.
    var graphQLOperationName: String = ""

    // Run-on row + status
    var runOnRequest: Bool = true
    var runOnResponse: Bool = true
    var runAsMock: Bool = false
    private(set) var savedAndActive: Bool = false
    private(set) var statusMessage: String = ""
    private(set) var statusTone: ScriptEditorStatusTone = .neutral

    /// Editor
    var code: String = ScriptTemplates.defaultSource

    // Console
    private(set) var consoleEntries: [ScriptConsoleEntry] = []
    var consoleFilter: Set<ScriptConsoleLogLevel> = Set(ScriptConsoleLogLevel.allCases)
    var consolePanelVisible: Bool = true

    /// Test-Match field (user-directed) + last preview outcome.
    var testRulePreview: String = ""
    var sampleURL: String = "https://api.example.com/path"

    /// Window presentation lifecycle for the intent-dependent editor.
    private(set) var contentState: ScriptEditorContentState = .awaitingIntent

    /// In-flight guards so the UI can disable actions and dedupe requests.
    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false

    /// The persisted baseline the live draft is compared against for dirty
    /// tracking. Updated only after a successful load or save.
    private(set) var baseline: ScriptEditorDraft = .initialDefault

    /// A load intent retained while the current draft has unsaved changes, so
    /// the native three-way prompt can resolve it. Cleared on cancel/discard or
    /// after a successful Save & Switch.
    private(set) var pendingIntent: ScriptEditorIntent?

    /// Drives the native "unsaved changes" confirmation dialog in the window.
    var isShowingUnsavedSwitchPrompt: Bool = false

    /// The live editor draft assembled from the bound fields.
    var currentDraft: ScriptEditorDraft {
        ScriptEditorDraft(
            name: name,
            urlPattern: urlPattern,
            method: method,
            patternMode: patternMode,
            includeSubpaths: includeSubpaths,
            runOnRequest: runOnRequest,
            runOnResponse: runOnResponse,
            runAsMock: runAsMock,
            code: code,
            graphQLOperationName: graphQLOperationName
        )
    }

    /// True when the live draft differs from the persisted baseline.
    var isDirty: Bool {
        currentDraft != baseline
    }

    /// True when there is a script bound and its draft has unsaved edits.
    var hasUnsavedBoundChanges: Bool {
        pluginID != nil && isDirty
    }

    /// Display name for confirmations / prompts naming the current script.
    var currentScriptDisplayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "this script", bundle: RockxyLocalization.bundle) : trimmed
    }

    /// Console entries passing the active level filter.
    var visibleConsoleEntries: [ScriptConsoleEntry] {
        consoleEntries.filter { consoleFilter.contains($0.level) }
    }

    /// Whether the console should render populated, truly-empty, or filtered-empty.
    var consoleEmptyState: ScriptConsoleEmptyState {
        if consoleEntries.isEmpty {
            return .empty
        }
        return visibleConsoleEntries.isEmpty ? .filtered : .populated
    }

    // MARK: - Wildcard → regex

    static func wildcardToRegex(_ pattern: String, includeSubpaths: Bool = false) -> String {
        RulePatternBuilder.regexSource(
            rawPattern: pattern,
            matchType: .wildcard,
            includeSubpaths: includeSubpaths
        )
    }

    static func editorPattern(for condition: RuleMatchCondition?) -> (
        pattern: String,
        mode: ScriptMatchPatternMode,
        includeSubpaths: Bool
    ) {
        guard let condition, let pattern = condition.urlPattern else {
            return ("", .wildcard, false)
        }
        if let matchType = condition.matchType {
            return (
                pattern,
                matchType == .wildcard ? .wildcard : .regex,
                matchType == .wildcard ? condition.includeSubpaths ?? false : false
            )
        }
        if let legacy = legacyGeneratedWildcardDisplayPattern(pattern) {
            return legacy
        }
        return (pattern, .regex, false)
    }

    // MARK: - Beautifier

    static func beautifyJavaScript(_ source: String) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var depth = 0
        var out: [String] = []
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                out.append("")
                continue
            }
            // Closing braces dedent before rendering.
            if line.first == "}" || line.first == "]" || line.first == ")" {
                depth = max(0, depth - 1)
            }
            let indent = String(repeating: "  ", count: depth)
            out.append(indent + line)
            // Increase depth for open braces not immediately closed on the same line.
            let opens = line.filter { $0 == "{" || $0 == "[" || $0 == "(" }.count
            let closes = line.filter { $0 == "}" || $0 == "]" || $0 == ")" }.count
            depth = max(0, depth + (opens - closes))
            // If the line both opened and closed the same brace (e.g. `if (x) { foo; }`) we
            // already compensated above — no special case.
            if line.first == "}" || line.first == "]" || line.first == ")" {
                // We dedented before rendering; compensate: if the same line also opens, we
                // already counted that in the opens/closes math, so no further action.
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Request-load flow

    /// Entry point the window uses for an incoming intent. When a bound plugin
    /// has unsaved changes the intent is retained for a native three-way
    /// decision; otherwise it loads immediately.
    func requestLoad(intent: ScriptEditorIntent) async {
        if hasUnsavedBoundChanges {
            pendingIntent = intent
            isShowingUnsavedSwitchPrompt = true
            return
        }
        await load(intent: intent)
    }

    /// Resolve the retained intent from the native unsaved-changes prompt.
    func resolveUnsavedSwitch(_ decision: ScriptEditorSwitchDecision) async {
        guard let intent = pendingIntent else {
            isShowingUnsavedSwitchPrompt = false
            return
        }
        switch decision {
        case .cancel:
            pendingIntent = nil
            isShowingUnsavedSwitchPrompt = false
        case .discard:
            pendingIntent = nil
            isShowingUnsavedSwitchPrompt = false
            await load(intent: intent)
        case .saveAndSwitch:
            isShowingUnsavedSwitchPrompt = false
            let saved = await saveAndActivate()
            // Only load the pending intent after a genuinely successful save;
            // otherwise keep the current draft and the retained intent so the
            // failure is not silently swallowed.
            guard saved, let pending = pendingIntent else {
                return
            }
            pendingIntent = nil
            await load(intent: pending)
        }
    }

    func load(intent: ScriptEditorIntent) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        contentState = .loading
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }
        switch intent {
        case .createNew:
            // Defer creation to the List window (which calls `createNewScript`).
            // If opened without a pending edit id, we still want a clean slate.
            resetToDefaults()
        case let .edit(pluginID):
            await loadExisting(pluginID: pluginID, generation: generation)
        }
        guard generation == loadGeneration else {
            return
        }
        baseline = currentDraft
        contentState = .editing
    }

    // MARK: - Save

    /// Persist the current draft, reload the runtime, and try to activate.
    /// Returns `true` when the manifest and source were written to disk (even if
    /// activation is deferred by quota), and `false` when preflight blocks the
    /// save or the write itself fails. Never writes files when preflight fails.
    @discardableResult
    func saveAndActivate() async -> Bool {
        guard !isSaving else {
            return false
        }
        guard let pluginID else {
            savedAndActive = false
            statusTone = .warning
            statusMessage = String(localized: "No script is loaded to save.", bundle: RockxyLocalization.bundle)
            appendConsole(.init(
                timestamp: .now,
                level: .warnings,
                message: String(
                    localized: "Save skipped: no script is loaded in the editor.",
                    bundle: RockxyLocalization.bundle
                )
            ))
            return false
        }

        // Capture the exact draft being written so an edit landing during the
        // async reload cannot make the completion baseline newer content.
        let draft = currentDraft

        if let failure = preflightFailure(for: draft) {
            savedAndActive = false
            statusTone = .error
            statusMessage = failure.status
            appendConsole(.init(timestamp: .now, level: .errors, message: failure.consoleMessage))
            return false
        }

        isSaving = true
        defer { isSaving = false }
        let generation = loadGeneration
        do {
            let manifestURL = pluginDir(for: pluginID).appendingPathComponent("plugin.json")
            let scriptURL = pluginDir(for: pluginID).appendingPathComponent("index.js")

            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

            let condition = buildMatchCondition(from: draft)
            let behavior = ScriptBehavior(
                matchCondition: condition,
                runOnRequest: draft.runOnRequest,
                runOnResponse: draft.runOnResponse,
                runAsMock: draft.runAsMock
            )

            let updated = PluginManifest(
                id: manifest.id,
                name: draft.name.isEmpty ? manifest.name : draft.name,
                version: manifest.version,
                author: manifest.author,
                description: manifest.description,
                types: manifest.types,
                entryPoints: manifest.entryPoints,
                capabilities: manifest.capabilities,
                configuration: manifest.configuration,
                minRockxyVersion: manifest.minRockxyVersion,
                homepage: manifest.homepage,
                license: manifest.license,
                scriptBehavior: behavior
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(updated).write(to: manifestURL)
            try draft.code.write(to: scriptURL, atomically: true, encoding: .utf8)

            // Reload the runtime so the new source + behavior are picked up.
            // For a brand-new script (or any disabled plugin) reload alone won't
            // make it active in the proxy pipeline — `runRequestHook` /
            // `runResponseHook` only fire for `isEnabled && status == .active`.
            // So we ALSO try to enable through the policy gate. If the user has
            // hit the 10-script quota, enable returns false and we report
            // "Saved" (not "Saved and Active!") so the UI doesn't lie.
            try await pluginManager.reloadPlugin(id: pluginID)

            let beforeSnapshot = await pluginManager.plugins.first(where: { $0.id == pluginID })
            let alreadyEnabled = beforeSnapshot?.isEnabled == true

            var enableSucceeded = alreadyEnabled
            var quotaReached = false
            var enableErrorMessage: String?
            if !alreadyEnabled {
                do {
                    try await effectivePolicyGate.enablePlugin(id: pluginID, using: pluginManager)
                    enableSucceeded = true
                } catch is ScriptQuotaError {
                    quotaReached = true
                } catch {
                    enableSucceeded = false
                    enableErrorMessage = String(
                        localized: "Enable failed: \(error.localizedDescription)",
                        bundle: RockxyLocalization.bundle
                    )
                }
            }

            // Re-read post-enable status to reflect any runtime errors.
            let afterSnapshot = await pluginManager.plugins.first(where: { $0.id == pluginID })
            let isLiveActive = afterSnapshot?.isEnabled == true && afterSnapshot?.status == .active

            guard generation == loadGeneration, self.pluginID == pluginID else {
                // A newer load or context switch owns the UI now; the write did
                // land on disk, so still report success without touching state.
                return true
            }
            // Baseline the captured draft only — never `currentDraft`, which may
            // already carry edits made during the async reload above.
            baseline = draft
            if let enableErrorMessage {
                appendConsole(.init(timestamp: .now, level: .errors, message: enableErrorMessage))
            }
            savedAndActive = isLiveActive
            if isLiveActive {
                statusTone = .success
                statusMessage = String(localized: "Saved and Active!", bundle: RockxyLocalization.bundle)
                appendConsole(.init(
                    timestamp: .now,
                    level: .userLogs,
                    message: String(localized: "Script saved and active.", bundle: RockxyLocalization.bundle)
                ))
            } else if quotaReached {
                statusTone = .warning
                statusMessage = String(
                    localized: "Saved (script quota reached — not active)",
                    bundle: RockxyLocalization.bundle
                )
                appendConsole(.init(
                    timestamp: .now,
                    level: .warnings,
                    message: String(
                        localized: "Saved, but the 10-enabled-script quota is reached. Disable another script to activate this one.",
                        bundle: RockxyLocalization.bundle
                    )
                ))
            } else if !enableSucceeded {
                statusTone = .neutral
                statusMessage = String(localized: "Saved (not active)", bundle: RockxyLocalization.bundle)
            } else if let afterSnapshot, case let .error(reason) = afterSnapshot.status {
                statusTone = .error
                statusMessage = String(localized: "Saved, but script failed to load", bundle: RockxyLocalization.bundle)
                appendConsole(.init(
                    timestamp: .now,
                    level: .errors,
                    message: reason
                ))
            } else {
                statusTone = .neutral
                statusMessage = String(localized: "Saved (not active)", bundle: RockxyLocalization.bundle)
            }
            return true
        } catch {
            guard generation == loadGeneration, self.pluginID == pluginID else {
                return false
            }
            savedAndActive = false
            statusTone = .error
            statusMessage = String(localized: "Save failed", bundle: RockxyLocalization.bundle)
            appendConsole(.init(
                timestamp: .now,
                level: .errors,
                message: String(
                    localized: "Save failed: \(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            ))
            Self.logger.error("Save failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Footer actions

    /// Tiny JS beautifier: normalizes indentation (2 spaces) per logical brace level.
    /// Intentionally simple — for a full beautifier we'd bundle js-beautify; this
    /// covers the common case of fixing indentation without adding a dependency.
    func beautify() {
        code = Self.beautifyJavaScript(code)
        appendConsole(.init(
            timestamp: .now,
            level: .system,
            message: String(localized: "Code beautified (indentation normalized).", bundle: RockxyLocalization.bundle)
        ))
    }

    func insertSnippet(_ snippet: String) {
        code += "\n" + snippet
    }

    /// Insert a real, runnable header-mutation example (not a nonexistent
    /// template) at the end of the current source.
    func insertHeaderExample() {
        insertSnippet("request.headers[\"X-Custom-Header\"] = \"value\";")
    }

    /// Toggle the Request phase, keeping the mock invariant (a mock script must
    /// run on Request) truthful.
    func setRunOnRequest(_ enabled: Bool) {
        runOnRequest = enabled
        if !enabled {
            runAsMock = false
        }
    }

    /// Toggle Mock, normalizing the phases it depends on: a mock script runs on
    /// Request and does not run on Response.
    func setRunAsMock(_ enabled: Bool) {
        runAsMock = enabled
        if enabled {
            runOnRequest = true
            runOnResponse = false
        }
    }

    func validateScript() {
        let result = ScriptSourceValidator.validate(
            source: code,
            runOnRequest: runOnRequest,
            runOnResponse: runOnResponse,
            runAsMock: runAsMock
        )
        switch result {
        case .valid:
            statusTone = .success
            statusMessage = String(localized: "Script is valid", bundle: RockxyLocalization.bundle)
            appendConsole(.init(
                timestamp: .now,
                level: .system,
                message: String(localized: "Validation passed.", bundle: RockxyLocalization.bundle)
            ))
        case let .invalid(reason):
            savedAndActive = false
            statusTone = .error
            statusMessage = String(localized: "Validation failed", bundle: RockxyLocalization.bundle)
            appendConsole(.init(
                timestamp: .now,
                level: .errors,
                message: String(localized: "Validation failed: \(reason)", bundle: RockxyLocalization.bundle)
            ))
        }
    }

    func testRule(against sampleURL: String) -> Bool {
        evaluateRule(against: sampleURL) == .match
    }

    /// Test the current matching rule, distinguishing an invalid pattern from a
    /// legitimate miss so the UI can report the two differently.
    func evaluateRule(against sampleURL: String) -> ScriptRuleTestOutcome {
        guard !urlPattern.isEmpty else {
            return .match
        }
        let pattern: String = switch patternMode {
        case .wildcard:
            Self.wildcardToRegex(urlPattern, includeSubpaths: includeSubpaths)
        case .regex,
             .advanced:
            urlPattern
        }
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            return .invalidPattern
        }
        let range = NSRange(sampleURL.startIndex ..< sampleURL.endIndex, in: sampleURL)
        return re.firstMatch(in: sampleURL, range: range) != nil ? .match : .noMatch
    }

    /// Run the Test-Match action against the editable Test URL field and record
    /// a user-facing preview line.
    func runRuleTest() {
        let sample = sampleURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSample = sample.isEmpty ? "https://api.example.com/path" : sample
        switch evaluateRule(against: effectiveSample) {
        case .match:
            testRulePreview = String(localized: "Matches: \(effectiveSample)", bundle: RockxyLocalization.bundle)
        case .noMatch:
            testRulePreview = String(localized: "No match for: \(effectiveSample)", bundle: RockxyLocalization.bundle)
        case .invalidPattern:
            testRulePreview = String(
                localized: "The matching pattern is not a valid regular expression.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    func clearConsole() {
        consoleEntries.removeAll()
    }

    func toggleConsolePanel() {
        consolePanelVisible.toggle()
    }

    func resetSharedState() {
        guard let pluginID else {
            return
        }
        let defaults = UserDefaults.standard
        let prefix = RockxyIdentity.current.pluginStoragePrefix(pluginID: pluginID)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        appendConsole(.init(
            timestamp: .now,
            level: .system,
            message: String(localized: "Shared state cleared.", bundle: RockxyLocalization.bundle)
        ))
    }

    // MARK: Private

    /// Hard cap on retained console entries (newest kept, oldest evicted).
    private static let maxConsoleEntries = 500

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ScriptEditorViewModel"
    )

    private let pluginManager: ScriptPluginManager
    private let policyGate: ScriptPolicyGate?
    private let pluginsDirectoryOverride: URL?
    private var pluginBundlePath: URL?
    private var loadGeneration: UInt = 0
    private var runtimeConsoleObserver: NSObjectProtocol?

    private var effectivePolicyGate: ScriptPolicyGate {
        policyGate ?? ScriptPolicyGate.shared
    }

    private static func pluginDir(for id: String) -> URL {
        RockxyIdentity.current.appSupportPath("Plugins").appendingPathComponent(id, isDirectory: true)
    }

    private static func consoleLogLevel(for runtimeLevel: ScriptConsoleEventLevel) -> ScriptConsoleLogLevel {
        switch runtimeLevel {
        case .error:
            .errors
        case .warn:
            .warnings
        case .debug,
             .info,
             .log:
            .userLogs
        }
    }

    private static func legacyGeneratedWildcardDisplayPattern(_ pattern: String) -> (
        pattern: String,
        mode: ScriptMatchPatternMode,
        includeSubpaths: Bool
    )? {
        let exactSuffix = "($|[?#])"
        if pattern.hasSuffix(exactSuffix) {
            let body = String(pattern.dropLast(exactSuffix.count))
            return (decodeLegacyGeneratedWildcardBody(body), .wildcard, false)
        }
        guard pattern.hasSuffix(".*") else {
            return nil
        }
        let body = String(pattern.dropLast(2))
        return (decodeLegacyGeneratedWildcardBody(body), .wildcard, true)
    }

    private static func decodeLegacyGeneratedWildcardBody(_ body: String) -> String {
        var output = ""
        var index = body.startIndex
        while index < body.endIndex {
            let next = body.index(after: index)
            if body[index] == ".",
               next < body.endIndex,
               body[next] == "*"
            {
                output.append("*")
                index = body.index(after: next)
                continue
            }
            if body[index] == "\\",
               next < body.endIndex
            {
                output.append(body[next])
                index = body.index(after: next)
                continue
            }
            output.append(body[index] == "." ? "?" : body[index])
            index = next
        }
        return output
    }

    private func pluginDir(for id: String) -> URL {
        if self.pluginID == id, let pluginBundlePath {
            return pluginBundlePath
        }
        if let override = pluginsDirectoryOverride {
            return override.appendingPathComponent(id, isDirectory: true)
        }
        return Self.pluginDir(for: id)
    }

    private func resetToDefaults() {
        pluginID = nil
        pluginBundlePath = nil
        name = ""
        urlPattern = ""
        method = .any
        patternMode = .wildcard
        includeSubpaths = false
        graphQLOperationName = ""
        runOnRequest = true
        runOnResponse = true
        runAsMock = false
        code = ScriptTemplates.defaultSource
        savedAndActive = false
        statusTone = .neutral
        statusMessage = ""
        sampleURL = "https://api.example.com/path"
        consoleEntries.removeAll()
    }

    private func loadExisting(pluginID: String, generation: UInt) async {
        resetToDefaults()
        let info = await pluginManager.plugins.first(where: { $0.id == pluginID })
        guard generation == loadGeneration else {
            return
        }
        let bundlePath = info?.bundlePath ?? pluginDir(for: pluginID)
        let manifestURL = bundlePath.appendingPathComponent("plugin.json")
        let scriptURL = bundlePath.appendingPathComponent("index.js")
        do {
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: manifestURL))
            let behavior = manifest.scriptBehavior ?? ScriptBehavior.defaults()
            self.pluginID = manifest.id
            pluginBundlePath = bundlePath
            name = manifest.name
            let editorPattern = Self.editorPattern(for: behavior.matchCondition)
            urlPattern = editorPattern.pattern
            patternMode = editorPattern.mode
            includeSubpaths = editorPattern.includeSubpaths
            method = ScriptMatchMethod(persisted: behavior.matchCondition?.method)
            graphQLOperationName = behavior.matchCondition?.graphQLOperationName ?? ""
            runOnRequest = behavior.runOnRequest
            runOnResponse = behavior.runOnResponse
            runAsMock = behavior.runAsMock
            code = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ScriptTemplates.defaultSource
            savedAndActive = info?.isEnabled == true && info?.status == .active
            statusTone = savedAndActive ? .success : .neutral
            statusMessage = savedAndActive ? String(localized: "Saved and Active!", bundle: RockxyLocalization.bundle) :
                String(
                    localized: "Saved",
                    bundle: RockxyLocalization.bundle
                )
        } catch {
            statusTone = .error
            statusMessage = String(
                localized: "Load failed: \(error.localizedDescription)",
                bundle: RockxyLocalization.bundle
            )
            appendConsole(.init(timestamp: .now, level: .errors, message: statusMessage))
        }
    }

    /// Validate the draft before touching disk or the runtime. Returns a
    /// failure describing the first blocking problem, or `nil` when the draft is
    /// safe to persist. Never mutates state.
    private func preflightFailure(for draft: ScriptEditorDraft) -> (status: String, consoleMessage: String)? {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return (
                status: String(localized: "Name is required", bundle: RockxyLocalization.bundle),
                consoleMessage: String(
                    localized: "Save blocked: the script name cannot be empty.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }

        let trimmedPattern = draft.urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesRegex = draft.patternMode == .regex || draft.patternMode == .advanced
        if usesRegex, !trimmedPattern.isEmpty, (try? NSRegularExpression(pattern: trimmedPattern)) == nil {
            return (
                status: String(localized: "Invalid matching pattern", bundle: RockxyLocalization.bundle),
                consoleMessage: String(
                    localized: "Save blocked: the matching pattern is not a valid regular expression.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }

        switch ScriptSourceValidator.validate(
            source: draft.code,
            runOnRequest: draft.runOnRequest,
            runOnResponse: draft.runOnResponse,
            runAsMock: draft.runAsMock
        ) {
        case .valid:
            return nil
        case let .invalid(reason):
            return (
                status: String(localized: "Cannot save this script", bundle: RockxyLocalization.bundle),
                consoleMessage: String(localized: "Save blocked: \(reason)", bundle: RockxyLocalization.bundle)
            )
        }
    }

    private func buildMatchCondition(from draft: ScriptEditorDraft) -> RuleMatchCondition? {
        let trimmedPattern = draft.urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let methodValue = draft.method.persistedValue
        let operation = draft.graphQLOperationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPattern.isEmpty, methodValue == nil, operation.isEmpty {
            return nil
        }
        let pattern = trimmedPattern.isEmpty ? nil : trimmedPattern
        let matchType: RuleMatchType? = if pattern == nil {
            nil
        } else {
            switch draft.patternMode {
            case .wildcard:
                .wildcard
            case .regex,
                 .advanced:
                .regex
            }
        }
        return RuleMatchCondition(
            urlPattern: pattern,
            method: methodValue,
            matchType: matchType,
            includeSubpaths: matchType == .wildcard ? draft.includeSubpaths : nil,
            graphQLOperationName: operation.isEmpty ? nil : operation
        )
    }

    private func appendConsole(_ entry: ScriptConsoleEntry) {
        consoleEntries.append(entry)
        // Bound the editor console deterministically so runtime spam or long
        // editing sessions cannot grow it without limit; evict oldest first.
        if consoleEntries.count > Self.maxConsoleEntries {
            consoleEntries.removeFirst(consoleEntries.count - Self.maxConsoleEntries)
        }
    }

    private func installRuntimeConsoleObserver() {
        runtimeConsoleObserver = NotificationCenter.default.addObserver(
            forName: .scriptConsoleDidAppend,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? ScriptConsoleEvent else {
                return
            }
            Task { @MainActor [weak self] in
                self?.appendRuntimeConsoleEvent(event)
            }
        }
    }

    private func appendRuntimeConsoleEvent(_ event: ScriptConsoleEvent) {
        guard event.pluginID == pluginID else {
            return
        }
        appendConsole(.init(
            timestamp: event.timestamp,
            level: Self.consoleLogLevel(for: event.level),
            message: event.message
        ))
    }
}

// MARK: - ScriptConsoleEntry

struct ScriptConsoleEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: ScriptConsoleLogLevel
    let message: String
}
