import Foundation

// MARK: - AssistantTrafficScope

/// Traffic the user has explicitly allowed the Assistant to inspect for a single investigation.
enum AssistantTrafficScope: String, Equatable, Sendable {
    case selectedOnly
    case selectedAndRelated

    var title: String {
        switch self {
        case .selectedOnly:
            String(localized: "Selected Traffic Only")
        case .selectedAndRelated:
            String(localized: "Selected and Related Traffic")
        }
    }
}

// MARK: - AssistantUserHandoff

/// Native workflows the user may open after reviewing an Assistant result.
/// These cases are handoffs only: the Assistant never executes the resulting action.
enum AssistantUserHandoff: String, CaseIterable, Identifiable, Sendable {
    case prepareReplay
    case compose
    case export
    case share

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prepareReplay:
            String(localized: "Prepare Replay…")
        case .compose:
            String(localized: "Open in Compose")
        case .export:
            String(localized: "Export Selected…")
        case .share:
            String(localized: "Review & Share…")
        }
    }

    var systemImage: String {
        switch self {
        case .prepareReplay: "arrow.clockwise"
        case .compose: "square.and.pencil"
        case .export: "square.and.arrow.up"
        case .share: "person.crop.circle.badge.checkmark"
        }
    }
}

// MARK: - AssistantTrustPolicy

/// Product-level trust boundary shared by the Assistant coordinator and native UI.
enum AssistantTrustPolicy {
    static let defaultTrafficScope: AssistantTrafficScope = .selectedOnly
    static let permitsDirectMutation = false

    static func isReviewedScopeValid(
        _ pack: InvestigationContextPack,
        for result: InvestigationResult
    )
        -> Bool
    {
        let reviewedIDs = pack.scopeTransactionIDs
        guard reviewedIDs.first == result.selectedTransactionID,
              !reviewedIDs.isEmpty else
        {
            return false
        }
        return Set(reviewedIDs).isSubset(of: Set(result.scopeTransactionIDs))
    }

    static func recommendedHandoffs(for recipe: DebugAssistantRecipe) -> [AssistantUserHandoff] {
        switch recipe {
        case .explainRequest:
            []
        case .explainFailure:
            [.prepareReplay]
        case .compareWithSuccess:
            [.compose, .export]
        case .checkAuthentication:
            [.compose]
        case .prepareBugReport:
            [.export, .share]
        }
    }
}
