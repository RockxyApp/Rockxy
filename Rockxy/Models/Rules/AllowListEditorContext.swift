import Foundation

// MARK: - AllowListEditorContext

/// Carries prefilled values and quick-create provenance to open the Allow List editor with context.
struct AllowListEditorContext {
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
    let defaultMatchType: RuleMatchType
    let httpMethod: HTTPMethodFilter
    let includeSubpaths: Bool
}
