import Foundation

// MARK: - BreakpointEditorContext

/// Carries prefilled values and quick-create provenance to open the Breakpoint Rules editor with context.
struct BreakpointEditorContext {
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
    let breakpointRequest: Bool
    let breakpointResponse: Bool
    /// Prefilled when the rule is created from a GraphQL request, so the breakpoint
    /// pauses that operation only instead of every call to the shared endpoint.
    var graphQLOperationName: String?
}
