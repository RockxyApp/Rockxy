import Foundation
import os

// Renders the diff interface for the diff workflow.

// MARK: - DiffViewModel

/// Persistent workspace state for the Diff window. Holds candidates, L/R assignment,
/// compare target, presentation mode, and diff results. Consumes from DiffTransactionStore
/// on ingress and appends to the candidate pool (deduped by ID).
@MainActor @Observable
final class DiffViewModel {
    // MARK: Lifecycle

    init() {
        transactionStore = .shared
    }

    init(transactionStore: DiffTransactionStore) {
        self.transactionStore = transactionStore
    }

    // MARK: Internal

    enum WorkspaceState: Equatable {
        case textPaste
        case textReady
        case missingBoth
        case missingLeft
        case missingRight
        case ready
    }

    enum WorkspaceMode: String, CaseIterable, Identifiable {
        case captured
        case text

        // MARK: Internal

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .captured: String(localized: "Captured", bundle: RockxyLocalization.bundle)
            case .text: String(localized: "Text", bundle: RockxyLocalization.bundle)
            }
        }
    }

    static let maximumCandidateCount = 24

    var candidates: [HTTPTransaction] = []
    var leftTransaction: HTTPTransaction?
    var rightTransaction: HTTPTransaction?
    var presentationMode: PresentationMode = .sideBySide
    var textA: String = ""
    var textB: String = ""
    private(set) var isPresentingTextDiff = false
    private(set) var activeDiffResult: DiffResult = .empty
    private(set) var isComparing = false

    var compareTarget: CompareTarget = .request {
        didSet {
            scheduleComparison()
        }
    }

    var workspaceMode: WorkspaceMode = .text {
        didSet {
            if workspaceMode == .text {
                isPresentingTextDiff = false
            }
            scheduleComparison()
        }
    }

    var diffResult: DiffResult {
        workspaceMode == .captured ? activeDiffResult : .empty
    }

    var isTextMode: Bool {
        workspaceMode == .text
    }

    var textDiffResult: DiffResult {
        workspaceMode == .text ? activeDiffResult : .empty
    }

    var canSwapSides: Bool {
        if isTextMode {
            return !textA.isEmpty || !textB.isEmpty
        }
        return leftTransaction != nil || rightTransaction != nil
    }

    var workspaceState: WorkspaceState {
        if isTextMode {
            return isPresentingTextDiff ? .textReady : .textPaste
        }
        if leftTransaction == nil, rightTransaction == nil {
            return .missingBoth
        }
        if leftTransaction == nil {
            return .missingLeft
        }
        if rightTransaction == nil {
            return .missingRight
        }
        return .ready
    }

    /// Consumes pending transactions from DiffTransactionStore and merges into the pool.
    func consumeFromStore() {
        if transactionStore.hasPendingSide {
            let sides = transactionStore.consumePendingSides()
            workspaceMode = .captured
            if let left = sides.left {
                appendCandidate(left)
                assignLeft(left)
            }
            if let right = sides.right {
                appendCandidate(right)
                assignRight(right)
            }
            return
        }
        guard let (a, b) = transactionStore.consumePending() else {
            return
        }

        appendCandidate(a)
        appendCandidate(b)

        workspaceMode = .captured
        assignLeft(a)
        assignRight(b)

        Self.logger.info("Ingressed 2 transactions into Diff workspace")
    }

    func assignLeft(_ transaction: HTTPTransaction) {
        leftTransaction = transaction
        if rightTransaction?.id == transaction.id {
            rightTransaction = nil
        }
        scheduleComparison()
    }

    func assignRight(_ transaction: HTTPTransaction) {
        rightTransaction = transaction
        if leftTransaction?.id == transaction.id {
            leftTransaction = nil
        }
        scheduleComparison()
    }

    func swapSides() {
        if isTextMode {
            let previousTextA = textA
            textA = textB
            textB = previousTextA
            if isPresentingTextDiff {
                scheduleComparison()
            }
            return
        }

        let temp = leftTransaction
        leftTransaction = rightTransaction
        rightTransaction = temp
        scheduleComparison()
    }

    func isLeft(_ transaction: HTTPTransaction) -> Bool {
        leftTransaction?.id == transaction.id
    }

    func isRight(_ transaction: HTTPTransaction) -> Bool {
        rightTransaction?.id == transaction.id
    }

    func compareText() {
        guard !textA.isEmpty || !textB.isEmpty else {
            return
        }
        isPresentingTextDiff = true
        scheduleComparison()
    }

    func editText() {
        comparisonTask?.cancel()
        comparisonGeneration &+= 1
        isPresentingTextDiff = false
        isComparing = false
        activeDiffResult = .empty
    }

    func clearCandidates() {
        candidates.removeAll()
        leftTransaction = nil
        rightTransaction = nil
        scheduleComparison()
    }

    func waitForComparison() async {
        await comparisonTask?.value
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "DiffViewModel")

    private let transactionStore: DiffTransactionStore

    @ObservationIgnored private var comparisonTask: Task<Void, Never>?
    @ObservationIgnored private var comparisonGeneration: UInt64 = 0

    private func appendCandidate(_ transaction: HTTPTransaction) {
        if !candidates.contains(where: { $0.id == transaction.id }) {
            candidates.append(transaction)
        }
        if candidates.count > Self.maximumCandidateCount {
            candidates.removeFirst(candidates.count - Self.maximumCandidateCount)
        }
    }

    private func scheduleComparison() {
        comparisonGeneration &+= 1
        let generation = comparisonGeneration
        comparisonTask?.cancel()
        activeDiffResult = .empty

        let input: DiffComparisonInput
        switch workspaceMode {
        case .captured:
            guard let leftTransaction, let rightTransaction else {
                isComparing = false
                return
            }
            input = .transactions(
                left: DiffTransactionSnapshot(transaction: leftTransaction),
                right: DiffTransactionSnapshot(transaction: rightTransaction),
                target: compareTarget
            )
        case .text:
            guard isPresentingTextDiff, !textA.isEmpty || !textB.isEmpty else {
                isComparing = false
                return
            }
            input = .text(left: textA, right: textB)
        }

        isComparing = true
        comparisonTask = Task { @MainActor [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                input.result()
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            guard let self,
                  !Task.isCancelled,
                  comparisonGeneration == generation else
            {
                return
            }
            activeDiffResult = result
            isComparing = false
        }
    }
}

// MARK: - DiffComparisonInput

private enum DiffComparisonInput: Sendable {
    case transactions(
        left: DiffTransactionSnapshot,
        right: DiffTransactionSnapshot,
        target: CompareTarget
    )
    case text(left: String, right: String)

    // MARK: Internal

    func result() -> DiffResult {
        switch self {
        case let .transactions(left, right, target):
            return DiffFormatter.diff(left: left, right: right, target: target)
        case let .text(left, right):
            let lines = DiffEngine.diffText(old: left, new: right)
            return DiffResult(
                sections: [
                    DiffSection(
                        title: String(localized: "Text", bundle: RockxyLocalization.bundle),
                        lines: lines
                    ),
                ]
            )
        }
    }
}
