import Foundation

// MARK: - SSLProxyingListType

/// Distinguishes whether a rule belongs to the Include or Exclude list.
enum SSLProxyingListType: String, Codable, CaseIterable {
    case include
    case exclude
}

// MARK: - SSLProxyingRule

/// A domain rule controlling whether Rockxy intercepts HTTPS traffic for that host.
/// Supports exact matches and wildcard prefixes (e.g., `*.example.com`).
struct SSLProxyingRule: Codable, Identifiable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), domain: String, isEnabled: Bool = true, listType: SSLProxyingListType = .include) {
        self.id = id
        self.domain = domain
        self.isEnabled = isEnabled
        self.listType = listType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        domain = try container.decode(String.self, forKey: .domain)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        listType = try container.decodeIfPresent(SSLProxyingListType.self, forKey: .listType) ?? .include
    }

    // MARK: Internal

    let id: UUID
    var domain: String
    var isEnabled: Bool
    var listType: SSLProxyingListType

    /// Checks whether the given host matches this rule's domain pattern.
    ///
    /// - Wildcard: `*.example.com` matches `foo.example.com`, `bar.baz.example.com`
    /// - Exact: `example.com` matches only `example.com`
    func matches(_ host: String) -> Bool {
        let lowerDomain = domain.lowercased()
        let lowerHost = host.lowercased()

        if lowerDomain == "*" {
            return true
        }

        if lowerDomain.hasPrefix("*.") {
            let suffix = String(lowerDomain.dropFirst(1))
            return lowerHost.hasSuffix(suffix) && lowerHost.count > suffix.count
        }

        return lowerHost == lowerDomain
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case id
        case domain
        case isEnabled
        case listType
    }
}
