import Foundation
@testable import Rockxy
import Testing

// Regression tests for `BypassDomain` in the models layer.

// MARK: - BypassDomainTests

struct BypassDomainTests {
    // MARK: - Exact Matching

    @Test("Exact match succeeds for identical domain")
    func exactMatch() {
        let domain = TestFixtures.makeBypassDomain(domain: "localhost")
        #expect(domain.matches("localhost"))
    }

    @Test("Exact match is case-insensitive")
    func exactMatchCaseInsensitive() {
        let domain = TestFixtures.makeBypassDomain(domain: "localhost")
        #expect(domain.matches("LocalHost"))
    }

    @Test("Exact match fails for different domain")
    func exactMismatch() {
        let domain = TestFixtures.makeBypassDomain(domain: "localhost")
        #expect(!domain.matches("example.com"))
    }

    // MARK: - Wildcard Matching

    @Test("Wildcard *.local matches subdomain")
    func wildcardMatch() {
        let domain = TestFixtures.makeBypassDomain(domain: "*.local")
        #expect(domain.matches("myhost.local"))
    }

    @Test("Wildcard *.example.com matches subdomain")
    func wildcardMatchSubdomain() {
        let domain = TestFixtures.makeBypassDomain(domain: "*.example.com")
        #expect(domain.matches("sub.example.com"))
    }

    @Test("Wildcard *.example.com does NOT match root domain")
    func wildcardNoMatchRoot() {
        let domain = TestFixtures.makeBypassDomain(domain: "*.example.com")
        #expect(!domain.matches("example.com"))
    }

    @Test("Wildcard *.local does NOT match unrelated domain")
    func wildcardNoMatchUnrelated() {
        let domain = TestFixtures.makeBypassDomain(domain: "*.local")
        #expect(!domain.matches("example.com"))
    }

    // MARK: - IP Address Matching

    @Test("IP address exact match")
    func ipAddressExact() {
        let domain = TestFixtures.makeBypassDomain(domain: "127.0.0.1")
        #expect(domain.matches("127.0.0.1"))
    }

    @Test("IP wildcard 169.254.* matches subnet")
    func ipWildcard() {
        let domain = TestFixtures.makeBypassDomain(domain: "169.254.*")
        #expect(domain.matches("169.254.1.1"))
        #expect(domain.matches("169.254.255.255"))
        #expect(!domain.matches("169.255.1.1"))
        #expect(!domain.matches("169.254.invalid"))
        #expect(BypassDomain.isIPv4PrefixWildcard("169.254.*"))
        #expect(!BypassDomain.isIPv4PrefixWildcard("169.999.*"))
    }

    @Test("IPv4 CIDR matches only addresses inside its prefix")
    func ipv4CIDR() {
        let domain = TestFixtures.makeBypassDomain(domain: "10.0.0.0/8")
        #expect(domain.matches("10.0.0.1"))
        #expect(domain.matches("10.255.255.255"))
        #expect(!domain.matches("11.0.0.1"))
        #expect(!domain.matches("api.example.com"))
        #expect(BypassDomain.systemProxyPatterns(for: domain.domain) == ["10.0.0.0/8"])
    }

    @Test("Global IPv4 CIDR fails closed")
    func globalIPv4CIDRFailsClosed() {
        let domain = TestFixtures.makeBypassDomain(domain: "0.0.0.0/0")

        #expect(!domain.matches("10.0.0.1"))
        #expect(!domain.matches("192.168.1.10"))
        #expect(BypassDomain.systemProxyPatterns(for: domain.domain).isEmpty)
    }

    // MARK: - Codable

    @Test("Codable roundtrip preserves all fields")
    func codableRoundtrip() throws {
        let original = TestFixtures.makeBypassDomain(domain: "*.example.com", isEnabled: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BypassDomain.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.domain == original.domain)
        #expect(decoded.isEnabled == original.isEnabled)
    }

    // MARK: - Hashable

    @Test("Hashable identity — same UUID produces same hash")
    func hashableIdentity() {
        let id = UUID()
        let a = BypassDomain(id: id, domain: "localhost", isEnabled: true)
        let b = BypassDomain(id: id, domain: "localhost", isEnabled: true)
        #expect(a.hashValue == b.hashValue)
        #expect(a == b)
    }

    @Test("Different UUIDs are not equal")
    func hashableDifferentIDs() {
        let a = TestFixtures.makeBypassDomain(domain: "localhost")
        let b = TestFixtures.makeBypassDomain(domain: "localhost")
        #expect(a != b)
    }
}
