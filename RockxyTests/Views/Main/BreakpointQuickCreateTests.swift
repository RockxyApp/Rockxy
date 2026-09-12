import Foundation
@testable import Rockxy
import Testing

struct BreakpointQuickCreateTests {
    @Test("Transaction context builder includes method and host-safe exact-path default")
    @MainActor
    func transactionBuilder() {
        let transaction = TestFixtures.makeTransaction(
            method: "PATCH",
            url: "https://api.example.com/v1/profile?include=team",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.suggestedName == "Breakpoint — PATCH api.example.com/v1/profile")
        #expect(context.sourceMethod == "PATCH")
        #expect(context.sourceHost == "api.example.com")
        #expect(context.sourcePath == "/v1/profile")
        #expect(context.defaultPattern == "*://api.example.com/v1/profile")
        #expect(context.defaultMatchType == .wildcard)
        #expect(context.includeSubpaths == false)
        #expect(context.breakpointRequest == true)
        #expect(context.breakpointResponse == true)
    }

    @Test("Transaction context builder normalizes empty path to slash")
    @MainActor
    func transactionBuilderNormalizesEmptyPath() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.suggestedName == "Breakpoint — GET api.example.com/")
        #expect(context.defaultPattern == "*://api.example.com/")
        #expect(context.includeSubpaths == false)
    }

    @Test("Transaction quick-create preserves a non-default local development port from the Host header")
    @MainActor
    func transactionBuilderPreservesPort() throws {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "http://localhost/api/users",
            statusCode: 201
        )
        transaction.request.headers.append(HTTPHeader(name: "Host", value: "localhost:8080"))

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)
        let rule = BreakpointRuleForm.makeRule(
            original: nil,
            ruleName: "Local API",
            rawPattern: context.defaultPattern,
            httpMethod: context.httpMethod,
            matchType: context.defaultMatchType,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: context.includeSubpaths
        )

        #expect(context.defaultPattern == "*://localhost:8080/api/users")
        #expect(try rule.matchCondition.matches(
            method: "POST",
            url: #require(URL(string: "http://localhost:8080/api/users")),
            headers: []
        ))
        #expect(try !rule.matchCondition.matches(
            method: "POST",
            url: #require(URL(string: "http://localhost:9090/api/users")),
            headers: []
        ))
    }

    @Test("Transaction quick-create ignores a Host header for a different authority")
    @MainActor
    func transactionBuilderRejectsMismatchedHostHeaderPort() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "http://localhost/api/users",
            statusCode: 200
        )
        transaction.request.headers.append(HTTPHeader(name: "Host", value: "attacker.example:8080"))

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.defaultPattern == "*://localhost/api/users")
    }

    @Test("Domain context builder omits method and scopes to the whole domain")
    func domainBuilder() {
        let context = BreakpointEditorContextBuilder.fromDomain("cdn.example.com")

        #expect(context.suggestedName == "Breakpoint — cdn.example.com")
        #expect(context.httpMethod == .any)
        #expect(context.sourceMethod == nil)
        #expect(context.defaultPattern == "*://cdn.example.com/*")
        #expect(context.includeSubpaths == false)
        #expect(context.breakpointRequest == true)
        #expect(context.breakpointResponse == true)
    }

    @Test("Domain context builder brackets bare IPv6 hosts without double-bracketing")
    func domainBuilderBracketsIPv6() {
        #expect(BreakpointEditorContextBuilder.fromDomain("::1").defaultPattern == "*://[::1]/*")
        #expect(
            BreakpointEditorContextBuilder.fromDomain("[2001:db8::1]").defaultPattern == "*://[2001:db8::1]/*"
        )
        // DNS hosts, including explicit ports, are left untouched.
        #expect(BreakpointEditorContextBuilder.fromDomain("cdn.example.com").defaultPattern == "*://cdn.example.com/*")
        #expect(
            BreakpointEditorContextBuilder.fromDomain("cdn.example.com:8443").defaultPattern
                == "*://cdn.example.com:8443/*"
        )
    }

    @Test("Transaction quick-create rule matches only the exact host and path")
    @MainActor
    func transactionQuickCreateRuleHostAndPathBoundaries() throws {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/v1/profile",
            statusCode: 200
        )
        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)
        let rule = BreakpointRuleForm.makeRule(
            original: nil,
            ruleName: "BP",
            rawPattern: context.defaultPattern,
            httpMethod: .any,
            matchType: context.defaultMatchType,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: context.includeSubpaths
        )

        func matches(_ urlString: String) throws -> Bool {
            let url = try #require(URL(string: urlString))
            return rule.matchCondition.matches(method: "GET", url: url, headers: [])
        }

        // Exact URL and an appended query/fragment still match.
        #expect(try matches("https://api.example.com/v1/profile"))
        #expect(try matches("https://api.example.com/v1/profile?team=1"))
        #expect(try matches("https://api.example.com/v1/profile#top"))

        // Path-boundary negative: a deeper path must not match (includeSubpaths == false).
        #expect(try !matches("https://api.example.com/v1/profile/extra"))
        // Sibling-host negative: a suffixed attacker host must not match.
        #expect(try !matches("https://api.example.com.attacker.com/v1/profile"))
        // Different-host negative.
        #expect(try !matches("https://cdn.example.com/v1/profile"))
    }

    @Test("Domain quick-create rule matches the whole domain but not siblings")
    @MainActor
    func domainQuickCreateRuleMatchesWholeDomain() throws {
        let context = BreakpointEditorContextBuilder.fromDomain("cdn.example.com")
        let rule = BreakpointRuleForm.makeRule(
            original: nil,
            ruleName: "BP",
            rawPattern: context.defaultPattern,
            httpMethod: .any,
            matchType: context.defaultMatchType,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: context.includeSubpaths
        )

        func matches(_ urlString: String) throws -> Bool {
            let url = try #require(URL(string: urlString))
            return rule.matchCondition.matches(method: "GET", url: url, headers: [])
        }

        #expect(try matches("https://cdn.example.com/"))
        #expect(try matches("https://cdn.example.com/assets/logo.png"))
        // Sibling-host negative.
        #expect(try !matches("https://cdn.example.com.attacker.com/asset"))
    }

    @Test("Context from transaction populates shared store for handoff")
    @MainActor
    func contextPopulatesStore() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.example.com/v1/users",
            statusCode: 201
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)
        let store = BreakpointEditorContextStore.shared
        store.setPending(context)

        let consumed = store.consumePending()
        #expect(consumed?.sourceHost == "api.example.com")
        #expect(consumed?.sourceMethod == "POST")
        #expect(consumed?.origin == .selectedTransaction)
    }

    @Test("Context from domain populates shared store for handoff")
    @MainActor
    func domainContextPopulatesStore() {
        let context = BreakpointEditorContextBuilder.fromDomain("cdn.example.com")
        let store = BreakpointEditorContextStore.shared
        store.setPending(context)

        let consumed = store.consumePending()
        #expect(consumed?.sourceHost == "cdn.example.com")
        #expect(consumed?.origin == .domainQuickCreate)
    }

    @Test("Shared store consumes context only once")
    @MainActor
    func storeConsumesOnce() {
        let context = BreakpointEditorContextBuilder.fromDomain("cdn.example.com")
        let store = BreakpointEditorContextStore.shared
        store.setPending(context)

        let first = store.consumePending()
        let second = store.consumePending()

        #expect(first != nil)
        #expect(second == nil)
    }
}
