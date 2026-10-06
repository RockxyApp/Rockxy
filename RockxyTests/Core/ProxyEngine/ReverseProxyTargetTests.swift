import Foundation
@testable import Rockxy
import Testing

// MARK: - ReverseProxyTargetTests

struct ReverseProxyTargetTests {
    @Test("Request targets are rewritten onto the configured server only")
    func rewritesOntoRemote() {
        let target = ReverseProxyTarget(
            id: UUID(), localPort: 10_000, scheme: .https, host: "api.example.com", port: 443, preserveHostHeader: false
        )

        #expect(target.authority == "api.example.com")
        #expect(target.absoluteURI(for: "/v1/users?page=2") == "https://api.example.com/v1/users?page=2")
        #expect(target.absoluteURI(for: "http://evil.example.net/steal") == "https://api.example.com/steal")
        #expect(target.absoluteURI(for: "http://evil.example.net") == "https://api.example.com/")
        #expect(target.absoluteURI(for: "http://evil.example.net?x=1") == "https://api.example.com/?x=1")
    }

    @Test("Non-default ports and IPv6 hosts form a valid authority")
    func authorityFormatting() {
        let local = ReverseProxyTarget(
            id: UUID(), localPort: 10_001, scheme: .http, host: "localhost", port: 8_080, preserveHostHeader: true
        )
        let ipv6 = ReverseProxyTarget(
            id: UUID(), localPort: 10_002, scheme: .http, host: "::1", port: 80, preserveHostHeader: false
        )

        #expect(local.authority == "localhost:8080")
        #expect(ipv6.authority == "[::1]")
    }
}
