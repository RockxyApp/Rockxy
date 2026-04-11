import Foundation
@testable import Rockxy
import Testing

struct BreakpointEditorContextStoreTests {
    @Test("setPending stores context")
    @MainActor
    func setPendingStoresContext() {
        let store = BreakpointEditorContextStore.shared
        let context = BreakpointEditorContextBuilder.fromDomain("example.com")

        store.setPending(context)

        #expect(store.pendingContext != nil)
        _ = store.consumePending()
    }

    @Test("consumePending returns and clears context")
    @MainActor
    func consumePendingReturnsAndClears() {
        let store = BreakpointEditorContextStore.shared
        let context = BreakpointEditorContextBuilder.fromDomain("example.com")

        store.setPending(context)
        let consumed = store.consumePending()

        #expect(consumed != nil)
        #expect(consumed?.sourceHost == "example.com")
        #expect(store.pendingContext == nil)
    }

    @Test("consumePending from empty returns nil")
    @MainActor
    func consumePendingFromEmptyReturnsNil() {
        let store = BreakpointEditorContextStore.shared
        _ = store.consumePending()

        let consumed = store.consumePending()

        #expect(consumed == nil)
    }

    @Test("contextVersion increments on each setPending")
    @MainActor
    func contextVersionIncrements() {
        let store = BreakpointEditorContextStore.shared
        let initial = store.contextVersion

        store.setPending(BreakpointEditorContextBuilder.fromDomain("a.com"))
        #expect(store.contextVersion == initial + 1)

        store.setPending(BreakpointEditorContextBuilder.fromDomain("b.com"))
        #expect(store.contextVersion == initial + 2)

        _ = store.consumePending()
    }

    @Test("Multiple setPending overwrites previous context")
    @MainActor
    func multipleSetPendingOverwrites() {
        let store = BreakpointEditorContextStore.shared

        store.setPending(BreakpointEditorContextBuilder.fromDomain("first.com"))
        store.setPending(BreakpointEditorContextBuilder.fromDomain("second.com"))

        let consumed = store.consumePending()
        #expect(consumed?.sourceHost == "second.com")
        #expect(store.consumePending() == nil)
    }
}
