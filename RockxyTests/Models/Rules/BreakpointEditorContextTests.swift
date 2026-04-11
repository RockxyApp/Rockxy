import Foundation
@testable import Rockxy
import Testing

struct BreakpointEditorContextBuilderTests {
    // MARK: - fromTransaction

    @Test("Context from transaction has selectedTransaction origin")
    @MainActor
    func transactionOrigin() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.example.com/v1/users",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.origin == .selectedTransaction)
    }

    @Test("Context from transaction extracts host and path")
    @MainActor
    func transactionExtractsHostAndPath() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/v1/users?page=1",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.sourceHost == "api.example.com")
        #expect(context.sourcePath == "/v1/users")
    }

    @Test("Context from transaction extracts method")
    @MainActor
    func transactionExtractsMethod() {
        let transaction = TestFixtures.makeTransaction(
            method: "PATCH",
            url: "https://api.example.com/v1/profile",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.sourceMethod == "PATCH")
    }

    @Test("Context from transaction maps known method to HTTPMethodFilter")
    @MainActor
    func transactionMapsKnownMethod() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.example.com/v1/users",
            statusCode: 201
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.httpMethod == .post)
    }

    @Test("Context from transaction sets wildcard match type as default")
    @MainActor
    func transactionDefaultMatchType() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/v1/users",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.defaultMatchType == .wildcard)
    }

    @Test("Context from transaction sets both phases true")
    @MainActor
    func transactionBothPhasesTrue() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/v1/users",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.breakpointRequest == true)
        #expect(context.breakpointResponse == true)
    }

    @Test("Context from transaction builds wildcard pattern from host and path")
    @MainActor
    func transactionBuildsWildcardPattern() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/v1/users",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.defaultPattern == "*api.example.com/v1/users")
    }

    @Test("Context from transaction normalizes empty path to slash")
    @MainActor
    func transactionNormalizesEmptyPath() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.sourcePath == "/")
        #expect(context.defaultPattern == "*api.example.com/")
    }

    @Test("Context from transaction sets includeSubpaths true")
    @MainActor
    func transactionIncludeSubpaths() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/v1/users",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.includeSubpaths == true)
    }

    @Test("Context from transaction provides suggested name with method and host")
    @MainActor
    func transactionSuggestsName() {
        let transaction = TestFixtures.makeTransaction(
            method: "DELETE",
            url: "https://api.example.com/v1/users/42",
            statusCode: 204
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.suggestedName == "Breakpoint — DELETE api.example.com/v1/users/42")
    }

    @Test("Context from transaction populates sourceURL")
    @MainActor
    func transactionPopulatesSourceURL() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/v1/users",
            statusCode: 200
        )

        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)

        #expect(context.sourceURL != nil)
    }

    // MARK: - fromDomain

    @Test("Context from domain has domainQuickCreate origin")
    func domainOrigin() {
        let context = BreakpointEditorContextBuilder.fromDomain("cdn.example.com")

        #expect(context.origin == .domainQuickCreate)
    }

    @Test("Context from domain sets wildcard pattern with domain")
    func domainSetsPattern() {
        let context = BreakpointEditorContextBuilder.fromDomain("cdn.example.com")

        #expect(context.defaultPattern == "*cdn.example.com/")
    }

    @Test("Context from domain sets ANY method")
    func domainSetsAnyMethod() {
        let context = BreakpointEditorContextBuilder.fromDomain("cdn.example.com")

        #expect(context.httpMethod == .any)
    }

    @Test("Context from domain has nil sourceMethod and sourceURL")
    func domainHasNilSourceFields() {
        let context = BreakpointEditorContextBuilder.fromDomain("cdn.example.com")

        #expect(context.sourceMethod == nil)
        #expect(context.sourceURL == nil)
    }

    @Test("Context from domain sets both phases true")
    func domainBothPhasesTrue() {
        let context = BreakpointEditorContextBuilder.fromDomain("cdn.example.com")

        #expect(context.breakpointRequest == true)
        #expect(context.breakpointResponse == true)
    }
}
