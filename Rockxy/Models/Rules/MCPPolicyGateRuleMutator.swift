import Foundation

// MARK: - MCPPolicyGateRuleMutator

struct MCPPolicyGateRuleMutator: MCPRuleMutating {
    func addRule(_ rule: ProxyRule) async -> RuleMutationResult {
        await RulePolicyGate.shared.addRulePersisting(rule)
    }

    func setRuleEnabled(id: UUID, enabled: Bool) async -> Bool {
        await RulePolicyGate.shared.setRuleEnabled(id: id, enabled: enabled)
    }

    func rule(id: UUID) async -> ProxyRule? {
        await RuleEngine.shared.allRules.first { $0.id == id }
    }
}
