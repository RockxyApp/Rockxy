import Foundation
import os

/// Evaluates an ordered list of proxy rules against incoming HTTP requests.
/// The first matching enabled rule wins — rules are evaluated sequentially,
/// so ordering determines priority when multiple rules could match.
actor RuleEngine {
    // MARK: Internal

    static let shared = RuleEngine()

    var allRules: [ProxyRule] {
        rules
    }

    func loadRules(from store: RuleStore) throws {
        rules = try store.loadRules()
        compilePatterns()
        let count = rules.count
        Self.logger.info("Loaded \(count) rules")
    }

    /// Evaluates rules and returns the first matching action.
    func evaluate(method: String, url: URL, headers: [HTTPHeader]) -> RuleAction? {
        evaluateRule(method: method, url: url, headers: headers)?.action
    }

    /// Evaluates rules and returns the full matching rule (action + match condition).
    /// Used by Map Local Directory to extract the URL pattern for subpath resolution.
    func evaluateRule(method: String, url: URL, headers: [HTTPHeader]) -> ProxyRule? {
        for rule in rules where rule.isEnabled {
            let compiled = compiledPatterns[rule.id]
            if rule.matchCondition.matches(method: method, url: url, headers: headers, compiledPattern: compiled) {
                Self.logger.debug("Rule matched: \(rule.name)")
                return rule
            }
        }
        return nil
    }

    func addRule(_ rule: ProxyRule) {
        rules.append(rule)
        if let pattern = rule.matchCondition.urlPattern {
            if case let .success(regex) = RegexValidator.compile(pattern) {
                compiledPatterns[rule.id] = regex
            }
        }
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        compiledPatterns.removeValue(forKey: id)
    }

    func toggleRule(id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        rules[index].isEnabled.toggle()
    }

    func updateRule(_ rule: ProxyRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            compiledPatterns.removeValue(forKey: rule.id)
            if let pattern = rule.matchCondition.urlPattern,
               case let .success(regex) = RegexValidator.compile(pattern)
            {
                compiledPatterns[rule.id] = regex
            }
        }
    }

    func replaceAll(_ newRules: [ProxyRule]) {
        rules = newRules
        compilePatterns()
    }

    func setEnabled(id: UUID, enabled: Bool) {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index].isEnabled = enabled
        }
    }

    func enableExclusiveNetworkCondition(id: UUID) {
        for i in rules.indices {
            if case .networkCondition = rules[i].action, rules[i].id != id {
                rules[i].isEnabled = false
            }
        }
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index].isEnabled = true
        }
    }

    func addNetworkConditionExclusive(_ rule: ProxyRule) {
        precondition(
            { if case .networkCondition = rule.action {
                return true
            }
            return false }(),
            "addNetworkConditionExclusive requires a .networkCondition rule"
        )
        for i in rules.indices {
            if case .networkCondition = rules[i].action {
                rules[i].isEnabled = false
            }
        }
        var enabledRule = rule
        enabledRule.isEnabled = true
        rules.append(enabledRule)
    }

    func disableAllNetworkConditions() {
        for i in rules.indices {
            if case .networkCondition = rules[i].action {
                rules[i].isEnabled = false
            }
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "RuleEngine")

    private var rules: [ProxyRule] = []
    private var compiledPatterns: [UUID: NSRegularExpression] = [:]

    private func compilePatterns() {
        compiledPatterns.removeAll()
        for i in rules.indices {
            guard let pattern = rules[i].matchCondition.urlPattern else {
                continue
            }
            switch RegexValidator.compile(pattern) {
            case let .success(regex):
                compiledPatterns[rules[i].id] = regex
            case let .failure(error):
                let ruleName = rules[i].name
                Self.logger
                    .warning("SECURITY: Disabling rule '\(ruleName)' — invalid regex: \(error.localizedDescription)")
                rules[i].isEnabled = false
            }
        }
    }
}
