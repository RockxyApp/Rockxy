import Foundation
import os

// Renders the diff interface for the diff workflow.

// MARK: - DiffViewModel

/// Persistent workspace state for the Diff window. Holds candidates, L/R assignment,
/// compare target, presentation mode, and diff results. Consumes from DiffTransactionStore
/// on ingress and appends to the candidate pool (deduped by ID).
@MainActor @Observable
final class DiffViewModel {
    // MARK: Internal

    enum WorkspaceState: Equatable {
        case textPaste
        case missingLeft
        case missingRight
        case ready
    }

    var candidates: [HTTPTransaction] = []
    var leftTransaction: HTTPTransaction?
    var rightTransaction: HTTPTransaction?
    var compareTarget: CompareTarget = .request
    var presentationMode: PresentationMode = .sideBySide
    var textA: String = ""
    var textB: String = ""

    var diffResult: DiffResult {
        guard let left = leftTransaction, let right = rightTransaction else {
            return .empty
        }
        return DiffFormatter.diff(left: left, right: right, target: compareTarget)
    }

    var isTextMode: Bool {
        candidates.isEmpty && leftTransaction == nil && rightTransaction == nil
    }

    var textDiffResult: DiffResult {
        guard !textA.isEmpty || !textB.isEmpty else {
            return .empty
        }
        let linesA = textA.components(separatedBy: "\n")
        let linesB = textB.components(separatedBy: "\n")
        let lines = DiffEngine.diff(old: linesA, new: linesB)
        return DiffResult(sections: [DiffSection(title: "Text", lines: lines)])
    }

    var activeDiffResult: DiffResult {
        isTextMode ? textDiffResult : diffResult
    }

    var workspaceState: WorkspaceState {
        if isTextMode {
            return .textPaste
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
        guard let (a, b) = DiffTransactionStore.shared.consumePending() else {
            return
        }

        appendCandidate(a)
        appendCandidate(b)

        leftTransaction = a
        rightTransaction = b

        Self.logger.info("Ingressed 2 transactions into Diff workspace")
    }

    func assignLeft(_ transaction: HTTPTransaction) {
        leftTransaction = transaction
    }

    func assignRight(_ transaction: HTTPTransaction) {
        rightTransaction = transaction
    }

    func swapSides() {
        let temp = leftTransaction
        leftTransaction = rightTransaction
        rightTransaction = temp
    }

    func isLeft(_ transaction: HTTPTransaction) -> Bool {
        leftTransaction?.id == transaction.id
    }

    func isRight(_ transaction: HTTPTransaction) -> Bool {
        rightTransaction?.id == transaction.id
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "DiffViewModel")

    private func appendCandidate(_ transaction: HTTPTransaction) {
        if !candidates.contains(where: { $0.id == transaction.id }) {
            candidates.append(transaction)
        }
    }
}
