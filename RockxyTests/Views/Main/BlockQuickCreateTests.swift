import Foundation
@testable import Rockxy
import Testing

struct BlockQuickCreateTests {
    @Test("Transaction block editor context builder produces safe wildcard defaults")
    @MainActor
    func transactionContextBuilder() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.example.com/v1/orders?page=2",
            statusCode: 201
        )

        let context = BlockRuleEditorContextBuilder.fromTransaction(transaction)

        #expect(context.origin == .selectedTransaction)
        #expect(context.sourceHost == "api.example.com")
        #expect(context.sourceMethod == "POST")
        #expect(context.sourcePath == "/v1/orders")
        #expect(context.sourceURL?.absoluteString == "https://api.example.com/v1/orders?page=2")
        #expect(context.defaultMatchType == .wildcard)
        #expect(context.defaultAction == .returnForbidden)
        #expect(context.defaultPattern == "*api.example.com/v1/orders")
        #expect(!context.defaultPattern.contains("?page=2"))
        #expect(context.httpMethod == .post)
        #expect(context.includeSubpaths == true)
    }

    @Test("Domain block editor context builder produces domain wildcard defaults")
    @MainActor
    func domainContextBuilder() {
        let context = BlockRuleEditorContextBuilder.fromDomain("cdn.example.com")

        #expect(context.origin == .domainQuickCreate)
        #expect(context.sourceHost == "cdn.example.com")
        #expect(context.sourceMethod == nil)
        #expect(context.sourceURL == nil)
        #expect(context.defaultPattern == "*cdn.example.com/")
        #expect(context.defaultMatchType == .wildcard)
        #expect(context.defaultAction == .returnForbidden)
        #expect(context.httpMethod == .any)
        #expect(context.includeSubpaths == true)
    }

    @Test("Block quick-create stores pending editor context")
    @MainActor
    func setsStore() {
        let store = BlockRuleEditorContextStore.shared
        _ = store.consumePending()

        let context = BlockRuleEditorContextBuilder.fromDomain("example.com")
        store.setPending(context)

        #expect(store.pendingContext?.sourceHost == "example.com")
        #expect(store.pendingContext?.defaultPattern == "*example.com/")

        _ = store.consumePending()
    }

    @Test("Block quick-create posts openBlockListWindow notification")
    @MainActor
    func postsNotification() async {
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .openBlockListWindow,
            object: nil,
            queue: .main
        ) { _ in
            received = true
        }

        let context = BlockRuleEditorContextBuilder.fromDomain("example.com")
        BlockRuleEditorContextStore.shared.setPending(context)
        NotificationCenter.default.post(name: .openBlockListWindow, object: nil)

        try? await Task.sleep(for: .milliseconds(50))
        #expect(received)

        NotificationCenter.default.removeObserver(observer)
        _ = BlockRuleEditorContextStore.shared.consumePending()
    }
}
