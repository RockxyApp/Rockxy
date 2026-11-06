import Foundation
@testable import Rockxy
import Testing

// MARK: - RuleMatchConditionCaseFoldingTests

/// `matches(...)` runs per rule carrying the condition, per request, across every pass in
/// `ProxyHandlerShared.evaluateRules`. The header check used to ICU-lowercase the RULE's own
/// header name inside the loop over the request's headers, so it was recomputed once per
/// header; the method check converted both sides on every call. These assert the folding
/// behaviour is unchanged now that both go through `caseInsensitiveCompare`.
struct RuleMatchConditionCaseFoldingTests {
    @Test("Header names fold case on both sides while the value stays case-sensitive")
    func headerNameFoldsCaseAndValueDoesNot() throws {
        let condition = RuleMatchCondition(headerName: "X-Auth-Token", headerValue: "Secret")
        let url = try #require(URL(string: "https://example.test/resource"))

        for name in ["X-Auth-Token", "x-auth-token", "X-AUTH-TOKEN", "x-AuTh-ToKeN"] {
            #expect(condition.matches(
                method: "GET",
                url: url,
                headers: [HTTPHeader(name: name, value: "Secret")]
            ))
        }
        #expect(!condition.matches(
            method: "GET",
            url: url,
            headers: [HTTPHeader(name: "X-Auth-Token", value: "secret")]
        ))
        #expect(!condition.matches(
            method: "GET",
            url: url,
            headers: [HTTPHeader(name: "X-Other", value: "Secret")]
        ))
    }

    @Test("A header condition matches whichever of many headers carries the name")
    func headerConditionScansEveryHeader() throws {
        let condition = RuleMatchCondition(headerName: "x-trace", headerValue: "abc")
        let url = try #require(URL(string: "https://example.test/resource"))
        var headers = (0 ..< 32).map { HTTPHeader(name: "X-Filler-\($0)", value: "v") }
        headers.append(HTTPHeader(name: "X-Trace", value: "abc"))

        #expect(condition.matches(method: "GET", url: url, headers: headers))
        #expect(!condition.matches(method: "GET", url: url, headers: Array(headers.dropLast())))
    }

    @Test("Methods fold case on both sides")
    func methodFoldsCase() throws {
        let condition = RuleMatchCondition(method: "post")
        let url = try #require(URL(string: "https://example.test/resource"))

        #expect(condition.matches(method: "POST", url: url, headers: []))
        #expect(condition.matches(method: "post", url: url, headers: []))
        #expect(condition.matches(method: "Post", url: url, headers: []))
        #expect(!condition.matches(method: "GET", url: url, headers: []))
    }
}
