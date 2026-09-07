import Foundation
@testable import Rockxy
import Testing

// Tests for `RuleEngine`: URL regex matching, HTTP method filtering, header matching,
// first-match-wins ordering, enable/disable toggling, and add/remove operations.

// MARK: - RuleEngineTests

struct RuleEngineTests {
    // MARK: Internal

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

    @Test("Breakpoint tool gate skips breakpoint rules only")
    func breakpointToolGateSkipsOnlyBreakpointRules() async throws {
        let engine = RuleEngine()
        let breakpointRule = ProxyRule(
            name: "Pause",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .breakpoint(phase: .both)
        )
        let throttleRule = ProxyRule(
            name: "Throttle",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .throttle(delayMs: 250)
        )
        await engine.addRule(breakpointRule)
        await engine.addRule(throttleRule)

        let url = try #require(URL(string: "https://example.com/test"))
        let enabledBreakpoint = await engine.evaluateBreakpointRule(method: "GET", url: url, headers: [])
        #expect(enabledBreakpoint?.id == breakpointRule.id)

        await engine.setBreakpointToolEnabled(false)
        let disabledBreakpoint = await engine.evaluateBreakpointRule(method: "GET", url: url, headers: [])
        #expect(disabledBreakpoint == nil)

        let disabledResult = await engine.evaluate(method: "GET", url: url, headers: [])
        if case let .throttle(delayMs) = disabledResult {
            #expect(delayMs == 250)
        } else {
            Issue.record("Expected non-breakpoint rule to remain active")
        }
    }

    @Test("Breakpoint host port path wildcard exact match handles query boundary")
    func breakpointHostPortPathWildcardExactMatch() async throws {
        let engine = RuleEngine()
        let pattern = RulePatternBuilder.regexSource(
            rawPattern: "127.0.0.1:43210/rockxy-demo/profile",
            matchType: .wildcard,
            includeSubpaths: false
        )
        let rule = ProxyRule(
            name: "Profile Breakpoint",
            matchCondition: RuleMatchCondition(urlPattern: pattern),
            action: .breakpoint(phase: .both)
        )
        await engine.addRule(rule)

        let exact = try #require(URL(string: "http://127.0.0.1:43210/rockxy-demo/profile"))
        let query = try #require(URL(string: "http://127.0.0.1:43210/rockxy-demo/profile?expected=staging"))
        let child = try #require(URL(string: "http://127.0.0.1:43210/rockxy-demo/profile/child"))
        let sibling = try #require(URL(string: "http://127.0.0.1:43210/rockxy-demo/profile-prod"))

        #expect(await engine.evaluateBreakpointRule(method: "GET", url: exact, headers: [])?.id == rule.id)
        #expect(await engine.evaluateBreakpointRule(method: "GET", url: query, headers: [])?.id == rule.id)
        #expect(await engine.evaluateBreakpointRule(method: "GET", url: child, headers: []) == nil)
        #expect(await engine.evaluateBreakpointRule(method: "GET", url: sibling, headers: []) == nil)
    }

    @Test("Breakpoint-specific evaluation finds breakpoint shadowed by earlier rule")
    func breakpointSpecificEvaluationFindsShadowedBreakpoint() async throws {
        let engine = RuleEngine()
        let mapRule = ProxyRule(
            name: "Map",
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com/profile.*"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
        )
        let breakpointRule = ProxyRule(
            name: "Pause",
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com/profile.*"),
            action: .breakpoint(phase: .both)
        )
        await engine.addRule(mapRule)
        await engine.addRule(breakpointRule)

        let url = try #require(URL(string: "https://example.com/profile"))
        let generalMatch = await engine.evaluateRule(method: "GET", url: url, headers: [])
        let breakpointMatch = await engine.evaluateBreakpointRule(method: "GET", url: url, headers: [])

        #expect(generalMatch?.id == mapRule.id)
        #expect(breakpointMatch?.id == breakpointRule.id)
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

    @Test("Modify Header tool gate skips modify header rules only")
    func modifyHeaderToolGateSkipsOnlyModifyHeaderRules() async throws {
        let engine = RuleEngine()
        let modifyRule = ProxyRule(
            name: "Inject Debug Header",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .modifyHeader(operations: [
                HeaderOperation(type: .add, headerName: "X-Debug", headerValue: "1"),
            ])
        )
        let throttleRule = ProxyRule(
            name: "Throttle",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .throttle(delayMs: 250)
        )
        await engine.addRule(modifyRule)
        await engine.addRule(throttleRule)

        let url = try #require(URL(string: "https://example.com/test"))
        let enabledResult = await engine.evaluate(method: "GET", url: url, headers: [])
        guard case .modifyHeader = enabledResult else {
            Issue.record("Expected modify header rule while Modify Headers tool is enabled")
            return
        }

        await engine.setModifyHeaderToolEnabled(false)
        let disabledResult = await engine.evaluate(method: "GET", url: url, headers: [])
        if case let .throttle(delayMs) = disabledResult {
            #expect(delayMs == 250)
        } else {
            Issue.record("Expected non-modify-header rule to remain active")
        }
    }

    @Test("Modify Header reorder preserves unrelated global slots")
    func modifyHeaderReorderPreservesUnrelatedSlots() async {
        let engine = RuleEngine()
        let block = ProxyRule(
            name: "Block",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .block(statusCode: 403)
        )
        let headerA = Self.modifyHeaderRule(named: "A")
        let throttle = ProxyRule(
            name: "Throttle",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .throttle(delayMs: 100)
        )
        let headerB = Self.modifyHeaderRule(named: "B")
        let headerC = Self.modifyHeaderRule(named: "C")
        await engine.replaceAll([block, headerA, throttle, headerB, headerC])

        await engine.reorderModifyHeaderRules(orderedIDs: [headerC.id, headerA.id, headerB.id])

        let reordered = await engine.allRules
        #expect(reordered.map(\.id) == [block.id, headerC.id, throttle.id, headerA.id, headerB.id])
    }

    @Test("Map Local reorder preserves unrelated global slots")
    func mapLocalReorderPreservesUnrelatedSlots() async {
        let engine = RuleEngine()
        let block = ProxyRule(
            name: "Block",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .block(statusCode: 403)
        )
        let mapA = Self.mapLocalRule(named: "A")
        let throttle = ProxyRule(
            name: "Throttle",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .throttle(delayMs: 100)
        )
        let mapB = Self.mapLocalRule(named: "B")
        let mapC = Self.mapLocalRule(named: "C")
        await engine.replaceAll([block, mapA, throttle, mapB, mapC])

        await engine.reorderMapLocalRules(orderedIDs: [mapC.id, mapA.id, mapB.id])

        let reordered = await engine.allRules
        #expect(reordered.map(\.id) == [block.id, mapC.id, throttle.id, mapA.id, mapB.id])
    }

    @Test("First enabled Map Local rule wins on overlapping matches")
    func mapLocalFirstMatchWins() async throws {
        let engine = RuleEngine()
        let first = ProxyRule(
            name: "First",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .mapLocal(filePath: "/tmp/first.json")
        )
        let second = ProxyRule(
            name: "Second",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .mapLocal(filePath: "/tmp/second.json")
        )
        await engine.replaceAll([first, second])

        let url = try #require(URL(string: "https://example.com/x"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])
        if case let .mapLocal(path, _, _, _, _) = result {
            #expect(path == "/tmp/first.json")
        } else {
            Issue.record("Expected .mapLocal")
        }
    }

    @Test("Map Local runtime matching uses authored metadata, not a stale compiled pattern")
    func mapLocalMetadataRuntimeMatching() async throws {
        let engine = RuleEngine()
        // The compiled `urlPattern` is deliberately wrong; the authored wildcard should win.
        let condition = RuleMatchCondition(
            urlPattern: ".*never-matches\\.invalid.*",
            sourceURLPattern: "https://api.example.com/*",
            matchType: .wildcard,
            includeSubpaths: true
        )
        let rule = ProxyRule(
            name: "MapLocal",
            isEnabled: true,
            matchCondition: condition,
            action: .mapLocal(filePath: "/tmp/mock.json")
        )
        await engine.addRule(rule)

        let url = try #require(URL(string: "https://api.example.com/users"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])
        guard case .mapLocal = result else {
            Issue.record("Expected the authored wildcard to match at runtime")
            return
        }
    }

    @Test("Wildcard ? matches exactly one character")
    func wildcardSingleCharacterBoundary() async throws {
        let engine = RuleEngine()
        let rule = ProxyRule(
            name: "MapLocal",
            isEnabled: true,
            matchCondition: RuleMatchCondition(
                urlPattern: "https://api.example.com/v?/users",
                sourceURLPattern: "https://api.example.com/v?/users",
                matchType: .wildcard,
                includeSubpaths: false
            ),
            action: .mapLocal(filePath: "/tmp/v.json")
        )
        await engine.addRule(rule)

        let oneChar = try #require(URL(string: "https://api.example.com/v1/users"))
        let zeroChar = try #require(URL(string: "https://api.example.com/v/users"))
        let twoChar = try #require(URL(string: "https://api.example.com/v12/users"))

        #expect(await engine.evaluate(method: "GET", url: oneChar, headers: []) != nil)
        #expect(await engine.evaluate(method: "GET", url: zeroChar, headers: []) == nil)
        #expect(await engine.evaluate(method: "GET", url: twoChar, headers: []) == nil)
    }

    @Test("includeSubpaths controls whether a Map Local wildcard matches child paths")
    func includeSubpathsBoundary() async throws {
        func engine(includeSubpaths: Bool) async -> RuleEngine {
            let engine = RuleEngine()
            await engine.addRule(ProxyRule(
                name: "MapLocal",
                isEnabled: true,
                matchCondition: RuleMatchCondition(
                    urlPattern: "https://api.example.com/data",
                    sourceURLPattern: "https://api.example.com/data",
                    matchType: .wildcard,
                    includeSubpaths: includeSubpaths
                ),
                action: .mapLocal(filePath: "/tmp/data.json")
            ))
            return engine
        }

        let exact = try #require(URL(string: "https://api.example.com/data"))
        let query = try #require(URL(string: "https://api.example.com/data?page=2"))
        let child = try #require(URL(string: "https://api.example.com/data/child"))

        let strict = await engine(includeSubpaths: false)
        #expect(await strict.evaluate(method: "GET", url: exact, headers: []) != nil)
        #expect(await strict.evaluate(method: "GET", url: query, headers: []) != nil)
        #expect(await strict.evaluate(method: "GET", url: child, headers: []) == nil)

        let subpaths = await engine(includeSubpaths: true)
        #expect(await subpaths.evaluate(method: "GET", url: child, headers: []) != nil)
    }

    @Test("Trailing ? wildcard anchors to end of URL and never allows a trailing query")
    func trailingQuestionMarkWildcardAnchorsToEnd() async throws {
        // `/api/item?` matches `item` plus exactly one character, then the URL must end.
        // A trailing `?query` must not match and should reach the origin.
        let engine = RuleEngine()
        await engine.addRule(ProxyRule(
            name: "MapLocal",
            isEnabled: true,
            matchCondition: RuleMatchCondition(
                urlPattern: "https://api.example.com/api/item?",
                sourceURLPattern: "https://api.example.com/api/item?",
                matchType: .wildcard,
                includeSubpaths: false
            ),
            action: .mapLocal(filePath: "/tmp/item.json")
        ))

        let oneChar = try #require(URL(string: "https://api.example.com/api/items"))
        let twoChar = try #require(URL(string: "https://api.example.com/api/itemss"))
        let query = try #require(URL(string: "https://api.example.com/api/items?x=1"))

        #expect(await engine.evaluate(method: "GET", url: oneChar, headers: []) != nil)
        #expect(await engine.evaluate(method: "GET", url: twoChar, headers: []) == nil)
        // The wildcard already consumed the boundary character, so the query must not match.
        #expect(await engine.evaluate(method: "GET", url: query, headers: []) == nil)
    }

    @Test("includeSubpaths on a bare path matches base, children, and query but not a sibling prefix")
    func includeSubpathsRejectsSiblingPrefix() async throws {
        let engine = RuleEngine()
        await engine.addRule(ProxyRule(
            name: "MapLocal",
            isEnabled: true,
            matchCondition: RuleMatchCondition(
                urlPattern: "https://api.example.com/data",
                sourceURLPattern: "https://api.example.com/data",
                matchType: .wildcard,
                includeSubpaths: true
            ),
            action: .mapLocal(filePath: "/tmp/data.json")
        ))

        let base = try #require(URL(string: "https://api.example.com/data"))
        let child = try #require(URL(string: "https://api.example.com/data/child"))
        let query = try #require(URL(string: "https://api.example.com/data?page=2"))
        let sibling = try #require(URL(string: "https://api.example.com/datax"))

        #expect(await engine.evaluate(method: "GET", url: base, headers: []) != nil)
        #expect(await engine.evaluate(method: "GET", url: child, headers: []) != nil)
        #expect(await engine.evaluate(method: "GET", url: query, headers: []) != nil)
        // A sibling that only shares the prefix must not be captured by includeSubpaths.
        #expect(await engine.evaluate(method: "GET", url: sibling, headers: []) == nil)
    }

    @Test("A rule whose regex cannot compile is disabled on load and never matches")
    func invalidRegexRuleDisabledOnLoad() async throws {
        let engine = RuleEngine()
        let invalid = ProxyRule(
            name: "Broken Regex",
            isEnabled: true,
            matchCondition: RuleMatchCondition(
                urlPattern: "https://api.example.com/[",
                sourceURLPattern: "https://api.example.com/[",
                matchType: .regex
            ),
            action: .mapLocal(filePath: "/tmp/broken.json")
        )
        // replaceAll runs compilePatterns(), which disables rules with an invalid regex.
        await engine.replaceAll([invalid])

        let disabled = await engine.allRules.first
        #expect(disabled?.isEnabled == false)

        let url = try #require(URL(string: "https://api.example.com/anything"))
        #expect(await engine.evaluate(method: "GET", url: url, headers: []) == nil)
    }

    @Test("Invalid imported Block regex does not consume the active quota")
    func invalidImportedBlockRegexDoesNotConsumeQuota() async {
        let engine = RuleEngine()
        let invalid = ProxyRule(
            name: "Broken Block Regex",
            matchCondition: RuleMatchCondition(
                urlPattern: "https://api.example.com/[]",
                sourceURLPattern: "https://api.example.com/[]",
                matchType: .regex
            ),
            action: .block(statusCode: 403)
        )
        let valid = ProxyRule(
            name: "Valid Block Regex",
            matchCondition: RuleMatchCondition(
                urlPattern: ".*valid\\.example\\.com.*",
                sourceURLPattern: ".*valid\\.example\\.com.*",
                matchType: .regex
            ),
            action: .block(statusCode: 403)
        )

        await engine.replaceBlockRules([invalid, valid], maxPerCategory: 1)

        let rules = await engine.allRules
        #expect(rules.count == 2)
        #expect(rules[0].isEnabled == false)
        #expect(rules[1].isEnabled == true)
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

    // MARK: Private

    private static func modifyHeaderRule(named name: String) -> ProxyRule {
        ProxyRule(
            name: name,
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .modifyHeader(operations: [
                HeaderOperation(type: .add, headerName: "X-\(name)", headerValue: "1"),
            ])
        )
    }

    private static func mapLocalRule(named name: String) -> ProxyRule {
        ProxyRule(
            name: name,
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*example\\.com.*"),
            action: .mapLocal(filePath: "/tmp/\(name).json")
        )
    }
}
