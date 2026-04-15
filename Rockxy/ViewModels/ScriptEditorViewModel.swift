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
        case .errors: String(localized: "Errors")
        case .warnings: String(localized: "Warnings")
        case .userLogs: String(localized: "User Logs")
        case .system: String(localized: "System")
        }
    }
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
        case .wildcard: String(localized: "Use Wildcard")
        case .regex: String(localized: "Use Regex")
        case .advanced: String(localized: "Advanced")
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

    // Run-on row + status
    var runOnRequest: Bool = true
    var runOnResponse: Bool = true
    var runAsMock: Bool = false
    private(set) var savedAndActive: Bool = false
    private(set) var statusMessage: String = .init(localized: "Saved and Active!")

    /// Editor
    var code: String = ScriptTemplates.defaultSource

    // Console
    private(set) var consoleEntries: [ScriptConsoleEntry] = []
    var consoleFilter: Set<ScriptConsoleLogLevel> = Set(ScriptConsoleLogLevel.allCases)
    var consolePanelVisible: Bool = true

    /// UI-only (deferred in this milestone)
    var testRulePreview: String = ""
    var sampleURL: String = "https://api.example.com/path"

    // MARK: - Wildcard → regex

    static func wildcardToRegex(_ pattern: String, includeSubpaths: Bool = false) -> String {
        var escaped = ""
        for ch in pattern {
            switch ch {
            case "*": escaped += ".*"
            case "?": escaped += "."
            case ".",
                 "+",
                 "(",
                 ")",
                 "[",
                 "]",
                 "{",
                 "}",
                 "^",
                 "$",
                 "|",
                 "\\":
                escaped += "\\"
                escaped.append(ch)
            default:
                escaped.append(ch)
            }
        }
        return includeSubpaths ? escaped : "^\(escaped)$"
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

    // MARK: - Load / Save

    func load(intent: ScriptEditorIntent) async {
        switch intent {
        case .createNew:
            // Defer creation to the List window (which calls `createNewScript`).
            // If opened without a pending edit id, we still want a clean slate.
            resetToDefaults()
        case let .edit(pluginID):
            await loadExisting(pluginID: pluginID)
        }
    }

    func saveAndActivate() async {
        guard let pluginID else {
            return
        }
        do {
            let manifestURL = pluginDir(for: pluginID).appendingPathComponent("plugin.json")
            let scriptURL = pluginDir(for: pluginID).appendingPathComponent("index.js")

            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

            let condition = buildMatchCondition()
            let behavior = ScriptBehavior(
                matchCondition: condition,
                runOnRequest: runOnRequest,
                runOnResponse: runOnResponse,
                runAsMock: runAsMock
            )

            let updated = PluginManifest(
                id: manifest.id,
                name: name.isEmpty ? manifest.name : name,
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
            try code.write(to: scriptURL, atomically: true, encoding: .utf8)

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
            if !alreadyEnabled {
                do {
                    try await effectivePolicyGate.enablePlugin(id: pluginID, using: pluginManager)
                    enableSucceeded = true
                } catch is ScriptQuotaError {
                    quotaReached = true
                } catch {
                    enableSucceeded = false
                    appendConsole(.init(
                        timestamp: .now,
                        level: .errors,
                        message: String(localized: "Enable failed: \(error.localizedDescription)")
                    ))
                }
            }

            // Re-read post-enable status to reflect any runtime errors.
            let afterSnapshot = await pluginManager.plugins.first(where: { $0.id == pluginID })
            let isLiveActive = afterSnapshot?.isEnabled == true && afterSnapshot?.status == .active

            savedAndActive = isLiveActive
            if isLiveActive {
                statusMessage = String(localized: "Saved and Active!")
                appendConsole(.init(
                    timestamp: .now,
                    level: .userLogs,
                    message: String(localized: "Script saved and active.")
                ))
            } else if quotaReached {
                statusMessage = String(localized: "Saved (script quota reached — not active)")
                appendConsole(.init(
                    timestamp: .now,
                    level: .warnings,
                    message: String(
                        localized: "Saved, but the 10-enabled-script quota is reached. Disable another script to activate this one."
                    )
                ))
            } else if !enableSucceeded {
                statusMessage = String(localized: "Saved (not active)")
            } else if let afterSnapshot, case let .error(reason) = afterSnapshot.status {
                statusMessage = String(localized: "Saved, but script failed to load")
                appendConsole(.init(
                    timestamp: .now,
                    level: .errors,
                    message: reason
                ))
            } else {
                statusMessage = String(localized: "Saved (not active)")
            }
        } catch {
            savedAndActive = false
            statusMessage = String(localized: "Save failed")
            appendConsole(.init(
                timestamp: .now,
                level: .errors,
                message: String(localized: "Save failed: \(error.localizedDescription)")
            ))
            Self.logger.error("Save failed: \(error.localizedDescription)")
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
            message: String(localized: "Code beautified (indentation normalized).")
        ))
    }

    func insertSnippet(_ snippet: String) {
        code += "\n" + snippet
    }

    func testRule(against sampleURL: String) -> Bool {
        guard !urlPattern.isEmpty else {
            return true
        }
        let pattern: String = switch patternMode {
        case .wildcard:
            Self.wildcardToRegex(urlPattern)
        case .regex:
            urlPattern
        case .advanced:
            urlPattern
        }
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(sampleURL.startIndex ..< sampleURL.endIndex, in: sampleURL)
        return re.firstMatch(in: sampleURL, range: range) != nil
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
        appendConsole(.init(timestamp: .now, level: .system, message: String(localized: "Shared state cleared.")))
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ScriptEditorViewModel"
    )

    private let pluginManager: ScriptPluginManager
    private let policyGate: ScriptPolicyGate?
    private let pluginsDirectoryOverride: URL?

    private var effectivePolicyGate: ScriptPolicyGate {
        policyGate ?? ScriptPolicyGate.shared
    }

    private static func pluginDir(for id: String) -> URL {
        RockxyIdentity.current.appSupportPath("Plugins").appendingPathComponent(id, isDirectory: true)
    }

    private func pluginDir(for id: String) -> URL {
        if let override = pluginsDirectoryOverride {
            return override.appendingPathComponent(id, isDirectory: true)
        }
        return Self.pluginDir(for: id)
    }

    private func resetToDefaults() {
        pluginID = nil
        name = ""
        urlPattern = ""
        method = .any
        patternMode = .wildcard
        includeSubpaths = false
        runOnRequest = true
        runOnResponse = true
        runAsMock = false
        code = ScriptTemplates.defaultSource
        savedAndActive = false
        statusMessage = ""
        sampleURL = "https://api.example.com/path"
        consoleEntries.removeAll()
    }

    private func loadExisting(pluginID: String) async {
        resetToDefaults()
        let manifestURL = pluginDir(for: pluginID).appendingPathComponent("plugin.json")
        let scriptURL = pluginDir(for: pluginID).appendingPathComponent("index.js")
        do {
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: manifestURL))
            let behavior = manifest.scriptBehavior ?? ScriptBehavior.defaults()
            self.pluginID = manifest.id
            name = manifest.name
            urlPattern = behavior.matchCondition?.urlPattern ?? ""
            method = ScriptMatchMethod(persisted: behavior.matchCondition?.method)
            runOnRequest = behavior.runOnRequest
            runOnResponse = behavior.runOnResponse
            runAsMock = behavior.runAsMock
            code = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ScriptTemplates.defaultSource
            let info = await pluginManager.plugins.first(where: { $0.id == pluginID })
            savedAndActive = info?.isEnabled == true && info?.status == .active
            statusMessage = savedAndActive ? String(localized: "Saved and Active!") : String(localized: "Saved")
        } catch {
            statusMessage = String(localized: "Load failed: \(error.localizedDescription)")
            appendConsole(.init(timestamp: .now, level: .errors, message: statusMessage))
        }
    }

    private func buildMatchCondition() -> RuleMatchCondition? {
        let trimmedPattern = urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let methodValue = method.persistedValue
        if trimmedPattern.isEmpty, methodValue == nil {
            return nil
        }
        var pattern: String? = trimmedPattern.isEmpty ? nil : trimmedPattern
        if let p = pattern, patternMode == .wildcard {
            pattern = Self.wildcardToRegex(p, includeSubpaths: includeSubpaths)
        }
        return RuleMatchCondition(urlPattern: pattern, method: methodValue)
    }

    private func appendConsole(_ entry: ScriptConsoleEntry) {
        consoleEntries.append(entry)
    }
}

// MARK: - ScriptConsoleEntry

struct ScriptConsoleEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: ScriptConsoleLogLevel
    let message: String
}
