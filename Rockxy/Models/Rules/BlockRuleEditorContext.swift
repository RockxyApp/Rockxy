import Foundation

/// Backward-compatible alias — `BlockMatchType` was extracted to `RuleMatchType` for reuse.
typealias BlockMatchType = RuleMatchType

// MARK: - BlockActionType

enum BlockActionType: String, CaseIterable {
    case returnForbidden = "Return 403 Forbidden"
    case dropConnection = "Drop Connection"

    // MARK: Internal

    /// The HTTP status code for the block action.
    var statusCode: Int {
        switch self {
        case .returnForbidden: 403
        case .dropConnection: 0
        }
    }
}

// MARK: - BlockRuleEditorContext

/// Carries prefilled values and quick-create provenance to open the Block editor with context.
struct BlockRuleEditorContext {
    enum Origin: Equatable {
        case selectedTransaction
        case domainQuickCreate
    }

    let origin: Origin
    let suggestedName: String
    let sourceURL: URL?
    let sourceHost: String
    let sourcePath: String?
    let sourceMethod: String?
    let defaultPattern: String
    let defaultMatchType: BlockMatchType
    let defaultAction: BlockActionType
    let httpMethod: HTTPMethodFilter
    let includeSubpaths: Bool
}
