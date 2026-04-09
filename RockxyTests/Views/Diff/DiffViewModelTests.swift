import Foundation
@testable import Rockxy
import Testing

// Regression tests for `DiffViewModel` in the views diff layer.

struct DiffViewModelTests {
    @Test("Initial state has no candidates")
    @MainActor
    func initialState() {
        let vm = DiffViewModel()
        #expect(vm.candidates.isEmpty)
        #expect(vm.leftTransaction == nil)
        #expect(vm.rightTransaction == nil)
        #expect(vm.compareTarget == .request)
        #expect(vm.presentationMode == .sideBySide)
        #expect(vm.workspaceState == .textPaste)
    }

    @Test("Assign left sets left transaction")
    @MainActor
    func assignLeft() {
        let vm = DiffViewModel()
        let tx = TestFixtures.makeTransaction()
        vm.candidates = [tx]
        vm.assignLeft(tx)
        #expect(vm.leftTransaction?.id == tx.id)
    }

    @Test("Assign right sets right transaction")
    @MainActor
    func assignRight() {
        let vm = DiffViewModel()
        let tx = TestFixtures.makeTransaction()
        vm.candidates = [tx]
        vm.assignRight(tx)
        #expect(vm.rightTransaction?.id == tx.id)
    }

    @Test("Swap sides exchanges left and right")
    @MainActor
    func swapSides() {
        let vm = DiffViewModel()
        let a = TestFixtures.makeTransaction(url: "https://a.com/test")
        let b = TestFixtures.makeTransaction(url: "https://b.com/test")
        vm.assignLeft(a)
        vm.assignRight(b)
        vm.swapSides()
        #expect(vm.leftTransaction?.id == b.id)
        #expect(vm.rightTransaction?.id == a.id)
    }

    @Test("isLeft and isRight detect correct assignment")
    @MainActor
    func isLeftRight() {
        let vm = DiffViewModel()
        let a = TestFixtures.makeTransaction(url: "https://a.com/test")
        let b = TestFixtures.makeTransaction(url: "https://b.com/test")
        vm.assignLeft(a)
        vm.assignRight(b)
        #expect(vm.isLeft(a))
        #expect(vm.isRight(b))
        #expect(!vm.isLeft(b))
        #expect(!vm.isRight(a))
    }

    @Test("isTextMode when no candidates")
    @MainActor
    func textMode() {
        let vm = DiffViewModel()
        #expect(vm.isTextMode)
    }

    @Test("isTextMode false when candidates exist")
    @MainActor
    func notTextMode() {
        let vm = DiffViewModel()
        vm.candidates = [TestFixtures.makeTransaction()]
        #expect(!vm.isTextMode)
    }

    @Test("consumeFromStore adds candidates and assigns L/R")
    @MainActor
    func consumeFromStore() {
        let store = DiffTransactionStore.shared
        let a = TestFixtures.makeTransaction(url: "https://a.com/test")
        let b = TestFixtures.makeTransaction(url: "https://b.com/test")
        store.setPending(a, b)

        let vm = DiffViewModel()
        vm.consumeFromStore()

        #expect(vm.candidates.count == 2)
        #expect(vm.leftTransaction?.id == a.id)
        #expect(vm.rightTransaction?.id == b.id)
    }

    @Test("Repeated consumeFromStore appends deduped candidates")
    @MainActor
    func appendDeduped() {
        let vm = DiffViewModel()
        let a = TestFixtures.makeTransaction(url: "https://a.com/test")
        let b = TestFixtures.makeTransaction(url: "https://b.com/test")
        let c = TestFixtures.makeTransaction(url: "https://c.com/test")

        let store = DiffTransactionStore.shared
        store.setPending(a, b)
        vm.consumeFromStore()
        #expect(vm.candidates.count == 2)

        store.setPending(b, c)
        vm.consumeFromStore()
        #expect(vm.candidates.count == 3)
        #expect(vm.leftTransaction?.id == b.id)
        #expect(vm.rightTransaction?.id == c.id)
    }

    @Test("consumeFromStore with empty store does nothing")
    @MainActor
    func consumeEmpty() {
        _ = DiffTransactionStore.shared.consumePending()

        let vm = DiffViewModel()
        vm.consumeFromStore()
        #expect(vm.candidates.isEmpty)
    }

    @Test("diffResult is empty when only left assigned")
    @MainActor
    func partialAssignment() {
        let vm = DiffViewModel()
        vm.assignLeft(TestFixtures.makeTransaction())
        #expect(vm.diffResult.differenceCount == 0)
        #expect(vm.workspaceState == .missingRight)
    }

    @Test("textDiffResult compares freeform text")
    @MainActor
    func textDiff() {
        let vm = DiffViewModel()
        vm.textA = "line 1\nline 2"
        vm.textB = "line 1\nline 3"
        let result = vm.textDiffResult
        #expect(result.differenceCount > 0)
    }

    @Test("workspaceState becomes ready when both sides are assigned")
    @MainActor
    func workspaceReady() {
        let vm = DiffViewModel()
        vm.candidates = [
            TestFixtures.makeTransaction(url: "https://a.com/test"),
            TestFixtures.makeTransaction(url: "https://b.com/test"),
        ]
        vm.assignLeft(vm.candidates[0])
        vm.assignRight(vm.candidates[1])

        #expect(vm.workspaceState == .ready)
    }
}
