import Foundation

// MARK: - AssistantTrafficScope

/// Traffic the user has explicitly allowed the Assistant to inspect for a single investigation.
enum AssistantTrafficScope: String, Equatable, Sendable {
    case selectedOnly
    case selectedAndRelated

    // MARK: Internal

    var title: String {
        switch self {
        case .selectedOnly:
            String(localized: "Selected Traffic Only", bundle: RockxyLocalization.bundle)
        case .selectedAndRelated:
            String(localized: "Selected and Related Traffic", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - DebugAssistantReviewSummary

/// Review-time accounting of automatically discovered related traffic for a single investigation.
/// Distinguishes Focus/Noise scope exclusion from context-bound (size/capacity) omission, which
/// stays in `InvestigationContextManifest.omittedTransactionCount`.
struct DebugAssistantReviewSummary: Equatable {
    /// Raw related requests discovered near the selection, before Focus/Noise scoping.
    var rawRelatedFound = 0
    /// Related requests actually included in the reviewed context pack.
    var relatedIncluded = 0
    /// Related requests withheld by the active Focus Set or muted Noise sources. Reported for
    /// transparency even after an override is applied — it never zeroes just because the excluded
    /// traffic was included once.
    var focusNoiseExcluded = 0
    /// True once the user applied the one-time include-excluded override for this review.
    var overrideApplied = false
    /// True only when recomputing related traffic while ignoring Focus/Noise would actually change
    /// the bounded reviewed related transaction-ID set. Merely having excluded raw candidates that
    /// fall outside the context bound is not enough to make the override material.
    var overrideExpandsReviewedSet = false

    /// An override is offered only when it has not already been applied and it would materially
    /// expand the bounded reviewed related set.
    var canOverrideFocusNoise: Bool {
        !overrideApplied && overrideExpandsReviewedSet
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

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .prepareReplay:
            String(localized: "Prepare Replay…", bundle: RockxyLocalization.bundle)
        case .compose:
            String(localized: "Open in Compose", bundle: RockxyLocalization.bundle)
        case .export:
            String(localized: "Export Selected…", bundle: RockxyLocalization.bundle)
        case .share:
            String(localized: "Review & Share…", bundle: RockxyLocalization.bundle)
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
        case .whyIsThisSlow:
            [.prepareReplay]
        case .findRelatedRequests:
            [.compose]
        case .prepareBugReport:
            [.export, .share]
        }
    }
}
