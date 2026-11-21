import Foundation
@testable import Rockxy
import Testing

// A body column was evaluated inline while a table cell drew, so the thread doing the drawing --
// the main thread -- parked on a semaphore once for every newly visible row. These tests hold the
// non-blocking pair that replaced that reading for the cell: a cell asks what is already resolved,
// and the evaluation itself happens off the caller and lands in the same per-transaction cache the
// blocking `bodyValue` fills.

// MARK: - CustomColumnOffMainActorTests

@MainActor
struct CustomColumnOffMainActorTests {
    // MARK: Internal

    @Test("A cell asking for an unresolved column gets nothing rather than an evaluation")
    func unresolvedColumnReportsNothingResolvedYet() {
        let transaction = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/orders")
        transaction.request.body = Data(#"{"id":11}"#.utf8)

        // The question a cell asks during layout. It must not reach the interpreter.
        #expect(CustomColumnValueResolver
            .cachedBodyValue(expression: ".id", response: false, transaction: transaction) == nil)
        #expect(transaction.customColumnValueCache.value(for: "req:.id") == nil)
    }

    @Test("Resolving off the main actor fills the same cache a cell then reads")
    func resolvingPublishesThroughTheSharedCache() async {
        let transaction = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/orders")
        transaction.request.body = Data(#"{"id":11}"#.utf8)

        let resolved = await CustomColumnValueResolver
            .resolveBodyValue(expression: ".id", response: false, transaction: transaction)

        #expect(resolved == "11")
        // The cell's next draw now has a value without evaluating anything, which is what makes
        // this one pass per transaction rather than one per newly visible row.
        #expect(CustomColumnValueResolver
            .cachedBodyValue(expression: ".id", response: false, transaction: transaction) == "11")
        #expect(transaction.customColumnValueCache.value(for: "req:.id") == "11")
    }

    @Test("A second resolve of a cached column never reaches the interpreter")
    func cachedColumnResolvesWithoutEvaluating() async {
        let transaction = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/orders")
        transaction.request.body = Data(#"{"id":11}"#.utf8)
        await CustomColumnValueResolver
            .resolveBodyValue(expression: ".id", response: false, transaction: transaction)

        // Stored directly, so a value that came back from an evaluation rather than the cache
        // would read as the body's "11" instead.
        transaction.customColumnValueCache.store("sentinel", for: "req:.id")
        let resolved = await CustomColumnValueResolver
            .resolveBodyValue(expression: ".id", response: false, transaction: transaction)

        #expect(resolved == "sentinel")
    }

    @Test("The off-caller evaluation agrees with the blocking one it replaces")
    func offCallerEvaluationMatchesTheBlockingOne() async {
        // Named with its type because in an async context the bare name resolves to the async
        // overload, which is the one under test here.
        let blockingEvaluate: (String, Data) -> String = CustomColumnValueResolver.evaluate
        let body = Data(#"{"data":{"user":{"name":"ana","roles":["admin","dev"]}},"count":2}"#.utf8)

        for expression in Self.expressions {
            let blocking = blockingEvaluate(expression, body)
            let offCaller = await CustomColumnValueResolver.evaluate(expression, on: body)

            #expect(offCaller == blocking, "\(expression) resolved differently off the caller")
        }
    }

    @Test("A response column resolves from decoded response evidence")
    func responseColumnResolvesFromResponseBody() async {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/orders")
        transaction.response = TestFixtures.makeResponse(body: Data(#"{"id":4}"#.utf8))

        let resolved = await CustomColumnValueResolver
            .resolveBodyValue(expression: ".id", response: true, transaction: transaction)

        #expect(resolved == "4")
        // A request column on the same transaction is a separate cache entry, not this one.
        #expect(CustomColumnValueResolver
            .cachedBodyValue(expression: ".id", response: false, transaction: transaction) == nil)
    }

    // MARK: Private

    /// Both expression dialects a column accepts, a failing one, and one that matches nothing:
    /// the off-caller path must agree with the blocking path on every outcome, not just success.
    private static let expressions = [
        "$.data.user.name",
        "$.data.user.roles[*]",
        ".data.user.roles | length",
        ".count + 1",
        ".nope(",
        ".absent",
    ]
}
