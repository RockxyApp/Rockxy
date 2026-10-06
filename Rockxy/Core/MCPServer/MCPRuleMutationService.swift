import Foundation
import os

nonisolated(unsafe) private let logger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "MCPRuleMutationService"
)

// MARK: - MCPChangePermission

/// Reads the user's "Allow Changes from MCP Clients" choice at call time, so turning the
/// setting off takes effect for the very next tool call without restarting the server.
struct MCPChangePermission: Sendable {
    // MARK: Lifecycle

    init(isAllowed: @escaping @Sendable () -> Bool = { MCPChangePermission.storedValue }) {
        self.isAllowed = isAllowed
    }

    // MARK: Internal

    static let defaultsKey = RockxyIdentity.current.defaultsKey("mcp.allowChanges")

    static var storedValue: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    let isAllowed: @Sendable () -> Bool

    static func deniedResult(tool: String) -> MCPToolCallResult {
        MCPToolResultEncoding.error(
            [
                "error": "Changes from MCP clients are turned off",
                "tool": tool,
                "how_to_enable": "In Rockxy, open Settings > MCP and turn on "
                    + "\"Allow MCP Clients to Change Rules and Capture\".",
            ]
        )
    }
}

// MARK: - MCPRuleMutating

/// The rule-writing seam. The app injects an implementation that applies the same per-tool
/// active-rule limit and durable save as the rule editors.
protocol MCPRuleMutating: Sendable {
    func addRule(_ rule: ProxyRule) async -> RuleMutationResult
    func setRuleEnabled(id: UUID, enabled: Bool) async -> Bool
    func rule(id: UUID) async -> ProxyRule?
}

// MARK: - MCPRuleMutationService

/// Creates and toggles proxy rules on behalf of MCP clients. Every entry point validates its
/// arguments before anything is written, so a rejected call leaves no rule and no response file.
struct MCPRuleMutationService: Sendable {
    // MARK: Lifecycle

    init(
        mutator: any MCPRuleMutating,
        mapLocalDirectory: URL = RockxyIdentity.current.appSupportDirectory()
            .appendingPathComponent("map-local", isDirectory: true)
    ) {
        self.mutator = mutator
        self.mapLocalDirectory = mapLocalDirectory
    }

    // MARK: Internal

    /// Largest Map Local response body an MCP client may supply inline.
    static let maxMapLocalBodyBytes = 512 * 1_024
    static let maxHeaderCount = 50
    static let maxNameLength = 200
    static let maxPatternLength = 2_048

    let mutator: any MCPRuleMutating
    let mapLocalDirectory: URL

    func createBreakpoint(_ args: [String: MCPJSONValue]) async -> MCPToolCallResult {
        let condition: RuleMatchCondition
        switch matchCondition(from: args) {
        case let .success(value): condition = value
        case let .failure(error): return error.result
        }
        let phaseText = string("phase", args)?.lowercased() ?? "both"
        guard let phase = BreakpointRulePhase(rawValue: phaseText) else {
            return MCPArgumentError(param: "phase", message: "phase must be request, response, or both").result
        }
        let rule = ProxyRule(
            name: ruleName(args, fallback: condition.sourceURLPattern ?? "Breakpoint"),
            matchCondition: condition,
            action: .breakpoint(phase: phase)
        )
        return await add(rule)
    }

    func createMapLocal(_ args: [String: MCPJSONValue]) async -> MCPToolCallResult {
        let condition: RuleMatchCondition
        switch matchCondition(from: args) {
        case let .success(value): condition = value
        case let .failure(error): return error.result
        }
        let statusCode = int("status_code", args) ?? 200
        guard (100 ... 599).contains(statusCode) else {
            return MCPArgumentError(param: "status_code", message: "status_code must be 100-599").result
        }
        let body = string("body", args) ?? ""
        guard body.utf8.count <= Self.maxMapLocalBodyBytes else {
            return MCPArgumentError(
                param: "body",
                message: "body must be at most 512 KB"
            ).result
        }
        let headers: [HTTPHeader]
        switch responseHeaders(args) {
        case let .success(value): headers = value
        case let .failure(error): return error.result
        }
        let delayMs = int("delay_ms", args) ?? 0
        guard (0 ... 60_000).contains(delayMs) else {
            return MCPArgumentError(param: "delay_ms", message: "delay_ms must be 0-60000").result
        }

        let ruleID = UUID()
        let fileURL = mapLocalDirectory.appendingPathComponent("mcp-\(ruleID.uuidString).body")
        do {
            try FileManager.default.createDirectory(at: mapLocalDirectory, withIntermediateDirectories: true)
            try Data(body.utf8).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("MCP Map Local body write failed: \(error.localizedDescription, privacy: .public)")
            return MCPToolResultEncoding.error(["error": "Could not save the response body"])
        }

        let rule = ProxyRule(
            id: ruleID,
            name: ruleName(args, fallback: condition.sourceURLPattern ?? "Map Local"),
            matchCondition: condition,
            action: .mapLocal(
                filePath: fileURL.path,
                statusCode: statusCode,
                delayMs: delayMs,
                responseHeaders: headers
            )
        )
        let result = await add(rule)
        if result.isError == true {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return result
    }

    func createMapRemote(_ args: [String: MCPJSONValue]) async -> MCPToolCallResult {
        let condition: RuleMatchCondition
        switch matchCondition(from: args, patternKey: "from_url") {
        case let .success(value): condition = value
        case let .failure(error): return error.result
        }
        guard let destination = string("to_url", args)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty else
        {
            return MCPArgumentError(param: "to_url", message: "Missing required parameter: to_url").result
        }
        guard let components = URLComponents(string: destination),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else
        {
            return MCPArgumentError(
                param: "to_url",
                message: "to_url must be an absolute http or https URL"
            ).result
        }
        let path = components.percentEncodedPath
        let configuration = MapRemoteConfiguration(
            scheme: scheme,
            host: host,
            port: components.port,
            path: path.isEmpty || path == "/" ? nil : path,
            query: components.percentEncodedQuery,
            preserveHostHeader: bool("preserve_host_header", args) ?? false
        )
        let rule = ProxyRule(
            name: ruleName(args, fallback: "\(condition.sourceURLPattern ?? "") → \(host)"),
            matchCondition: condition,
            action: .mapRemote(configuration: configuration)
        )
        return await add(rule)
    }

    func createBlockRule(_ args: [String: MCPJSONValue]) async -> MCPToolCallResult {
        let condition: RuleMatchCondition
        switch matchCondition(from: args) {
        case let .success(value): condition = value
        case let .failure(error): return error.result
        }
        let actionText = string("action", args)?.lowercased() ?? "forbidden"
        let statusCode: Int
        switch actionText {
        case "forbidden": statusCode = BlockActionType.returnForbidden.statusCode
        case "drop": statusCode = BlockActionType.dropConnection.statusCode
        default:
            return MCPArgumentError(param: "action", message: "action must be forbidden or drop").result
        }
        let rule = ProxyRule(
            name: ruleName(args, fallback: condition.sourceURLPattern ?? "Block"),
            matchCondition: condition,
            action: .block(statusCode: statusCode)
        )
        return await add(rule)
    }

    func setRuleEnabled(_ args: [String: MCPJSONValue]) async -> MCPToolCallResult {
        guard let idText = string("rule_id", args), let id = UUID(uuidString: idText) else {
            return MCPArgumentError(param: "rule_id", message: "rule_id must be a rule UUID from list_rules").result
        }
        guard let enabled = bool("enabled", args) else {
            return MCPArgumentError(param: "enabled", message: "Missing required parameter: enabled").result
        }
        guard await mutator.rule(id: id) != nil else {
            return MCPArgumentError(param: "rule_id", message: "No rule has this id").result
        }
        guard await mutator.setRuleEnabled(id: id, enabled: enabled) else {
            return MCPToolResultEncoding.error([
                "error": "The active rule limit for this tool was reached. Disable another rule first.",
            ])
        }
        return MCPToolResultEncoding.object([
            "rule_id": .string(id.uuidString),
            "is_enabled": .bool(enabled),
        ])
    }

    // MARK: Private

    private func add(_ rule: ProxyRule) async -> MCPToolCallResult {
        switch await mutator.addRule(rule) {
        case .quotaExceeded:
            return MCPToolResultEncoding.error([
                "error": "The active rule limit for this tool was reached. Disable another rule first.",
            ])
        case let .loadFailed(message):
            return MCPToolResultEncoding.error(["error": "Existing rules could not be loaded: \(message)"])
        case let .persisted(.failed(message)):
            return MCPToolResultEncoding.error(["error": "The rule could not be saved: \(message)"])
        case .persisted(.saved):
            logger.info("MCP client created a \(rule.action.toolCategory, privacy: .public) rule")
            return MCPToolResultEncoding.object([
                "rule_id": .string(rule.id.uuidString),
                "name": .string(rule.name),
                "action_type": .string(rule.action.toolCategory),
                "is_enabled": .bool(rule.isEnabled),
                "action_summary": .string(rule.action.matchedRuleActionSummary),
            ])
        }
    }

    func matchCondition(
        from args: [String: MCPJSONValue],
        patternKey: String = "url"
    )
        -> Result<RuleMatchCondition, MCPArgumentError>
    {
        guard let rawPattern = string(patternKey, args)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPattern.isEmpty else
        {
            return .failure(MCPArgumentError(
                param: patternKey,
                message: "Missing required parameter: \(patternKey)"
            ))
        }
        guard rawPattern.count <= Self.maxPatternLength else {
            return .failure(MCPArgumentError(param: patternKey, message: "\(patternKey) is too long"))
        }

        let matchTypeText = string("match_type", args)?.lowercased() ?? "wildcard"
        let matchType: RuleMatchType
        switch matchTypeText {
        case "wildcard": matchType = .wildcard
        case "regex": matchType = .regex
        default:
            return .failure(MCPArgumentError(param: "match_type", message: "match_type must be wildcard or regex"))
        }
        let includeSubpaths = matchType == .wildcard ? (bool("include_subpaths", args) ?? true) : false
        let compiled = RulePatternBuilder.regexSource(
            rawPattern: rawPattern,
            matchType: matchType,
            includeSubpaths: includeSubpaths
        )
        if case let .failure(error) = RegexValidator.compile(compiled) {
            return .failure(MCPArgumentError(param: patternKey, message: error.localizedDescription))
        }

        var method: String?
        if let rawMethod = string("method", args)?.trimmingCharacters(in: .whitespaces).uppercased(),
           !rawMethod.isEmpty, rawMethod != "ANY"
        {
            guard rawMethod.allSatisfy(\.isLetter), rawMethod.count <= 16 else {
                return .failure(MCPArgumentError(param: "method", message: "method must be an HTTP method name"))
            }
            method = rawMethod
        }

        let operation = string("graphql_operation", args)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(RuleMatchCondition(
            urlPattern: compiled,
            sourceURLPattern: rawPattern,
            method: method,
            matchType: matchType,
            includeSubpaths: includeSubpaths,
            graphQLOperationName: operation?.isEmpty == false ? operation : nil
        ))
    }

    private func responseHeaders(_ args: [String: MCPJSONValue]) -> Result<[HTTPHeader], MCPArgumentError> {
        guard let value = args["headers"] else {
            return .success([])
        }
        guard case let .object(dict) = value else {
            return .failure(MCPArgumentError(param: "headers", message: "headers must be an object of name: value"))
        }
        guard dict.count <= Self.maxHeaderCount else {
            return .failure(MCPArgumentError(param: "headers", message: "At most \(Self.maxHeaderCount) headers"))
        }
        var headers: [HTTPHeader] = []
        for (name, raw) in dict.sorted(by: { $0.key < $1.key }) {
            guard case let .string(headerValue) = raw else {
                return .failure(MCPArgumentError(param: "headers", message: "Header values must be strings"))
            }
            let isValidName = !name.isEmpty && name.unicodeScalars.allSatisfy {
                $0.isASCII && $0.value > 32 && $0.value < 127 && $0 != ":"
            }
            guard isValidName, !headerValue.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" }) else {
                return .failure(MCPArgumentError(param: "headers", message: "Invalid header: \(name)"))
            }
            headers.append(HTTPHeader(name: name, value: headerValue))
        }
        return .success(headers)
    }

    private func ruleName(_ args: [String: MCPJSONValue], fallback: String) -> String {
        let provided = string("name", args)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = provided.isEmpty ? fallback : provided
        return String(name.prefix(Self.maxNameLength))
    }

    private func string(_ key: String, _ args: [String: MCPJSONValue]) -> String? {
        guard case let .string(value) = args[key] else {
            return nil
        }
        return value
    }

    private func bool(_ key: String, _ args: [String: MCPJSONValue]) -> Bool? {
        guard case let .bool(value) = args[key] else {
            return nil
        }
        return value
    }

    private func int(_ key: String, _ args: [String: MCPJSONValue]) -> Int? {
        switch args[key] {
        case let .int(value):
            value
        case let .double(value) where value.isFinite && value.rounded() == value && abs(value) < 1e9:
            Int(value)
        default:
            nil
        }
    }
}

// MARK: - MCPArgumentError

struct MCPArgumentError: Error {
    let param: String
    let message: String

    var result: MCPToolCallResult {
        MCPToolResultEncoding.error(["error": message, "param": param])
    }
}

// MARK: - MCPToolResultEncoding

enum MCPToolResultEncoding {
    static func object(_ fields: [String: MCPJSONValue]) -> MCPToolCallResult {
        let value: MCPJSONValue = .object(fields)
        guard let data = try? value.encodeToData(), let text = String(data: data, encoding: .utf8) else {
            return error(["error": "Internal encoding error"])
        }
        return MCPToolCallResult(content: [.text(text)], isError: nil)
    }

    static func error(_ payload: [String: String]) -> MCPToolCallResult {
        let value: MCPJSONValue = .object(payload.mapValues { .string($0) })
        let text = (try? value.encodeToData()).flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{"error":"Internal encoding error"}"#
        return MCPToolCallResult(content: [.text(text)], isError: true)
    }
}
