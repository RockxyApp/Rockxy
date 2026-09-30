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
        #expect(vm.workspaceMode == .text)
        #expect(vm.workspaceState == .textPaste)
        #expect(vm.canSwapSides == false)
        #expect(vm.activeDiffResult.differenceCount == 0)
    }

    @Test("A pair can be assembled one side at a time")
    @MainActor
    func sidesArriveOneAtATime() {
        let store = DiffTransactionStore()
        let vm = DiffViewModel(transactionStore: store)
        let first = TestFixtures.makeTransaction(url: "https://api.example.com/a")
        let second = TestFixtures.makeTransaction(url: "https://api.example.com/b")

        store.pendingLeft = first
        vm.consumeFromStore()
        #expect(vm.leftTransaction?.id == first.id)
        #expect(vm.rightTransaction == nil)
        #expect(vm.workspaceMode == .captured)
        #expect(!store.hasPendingSide)

        store.pendingRight = second
        vm.consumeFromStore()
        #expect(vm.leftTransaction?.id == first.id)
        #expect(vm.rightTransaction?.id == second.id)
        #expect(vm.workspaceState == .ready)
    }

    @Test("Assign left sets left transaction")
    @MainActor
    func assignLeft() {
        let vm = DiffViewModel()
        let tx = TestFixtures.makeTransaction()
        vm.workspaceMode = .captured
        vm.candidates = [tx]
        vm.assignLeft(tx)
        #expect(vm.leftTransaction?.id == tx.id)
    }

    @Test("Assign right sets right transaction")
    @MainActor
    func assignRight() {
        let vm = DiffViewModel()
        let tx = TestFixtures.makeTransaction()
        vm.workspaceMode = .captured
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
        vm.workspaceMode = .captured
        vm.assignLeft(a)
        vm.assignRight(b)
        vm.swapSides()
        #expect(vm.leftTransaction?.id == b.id)
        #expect(vm.rightTransaction?.id == a.id)
    }

    @Test("Swap sides exchanges pasted text")
    @MainActor
    func swapPastedText() {
        let vm = DiffViewModel()
        vm.textA = "before"
        vm.textB = "after"
        #expect(vm.canSwapSides)

        vm.swapSides()

        #expect(vm.textA == "after")
        #expect(vm.textB == "before")
    }

    @Test("Assigning one transaction to both sides clears the opposite side")
    @MainActor
    func sidesRemainExclusive() {
        let vm = DiffViewModel()
        let transaction = TestFixtures.makeTransaction()
        vm.workspaceMode = .captured

        vm.assignLeft(transaction)
        #expect(vm.canSwapSides)
        vm.assignRight(transaction)

        #expect(vm.leftTransaction == nil)
        #expect(vm.rightTransaction?.id == transaction.id)
    }

    @Test("isLeft and isRight detect correct assignment")
    @MainActor
    func isLeftRight() {
        let vm = DiffViewModel()
        let a = TestFixtures.makeTransaction(url: "https://a.com/test")
        let b = TestFixtures.makeTransaction(url: "https://b.com/test")
        vm.workspaceMode = .captured
        vm.assignLeft(a)
        vm.assignRight(b)
        #expect(vm.isLeft(a))
        #expect(vm.isRight(b))
        #expect(!vm.isLeft(b))
        #expect(!vm.isRight(a))
    }

    @Test("Comparison source is controlled explicitly")
    @MainActor
    func explicitWorkspaceMode() {
        let vm = DiffViewModel()
        #expect(vm.isTextMode)

        vm.candidates = [TestFixtures.makeTransaction()]
        #expect(vm.isTextMode)

        vm.workspaceMode = .captured
        #expect(!vm.isTextMode)
    }

    @Test("consumeFromStore adds candidates and assigns L/R")
    @MainActor
    func consumeFromStore() {
        let store = DiffTransactionStore()
        let a = TestFixtures.makeTransaction(url: "https://a.com/test")
        let b = TestFixtures.makeTransaction(url: "https://b.com/test")
        store.setPending(a, b)

        let vm = DiffViewModel(transactionStore: store)
        vm.consumeFromStore()

        #expect(vm.candidates.count == 2)
        #expect(vm.leftTransaction?.id == a.id)
        #expect(vm.rightTransaction?.id == b.id)
        #expect(vm.workspaceMode == .captured)
    }

    @Test("Repeated consumeFromStore appends deduped candidates")
    @MainActor
    func appendDeduped() {
        let store = DiffTransactionStore()
        let vm = DiffViewModel(transactionStore: store)
        let a = TestFixtures.makeTransaction(url: "https://a.com/test")
        let b = TestFixtures.makeTransaction(url: "https://b.com/test")
        let c = TestFixtures.makeTransaction(url: "https://c.com/test")

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
        let vm = DiffViewModel(transactionStore: DiffTransactionStore())
        vm.consumeFromStore()
        #expect(vm.candidates.isEmpty)
    }

    @Test("diffResult is empty when only left assigned")
    @MainActor
    func partialAssignment() {
        let vm = DiffViewModel()
        vm.workspaceMode = .captured
        vm.assignLeft(TestFixtures.makeTransaction())
        #expect(vm.diffResult.differenceCount == 0)
        #expect(vm.workspaceState == .missingRight)
    }

    @Test("textDiffResult compares freeform text")
    @MainActor
    func textDiff() async {
        let vm = DiffViewModel()
        vm.textA = "line 1\nline 2"
        vm.textB = "line 1\nline 3"
        vm.compareText()
        await vm.waitForComparison()

        let result = vm.textDiffResult
        #expect(vm.workspaceState == .textReady)
        #expect(result.differenceCount > 0)
    }

    @Test("workspaceState becomes ready when both sides are assigned")
    @MainActor
    func workspaceReady() async {
        let vm = DiffViewModel()
        vm.workspaceMode = .captured
        vm.candidates = [
            TestFixtures.makeTransaction(url: "https://a.com/test"),
            TestFixtures.makeTransaction(url: "https://b.com/test"),
        ]
        vm.assignLeft(vm.candidates[0])
        vm.assignRight(vm.candidates[1])
        await vm.waitForComparison()

        #expect(vm.workspaceState == .ready)
        #expect(!vm.isComparing)
    }

    @Test("Assigning left clears the same transaction from right")
    @MainActor
    func sidesRemainExclusiveFromLeft() {
        let vm = DiffViewModel()
        let transaction = TestFixtures.makeTransaction()
        vm.workspaceMode = .captured

        vm.assignRight(transaction)
        vm.assignLeft(transaction)

        #expect(vm.leftTransaction?.id == transaction.id)
        #expect(vm.rightTransaction == nil)
    }

    @Test("Same transaction store ingress never produces a ready comparison")
    @MainActor
    func sameTransactionIngress() {
        let store = DiffTransactionStore()
        let transaction = TestFixtures.makeTransaction()
        store.setPending(transaction, transaction)

        let vm = DiffViewModel(transactionStore: store)
        vm.consumeFromStore()

        #expect(vm.candidates.count == 1)
        #expect(vm.workspaceState == .missingLeft)
        #expect(vm.leftTransaction == nil)
        #expect(vm.rightTransaction?.id == transaction.id)
    }

    @Test("Candidate pool is bounded and can be cleared")
    @MainActor
    func boundedCandidatePool() {
        let store = DiffTransactionStore()
        let vm = DiffViewModel(transactionStore: store)

        for index in 0 ..< 15 {
            let left = TestFixtures.makeTransaction(url: "https://left.example.com/\(index)")
            let right = TestFixtures.makeTransaction(url: "https://right.example.com/\(index)")
            store.setPending(left, right)
            vm.consumeFromStore()
        }

        #expect(vm.candidates.count == DiffViewModel.maximumCandidateCount)
        #expect(vm.candidates.first?.request.url.absoluteString == "https://left.example.com/3")
        #expect(vm.candidates.last?.request.url.absoluteString == "https://right.example.com/14")
        #expect(vm.leftTransaction?.request.url.absoluteString == "https://left.example.com/14")
        #expect(vm.rightTransaction?.request.url.absoluteString == "https://right.example.com/14")
        vm.clearCandidates()
        #expect(vm.candidates.isEmpty)
        #expect(vm.workspaceState == .missingBoth)
    }

    @Test("Text comparison returns to editing without retaining a rendered result")
    @MainActor
    func editComparedText() async {
        let vm = DiffViewModel()
        vm.textA = "before"
        vm.textB = "after"
        vm.compareText()
        await vm.waitForComparison()
        #expect(vm.activeDiffResult.differenceCount == 2)

        vm.editText()

        #expect(vm.workspaceState == .textPaste)
        #expect(vm.activeDiffResult.differenceCount == 0)
        #expect(vm.textA == "before")
        #expect(vm.textB == "after")
    }

    @Test("A stale comparison cannot replace the latest requested result")
    @MainActor
    func staleComparisonCannotApply() async {
        let vm = DiffViewModel()
        let shared = (0 ... DiffEngine.maximumLineCount).map { "line \($0)" }.joined(separator: "\n")
        vm.textA = shared + "\nold left"
        vm.textB = shared + "\nold right"
        vm.compareText()

        vm.textA = "current left"
        vm.textB = "current right"
        vm.compareText()
        await vm.waitForComparison()

        #expect(vm.activeDiffResult.allLines.contains { $0.content == "current left" })
        #expect(vm.activeDiffResult.allLines.contains { $0.content == "current right" })
        #expect(!vm.activeDiffResult.allLines.contains { $0.content == "old left" })
    }
}
