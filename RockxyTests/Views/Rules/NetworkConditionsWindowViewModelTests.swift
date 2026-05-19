import Foundation
@testable import Rockxy
import Testing

// MARK: - NetworkConditionsWindowViewModelTests

@MainActor
struct NetworkConditionsWindowViewModelTests {
    @Test
    func filteringMatchesNameHostAndPresetWhileIgnoringOtherRuleTypes() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let apiRule = networkRule(name: "3G API Slowdown", host: "api.proxyman.com", preset: .threeG)
        let checkoutRule = networkRule(name: "Checkout EDGE", host: "shop.example.com", preset: .edge)
        let blockRule = ProxyRule(
            name: "Blocked API",
            matchCondition: RuleMatchCondition(urlPattern: ".*api.proxyman.com.*"),
            action: .block(statusCode: 403)
        )
        seed(viewModel, rules: [apiRule, checkoutRule, blockRule])

        viewModel.searchText = "edge"
        #expect(viewModel.filteredRules.map(\.id) == [checkoutRule.id])

        viewModel.searchText = "proxyman"
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
        #expect(profile.packetLoss == "0.0%")
        #expect(profile.systemImage == "antenna.radiowaves.left.and.right")
        #expect(viewModel.statusLabel(for: activeRule).0 == "Active")
        #expect(viewModel.statusLabel(for: inactiveRule).0 == "Inactive")
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

        #expect(pattern == "^https?://api\\.example\\.com:8443(?:/.*)?$")
        #expect(NetworkConditionsPatternFormatter.hostText(from: pattern) == "api.example.com:8443")
        #expect(NetworkConditionsPatternFormatter.hostText(from: nil) == "")
    }

    @Test
    func ruleFormDefaultsValidationAndSaveContractMatchAddSheet() {
        #expect(NetworkConditionsRuleForm.defaultName == "Untitled")
        #expect(NetworkConditionsRuleForm.defaultPreset == .threeG)
        #expect(NetworkConditionsRuleForm.defaultCustomLatencyMs == 500)
        #expect(NetworkConditionsRuleForm.isValid(
            name: "Untitled",
            hostText: "api.proxyman.com",
            applySystemWide: false,
            preset: .threeG,
            customLatencyMs: 500
        ))
        #expect(!NetworkConditionsRuleForm.isValid(
            name: " ",
            hostText: "api.proxyman.com",
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
            hostText: "api.proxyman.com",
            applySystemWide: false,
            preset: .custom,
            customLatencyMs: 0
        ))

        let rule = NetworkConditionsRuleForm.makeRule(
            existingID: nil,
            name: NetworkConditionsRuleForm.defaultName,
            isEnabled: true,
            hostText: "api.proxyman.com",
            applySystemWide: false,
            preset: NetworkConditionsRuleForm.defaultPreset,
            customLatencyMs: NetworkConditionsRuleForm.defaultCustomLatencyMs
        )

        #expect(rule.name == "Untitled")
        #expect(rule.isEnabled)
        #expect(rule.matchCondition.urlPattern == "^https?://api\\.proxyman\\.com(?::\\d+)?(?:/.*)?$")
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

    private func seed(_ viewModel: NetworkConditionsWindowViewModel, rules: [ProxyRule]) {
        viewModel.handleRulesDidChange(Notification(name: .rulesDidChange, object: rules))
    }

    private func networkRule(
        name: String,
        host: String,
        preset: NetworkConditionPreset,
        isEnabled: Bool = true
    ) -> ProxyRule {
        ProxyRule(
            name: name,
            isEnabled: isEnabled,
            matchCondition: RuleMatchCondition(urlPattern: ".*\(NSRegularExpression.escapedPattern(for: host)).*"),
            action: .networkCondition(preset: preset, delayMs: preset.defaultLatencyMs)
        )
    }
}
