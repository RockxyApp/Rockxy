import Foundation
@testable import Rockxy
import Testing

struct BreakpointQuickCreateTests {
    @Test("Transaction context builder includes method and normalized path")
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
        #expect(context.defaultPattern == "*api.example.com/v1/profile")
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
        #expect(context.defaultPattern == "*api.example.com/")
    }

    @Test("Domain context builder omits method and scopes to domain")
    func domainBuilder() {
        let context = BreakpointEditorContextBuilder.fromDomain("cdn.example.com")

        #expect(context.suggestedName == "Breakpoint — cdn.example.com")
        #expect(context.httpMethod == .any)
        #expect(context.sourceMethod == nil)
        #expect(context.defaultPattern == "*cdn.example.com/")
        #expect(context.breakpointRequest == true)
        #expect(context.breakpointResponse == true)
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
