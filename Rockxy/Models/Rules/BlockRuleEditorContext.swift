import Foundation

// MARK: - HTTPMethodFilter

enum HTTPMethodFilter: String, CaseIterable {
    case any = "ANY"
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
    case trace = "TRACE"

    // MARK: Internal

    /// Returns the method string for rule matching, or `nil` for `.any`.
    var methodValue: String? {
        self == .any ? nil : rawValue
    }
}

// MARK: - BlockMatchType

enum BlockMatchType: String, CaseIterable {
    case wildcard = "Use Wildcard"
    case regex = "Use Regex"
}

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
