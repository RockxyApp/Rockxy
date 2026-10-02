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

    /// Evaluates only Breakpoint rules and returns the first matching enabled rule.
    /// Breakpoint is an interruption tool, so request-phase breakpoints need a chance
    /// to pause traffic before another rule category consumes the same request.
    func evaluateBreakpointRule(
        method: String,
        url: URL,
        headers: [HTTPHeader],
        graphQLOperationName: String? = nil,
        clientApplication: ClientApplicationIdentity? = nil
    )
        -> ProxyRule?
    {
        guard breakpointToolEnabled else {
            return nil
        }
        for rule in rules where rule.isEnabled {
            guard case .breakpoint = rule.action else {
                continue
            }
            let compiled = compiledPatterns[rule.id]
            if rule.matchCondition.matches(
                method: method,
                url: url,
                headers: headers,
                compiledPattern: compiled,
                graphQLOperationName: graphQLOperationName,
                clientApplication: clientApplication
            ) {
                Self.logger.debug("Breakpoint rule matched: \(rule.name, privacy: .private)")
                return rule
            }
        }
        return nil
    }

    /// Evaluates rules and returns the full matching rule (action + match condition).
    /// Used by Map Local Directory to extract the URL pattern for subpath resolution.
    func evaluateRule(
        method: String,
        url: URL,
        headers: [HTTPHeader],
        graphQLOperationName: String? = nil,
        clientApplication: ClientApplicationIdentity? = nil
    )
        -> ProxyRule?
    {
        rules.first { rule in
            ruleApplies(
                rule,
                method: method,
                url: url,
                headers: headers,
                graphQLOperationName: graphQLOperationName,
                clientApplication: clientApplication
            )
        }
    }

    /// The first matching rule that decides where a request goes (Block, Map Local,
    /// Map Remote, Throttle, Network Conditions). Modify Headers rules never compete for
    /// this slot: they layer on top of whatever happens, through `matchingHeaderRules`.
    func evaluatePrimaryRule(
        method: String,
        url: URL,
        headers: [HTTPHeader],
        graphQLOperationName: String? = nil,
        clientApplication: ClientApplicationIdentity? = nil
    )
        -> ProxyRule?
    {
        rules.first { rule in
            if case .modifyHeader = rule.action {
                return false
            }
            return ruleApplies(
                rule,
                method: method,
                url: url,
                headers: headers,
                graphQLOperationName: graphQLOperationName,
                clientApplication: clientApplication
            )
        }
    }

    /// Every enabled Modify Headers rule that matches, in list order, so a header rule
    /// also reaches Map Local, Map Remote and scripted traffic on the same URL.
    func matchingHeaderRules(
        method: String,
        url: URL,
        headers: [HTTPHeader],
        graphQLOperationName: String? = nil,
        clientApplication: ClientApplicationIdentity? = nil
    )
        -> [ProxyRule]
    {
        rules.filter { rule in
            guard case .modifyHeader = rule.action else {
                return false
            }
            return ruleApplies(
                rule,
                method: method,
                url: url,
                headers: headers,
                graphQLOperationName: graphQLOperationName,
                clientApplication: clientApplication
            )
        }
    }

    /// Whether any enabled rule is scoped to a client application, so the proxy must resolve
    /// which process made a connection before it can evaluate rules.
    var hasApplicationScopedRules: Bool {
        rules.contains { $0.isEnabled && $0.matchCondition.requiredClientApplication != nil }
    }

    func addRule(_ rule: ProxyRule) {
        rules.append(rule)
        if let pattern = rule.matchCondition.runtimeURLPattern {
            if case let .success(regex) = RegexValidator.compile(pattern) {
                compiledPatterns[rule.id] = regex
            }
        }
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        compiledPatterns.removeValue(forKey: id)
    }

    /// Removes only the rules whose IDs are in `ids`, against current engine state.
    /// Rules absent from `ids` — including concurrent additions from other windows —
    /// are left untouched, so a stale caller snapshot can never clobber them.
    func removeRules(ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }
        rules.removeAll { ids.contains($0.id) }
        for id in ids {
            compiledPatterns.removeValue(forKey: id)
        }
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
            if let pattern = rule.matchCondition.runtimeURLPattern,
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

    /// Replaces every Block rule with `importedBlockRules` against current engine
    /// state, retaining all non-Block rules — including concurrent additions from
    /// other windows (e.g. Map Local) — in their existing order. The imported set is
    /// appended after the retained non-Block rules, preserving the import semantic
    /// that the imported rules become the entire Block category. Enabled imported
    /// Block rules beyond `maxPerCategory` are disabled so the per-category active
    /// quota is never exceeded, mirroring the capping applied by a full replace.
    func replaceBlockRules(_ importedBlockRules: [ProxyRule], maxPerCategory: Int) {
        let retained = rules.filter { rule in
            if case .block = rule.action {
                return false
            }
            return true
        }
        rules = retained + importedBlockRules
        compilePatterns()
        var activeBlockCount = 0
        for index in rules.indices {
            guard case .block = rules[index].action, rules[index].isEnabled else {
                continue
            }
            if activeBlockCount < maxPerCategory {
                activeBlockCount += 1
            } else {
                rules[index].isEnabled = false
            }
        }
    }

    /// Reorders only Modify Header rules within their existing global slots.
    /// Missing IDs are ignored and newly-added Modify Header rules retain their
    /// current relative order after the explicitly ordered rules.
    func reorderModifyHeaderRules(orderedIDs: [UUID]) {
        let headerRules = rules.filter { rule in
            if case .modifyHeader = rule.action {
                return true
            }
            return false
        }
        let byID = Dictionary(uniqueKeysWithValues: headerRules.map { ($0.id, $0) })
        let orderedIDSet = Set(orderedIDs)
        let reordered = orderedIDs.compactMap { byID[$0] }
            + headerRules.filter { !orderedIDSet.contains($0.id) }
        guard reordered.count == headerRules.count else {
            return
        }

        var iterator = reordered.makeIterator()
        rules = rules.map { rule in
            if case .modifyHeader = rule.action {
                return iterator.next() ?? rule
            }
            return rule
        }
    }

    /// Reorders only Map Local rules within their existing global slots.
    /// Missing IDs are ignored and newly-added Map Local rules retain their
    /// current relative order after the explicitly ordered rules.
    func reorderMapLocalRules(orderedIDs: [UUID]) {
        let mapLocalRules = rules.filter { rule in
            if case .mapLocal = rule.action {
                return true
            }
            return false
        }
        let byID = Dictionary(uniqueKeysWithValues: mapLocalRules.map { ($0.id, $0) })
        let orderedIDSet = Set(orderedIDs)
        let reordered = orderedIDs.compactMap { byID[$0] }
            + mapLocalRules.filter { !orderedIDSet.contains($0.id) }
        guard reordered.count == mapLocalRules.count else {
            return
        }

        var iterator = reordered.makeIterator()
        rules = rules.map { rule in
            if case .mapLocal = rule.action {
                return iterator.next() ?? rule
            }
            return rule
        }
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

    func enableExclusiveNetworkConditionIfAllowed(id: UUID, maxPerCategory: Int) -> Bool {
        guard rules.contains(where: { $0.id == id }) else {
            return false
        }
        // Exclusive enable disables all others then enables the target,
        // so the post-switch count is always exactly 1.
        guard maxPerCategory >= 1 else {
            return false
        }
        enableExclusiveNetworkCondition(id: id)
        return true
    }

    func addNetworkConditionExclusive(_ rule: ProxyRule) {
        precondition(
            {
                if case .networkCondition = rule.action {
                    return true
                }
                return false
            }(),
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

    func setBreakpointToolEnabled(_ enabled: Bool) {
        breakpointToolEnabled = enabled
    }

    func setBlockListToolEnabled(_ enabled: Bool) {
        blockListToolEnabled = enabled
    }

    func setMapLocalToolEnabled(_ enabled: Bool) {
        mapLocalToolEnabled = enabled
    }

    func setMapRemoteToolEnabled(_ enabled: Bool) {
        mapRemoteToolEnabled = enabled
    }

    func setNetworkConditionsToolEnabled(_ enabled: Bool) {
        networkConditionsToolEnabled = enabled
    }

    func setModifyHeaderToolEnabled(_ enabled: Bool) {
        modifyHeaderToolEnabled = enabled
    }

    // MARK: - Atomic Quota-Checked Operations

    func addRuleIfAllowed(_ rule: ProxyRule, maxPerCategory: Int) -> Bool {
        guard rule.isEnabled else {
            addRule(rule)
            return true
        }
        let category = rule.action.toolCategory
        let activeCount = rules.filter { $0.isEnabled && $0.action.toolCategory == category }.count
        guard activeCount < maxPerCategory else {
            return false
        }
        addRule(rule)
        return true
    }

    func toggleRuleIfAllowed(id: UUID, maxPerCategory: Int) -> Bool {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return false
        }
        if rules[index].isEnabled {
            rules[index].isEnabled = false
            return true
        }
        let category = rules[index].action.toolCategory
        let activeCount = rules.filter { $0.isEnabled && $0.action.toolCategory == category }.count
        guard activeCount < maxPerCategory else {
            return false
        }
        rules[index].isEnabled = true
        return true
    }

    func setEnabledIfAllowed(id: UUID, enabled: Bool, maxPerCategory: Int) -> Bool {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard enabled else {
            rules[index].isEnabled = false
            return true
        }
        // Already enabled — no-op success
        if rules[index].isEnabled {
            return true
        }
        let category = rules[index].action.toolCategory
        let activeCount = rules.filter { $0.isEnabled && $0.action.toolCategory == category }.count
        guard activeCount < maxPerCategory else {
            return false
        }
        rules[index].isEnabled = true
        return true
    }

    /// Bulk enables or disables every Map Local rule against current engine state,
    /// mutating only Map Local rules and leaving all other categories (and concurrent
    /// additions) untouched. When enabling, already-enabled rules are preserved first
    /// and additional rules are enabled in order only while the active Map Local count
    /// stays below `maxPerCategory`, so the quota is never exceeded.
    func setMapLocalRulesEnabled(_ enabled: Bool, maxPerCategory: Int) {
        guard enabled else {
            for index in rules.indices {
                if case .mapLocal = rules[index].action {
                    rules[index].isEnabled = false
                }
            }
            return
        }
        var activeCount = rules.filter { rule in
            guard rule.isEnabled, case .mapLocal = rule.action else {
                return false
            }
            return true
        }.count
        for index in rules.indices {
            guard case .mapLocal = rules[index].action, !rules[index].isEnabled else {
                continue
            }
            guard activeCount < maxPerCategory else {
                continue
            }
            rules[index].isEnabled = true
            activeCount += 1
        }
    }

    func addNetworkConditionExclusiveIfAllowed(_ rule: ProxyRule, maxPerCategory: Int) -> Bool {
        // addNetworkConditionExclusive disables all existing network conditions
        // then adds the new one enabled, so post-switch count is always 1.
        guard maxPerCategory >= 1 else {
            return false
        }
        addNetworkConditionExclusive(rule)
        return true
    }

    // MARK: Private

    private func ruleApplies(
        _ rule: ProxyRule,
        method: String,
        url: URL,
        headers: [HTTPHeader],
        graphQLOperationName: String?,
        clientApplication: ClientApplicationIdentity?
    )
        -> Bool
    {
        guard rule.isEnabled, isToolEnabled(for: rule.action) else {
            return false
        }
        let matched = rule.matchCondition.matches(
            method: method,
            url: url,
            headers: headers,
            compiledPattern: compiledPatterns[rule.id],
            graphQLOperationName: graphQLOperationName,
            clientApplication: clientApplication
        )
        if matched {
            Self.logger.debug("Rule matched: \(rule.name, privacy: .private)")
        }
        return matched
    }

    private func isToolEnabled(for action: RuleAction) -> Bool {
        switch action {
        case .block: blockListToolEnabled
        case .breakpoint: breakpointToolEnabled
        case .mapLocal: mapLocalToolEnabled
        case .mapRemote: mapRemoteToolEnabled
        case .networkCondition: networkConditionsToolEnabled
        case .modifyHeader: modifyHeaderToolEnabled
        case .throttle: true
        }
    }

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "RuleEngine")

    private var rules: [ProxyRule] = []
    private var blockListToolEnabled: Bool = true
    private var breakpointToolEnabled: Bool = true
    private var mapLocalToolEnabled: Bool = true
    private var mapRemoteToolEnabled: Bool = true
    private var networkConditionsToolEnabled: Bool = true
    private var modifyHeaderToolEnabled: Bool = true
    private var compiledPatterns: [UUID: NSRegularExpression] = [:]

    private func compilePatterns() {
        compiledPatterns.removeAll()
        for i in rules.indices {
            guard let pattern = rules[i].matchCondition.runtimeURLPattern else {
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
