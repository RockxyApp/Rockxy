import Foundation

// MARK: - MCPScriptCreating

/// Creates a script on behalf of an MCP client. The app injects an implementation that uses the
/// same plugin layout and enabled-script limit as the Scripting window.
protocol MCPScriptCreating: Sendable {
    func createScript(name: String, source: String, behavior: ScriptBehavior, enable: Bool) async
        -> MCPScriptCreationResult
}

// MARK: - MCPScriptCreationResult

enum MCPScriptCreationResult: Equatable, Sendable {
    case created(id: String, isEnabled: Bool)
    /// The script was saved but not enabled because the enabled-script limit was reached.
    case createdButLimitReached(id: String, limit: Int)
    case failed(message: String)
}

// MARK: - MCPScriptToolHandler

/// Validates `create_script` arguments and turns the outcome into a tool result.
struct MCPScriptToolHandler: Sendable {
    // MARK: Internal

    static let maxSourceBytes = 256 * 1_024

    let creator: any MCPScriptCreating
    let ruleMutations: MCPRuleMutationService

    func createScript(_ args: [String: MCPJSONValue]) async -> MCPToolCallResult {
        guard case let .string(source) = args["code"],
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else
        {
            return MCPArgumentError(param: "code", message: "Missing required parameter: code").result
        }
        guard source.utf8.count <= Self.maxSourceBytes else {
            return MCPArgumentError(param: "code", message: "code must be at most 256 KB").result
        }
        guard source.contains("onRequest") || source.contains("onResponse") else {
            return MCPArgumentError(
                param: "code",
                message: "code must define function onRequest(context, url, request) and/or "
                    + "function onResponse(context, url, request, response)"
            ).result
        }

        let condition: RuleMatchCondition
        switch ruleMutations.matchCondition(from: args) {
        case let .success(value): condition = value
        case let .failure(error): return error.result
        }
        let runOnRequest = bool("run_on_request", args) ?? true
        let runOnResponse = bool("run_on_response", args) ?? true
        guard runOnRequest || runOnResponse else {
            return MCPArgumentError(
                param: "run_on_request",
                message: "Enable run_on_request, run_on_response, or both"
            ).result
        }
        var name = (string("name", args) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = condition.sourceURLPattern ?? "Script"
        }
        let behavior = ScriptBehavior(
            matchCondition: condition,
            runOnRequest: runOnRequest,
            runOnResponse: runOnResponse
        )

        switch await creator.createScript(
            name: String(name.prefix(MCPRuleMutationService.maxNameLength)),
            source: source,
            behavior: behavior,
            enable: bool("enabled", args) ?? true
        ) {
        case let .created(id, isEnabled):
            return MCPToolResultEncoding.object([
                "script_id": .string(id),
                "name": .string(name),
                "is_enabled": .bool(isEnabled),
            ])
        case let .createdButLimitReached(id, limit):
            return MCPToolResultEncoding.object([
                "script_id": .string(id),
                "name": .string(name),
                "is_enabled": .bool(false),
                "note": .string("Saved but not enabled: at most \(limit) scripts can be enabled. Disable one first."),
            ])
        case let .failed(message):
            return MCPToolResultEncoding.error(["error": "The script could not be created: \(message)"])
        }
    }

    // MARK: Private

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
}
