import Foundation
@testable import Rockxy
import Testing

// MARK: - GraphQLOperationRuleMatchingTests

struct GraphQLOperationRuleMatchingTests {
    // MARK: Internal

    @Test("A rule with an operation name matches only that operation on a shared endpoint")
    func operationScopedRuleMatching() async {
        let engine = RuleEngine()
        let rule = ProxyRule(
            name: "Pause GetUser",
            matchCondition: RuleMatchCondition(
                urlPattern: ".*api\\.example\\.com/graphql.*",
                graphQLOperationName: "GetUser"
            ),
            action: .breakpoint(phase: .both)
        )
        await engine.addRule(rule)

        let getUser = await engine.evaluateBreakpointRule(
            method: "POST", url: Self.endpoint, headers: [], graphQLOperationName: "GetUser"
        )
        let listPosts = await engine.evaluateBreakpointRule(
            method: "POST", url: Self.endpoint, headers: [], graphQLOperationName: "ListPosts"
        )
        let anonymous = await engine.evaluateBreakpointRule(method: "POST", url: Self.endpoint, headers: [])
        let differentCase = await engine.evaluateRule(
            method: "POST", url: Self.endpoint, headers: [], graphQLOperationName: "getuser"
        )

        #expect(getUser?.id == rule.id)
        #expect(listPosts == nil)
        #expect(anonymous == nil)
        #expect(differentCase == nil)
    }

    @Test("Rules without an operation name keep matching every request to the URL")
    func unscopedRulesAreUnchanged() {
        let condition = RuleMatchCondition(urlPattern: ".*graphql.*", graphQLOperationName: "  ")

        #expect(condition.requiredGraphQLOperationName == nil)
        #expect(condition.matches(method: "POST", url: Self.endpoint, headers: [], graphQLOperationName: "Any"))
        #expect(condition.matches(method: "POST", url: Self.endpoint, headers: []))
    }

    @Test("Older persisted rules without the field still decode")
    func legacyDecoding() throws {
        let json = Data(#"{"urlPattern":".*","method":"POST"}"#.utf8)
        let condition = try JSONDecoder().decode(RuleMatchCondition.self, from: json)

        #expect(condition.graphQLOperationName == nil)
    }

    @Test("Breakpoint editor round-trips the operation name and prefills it from a GraphQL request")
    func breakpointFormRoundTrip() throws {
        let transaction = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/graphql")
        transaction.graphQLInfo = GraphQLInfo(
            operationName: "GetUser",
            operationType: .query,
            query: "query GetUser { me { id } }",
            variables: nil
        )
        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)
        #expect(context.graphQLOperationName == "GetUser")

        let rule = BreakpointRuleForm.makeRule(
            original: nil,
            ruleName: "GetUser",
            rawPattern: context.defaultPattern,
            httpMethod: context.httpMethod,
            matchType: context.defaultMatchType,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false,
            graphQLOperationName: " GetUser "
        )
        #expect(rule.matchCondition.graphQLOperationName == "GetUser")
        #expect(BreakpointRuleForm.decode(rule: rule).graphQLOperationName == "GetUser")

        let cleared = BreakpointRuleForm.makeRule(
            original: rule,
            ruleName: "GetUser",
            rawPattern: context.defaultPattern,
            httpMethod: context.httpMethod,
            matchType: context.defaultMatchType,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false,
            graphQLOperationName: ""
        )
        #expect(cleared.matchCondition.graphQLOperationName == nil)
        #expect(cleared.id == rule.id)
    }

    @Test("Operation names are read from the document when operationName is omitted")
    func detectorFallsBackToDocumentName() {
        #expect(GraphQLDetector.operationName(inQuery: "query GetUser($id: ID!) { user(id: $id) { id } }") == "GetUser")
        #expect(GraphQLDetector.operationName(inQuery: "  mutation\n  UpdateName { ok }") == "UpdateName")
        #expect(GraphQLDetector.operationName(inQuery: "# comment\nsubscription OnPost { id }") == "OnPost")
        #expect(GraphQLDetector.operationName(inQuery: "{ me { id } }") == nil)
        #expect(GraphQLDetector.operationName(inQuery: "query { me { id } }") == nil)

        let request = HTTPRequestData(
            method: "POST",
            url: Self.endpoint,
            httpVersion: "HTTP/1.1",
            headers: [],
            body: Data(#"{"query":"query ListPosts { posts { id } }"}"#.utf8)
        )
        #expect(GraphQLDetector.detect(request: request)?.operationName == "ListPosts")
    }

    // MARK: Private

    private static let endpoint = URL(string: "https://api.example.com/graphql")!
}

// MARK: - GraphQLDetectorCoverageTests

struct GraphQLDetectorCoverageTests {
    @Test("GET requests carry the document and operation name in the URL")
    func detectsGET() throws {
        var components = try #require(URLComponents(string: "https://api.example.com/graphql"))
        components.queryItems = [
            URLQueryItem(name: "query", value: "query Me { me { id } }"),
            URLQueryItem(name: "variables", value: #"{"a":1}"#),
        ]
        let request = HTTPRequestData(method: "GET", url: try #require(components.url), httpVersion: "HTTP/1.1", headers: [])

        let info = try #require(GraphQLDetector.detect(request: request))
        #expect(info.operationName == "Me")
        #expect(info.variables == #"{"a":1}"#)
    }

    @Test("Automatic persisted queries are detected by hash and operation name")
    func detectsPersistedQuery() throws {
        let body = Data(#"{"operationName":"Feed","extensions":{"persistedQuery":{"version":1,"sha256Hash":"abc"}}}"#.utf8)
        let request = HTTPRequestData(
            method: "POST",
            url: try #require(URL(string: "https://api.example.com/GraphQL")),
            httpVersion: "HTTP/1.1",
            headers: [],
            body: body
        )

        let info = try #require(GraphQLDetector.detect(request: request))
        #expect(info.operationName == "Feed")
        #expect(info.query.isEmpty)
    }

    @Test("Batched requests are not treated as a single operation")
    func ignoresBatches() throws {
        let body = Data(#"[{"query":"query A { a }"},{"query":"query B { b }"}]"#.utf8)
        let request = HTTPRequestData(
            method: "POST",
            url: try #require(URL(string: "https://api.example.com/graphql")),
            httpVersion: "HTTP/1.1",
            headers: [],
            body: body
        )

        #expect(GraphQLDetector.detect(request: request) == nil)
    }
}
