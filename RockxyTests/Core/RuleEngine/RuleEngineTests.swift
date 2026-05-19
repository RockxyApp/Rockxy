import Foundation
@testable import Rockxy
import Testing

// Tests for `RuleEngine`: URL regex matching, HTTP method filtering, header matching,
// first-match-wins ordering, enable/disable toggling, and add/remove operations.

// MARK: - RuleEngineTests

struct RuleEngineTests {
    @Test("URL pattern matching with regex")
    func urlPatternMatching() async throws {
        let engine = RuleEngine()
        let rule = ProxyRule(
            name: "Block API",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com/api.*"),
            action: .block(statusCode: 403)
        )
        await engine.addRule(rule)

        let matchURL = try #require(URL(string: "https://example.com/api/users"))
        let noMatchURL = try #require(URL(string: "https://other.com/data"))

        let matchResult = await engine.evaluate(
            method: "GET", url: matchURL, headers: []
        )
        let noMatchResult = await engine.evaluate(
            method: "GET", url: noMatchURL, headers: []
        )

        #expect(matchResult != nil)
        #expect(noMatchResult == nil)
    }

    @Test("Method filter matching")
    func methodMatching() async throws {
        let engine = RuleEngine()
        let rule = ProxyRule(
            name: "Block POST",
            isEnabled: true,
            matchCondition: RuleMatchCondition(method: "POST"),
            action: .block(statusCode: 403)
        )
        await engine.addRule(rule)

        let url = try #require(URL(string: "https://example.com/data"))

        let postResult = await engine.evaluate(method: "POST", url: url, headers: [])
        let getResult = await engine.evaluate(method: "GET", url: url, headers: [])

        #expect(postResult != nil)
        #expect(getResult == nil)
    }

    @Test("Header matching")
    func headerMatching() async throws {
        let engine = RuleEngine()
        let rule = ProxyRule(
            name: "Match Auth Header",
            isEnabled: true,
            matchCondition: RuleMatchCondition(
                headerName: "Authorization",
                headerValue: "Bearer test-token"
            ),
            action: .block(statusCode: 401)
        )
        await engine.addRule(rule)

        let url = try #require(URL(string: "https://example.com/data"))
        let matchHeaders = [HTTPHeader(name: "Authorization", value: "Bearer test-token")]
        let noMatchHeaders = [HTTPHeader(name: "Authorization", value: "Bearer other")]

        let matchResult = await engine.evaluate(
            method: "GET", url: url, headers: matchHeaders
        )
        let noMatchResult = await engine.evaluate(
            method: "GET", url: url, headers: noMatchHeaders
        )

        #expect(matchResult != nil)
        #expect(noMatchResult == nil)
    }

    @Test("First enabled match wins by order")
    func firstMatchWins() async throws {
        let engine = RuleEngine()
        let rule1 = ProxyRule(
            name: "First Rule",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .block(statusCode: 403)
        )
        let rule2 = ProxyRule(
            name: "Second Rule",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .block(statusCode: 503)
        )
        await engine.addRule(rule1)
        await engine.addRule(rule2)

        let url = try #require(URL(string: "https://example.com/test"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        if case let .block(statusCode) = result {
            #expect(statusCode == 403)
        } else {
            #expect(Bool(false), "Expected block action")
        }
    }

    @Test("Disabled rules are skipped during evaluation")
    func toggleRuleDisabled() async throws {
        let engine = RuleEngine()
        let rule = ProxyRule(
            name: "Toggleable Rule",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .block(statusCode: 403)
        )
        await engine.addRule(rule)

        let url = try #require(URL(string: "https://example.com/test"))
        let beforeToggle = await engine.evaluate(method: "GET", url: url, headers: [])
        #expect(beforeToggle != nil)

        await engine.toggleRule(id: rule.id)
        let afterToggle = await engine.evaluate(method: "GET", url: url, headers: [])
        #expect(afterToggle == nil)
    }

    @Test("Block List tool gate skips block rules only")
    func blockListToolGateSkipsOnlyBlockRules() async throws {
        let engine = RuleEngine()
        let blockRule = ProxyRule(
            name: "Blocked",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .block(statusCode: 403)
        )
        let throttleRule = ProxyRule(
            name: "Throttle",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .throttle(delayMs: 250)
        )
        await engine.addRule(blockRule)
        await engine.addRule(throttleRule)

        let url = try #require(URL(string: "https://example.com/test"))
        let enabledResult = await engine.evaluate(method: "GET", url: url, headers: [])
        guard case .block = enabledResult else {
            Issue.record("Expected block rule while Block List tool is enabled")
            return
        }

        await engine.setBlockListToolEnabled(false)
        let disabledResult = await engine.evaluate(method: "GET", url: url, headers: [])
        if case let .throttle(delayMs) = disabledResult {
            #expect(delayMs == 250)
        } else {
            Issue.record("Expected non-block rule to remain active")
        }
    }

    @Test("Map Remote tool gate skips map remote rules only")
    func mapRemoteToolGateSkipsOnlyMapRemoteRules() async throws {
        let engine = RuleEngine()
        let remoteRule = ProxyRule(
            name: "Remote",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
        )
        let throttleRule = ProxyRule(
            name: "Throttle",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .throttle(delayMs: 250)
        )
        await engine.addRule(remoteRule)
        await engine.addRule(throttleRule)

        let url = try #require(URL(string: "https://example.com/test"))
        let enabledResult = await engine.evaluate(method: "GET", url: url, headers: [])
        guard case .mapRemote = enabledResult else {
            Issue.record("Expected map remote rule while Map Remote tool is enabled")
            return
        }

        await engine.setMapRemoteToolEnabled(false)
        let disabledResult = await engine.evaluate(method: "GET", url: url, headers: [])
        if case let .throttle(delayMs) = disabledResult {
            #expect(delayMs == 250)
        } else {
            Issue.record("Expected non-map-remote rule to remain active")
        }
    }

    @Test("Network Conditions tool gate skips network condition rules only")
    func networkConditionsToolGateSkipsOnlyNetworkConditionRules() async throws {
        let engine = RuleEngine()
        let networkRule = ProxyRule(
            name: "3G API",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .networkCondition(preset: .threeG, delayMs: 400)
        )
        let throttleRule = ProxyRule(
            name: "Throttle",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .throttle(delayMs: 250)
        )
        await engine.addRule(networkRule)
        await engine.addRule(throttleRule)

        let url = try #require(URL(string: "https://example.com/test"))
        let enabledResult = await engine.evaluate(method: "GET", url: url, headers: [])
        guard case let .networkCondition(preset, delayMs) = enabledResult else {
            Issue.record("Expected network condition rule while Network Conditions tool is enabled")
            return
        }
        #expect(preset == .threeG)
        #expect(delayMs == 400)

        await engine.setNetworkConditionsToolEnabled(false)
        let disabledResult = await engine.evaluate(method: "GET", url: url, headers: [])
        if case let .throttle(delayMs) = disabledResult {
            #expect(delayMs == 250)
        } else {
            Issue.record("Expected non-network-condition rule to remain active")
        }
    }

    @Test("Add rule and evaluate successfully")
    func addRuleAndEvaluate() async throws {
        let engine = RuleEngine()
        let initialRules = await engine.allRules
        #expect(initialRules.isEmpty)

        let rule = ProxyRule(
            name: "New Rule",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*test.*"),
            action: .throttle(delayMs: 500)
        )
        await engine.addRule(rule)

        let rulesAfterAdd = await engine.allRules
        #expect(rulesAfterAdd.count == 1)

        let url = try #require(URL(string: "https://example.com/test"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])
        #expect(result != nil)
    }

    @Test("Remove rule by id")
    func removeRule() async {
        let engine = RuleEngine()
        let rule = ProxyRule(
            name: "To Remove",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .block(statusCode: 403)
        )
        await engine.addRule(rule)
        let rulesAfterAdd = await engine.allRules
        #expect(rulesAfterAdd.count == 1)

        await engine.removeRule(id: rule.id)
        let rulesAfterRemove = await engine.allRules
        #expect(rulesAfterRemove.isEmpty)
    }
}
