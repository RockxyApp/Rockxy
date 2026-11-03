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
        self.domain = Self.normalizedPattern(domain)
        self.isEnabled = isEnabled
        self.listType = listType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        domain = try Self.normalizedPattern(container.decode(String.self, forKey: .domain))
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
    ///
    /// The PATTERN is normalized, the HOST is not, and the asymmetry is deliberate. The pattern is
    /// configuration: a stray space around `example.com` left an Exclude (Tunnel) rule matching
    /// nothing, so a host the user had explicitly marked "do not decrypt" was decrypted anyway.
    /// The host is wire-supplied — the CONNECT target or Host header — and trimming it would let a
    /// malformed ` example.com` be normalized into an Include (Decrypt) match, widening what gets
    /// decrypted on attacker-controlled input. Left untrimmed it matches neither list, so
    /// `isDecryptionConfigured` lands on its fail-closed tunnel default. Callers that must accept
    /// user-typed hosts normalize before asking (see `SSLProxyingManager`).
    func matches(_ host: String) -> Bool {
        let lowerDomain = Self.normalizedPattern(domain).lowercased()
        let lowerHost = host.lowercased()

        // An empty pattern addresses no host. Treating it as a wildcard would make a blank rule
        // decrypt everything (Include) or tunnel everything (Exclude).
        if lowerDomain.isEmpty {
            return false
        }

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

    /// Canonical form of a stored pattern. `domain` is settable and decoded from persisted or
    /// imported JSON, so normalizing only at the sheets that create a rule would still leave
    /// untrimmed patterns in the matcher.
    private static func normalizedPattern(_ domain: String) -> String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
