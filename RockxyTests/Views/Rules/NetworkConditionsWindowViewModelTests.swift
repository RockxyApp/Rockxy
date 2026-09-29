import Foundation
@testable import Rockxy
import Testing

// MARK: - NetworkConditionsWindowViewModelTests

@MainActor
struct NetworkConditionsWindowViewModelTests {
    // MARK: Internal

    @Test
    func filteringMatchesNameHostAndPresetWhileIgnoringOtherRuleTypes() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let apiRule = networkRule(name: "3G API Slowdown", host: "api.service.test", preset: .threeG)
        let checkoutRule = networkRule(name: "Checkout EDGE", host: "shop.example.com", preset: .edge)
        let blockRule = ProxyRule(
            name: "Blocked API",
            matchCondition: RuleMatchCondition(urlPattern: ".*api.service.test.*"),
            action: .block(statusCode: 403)
        )
        seed(viewModel, rules: [apiRule, checkoutRule, blockRule])

        viewModel.searchText = "edge"
        #expect(viewModel.filteredRules.map(\.id) == [checkoutRule.id])

        viewModel.searchText = "service"
        #expect(viewModel.filteredRules.map(\.id) == [apiRule.id])
    }

    @Test
    func toggleRuleEnforcesSingleActiveNetworkConditionOptimistically() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let activeRule = networkRule(name: "3G", host: "api.example.com", preset: .threeG, isEnabled: true)
        let inactiveRule = networkRule(name: "WiFi", host: "local.example.com", preset: .wifi, isEnabled: false)
        seed(viewModel, rules: [activeRule, inactiveRule])

        viewModel.toggleRule(id: inactiveRule.id)

        #expect(viewModel.allRules.first { $0.id == activeRule.id }?.isEnabled == false)
        #expect(viewModel.allRules.first { $0.id == inactiveRule.id }?.isEnabled == true)
        #expect(viewModel.activeCount == 1)
    }

    @Test
    func addRuleSelectsNewRuleAndDisablesExistingActiveNetworkConditionOnly() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let activeRule = networkRule(name: "3G", host: "api.example.com", preset: .threeG, isEnabled: true)
        let blockRule = ProxyRule(
            name: "Block API",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*api\\.example\\.com.*"),
            action: .block(statusCode: 403)
        )
        let newRule = networkRule(name: "EDGE", host: "edge.example.com", preset: .edge, isEnabled: true)
        seed(viewModel, rules: [activeRule, blockRule])

        viewModel.addRule(newRule)

        #expect(viewModel.allRules.first { $0.id == activeRule.id }?.isEnabled == false)
        #expect(viewModel.allRules.first { $0.id == blockRule.id }?.isEnabled == true)
        #expect(viewModel.selectedRuleID == newRule.id)
        #expect(viewModel.activeCount == 1)
    }

    @Test
    func updateRuleReplacesSelectedRuleWithoutChangingOtherRows() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let original = networkRule(name: "Original", host: "api.example.com", preset: .threeG)
        let other = networkRule(name: "Other", host: "other.example.com", preset: .edge, isEnabled: false)
        seed(viewModel, rules: [original, other])

        let updated = ProxyRule(
            id: original.id,
            name: "Updated LTE",
            isEnabled: false,
            matchCondition: RuleMatchCondition(urlPattern: NetworkConditionsPatternFormatter.hostScopedPattern(
                from: "cdn.example.com"
            )),
            action: .networkCondition(preset: .lte, delayMs: NetworkConditionPreset.lte.defaultLatencyMs)
        )
        viewModel.updateRule(updated)

        #expect(viewModel.selectedRuleID == original.id)
        #expect(viewModel.allRules.first { $0.id == original.id }?.name == "Updated LTE")
        #expect(viewModel.hostLabel(for: updated) == "cdn.example.com")
        #expect(viewModel.allRules.first { $0.id == other.id }?.name == "Other")
    }

    @Test
    func duplicateAndRemoveSelectedRuleUpdateSelection() throws {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let rule = networkRule(name: "Checkout EDGE", host: "shop.example.com", preset: .edge)
        seed(viewModel, rules: [rule])
        viewModel.selectedRuleID = rule.id

        viewModel.duplicateSelectedRule()

        #expect(viewModel.networkConditionRules.count == 2)
        let copy = try #require(viewModel.selectedRule)
        #expect(copy.id != rule.id)
        #expect(copy.name == "Copy of Checkout EDGE")
        #expect(copy.isEnabled == false)

        viewModel.removeSelectedRule()

        #expect(viewModel.networkConditionRules.count == 1)
        #expect(viewModel.selectedRuleID == nil)
    }

    @Test
    func duplicateSelectedRulePreservesPayloadPriorityAndDisablesCopy() throws {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let rule = ProxyRule(
            name: "Checkout EDGE",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: NetworkConditionsPatternFormatter.hostScopedPattern(
                from: "shop.example.com:8443"
            )),
            action: .networkCondition(preset: .edge, delayMs: 850),
            priority: 42
        )
        seed(viewModel, rules: [rule])
        viewModel.selectedRuleID = rule.id

        viewModel.duplicateSelectedRule()

        let copy = try #require(viewModel.selectedRule)
        #expect(copy.id != rule.id)
        #expect(copy.name == "Copy of Checkout EDGE")
        #expect(copy.isEnabled == false)
        #expect(viewModel.allRules.first { $0.id == rule.id }?.isEnabled == true)
        #expect(copy.matchCondition == rule.matchCondition)
        #expect(copy.priority == 42)
        if case let .networkCondition(preset, delayMs) = copy.action {
            #expect(preset == .edge)
            #expect(delayMs == 850)
        } else {
            Issue.record("Expected .networkCondition action")
        }
    }

    @Test
    func duplicateAndRemoveNoOpWithoutSelection() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let rule = networkRule(name: "Checkout EDGE", host: "shop.example.com", preset: .edge)
        seed(viewModel, rules: [rule])

        viewModel.duplicateSelectedRule()
        viewModel.removeSelectedRule()

        #expect(viewModel.networkConditionRules.map(\.id) == [rule.id])
    }

    @Test
    func removeRuleDeletesClickedRowAndClearsSelectionOnlyWhenNeeded() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let first = networkRule(name: "First", host: "one.example.com", preset: .threeG)
        let second = networkRule(name: "Second", host: "two.example.com", preset: .edge)
        seed(viewModel, rules: [first, second])
        viewModel.selectedRuleID = second.id

        viewModel.removeRule(id: first.id)

        #expect(viewModel.networkConditionRules.map(\.id) == [second.id])
        #expect(viewModel.selectedRuleID == second.id)

        viewModel.removeRule(id: second.id)

        #expect(viewModel.networkConditionRules.isEmpty)
        #expect(viewModel.selectedRuleID == nil)
    }

    @Test
    func disableAllDisablesOnlyNetworkConditionRules() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let first = networkRule(name: "First", host: "one.example.com", preset: .threeG, isEnabled: true)
        let second = networkRule(name: "Second", host: "two.example.com", preset: .edge, isEnabled: true)
        let blockRule = ProxyRule(
            name: "Block API",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*api\\.example\\.com.*"),
            action: .block(statusCode: 403)
        )
        seed(viewModel, rules: [first, second, blockRule])

        viewModel.disableAll()

        #expect(viewModel.allRules.first { $0.id == first.id }?.isEnabled == false)
        #expect(viewModel.allRules.first { $0.id == second.id }?.isEnabled == false)
        #expect(viewModel.allRules.first { $0.id == blockRule.id }?.isEnabled == true)
        #expect(viewModel.activeCount == 0)
    }

    @Test
    func disablingToolPreservesRuleEnabledStateAndPausesStatus() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let rule = networkRule(name: "3G API", host: "api.example.com", preset: .threeG, isEnabled: true)
        seed(viewModel, rules: [rule])

        viewModel.setToolEnabled(false)

        #expect(viewModel.allRules.first { $0.id == rule.id }?.isEnabled == true)
        #expect(viewModel.statusLabel(for: rule).0 == "Paused")
    }

    @Test
    func profileMetadataAndStatusLabelsReflectRuleState() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let activeRule = networkRule(name: "3G API", host: "api.example.com", preset: .threeG, isEnabled: true)
        let inactiveRule = networkRule(name: "WiFi API", host: "wifi.example.com", preset: .wifi, isEnabled: false)
        seed(viewModel, rules: [activeRule, inactiveRule])

        let profile = viewModel.networkProfile(for: activeRule)

        #expect(profile.name == "3G")
        #expect(profile.downloadBandwidth == "< 780 kbps")
        #expect(profile.uploadBandwidth == "< 330 kbps")
        // The percent sign is placed by the locale (`de_DE` writes "0,0 %"), so this pins the
        // shared formatter rather than one machine's spelling.
        #expect(profile.packetLoss == DecimalFormatter.percent(0, fractionDigits: 1))
        #expect(NetworkConditionPreset.veryBadNetwork.packetLossLabel == DecimalFormatter.percent(0.1, fractionDigits: 1))
        #expect(profile.systemImage == "antenna.radiowaves.left.and.right")
        #expect(viewModel.statusLabel(for: activeRule).0 == "Enabled")
        #expect(viewModel.statusLabel(for: inactiveRule).0 == "Inactive")

        let customRule = networkRule(name: "Custom API", host: "custom.example.com", preset: .custom)
        #expect(viewModel.networkProfile(for: customRule).name == "Custom Latency")
    }

    @Test
    func hostScopedPatternMatchesHTTPHTTPSAndOptionalPort() throws {
        let pattern = NetworkConditionsPatternFormatter.hostScopedPattern(from: "api.example.com")
        let regex = try NSRegularExpression(pattern: pattern)
        let condition = RuleMatchCondition(urlPattern: pattern)

        #expect(condition.matches(
            method: "GET",
            url: try #require(URL(string: "http://api.example.com/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
        #expect(condition.matches(
            method: "GET",
            url: try #require(URL(string: "https://api.example.com:8443/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
        #expect(!condition.matches(
            method: "GET",
            url: try #require(URL(string: "https://other.example.com/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
    }

    @Test
    func hostScopedPatternRespectsExplicitPort() throws {
        let pattern = NetworkConditionsPatternFormatter.hostScopedPattern(from: "api.example.com:8443")
        let regex = try NSRegularExpression(pattern: pattern)
        let condition = RuleMatchCondition(urlPattern: pattern)

        #expect(condition.matches(
            method: "GET",
            url: try #require(URL(string: "https://api.example.com:8443/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
        #expect(!condition.matches(
            method: "GET",
            url: try #require(URL(string: "https://api.example.com:9443/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
    }

    @Test
    func hostFormatterNormalizesURLsAndRoundTripsHostText() {
        let pattern = NetworkConditionsPatternFormatter.hostScopedPattern(
            from: " https://api.example.com:8443/v1/users?debug=true "
        )

        #expect(pattern == "(?i)^https?://api\\.example\\.com:8443(?:/.*)?$")
        #expect(NetworkConditionsPatternFormatter.hostText(from: pattern) == "api.example.com:8443")
        #expect(NetworkConditionsPatternFormatter.hostText(from: nil) == "")
    }

    @Test
    func hostFormatterSupportsCaseInsensitiveHostsAndIPv6Authorities() throws {
        let hostnamePattern = NetworkConditionsPatternFormatter.hostScopedPattern(from: "API.Example.COM")
        let hostnameRegex = try NSRegularExpression(pattern: hostnamePattern)
        let hostnameCondition = RuleMatchCondition(urlPattern: hostnamePattern)

        #expect(hostnameCondition.matches(
            method: "GET",
            url: try #require(URL(string: "https://api.example.com/v1")),
            headers: [],
            compiledPattern: hostnameRegex
        ))

        let ipv6Pattern = NetworkConditionsPatternFormatter.hostScopedPattern(from: "::1")
        let ipv6Regex = try NSRegularExpression(pattern: ipv6Pattern)
        let ipv6Condition = RuleMatchCondition(urlPattern: ipv6Pattern)
        #expect(NetworkConditionsPatternFormatter.hostText(from: ipv6Pattern) == "[::1]")
        #expect(ipv6Condition.matches(
            method: "GET",
            url: try #require(URL(string: "https://[::1]:8443/v1")),
            headers: [],
            compiledPattern: ipv6Regex
        ))

        let explicitPortPattern = NetworkConditionsPatternFormatter.hostScopedPattern(from: "[::1]:9443")
        #expect(NetworkConditionsPatternFormatter.hostText(from: explicitPortPattern) == "[::1]:9443")
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: "[::1]:9443") == nil)
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: "api.example.com:0") != nil)
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: "not a host") != nil)
    }

    @Test
    func hostFormatterNormalizesIPv6URLsWithoutDoubleBrackets() throws {
        let pattern = NetworkConditionsPatternFormatter.hostScopedPattern(
            from: "https://[::1]:8443/v1/users?debug=true"
        )
        let regex = try NSRegularExpression(pattern: pattern)
        let condition = RuleMatchCondition(urlPattern: pattern)

        #expect(pattern == "(?i)^https?://\\[::1]:8443(?:/.*)?$")
        #expect(NetworkConditionsPatternFormatter.hostText(from: pattern) == "[::1]:8443")
        #expect(condition.matches(
            method: "GET",
            url: try #require(URL(string: "https://[::1]:8443/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
    }

    @Test
    func hostValidationRejectsUnsupportedSchemesAndMalformedHosts() {
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(
            for: "https://api.example.com/v1?debug=true"
        ) == nil)
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: "ftp://api.example.com/v1") != nil)
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: "bad..example") != nil)
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: "[not-ipv6]") != nil)
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: "::gg") != nil)
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: "999.999.999.999") != nil)
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: "localhost") == nil)
        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: "internal-host") == nil)
    }

    @Test
    func ruleFormDefaultsValidationAndSaveContractMatchAddSheet() {
        #expect(NetworkConditionsRuleForm.defaultName == "Untitled")
        #expect(NetworkConditionsRuleForm.defaultPreset == .threeG)
        #expect(NetworkConditionsRuleForm.defaultCustomLatencyMs == 500)
        #expect(NetworkConditionsRuleForm.isValid(
            name: "Untitled",
            hostText: "api.service.test",
            applySystemWide: false,
            preset: .threeG,
            customLatencyMs: 500
        ))
        #expect(!NetworkConditionsRuleForm.isValid(
            name: " ",
            hostText: "api.service.test",
            applySystemWide: false,
            preset: .threeG,
            customLatencyMs: 500
        ))
        #expect(!NetworkConditionsRuleForm.isValid(
            name: "Untitled",
            hostText: " ",
            applySystemWide: false,
            preset: .threeG,
            customLatencyMs: 500
        ))
        #expect(!NetworkConditionsRuleForm.isValid(
            name: "Custom",
            hostText: "api.service.test",
            applySystemWide: false,
            preset: .custom,
            customLatencyMs: 0
        ))

        let rule = NetworkConditionsRuleForm.makeRule(
            existingID: nil,
            name: NetworkConditionsRuleForm.defaultName,
            isEnabled: true,
            hostText: "api.service.test",
            applySystemWide: false,
            preset: NetworkConditionsRuleForm.defaultPreset,
            customLatencyMs: NetworkConditionsRuleForm.defaultCustomLatencyMs
        )

        #expect(rule.name == "Untitled")
        #expect(rule.isEnabled)
        #expect(rule.matchCondition.urlPattern == "(?i)^https?://api\\.service\\.test(?::\\d+)?(?:/.*)?$")
        if case let .networkCondition(preset, delayMs) = rule.action {
            #expect(preset == .threeG)
            #expect(delayMs == 400)
        } else {
            Issue.record("Expected .networkCondition action")
        }
    }

    @Test
    func ruleFormPreservesExistingIDAndBuildsSystemWideEdit() {
        let id = UUID()
        let rule = NetworkConditionsRuleForm.makeRule(
            existingID: id,
            name: "Edited",
            isEnabled: false,
            hostText: "ignored.example.com",
            applySystemWide: true,
            preset: .custom,
            customLatencyMs: 1_234
        )

        #expect(rule.id == id)
        #expect(rule.name == "Edited")
        #expect(rule.isEnabled == false)
        #expect(rule.matchCondition.urlPattern == nil)
        if case let .networkCondition(preset, delayMs) = rule.action {
            #expect(preset == .custom)
            #expect(delayMs == 1_234)
        } else {
            Issue.record("Expected .networkCondition action")
        }
    }

    @Test
    func filteringTrimsWhitespaceAndTreatsBlankQueryAsNoSearch() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let apiRule = networkRule(name: "3G API Slowdown", host: "api.service.test", preset: .threeG)
        let checkoutRule = networkRule(name: "Checkout EDGE", host: "shop.example.com", preset: .edge)
        seed(viewModel, rules: [apiRule, checkoutRule])

        // A whitespace-only query behaves as no search.
        viewModel.searchText = "   "
        #expect(viewModel.filteredRules.map(\.id) == viewModel.networkConditionRules.map(\.id))

        // The trimmed query matches a single rule.
        viewModel.searchText = "edge"
        let trimmedMatch = viewModel.filteredRules.map(\.id)
        #expect(trimmedMatch == [checkoutRule.id])

        // A padded query matches exactly the same rule as the trimmed query.
        viewModel.searchText = "   edge   "
        #expect(viewModel.filteredRules.map(\.id) == trimmedMatch)
    }

    @Test
    func ruleFormEditPreservesNonManagedRuleSemantics() {
        let id = UUID()
        let canonicalPattern = NetworkConditionsPatternFormatter.hostScopedPattern(from: "api.example.com")
        let original = ProxyRule(
            id: id,
            name: "3G API",
            isEnabled: true,
            matchCondition: RuleMatchCondition(
                urlPattern: canonicalPattern,
                sourceURLPattern: "api.example.com/*",
                method: "POST",
                headerName: "X-Env",
                headerValue: "staging",
                matchType: .wildcard,
                includeSubpaths: true
            ),
            action: .networkCondition(preset: .threeG, delayMs: NetworkConditionPreset.threeG.defaultLatencyMs),
            priority: 42
        )

        // Edit only the managed fields (name, enabled, preset) while leaving the host scope untouched:
        // the editor passes back the host text derived from the original pattern.
        let edited = NetworkConditionsRuleForm.makeRule(
            original: original,
            name: "3G API (edited)",
            isEnabled: false,
            hostText: NetworkConditionsPatternFormatter.hostText(from: canonicalPattern),
            applySystemWide: false,
            preset: .lte,
            customLatencyMs: NetworkConditionsRuleForm.defaultCustomLatencyMs
        )

        // Editor-managed fields change as requested.
        #expect(edited.id == id)
        #expect(edited.name == "3G API (edited)")
        #expect(edited.isEnabled == false)
        if case let .networkCondition(preset, delayMs) = edited.action {
            #expect(preset == .lte)
            #expect(delayMs == NetworkConditionPreset.lte.defaultLatencyMs)
        } else {
            Issue.record("Expected .networkCondition action")
        }

        // Every field the editor does not manage survives the save.
        #expect(edited.priority == 42)
        #expect(edited.matchCondition.method == "POST")
        #expect(edited.matchCondition.headerName == "X-Env")
        #expect(edited.matchCondition.headerValue == "staging")
        #expect(edited.matchCondition.matchType == .wildcard)
        #expect(edited.matchCondition.sourceURLPattern == "api.example.com/*")
        #expect(edited.matchCondition.includeSubpaths == true)
        // Host untouched → the original canonical pattern is preserved, not regenerated.
        #expect(edited.matchCondition.urlPattern == canonicalPattern)
    }

    @Test
    func ruleFormEditPreservesLegacyPatternButRoundTripsCanonicalHost() {
        // A legacy / noncanonical regex authored before host-scoped patterns existed.
        let legacyPattern = ".*api\\.example\\.com.*"
        let legacyOriginal = ProxyRule(
            name: "Legacy 3G",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: legacyPattern),
            action: .networkCondition(preset: .threeG, delayMs: NetworkConditionPreset.threeG.defaultLatencyMs)
        )
        // No scope change (host text is the value the editor derived from the legacy pattern):
        // the legacy regex must survive verbatim instead of being flattened to a canonical pattern.
        let legacyEdited = NetworkConditionsRuleForm.makeRule(
            original: legacyOriginal,
            name: "Legacy 3G",
            isEnabled: true,
            hostText: NetworkConditionsPatternFormatter.hostText(from: legacyPattern),
            applySystemWide: false,
            preset: .edge,
            customLatencyMs: NetworkConditionsRuleForm.defaultCustomLatencyMs
        )
        #expect(legacyEdited.matchCondition.urlPattern == legacyPattern)

        // A canonical Rockxy host-scoped pattern still round-trips through host text on a scope change.
        let canonicalPattern = NetworkConditionsPatternFormatter.hostScopedPattern(from: "api.example.com")
        let canonicalOriginal = ProxyRule(
            name: "Canonical 3G",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: canonicalPattern),
            action: .networkCondition(preset: .threeG, delayMs: NetworkConditionPreset.threeG.defaultLatencyMs)
        )
        #expect(NetworkConditionsPatternFormatter.hostText(from: canonicalPattern) == "api.example.com")

        let canonicalEdited = NetworkConditionsRuleForm.makeRule(
            original: canonicalOriginal,
            name: "Canonical 3G",
            isEnabled: true,
            hostText: "cdn.example.com",
            applySystemWide: false,
            preset: .threeG,
            customLatencyMs: NetworkConditionsRuleForm.defaultCustomLatencyMs
        )
        #expect(
            canonicalEdited.matchCondition.urlPattern
                == NetworkConditionsPatternFormatter.hostScopedPattern(from: "cdn.example.com")
        )
        #expect(
            NetworkConditionsPatternFormatter.hostText(from: canonicalEdited.matchCondition.urlPattern)
                == "cdn.example.com"
        )
    }

    @Test
    func unchangedLegacyRegexRemainsValidForUnrelatedEdits() {
        let legacyPattern = "^https://(api|cdn)\\.example\\.com/.*$"
        let original = ProxyRule(
            name: "Legacy profile",
            matchCondition: RuleMatchCondition(urlPattern: legacyPattern),
            action: .networkCondition(preset: .threeG, delayMs: NetworkConditionPreset.threeG.defaultLatencyMs)
        )
        let derivedHostText = NetworkConditionsPatternFormatter.hostText(from: legacyPattern)

        #expect(NetworkConditionsPatternFormatter.hostValidationMessage(for: derivedHostText) != nil)
        #expect(NetworkConditionsRuleForm.isValid(
            name: "Renamed legacy profile",
            hostText: derivedHostText,
            applySystemWide: false,
            preset: .lte,
            customLatencyMs: NetworkConditionsRuleForm.defaultCustomLatencyMs,
            original: original
        ))
    }

    @Test
    func rejectedPolicySaveDoesNotOptimisticallyInsertRule() async {
        let viewModel = NetworkConditionsWindowViewModel(isToolEnabled: true)
        let candidate = networkRule(
            name: "Rejected profile",
            host: "quota.example.com",
            preset: .threeG
        )

        let accepted = await viewModel.saveRule(
            candidate,
            using: RulePolicyGate(policy: NetworkConditionsTestPolicy(maxActiveRulesPerTool: 0))
        )

        #expect(!accepted)
        #expect(!viewModel.allRules.contains { $0.id == candidate.id })
        #expect(viewModel.selectedRuleID != candidate.id)
    }

    // MARK: Private

    private func seed(_ viewModel: NetworkConditionsWindowViewModel, rules: [ProxyRule]) {
        viewModel.handleRulesDidChange(Notification(name: .rulesDidChange, object: rules))
    }

    private func networkRule(
        name: String,
        host: String,
        preset: NetworkConditionPreset,
        isEnabled: Bool = true
    )
        -> ProxyRule
    {
        ProxyRule(
            name: name,
            isEnabled: isEnabled,
            matchCondition: RuleMatchCondition(urlPattern: ".*\(NSRegularExpression.escapedPattern(for: host)).*"),
            action: .networkCondition(preset: preset, delayMs: preset.defaultLatencyMs)
        )
    }
}

private struct NetworkConditionsTestPolicy: AppPolicy {
    let maxActiveRulesPerTool: Int
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
}
