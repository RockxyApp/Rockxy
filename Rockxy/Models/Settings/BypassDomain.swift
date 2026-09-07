import Foundation

/// A domain entry in the Bypass Proxy List.
/// Domains matching these patterns are excluded from Rockxy's system proxy.
/// Supports exact matches, bare domain subdomain matches, and wildcard prefixes (e.g., `*.local`).
struct BypassDomain: Identifiable, Codable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), domain: String, isEnabled: Bool = true) {
        self.id = id
        self.domain = domain
        self.isEnabled = isEnabled
    }

    // MARK: Internal

    let id: UUID
    var domain: String
    var isEnabled: Bool

    /// Checks whether the given host matches this bypass domain pattern.
    ///
    /// - Wildcard: `*.local` matches `myhost.local`, `sub.myhost.local`
    /// - Bare DNS: `example.com` matches `example.com` and `api.example.com`
    /// - Exact local/IP: `localhost`, `127.0.0.1`, and `::1` match only themselves
    func matches(_ host: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !normalizedHost.isEmpty, !normalizedDomain.isEmpty else {
            return false
        }

        if Self.isIPv4PrefixWildcard(normalizedDomain) {
            let prefix = String(normalizedDomain.dropLast())
            return normalizedHost.hasPrefix(prefix)
                && Self.isIPv4Address(normalizedHost)
        }

        if let cidr = ProxyBypassDomainValidator.ipv4CIDR(normalizedDomain),
           let address = ProxyBypassDomainValidator.ipv4Address(normalizedHost)
        {
            return address & cidr.mask == cidr.network
        }

        if Self.shouldMatchSubdomains(normalizedDomain) {
            return normalizedHost == normalizedDomain || normalizedHost.hasSuffix(".\(normalizedDomain)")
        }

        return HostPatternMatcher.matches(host: normalizedHost, pattern: normalizedDomain, extendedWildcards: false)
    }

    static func systemProxyPatterns(for domain: String) -> [String] {
        let normalizedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedDomain.isEmpty else {
            return []
        }

        if ProxyBypassDomainValidator.ipv4CIDR(normalizedDomain) != nil {
            return [normalizedDomain]
        }

        if shouldMatchSubdomains(normalizedDomain) {
            return [normalizedDomain, "*.\(normalizedDomain)"]
        }

        return [normalizedDomain]
    }

    /// Supports the IPv4-prefix form used by macOS proxy exceptions and Rockxy's
    /// built-in link-local preset, for example `169.254.*`.
    static func isIPv4PrefixWildcard(_ value: String) -> Bool {
        guard value.hasSuffix(".*") else {
            return false
        }
        let prefix = value.dropLast(2)
        let octets = prefix.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 3).contains(octets.count) else {
            return false
        }
        return octets.allSatisfy { octet in
            !octet.isEmpty
                && octet.allSatisfy(\.isNumber)
                && (0 ... 255).contains(Int(octet) ?? -1)
        }
    }

    private static func shouldMatchSubdomains(_ domain: String) -> Bool {
        domain.contains(".")
            && !domain.contains("*")
            && !domain.contains(":")
            && !domain.contains("[")
            && !domain.contains("]")
            && !domain.contains("/")
            && !isIPv4Address(domain)
    }

    private static func isIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return false
        }

        return parts.allSatisfy { part in
            !part.isEmpty
                && part.allSatisfy(\.isNumber)
                && (Int(part) ?? -1) <= 255
        }
    }
}
