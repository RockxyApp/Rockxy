import Foundation

/// Identifies the product edition at runtime: community, pro, or enterprise.
///
/// Resolution flows through the standard identity chain:
/// `Base.xcconfig` → `Info.plist` → `Bundle.main.infoDictionary` → `resolve(from:)`.
///
/// Tests use `resolve(from:)` directly with a plain dictionary — no mock bundle needed.
enum ProductEdition: String {
    case community
    case pro
    case enterprise

    // MARK: Internal

    static let current = resolve(from: Bundle.main.infoDictionary)

    static func resolve(from infoDictionary: [String: Any]?) -> ProductEdition {
        guard let raw = infoDictionary?["RockxyProductEdition"] as? String else {
            return .community
        }
        return ProductEdition(rawValue: raw.lowercased()) ?? .community
    }
}
