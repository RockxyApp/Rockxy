import Foundation
@testable import Rockxy
import Testing

/// `AllowListEditorContextBuilder` pre-fill correctness for quick-create flows.
@MainActor
struct AllowListEditorContextBuilderTests {
    // MARK: - fromTransaction

    @Test
    func fromTransactionPopulatesFromGetRequest() {
        let tx = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.github.com/repos/owner/repo/issues"
        )

        let context = AllowListEditorContextBuilder.fromTransaction(tx)

        #expect(context.origin == .selectedTransaction)
        #expect(context.sourceHost == "api.github.com")
        #expect(context.sourcePath == "/repos/owner/repo/issues")
        #expect(context.sourceMethod == "GET")
        #expect(context.suggestedName == "Allow — GET api.github.com/repos/owner/repo/issues")
        #expect(context.defaultPattern == "*api.github.com/repos/owner/repo/issues*")
        #expect(context.defaultMatchType == .wildcard)
        #expect(context.httpMethod == .get)
        #expect(context.includeSubpaths)
    }

    @Test
    func fromTransactionHandlesAllStandardMethods() {
        let methods: [(String, HTTPMethodFilter)] = [
            ("POST", .post),
            ("PUT", .put),
            ("DELETE", .delete),
            ("PATCH", .patch),
            ("HEAD", .head),
            ("OPTIONS", .options),
            ("TRACE", .trace),
        ]
        for (method, expected) in methods {
            let tx = TestFixtures.makeTransaction(method: method, url: "https://example.com/api")
            let context = AllowListEditorContextBuilder.fromTransaction(tx)
            #expect(context.httpMethod == expected, "method \(method) should map to \(expected)")
            #expect(context.sourceMethod == method)
        }
    }

    @Test
    func fromTransactionUnknownMethodFallsBackToAny() {
        let tx = TestFixtures.makeTransaction(method: "PROPFIND", url: "https://example.com/api")
        let context = AllowListEditorContextBuilder.fromTransaction(tx)
        #expect(context.httpMethod == .any)
        #expect(context.sourceMethod == "PROPFIND")
    }

    @Test
    func fromTransactionNormalizesEmptyPathToSlash() {
        let tx = TestFixtures.makeTransaction(method: "GET", url: "https://example.com")
        let context = AllowListEditorContextBuilder.fromTransaction(tx)
        #expect(context.sourcePath == "/")
        #expect(context.defaultPattern == "*example.com/*")
    }

    // MARK: - fromDomain

    @Test
    func fromDomainProducesWildcardPatternWithAny() {
        let context = AllowListEditorContextBuilder.fromDomain("api.stripe.com")

        #expect(context.origin == .domainQuickCreate)
        #expect(context.sourceHost == "api.stripe.com")
        #expect(context.sourcePath == nil)
        #expect(context.sourceMethod == nil)
        #expect(context.suggestedName == "Allow — api.stripe.com")
        #expect(context.defaultPattern == "*api.stripe.com/*")
        #expect(context.defaultMatchType == .wildcard)
        #expect(context.httpMethod == .any)
        #expect(context.includeSubpaths)
    }

    @Test
    func fromDomainHandlesSubdomainWildcard() {
        let context = AllowListEditorContextBuilder.fromDomain("*.example.com")
        #expect(context.sourceHost == "*.example.com")
        #expect(context.defaultPattern == "**.example.com/*")
    }
}
