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
}
