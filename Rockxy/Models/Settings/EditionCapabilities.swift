import Foundation

/// Maps each product edition to its capability limits.
///
/// Currently only gates workspace tab count. Add new properties
/// only when a real consumer exists — do not add speculative keys.
struct EditionCapabilities {
    static let current = capabilities(for: .current)

    let maxWorkspaceTabs: Int

    static func capabilities(for edition: ProductEdition) -> EditionCapabilities {
        switch edition {
        case .community:
            EditionCapabilities(maxWorkspaceTabs: 8)
        case .pro,
             .enterprise:
            EditionCapabilities(maxWorkspaceTabs: 20)
        }
    }
}
