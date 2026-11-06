import Foundation
import JavaScriptCore
@testable import Rockxy
import Testing

// MARK: - ScriptFlowStateStoreTests

struct ScriptFlowStateStoreTests {
    @Test("A response receives the object its request populated, once")
    func responseConsumesRequestState() throws {
        let context = try #require(JSContext())
        let store = ScriptFlowStateStore()
        let flow = UUID()

        let requestState = try #require(store.beginFlow(flow, in: context))
        requestState.setObject("GetUser", forKeyedSubscript: "operation" as NSString)

        let responseState = try #require(store.endFlow(flow, in: context))
        #expect(responseState.objectForKeyedSubscript("operation")?.toString() == "GetUser")
        #expect(store.isEmpty)

        let secondRead = try #require(store.endFlow(flow, in: context))
        #expect(secondRead.objectForKeyedSubscript("operation")?.isUndefined == true)
    }

    @Test("Flows that never reach a response are evicted oldest first")
    func abandonedFlowsAreBounded() throws {
        let context = try #require(JSContext())
        let store = ScriptFlowStateStore(capacity: 2)
        let first = UUID()
        let second = UUID()
        let third = UUID()

        try #require(store.beginFlow(first, in: context)).setObject(1, forKeyedSubscript: "n" as NSString)
        try #require(store.beginFlow(second, in: context)).setObject(2, forKeyedSubscript: "n" as NSString)
        try #require(store.beginFlow(third, in: context)).setObject(3, forKeyedSubscript: "n" as NSString)

        #expect(store.count == 2)
        #expect(try #require(store.endFlow(first, in: context)).objectForKeyedSubscript("n")?.isUndefined == true)
        #expect(try #require(store.endFlow(third, in: context)).objectForKeyedSubscript("n")?.toInt32() == 3)
    }

    @Test("Discarding a flow frees its slot instead of waiting for eviction")
    func discardFreesSlotImmediately() throws {
        let context = try #require(JSContext())
        let store = ScriptFlowStateStore(capacity: 2)
        let discarded = UUID()
        let live = UUID()

        _ = try #require(store.beginFlow(discarded, in: context))
        try #require(store.beginFlow(live, in: context)).setObject(1, forKeyedSubscript: "n" as NSString)
        store.discardFlow(discarded)
        #expect(store.count == 1)

        // The surviving flow must still be the one it was, not a victim of the
        // eviction that discarding exists to avoid.
        #expect(try #require(store.endFlow(live, in: context)).objectForKeyedSubscript("n")?.toInt32() == 1)
        #expect(store.isEmpty)
    }

    @Test("Discarding an unknown or already ended flow is a no-op")
    func discardIsIdempotent() throws {
        let context = try #require(JSContext())
        let store = ScriptFlowStateStore()
        let flow = UUID()

        store.discardFlow(flow)
        _ = try #require(store.beginFlow(flow, in: context))
        store.discardFlow(flow)
        store.discardFlow(flow)
        #expect(store.isEmpty)
    }
}
