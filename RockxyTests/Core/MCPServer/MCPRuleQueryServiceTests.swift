import Foundation
@testable import Rockxy
import Testing

@Suite("MCP Rule Query Service")
struct MCPRuleQueryServiceTests {
    // MARK: Internal

    @Test("listRules emits stable JSON shape")
    func listRulesJSONShape() async throws {
        let engine = RuleEngine()
        await engine.addRule(
            ProxyRule(
                name: "Breakpoint Rule",
                isEnabled: true,
                matchCondition: RuleMatchCondition(
                    urlPattern: "api.example.com",
                    method: "GET",
                    headerName: nil,
                    headerValue: nil
                ),
                action: .breakpoint(phase: .request),
                priority: 10
            )
        )
        await engine.addRule(
            ProxyRule(
                name: "Header Rule",
                isEnabled: false,
                matchCondition: RuleMatchCondition(
                    urlPattern: nil,
                    method: nil,
                    headerName: "X-Test",
                    headerValue: "yes"
                ),
                action: .modifyHeader(operations: []),
                priority: 1
            )
        )

        let service = MCPRuleQueryService(ruleEngine: engine)
        let result = await service.listRules()

        let json = try decodeJSONObject(from: result)
        let rules = try #require(json["rules"] as? [[String: Any]])
        #expect(json["total_count"] as? Int == 2)
        #expect(rules.count == 2)

        let first = try #require(rules.first)
        #expect(first["id"] as? String != nil)
        #expect(first["name"] as? String == "Breakpoint Rule")
        #expect(first["is_enabled"] as? Bool == true)
        #expect(first["priority"] as? Int == 10)
        #expect(first["action_type"] as? String == "breakpoint")
        #expect(first["action_summary"] as? String != nil)
        let firstCondition = try #require(first["match_condition"] as? [String: Any])
        #expect(firstCondition["url_pattern"] as? String == "api.example.com")
        #expect(firstCondition["method"] as? String == "GET")

        let second = try #require(rules.last)
        let secondCondition = try #require(second["match_condition"] as? [String: Any])
        #expect(secondCondition["header_name"] as? String == "X-Test")
        #expect(secondCondition["header_value"] as? String == "yes")
    }

    @Test("listRules returns empty match_condition object for rules without conditions")
    func listRulesStableEmptyCondition() async throws {
        let engine = RuleEngine()
        await engine.addRule(
            ProxyRule(
                name: "Block Rule",
                isEnabled: true,
                matchCondition: RuleMatchCondition(
                    urlPattern: nil,
                    method: nil,
                    headerName: nil,
                    headerValue: nil
                ),
                action: .block(statusCode: 403),
                priority: 0
            )
        )

        let service = MCPRuleQueryService(ruleEngine: engine)
        let result = await service.listRules()

        let json = try decodeJSONObject(from: result)
        let rules = try #require(json["rules"] as? [[String: Any]])
        let rule = try #require(rules.first)
        let condition = try #require(rule["match_condition"] as? [String: Any])
        #expect(condition.isEmpty)
    }

    @Test("listRules handles empty rule set")
    func listRulesEmpty() async throws {
        let engine = RuleEngine()
        let service = MCPRuleQueryService(ruleEngine: engine)
        let result = await service.listRules()

        let json = try decodeJSONObject(from: result)
        let rules = try #require(json["rules"] as? [[String: Any]])
        #expect(rules.isEmpty)
        #expect(json["total_count"] as? Int == 0)
    }

    // MARK: Private

    private func decodeJSONObject(from result: MCPToolCallResult) throws -> [String: Any] {
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
