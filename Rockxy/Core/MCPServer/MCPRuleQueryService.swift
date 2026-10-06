import Foundation
import os

nonisolated(unsafe) private let logger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "MCPRuleQueryService"
)

// MARK: - MCPRuleQueryService

struct MCPRuleQueryService {
    // MARK: Lifecycle

    init(ruleEngine: RuleEngine, redactionPolicy: MCPRedactionPolicy = MCPRedactionPolicy(isEnabled: false)) {
        self.ruleEngine = ruleEngine
        self.redactionPolicy = redactionPolicy
    }

    // MARK: Internal

    let ruleEngine: RuleEngine
    let redactionPolicy: MCPRedactionPolicy

    func listRules() async -> MCPToolCallResult {
        let rules = await ruleEngine.allRules

        let ruleValues: [MCPJSONValue] = rules.map { rule in
            var fields: [String: MCPJSONValue] = [
                "id": .string(rule.id.uuidString),
                "name": .string(rule.name),
                "is_enabled": .bool(rule.isEnabled),
                "priority": .int(rule.priority),
                "action_type": .string(rule.action.toolCategory),
                "action_summary": .string(redactedActionSummary(for: rule)),
            ]

            var condition: [String: MCPJSONValue] = [:]
            if let pattern = rule.matchCondition.urlPattern {
                condition["url_pattern"] = .string(pattern)
            }
            if let method = rule.matchCondition.method {
                condition["method"] = .string(method)
            }
            if let headerName = rule.matchCondition.headerName {
                condition["header_name"] = .string(headerName)
            }
            if let headerValue = rule.matchCondition.headerValue {
                condition["header_value"] = .string(
                    redactedHeaderValue(name: rule.matchCondition.headerName, value: headerValue)
                )
            }

            fields["match_condition"] = .object(condition)

            return .object(fields)
        }

        let result: MCPJSONValue = .object([
            "rules": .array(ruleValues),
            "total_count": .int(rules.count),
        ])

        return jsonResult(result)
    }

    // MARK: Private

    private func redactedActionSummary(for rule: ProxyRule) -> String {
        let summary = rule.action.matchedRuleActionSummary
        guard redactionPolicy.isEnabled else {
            return summary
        }
        return redactionPolicy.redactGenericText(summary)
    }

    private func redactedHeaderValue(name: String?, value: String) -> String {
        guard redactionPolicy.isEnabled else {
            return value
        }
        if let name, SensitiveDataRedactor.isSensitiveName(name, exact: MCPRedactionPolicy.sensitiveHeaders) {
            return "[REDACTED]"
        }
        return redactionPolicy.redactGenericText(value)
    }

    private func jsonResult(_ value: MCPJSONValue) -> MCPToolCallResult {
        do {
            let data = try value.encodeToData()
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return MCPToolCallResult(content: [.text(text)], isError: nil)
        } catch {
            logger.error("Failed to encode tool result: \(error.localizedDescription, privacy: .public)")
            return MCPToolCallResult(
                content: [.text("{\"error\": \"Internal encoding error\"}")],
                isError: true
            )
        }
    }
}
